import Foundation

enum LogError: Error, LocalizedError {
	case notAGitRepository
	case branchNotFound(String)

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .branchNotFound(branch):
			return "Branch '\(branch)' not found"
		}
	}
}

func log(at path: String, options: LogOptions? = nil) async throws -> [LogEntry] {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

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

	while let sha = currentSha, entries.count < limit {
		let entry = try await parseCommitEntry(gitDir: gitDir.path, commitSha: sha)
		entries.append(entry)
		currentSha = entry.parent
	}

	return entries
}

private func parseCommitEntry(gitDir: String, commitSha: String) async throws -> LogEntry {
	let commitData = try await readObject(at: gitDir, sha: commitSha)

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
		committer: formatAuthor(committer.isEmpty ? author : committer),
		date: timestamp,
		message: message
	)
}

private func extractField(from commitData: String, fieldName: String) -> String? {
	let lines = commitData.components(separatedBy: .newlines)
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

private func extractTimestamp(from author: String) -> Date {
	// Match pattern: digits followed by timezone offset (e.g., "1234567890 +0000")
	let pattern = /(\d+)\s+([+-]\d{4})$/
	guard let match = author.wholeMatch(of: pattern) else {
		return Date()
	}

	guard let timestamp = Int(match.1) else {
		return Date()
	}

	return Date(timeIntervalSince1970: TimeInterval(timestamp))
}

private func formatAuthor(_ author: String) -> String {
	// Match pattern: Name <email> timestamp timezone
	let pattern = /^(.+?)\s+(<[^>]+>)\s+\d+/
	guard let match = author.wholeMatch(of: pattern) else {
		return author.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
}
