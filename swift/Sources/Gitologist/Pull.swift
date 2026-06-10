import CryptoKit
import Foundation

enum PullError: Error, LocalizedError, Equatable {
	case notAGitRepository
	case remoteBranchDoesNotExist(String)
	case invalidCommitObject
	case invalidBlobObject
	case localChangesWouldBeOverwritten(String)

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
		case let .localChangesWouldBeOverwritten(path):
			return "Your local changes to '\(path)' would be overwritten by merge. Please commit or stash them."
		}
	}
}

func pull(at path: String, remote: String? = nil, branch: String? = nil, options: RemoteOptions? = nil) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
	let cache = PackfileCache()

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

	_ = try await fetchFromRemote(at: path, remote: remoteName, options: options)

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
	let currentCommitSha = try await getCurrentCommit(at: gitDir.path)

	guard let currentCommitSha = currentCommitSha else {
		try await updateBranch(at: gitDir.path, branchName: branchName, commitSha: remoteCommitSha)
		let commitData = try await readObject(at: gitDir.path, sha: remoteCommitSha, cache: cache)
		let treeSha = try extractTreeFromCommit(commitData)

		try await extractTreeToWorkingDirectory(gitDir: gitDir.path, workingPath: path, treeSha: treeSha, currentBlobs: [:], cache: cache)
		try await updateIndex(gitDir: gitDir.path, workingPath: path, treeSha: treeSha)
		return
	}

	guard currentCommitSha != remoteCommitSha else {
		return
	}

	let isAncestor = try await isAncestorOf(gitDir: gitDir.path, ancestorSha: currentCommitSha, descendantSha: remoteCommitSha, cache: cache)

	let currentTreeSha = try await getTree(gitDir: gitDir.path, sha: currentCommitSha, cache: cache)
	let currentBlobs = currentTreeSha != nil ? try await getTreeBlobs(gitDir: gitDir.path, treeSha: currentTreeSha!, cache: cache) : [:]

	if isAncestor {
		try await updateBranch(at: gitDir.path, branchName: branchName, commitSha: remoteCommitSha)
		let commitData = try await readObject(at: gitDir.path, sha: remoteCommitSha, cache: cache)
		let treeSha = try extractTreeFromCommit(commitData)

		try await checkForLocalChanges(gitDir: gitDir.path, workingPath: path, currentBlobs: currentBlobs, newTreeSha: treeSha, cache: cache)
		try await extractTreeToWorkingDirectory(gitDir: gitDir.path, workingPath: path, treeSha: treeSha, currentBlobs: currentBlobs, cache: cache)
		try await updateIndex(gitDir: gitDir.path, workingPath: path, treeSha: treeSha)
		return
	}

	let mergeBase = try await findMergeBase(gitDir: gitDir.path, sha1: currentCommitSha, sha2: remoteCommitSha, cache: cache)

	guard let mergeBase = mergeBase, mergeBase != remoteCommitSha else {
		return
	}

	let mergeCommitSha = try await createMergeCommit(
		gitDir: gitDir.path,
		parent1: currentCommitSha,
		parent2: remoteCommitSha,
		message: "Merge branch '\(branchName)' of \(remoteName)",
		cache: cache
	)

	try await updateBranch(at: gitDir.path, branchName: branchName, commitSha: mergeCommitSha)
	let commitData = try await readObject(at: gitDir.path, sha: mergeCommitSha, cache: cache)
	let treeSha = try extractTreeFromCommit(commitData)

	try await checkForLocalChanges(gitDir: gitDir.path, workingPath: path, currentBlobs: currentBlobs, newTreeSha: treeSha, cache: cache)
	try await extractTreeToWorkingDirectory(gitDir: gitDir.path, workingPath: path, treeSha: treeSha, currentBlobs: currentBlobs, cache: cache)
	try await updateIndex(gitDir: gitDir.path, workingPath: path, treeSha: treeSha)
}

