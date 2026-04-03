import Foundation

enum CommitError: Error, LocalizedError {
	case nothingToCommit
	case noFilesStaged
	case notAGitRepository

	var errorDescription: String? {
		switch self {
		case .nothingToCommit:
			return "Nothing to commit"
		case .noFilesStaged:
			return "No files staged"
		case .notAGitRepository:
			return "Not a git repository"
		}
	}
}

func commit(at path: String, message: String) async throws -> String {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw CommitError.notAGitRepository
	}

	let currentStatus = try await status(at: path)

	if currentStatus.staged.isEmpty && currentStatus.modified.isEmpty && currentStatus.untracked.isEmpty {
		throw CommitError.nothingToCommit
	}

	let indexPath = gitDir.appendingPathComponent("index")
	let index = try await getIndex(at: indexPath.path)

	guard !index.isEmpty else {
		throw CommitError.noFilesStaged
	}

	let treeSha = try await createTree(at: path, gitDir: gitDir.path, index: index)
	let parentSha = try await getCurrentCommit(at: gitDir.path)
	let commitSha = try await createCommit(at: gitDir.path, treeSha: treeSha, message: message, parentSha: parentSha)

	let branchName = try await getCurrentBranch(at: gitDir.path)
	try await updateBranch(at: gitDir.path, branchName: branchName, commitSha: commitSha)

	return commitSha
}

private func createTree(at rootPath: String, gitDir: String, index: [String: IndexEntry]) async throws -> String {
	return try await createTreeRecursive(at: rootPath, gitDir: gitDir, index: index, prefix: "")
}

private func createTreeRecursive(at rootPath: String, gitDir: String, index: [String: IndexEntry], prefix: String) async throws -> String {
	var treeEntries: [(path: String, sha: String, mode: String, type: TreeEntryType)] = []

	// Get paths at this level
	let paths = index.keys.filter { path in
		if prefix.isEmpty {
			return !path.contains("/")
		}
		if path.hasPrefix(prefix + "/") {
			let remaining = path.dropFirst(prefix.count + 1)
			return !remaining.contains("/")
		}
		return false
	}.sorted()

	// Add blobs (files) at this level
	for path in paths {
		guard let entry = index[path] else { continue }
		let fullPath = URL(fileURLWithPath: rootPath).appendingPathComponent(path)
		let content = try String(contentsOf: fullPath, encoding: .utf8)
		let blobSha = try await hashObject(at: gitDir, content: content, type: "blob")
		let fileName = prefix.isEmpty ? path : String(path.dropFirst(prefix.count + 1))
		treeEntries.append((path: fileName, sha: blobSha, mode: entry.mode, type: .blob))
	}

	// Find subdirectories
	var subdirs = Set<String>()
	for path in index.keys {
		if path.contains("/") {
			let parts = path.split(separator: "/")
			if prefix.isEmpty {
				subdirs.insert(String(parts[0]))
			} else if path.hasPrefix(prefix + "/") {
				let remaining = path.dropFirst(prefix.count + 1)
				if remaining.contains("/") {
					let subparts = remaining.split(separator: "/")
					subdirs.insert(String(subparts[0]))
				}
			}
		}
	}

	// Add trees (directories)
	for dir in subdirs.sorted() {
		let dirPrefix = prefix.isEmpty ? dir : "\(prefix)/\(dir)"
		let dirSha = try await createTreeRecursive(at: rootPath, gitDir: gitDir, index: index, prefix: dirPrefix)
		treeEntries.append((path: dir, sha: dirSha, mode: "040000", type: .tree))
	}

	// Build tree content - format: "<mode> <type> <sha>\t<path>\0"
	var treeContent = ""
	for entry in treeEntries {
		treeContent += "\(entry.mode) \(entry.type == .blob ? "blob" : "tree") \(entry.sha)\t\(entry.path)\u{0000}"
	}

	return try await hashObject(at: gitDir, content: treeContent, type: "tree")
}

private func createCommit(at gitDir: String, treeSha: String, message: String, parentSha: String?) async throws -> String {
	let now = Date()
	let timestamp = Int(now.timeIntervalSince1970)
	let offset = TimeZone.current.secondsFromGMT()
	let hours = abs(offset) / 3600
	let minutes = (abs(offset) % 3600) / 60
	let sign = offset >= 0 ? "+" : "-"

	let author = String(format: "User <user@example.com> %d %@%02d%02d", timestamp, sign as CVarArg, hours, minutes)

	var commitContent = "tree \(treeSha)\n"
	if let parentSha = parentSha {
		commitContent += "parent \(parentSha)\n"
	}
	commitContent += "author \(author)\n"
	commitContent += "committer \(author)\n"
	commitContent += "\n\(message)\n"

	return try await hashObject(at: gitDir, content: commitContent, type: "commit")
}
