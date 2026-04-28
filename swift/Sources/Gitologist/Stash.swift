import Foundation

enum StashError: Error, LocalizedError {
	case nothingToStash
	case headNotFound
	case notAGitRepository

	var errorDescription: String? {
		switch self {
		case .nothingToStash:
			return "Nothing to stash"
		case .headNotFound:
			return "HEAD not found"
		case .notAGitRepository:
			return "Not a git repository"
		}
	}
}

func stash(at path: String, message: String = "WIP") async throws -> String {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw StashError.notAGitRepository
	}

	let currentStatus = try await status(at: path)

	let headCommitSha = try await getCurrentCommit(at: gitDir.path)
	guard let headCommitSha = headCommitSha else {
		throw StashError.headNotFound
	}

	let indexPath = gitDir.appendingPathComponent("index")
	var index = try await getIndex(at: indexPath.path)

	let headCommitData = try await readObject(at: gitDir.path, sha: headCommitSha)
	let headTreeSha = try extractTreeFromCommit(headCommitData)
	var headTreeEntries: [String: String] = [:]

	let headEntries = try parseTreeEntries(await readObject(at: gitDir.path, sha: headTreeSha))
	for entry in headEntries {
		headTreeEntries[entry.path] = entry.sha
	}

	var hasStagedChanges = false

	for (filePath, entry) in index {
		let headSha = headTreeEntries[filePath]
		if headSha != entry.sha {
			hasStagedChanges = true
			break
		}
	}

	if !hasStagedChanges && currentStatus.modified.isEmpty && currentStatus.untracked.isEmpty && currentStatus.deleted.isEmpty {
		throw StashError.nothingToStash
	}

	for file in currentStatus.modified {
		try await stageFile(at: path, gitDir: gitDir.path, filePath: file, index: &index)
	}

	for file in currentStatus.untracked {
		try await stageFile(at: path, gitDir: gitDir.path, filePath: file, index: &index)
	}

	for file in currentStatus.deleted {
		index.removeValue(forKey: file)
	}

	let treeSha = try await createTree(at: path, gitDir: gitDir.path, index: index)
	let stashCommitSha = try await createCommit(at: gitDir.path, treeSha: treeSha, message: message, parentSha: headCommitSha)

	let stashRefPath = gitDir.appendingPathComponent("refs").appendingPathComponent("stash")
	try FileManager.default.createDirectory(at: stashRefPath.deletingLastPathComponent(), withIntermediateDirectories: true)
	try "\(stashCommitSha)\n".write(to: stashRefPath, atomically: true, encoding: .utf8)

	try await resetHard(at: path, gitDir: gitDir.path, commitSha: headCommitSha)

	return stashCommitSha
}

private func stageFile(at repoPath: String, gitDir: String, filePath: String, index: inout [String: IndexEntry]) async throws {
	let fullPath = URL(fileURLWithPath: repoPath).appendingPathComponent(filePath)
	let content = try String(contentsOf: fullPath, encoding: .utf8)
	let hash = try await hashObject(at: gitDir, content: content, type: "blob")
	let attributes = try FileManager.default.attributesOfItem(atPath: fullPath.path)

	let fileSize = attributes[.size] as? UInt32 ?? 0
	let ctime = attributes[.creationDate] as? Date ?? Date()
	let mtime = attributes[.modificationDate] as? Date ?? Date()

	index[filePath] = IndexEntry(
		path: filePath,
		sha: hash,
		mode: "100644",
		size: fileSize,
		ctimeSeconds: UInt32(ctime.timeIntervalSince1970),
		ctimeNanos: 0,
		mtimeSeconds: UInt32(mtime.timeIntervalSince1970),
		mtimeNanos: 0,
		dev: 0,
		ino: 0,
		uid: 0,
		gid: 0
	)
}

private func resetHard(at path: String, gitDir: String, commitSha: String) async throws {
	let commitData = try await readObject(at: gitDir, sha: commitSha)
	let treeSha = try extractTreeFromCommit(commitData)

	let entries = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: path), includingPropertiesForKeys: nil)

	for entry in entries {
		if entry.lastPathComponent == ".git" { continue }

		try? FileManager.default.removeItem(at: entry)
	}

	try await restoreTree(at: path, gitDir: gitDir, treeSha: treeSha, prefix: "")

	try await updateIndex(gitDir: gitDir, workingPath: path, treeSha: treeSha)
}

private func restoreTree(at path: String, gitDir: String, treeSha: String, prefix: String) async throws {
	let treeData = try await readObject(at: gitDir, sha: treeSha)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		let entryPath = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"

		if entry.type == .blob {
			let blobData = try await readObject(at: gitDir, sha: entry.sha)
			let content = try extractContentFromBlob(blobData)
			let fullPath = URL(fileURLWithPath: path).appendingPathComponent(entryPath)
			try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
			try content.write(to: fullPath, atomically: true, encoding: .utf8)
		} else if entry.type == .tree {
			try await restoreTree(at: path, gitDir: gitDir, treeSha: entry.sha, prefix: entryPath)
		}
	}
}