private func getTreeBlobs(gitDir: String, treeSha: String, prefix: String = "", cache: PackfileCache) async throws -> [String: String] {
	var blobs: [String: String] = [:]
	let treeData = try await readObject(at: gitDir, sha: treeSha, cache: cache)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		let path = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"
		switch entry.type {
		case .blob:
			blobs[path] = entry.sha
		case .tree:
			let childBlobs = try await getTreeBlobs(gitDir: gitDir, treeSha: entry.sha, prefix: path, cache: cache)
			for (childPath, childSha) in childBlobs {
				blobs[childPath] = childSha
			}
		}
	}

	return blobs
}

private func checkForLocalChanges(gitDir: String, workingPath: String, currentBlobs: [String: String], newTreeSha: String, cache: PackfileCache) async throws {
	let indexPath = URL(fileURLWithPath: gitDir).appendingPathComponent("index")
	let index = try await getIndex(at: indexPath.path)
	let newBlobs = try await getTreeBlobs(gitDir: gitDir, treeSha: newTreeSha, cache: cache)

	for (path, newSha) in newBlobs {
		let currentSha = currentBlobs[path]

		// Only check files that will be updated (currentSha != newSha)
		if currentSha == newSha {
			continue
		}

		let fullPath = URL(fileURLWithPath: workingPath).appendingPathComponent(path).path
		guard FileManager.default.fileExists(atPath: fullPath), let indexEntry = index[path] else {
			continue
		}

		let currentHash = try await hashFileAsBlob(at: fullPath)
		if currentHash != indexEntry.sha {
			throw PullError.localChangesWouldBeOverwritten(path)
		}
	}
}

private func isAncestorOf(gitDir: String, ancestorSha: String, descendantSha: String, cache: PackfileCache) async throws -> Bool {
	var visited = Set<String>()
	var queue = [descendantSha]

	while !queue.isEmpty {
		let current = queue.removeFirst()

		if current == ancestorSha {
			return true
		}

		if visited.contains(current) {
			continue
		}
		visited.insert(current)

		let parents = try await getParents(gitDir: gitDir, sha: current, cache: cache)
		queue.append(contentsOf: parents)
	}

	return false
}

private func findMergeBase(gitDir: String, sha1: String, sha2: String, cache: PackfileCache) async throws -> String? {
	if sha1 == sha2 {
		return sha1
	}

	let ancestors1 = try await getAllAncestors(gitDir: gitDir, sha: sha1, cache: cache)
	let ancestors2 = try await getAllAncestors(gitDir: gitDir, sha: sha2, cache: cache)

	var allAncestors1 = ancestors1
	allAncestors1.insert(sha1)

	var allAncestors2 = ancestors2
	allAncestors2.insert(sha2)

	for ancestor in allAncestors1 {
		if allAncestors2.contains(ancestor) {
			return ancestor
		}
	}

	return nil
}

private func getAllAncestors(gitDir: String, sha: String, cache: PackfileCache) async throws -> Set<String> {
	var ancestors = Set<String>()
	var queue = [sha]

	while !queue.isEmpty {
		let current = queue.removeFirst()

		if ancestors.contains(current) {
			continue
		}

		let parents = try await getParents(gitDir: gitDir, sha: current, cache: cache)
		for parent in parents {
			ancestors.insert(parent)
			queue.append(parent)
		}
	}

	return ancestors
}

private func getParents(gitDir: String, sha: String, cache: PackfileCache) async throws -> [String] {
	do {
		let commitData = try await readObject(at: gitDir, sha: sha, cache: cache)
		var parents: [String] = []
		let lines = commitData.components(separatedBy: .newlines)

		for line in lines {
			if line.starts(with: "parent ") {
				parents.append(String(line.dropFirst(7)))
			}
		}

		return parents
	} catch {
		return []
	}
}

