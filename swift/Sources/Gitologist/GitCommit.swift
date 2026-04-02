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
	// Create a flat tree (no subdirectories for now)
	var treeEntries: [(path: String, sha: String, mode: String)] = []
	
	for entry in index.values.sorted(by: { $0.path < $1.path }) {
		// Skip paths with subdirectories for now
		guard !entry.path.contains("/") else { continue }
		
		// Read file content and create blob
		let fullPath = URL(fileURLWithPath: rootPath).appendingPathComponent(entry.path)
		let content = try String(contentsOf: fullPath, encoding: .utf8)
		let blobSha = try await hashObject(at: gitDir, content: content, type: "blob")
		
		treeEntries.append((path: entry.path, sha: blobSha, mode: entry.mode))
	}
	
	// Build tree content - format: "<mode> blob <sha>\t<path>\0"
	var treeContent = ""
	for entry in treeEntries {
		treeContent += "\(entry.mode) blob \(entry.sha)\t\(entry.path)\u{0000}"
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
