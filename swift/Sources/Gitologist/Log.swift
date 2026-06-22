import Foundation

public enum LogError: Error, LocalizedError {
	case notAGitRepository
	case branchNotFound(String)

	public var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .branchNotFound(branch):
			return "Branch '\(branch)' not found"
		}
	}
}

public func log(at path: String, options: LogOptions? = nil) async throws -> [LogEntry] {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
	let cache = PackfileCache()

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw LogError.notAGitRepository
	}

	let branchName: String
	if let customBranch = options?.branch {
		branchName = customBranch
	} else {
		branchName = (try? await getCurrentBranch(at: gitDir.path)) ?? "main"
	}
	let branchPath = gitDir
		.appendingPathComponent("refs")
		.appendingPathComponent("heads")
		.appendingPathComponent(branchName)

	guard FileManager.default.fileExists(atPath: branchPath.path) else {
		if options?.branch != nil {
			throw LogError.branchNotFound(branchName)
		}
		return []
	}

	let commitSha = try String(contentsOf: branchPath, encoding: .utf8)
		.trimmingCharacters(in: .whitespacesAndNewlines)

	var entries: [LogEntry] = []
	var currentSha: String? = commitSha
	let limit = options?.limit ?? Int.max

	if let fileFilter = options?.file {
		var treeCache: [String: String?] = [:]

		while let sha = currentSha {
			let entry = try await parseCommitEntry(gitDir: gitDir.path, commitSha: sha, cache: cache)
			let currentBlobSha = try await getFileBlobSha(
				gitDir: gitDir.path, treeSha: entry.tree, filePath: fileFilter, treeCache: &treeCache, cache: cache
			)

			if entry.parent == nil {
				if currentBlobSha != nil {
					entries.append(entry)
				}
			} else {
				let parentEntry = try await parseCommitEntry(
					gitDir: gitDir.path, commitSha: entry.parent!, cache: cache
				)
				let parentBlobSha = try await getFileBlobSha(
					gitDir: gitDir.path, treeSha: parentEntry.tree, filePath: fileFilter,
					treeCache: &treeCache, cache: cache
				)
				if currentBlobSha != parentBlobSha {
					entries.append(entry)
				}
			}

			if entries.count >= limit { break }
			currentSha = entry.parent
		}

		return entries
	}

	while let sha = currentSha, entries.count < limit {
		let entry = try await parseCommitEntry(gitDir: gitDir.path, commitSha: sha, cache: cache)
		entries.append(entry)
		currentSha = entry.parent
	}

	return entries
}

private func parseCommitEntry(gitDir: String, commitSha: String, cache: PackfileCache) async throws -> LogEntry {
	let commitData = try await readObject(at: gitDir, sha: commitSha, cache: cache)

	let tree = extractField(from: commitData, fieldName: "tree") ?? ""
	let parent = extractField(from: commitData, fieldName: "parent")
	let author = extractField(from: commitData, fieldName: "author") ?? ""
	let committer = extractField(from: commitData, fieldName: "committer") ?? ""
	let message = extractMessage(from: commitData)
	let timestamp = extractTimestamp(from: author.isEmpty ? committer : author)

	return LogEntry(
		sha: commitSha,
		abbreviatedSha: String(commitSha.prefix(7)),
		tree: tree,
		parent: parent,
		author: formatAuthor(author.isEmpty ? committer : author),
		authorEmail: extractEmail(from: author.isEmpty ? committer : author),
		committer: formatAuthor(committer.isEmpty ? author : committer),
		date: Date(timeIntervalSince1970: TimeInterval(Int(timestamp) ?? 0)),
		message: message
	)
}

private func getFileBlobSha(
	gitDir: String, treeSha: String, filePath: String,
	treeCache: inout [String: String?], cache: PackfileCache
) async throws -> String? {
	if let cached = treeCache[treeSha] {
		return cached
	}

	let treeData = try await readObject(at: gitDir, sha: treeSha, cache: cache)
	let entries = try parseTreeEntries(treeData)

	let parts = filePath.split(separator: "/").map(String.init)
	guard var current = entries.first(where: { $0.path == parts[0] }) else {
		treeCache[treeSha] = nil
		return nil
	}

	for i in 1 ..< parts.count {
		guard current.type == .tree else {
			treeCache[treeSha] = nil
			return nil
		}

		let subTreeData = try await readObject(at: gitDir, sha: current.sha, cache: cache)
		let subEntries = try parseTreeEntries(subTreeData)

		guard let next = subEntries.first(where: { $0.path == parts[i] }) else {
			treeCache[treeSha] = nil
			return nil
		}
		current = next
	}

	treeCache[treeSha] = current.sha
	return current.sha
}

private func extractField(from commitData: String, fieldName: String) -> String? {
	var content = commitData
	if let nullIndex = content.firstIndex(of: "\0") {
		content = String(content[content.index(after: nullIndex)...])
	}

	let lines = content.components(separatedBy: .newlines)
	for line in lines {
		if line.starts(with: "\(fieldName) ") {
			return String(line.dropFirst(fieldName.count + 1))
		}
	}
	return nil
}

private func extractMessage(from commitData: String) -> String {
	guard let emptyLineRange = commitData.range(of: "\n\n") else {
		return ""
	}

	let messageStart = commitData.index(emptyLineRange.upperBound, offsetBy: 0)
	return String(commitData[messageStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func extractTimestamp(from author: String) -> String {
	let pattern = /(\d+)\s+[+-]\d{4}$/
	return author.firstMatch(of: pattern).map { String($0.1) } ?? ""
}

private func formatAuthor(_ author: String) -> String {
	let pattern = /^(.+?)\s+<[^>]+>/
	return author.firstMatch(of: pattern).map { String($0.1) } ?? author
}

private func extractEmail(from author: String) -> String {
	let pattern = /<([^>]+)>/
	return author.firstMatch(of: pattern).map { String($0.1) } ?? ""
}