private func getTree(gitDir: String, sha: String, cache: PackfileCache) async throws -> String? {
	do {
		let commitData = try await readObject(at: gitDir, sha: sha, cache: cache)
		guard let nullIndex = commitData.firstIndex(of: "\0") else {
			return nil
		}
		let contentIndex = commitData.index(after: nullIndex)
		guard contentIndex < commitData.endIndex else {
			return nil
		}
		let content = String(commitData[contentIndex...])

		let lines = content.components(separatedBy: .newlines)
		for line in lines {
			if line.starts(with: "tree ") {
				return String(line.dropFirst(5))
			}
		}
		return nil
	} catch {
		return nil
	}
}

private func createMergeCommit(gitDir: String, parent1: String, parent2: String, message: String, cache: PackfileCache) async throws -> String {
	guard let treeSha = try await getTree(gitDir: gitDir, sha: parent1, cache: cache) else {
		throw PullError.invalidCommitObject
	}

	let now = Date()
	let timestamp = Int(now.timeIntervalSince1970)
	let offset = TimeZone.current.secondsFromGMT()
	let hours = abs(offset) / 3600
	let minutes = (abs(offset) % 3600) / 60
	let sign = offset >= 0 ? "+" : "-"

	let author = String(format: "User <user@example.com> %d %@%02d%02d", timestamp, sign, hours, minutes)

	var commitContent = "tree \(treeSha)\n"
	commitContent += "parent \(parent1)\n"
	commitContent += "parent \(parent2)\n"
	commitContent += "author \(author)\n"
	commitContent += "committer \(author)\n"
	commitContent += "\n\(message)\n"

	return try await hashObject(at: gitDir, content: commitContent, type: "commit")
}

private func extractTreeToWorkingDirectory(gitDir: String, workingPath: String, treeSha: String, currentBlobs: [String: String], cache: PackfileCache) async throws {
	try await extractTreeRecursive(gitDir: gitDir, workingPath: workingPath, treeSha: treeSha, prefix: "", currentBlobs: currentBlobs, cache: cache)
}

private func extractTreeRecursive(gitDir: String, workingPath: String, treeSha: String, prefix: String, currentBlobs: [String: String], cache: PackfileCache) async throws {
	let treeData = try await readObject(at: gitDir, sha: treeSha, cache: cache)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		let entryPath: String
		if prefix.isEmpty {
			entryPath = URL(fileURLWithPath: workingPath).appendingPathComponent(entry.path).path
		} else {
			let prefixPath = URL(fileURLWithPath: workingPath).appendingPathComponent(prefix)
			entryPath = prefixPath.appendingPathComponent(entry.path).path
		}

		let path = prefix.isEmpty ? entry.path : "\(prefix)/\(entry.path)"

		switch entry.type {
		case .blob:
			if currentBlobs[path] == entry.sha {
				continue
			}
			let blobData = try await readObject(at: gitDir, sha: entry.sha, cache: cache)
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
				prefix: newPrefix,
				currentBlobs: currentBlobs,
				cache: cache
			)
		}
	}
}

func updateIndex(gitDir: String, workingPath _: String, treeSha: String) async throws {
	let indexPath = URL(fileURLWithPath: gitDir).appendingPathComponent("index")
	let cache = PackfileCache()
	var index = try await getIndex(at: indexPath.path)

	index.removeAll()

	index = try await updateIndexRecursive(gitDir: gitDir, treeSha: treeSha, prefix: "", index: index, cache: cache)

	try await writeIndex(at: indexPath.path, index: index)
}

private func updateIndexRecursive(
	gitDir: String,
	treeSha: String,
	prefix: String,
	index: [String: IndexEntry],
	cache: PackfileCache
) async throws -> [String: IndexEntry] {
	let treeData = try await readObject(at: gitDir, sha: treeSha, cache: cache)
	let entries = try parseTreeEntries(treeData)
	var newIndex = index

	for entry in entries {
		switch entry.type {
		case .blob:
			let blobData = try await readObject(at: gitDir, sha: entry.sha, cache: cache)
			let fileContent = try extractContentFromBlob(blobData)
			// Use git blob hash format (with "blob <size>\0" header)
			let blobHeader = "blob \(fileContent.utf8.count)\0\(fileContent)"
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
				index: newIndex,
				cache: cache
			)
		}
	}

	return newIndex
}
