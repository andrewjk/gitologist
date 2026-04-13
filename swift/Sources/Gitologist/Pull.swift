import CryptoKit
import Foundation

enum PullError: Error, LocalizedError {
	case notAGitRepository
	case remoteBranchDoesNotExist(String)
	case invalidCommitObject
	case invalidBlobObject

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .remoteBranchDoesNotExist(branch):
			return "Remote branch '\(branch)' does not exist"
		case .invalidCommitObject:
			return "Invalid commit object"
		case .invalidBlobObject:
			return "Invalid blob object"
		}
	}
}

func pull(at path: String, remote: String? = nil, branch: String? = nil) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw PullError.notAGitRepository
	}

	let remoteName = remote ?? "origin"
	let branchName: String

	if let customBranch = branch {
		branchName = customBranch
	} else {
		branchName = try await getCurrentBranch(at: gitDir.path)
	}

	_ = try await fetchFromRemote(at: path, remote: remoteName)

	let remoteBranchPath = gitDir
		.appendingPathComponent("refs")
		.appendingPathComponent("remotes")
		.appendingPathComponent(remoteName)
		.appendingPathComponent(branchName)

	guard FileManager.default.fileExists(atPath: remoteBranchPath.path) else {
		throw PullError.remoteBranchDoesNotExist("\(remoteName)/\(branchName)")
	}

	let remoteCommitSha = try String(contentsOf: remoteBranchPath, encoding: .utf8)
		.trimmingCharacters(in: .whitespacesAndNewlines)

	let localBranchPath = gitDir
		.appendingPathComponent("refs")
		.appendingPathComponent("heads")
		.appendingPathComponent(branchName)

	try FileManager.default.createDirectory(
		at: localBranchPath.deletingLastPathComponent(),
		withIntermediateDirectories: true
	)

	try "\(remoteCommitSha)\n".write(to: localBranchPath, atomically: true, encoding: .utf8)

	let commitData = try await readObject(at: gitDir.path, sha: remoteCommitSha)
	let treeSha = try extractTreeFromCommit(commitData)

	try await extractTreeToWorkingDirectory(gitDir: gitDir.path, workingPath: path, treeSha: treeSha)
	try await updateIndex(gitDir: gitDir.path, workingPath: path, treeSha: treeSha)
}

private func extractTreeToWorkingDirectory(gitDir: String, workingPath: String, treeSha: String) async throws {
	try await extractTreeRecursive(gitDir: gitDir, workingPath: workingPath, treeSha: treeSha, prefix: "")
}

private func extractTreeRecursive(gitDir: String, workingPath: String, treeSha: String, prefix: String) async throws {
	let treeData = try await readObject(at: gitDir, sha: treeSha)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		let entryPath: String
		if prefix.isEmpty {
			entryPath = URL(fileURLWithPath: workingPath).appendingPathComponent(entry.path).path
		} else {
			let prefixPath = URL(fileURLWithPath: workingPath).appendingPathComponent(prefix)
			entryPath = prefixPath.appendingPathComponent(entry.path).path
		}

		switch entry.type {
		case .blob:
			let blobData = try await readObject(at: gitDir, sha: entry.sha)
			let content = try extractContentFromBlob(blobData)
			try content.write(toFile: entryPath, atomically: true, encoding: .utf8)

		case .tree:
			if !FileManager.default.fileExists(atPath: entryPath) {
				try FileManager.default.createDirectory(
					atPath: entryPath,
					withIntermediateDirectories: true
				)
			}
			let newPrefix = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"
			try await extractTreeRecursive(
				gitDir: gitDir,
				workingPath: workingPath,
				treeSha: entry.sha,
				prefix: newPrefix
			)
		}
	}
}

private func updateIndex(gitDir: String, workingPath _: String, treeSha: String) async throws {
	let indexPath = URL(fileURLWithPath: gitDir).appendingPathComponent("index")
	var index = try await getIndex(at: indexPath.path)

	// Clear existing index and rebuild from tree
	index.removeAll()

	index = try await updateIndexRecursive(gitDir: gitDir, treeSha: treeSha, prefix: "", index: index)

	try await writeIndex(at: indexPath.path, index: index)
}

private func updateIndexRecursive(
	gitDir: String,
	treeSha: String,
	prefix: String,
	index: [String: IndexEntry]
) async throws -> [String: IndexEntry] {
	let treeData = try await readObject(at: gitDir, sha: treeSha)
	let entries = try parseTreeEntries(treeData)
	var newIndex = index

	for entry in entries {
		switch entry.type {
		case .blob:
			let blobData = try await readObject(at: gitDir, sha: entry.sha)
			let fileContent = try extractContentFromBlob(blobData)
			// Use git blob hash format (with "blob <size>\0" header)
			let blobHeader = "blob \(fileContent.count)\0\(fileContent)"
			let sha = Insecure.SHA1.hash(data: Data(blobHeader.utf8))
				.compactMap { String(format: "%02x", $0) }
				.joined()
			let path = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"
			newIndex[path] = IndexEntry(
				path: path,
				sha: sha,
				mode: entry.mode,
				size: UInt32(fileContent.utf8.count),
				ctimeSeconds: 0,
				ctimeNanos: 0,
				mtimeSeconds: 0,
				mtimeNanos: 0,
				dev: 0,
				ino: 0,
				uid: 0,
				gid: 0
			)

		case .tree:
			let newPrefix = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"
			newIndex = try await updateIndexRecursive(
				gitDir: gitDir,
				treeSha: entry.sha,
				prefix: newPrefix,
				index: newIndex
			)
		}
	}

	return newIndex
}
