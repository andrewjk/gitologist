import Foundation

public enum MergeError: Error, LocalizedError {
	case notAGitRepository
	case cannotMergeIntoSelf
	case branchNotFound(String)
	case cannotMergeIntoEmptyBranch
	case couldNotGetTree

	public var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case .cannotMergeIntoSelf:
			return "Cannot merge a branch into itself"
		case let .branchNotFound(branch):
			return "Branch '\(branch)' not found"
		case .cannotMergeIntoEmptyBranch:
			return "Cannot merge into an empty branch"
		case .couldNotGetTree:
			return "Could not get tree for merge commit"
		}
	}
}

public func merge(at path: String, branchName: String, options: MergeOptions? = nil) async throws -> MergeResult {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw MergeError.notAGitRepository
	}

	let currentBranch = try await getCurrentBranch(at: gitDir.path)
	if currentBranch == branchName {
		throw MergeError.cannotMergeIntoSelf
	}

	let currentSha = try await getCurrentCommit(at: gitDir.path)
	let branchSha = try await getBranchCommit(at: gitDir.path, branchName: branchName)

	guard let branchSha = branchSha else {
		throw MergeError.branchNotFound(branchName)
	}

	guard let currentSha = currentSha else {
		throw MergeError.cannotMergeIntoEmptyBranch
	}

	if currentSha == branchSha {
		return MergeResult(
			success: true,
			fastForward: false,
			commitSha: nil,
			message: "Already up to date."
		)
	}

	let cache = PackfileCache()

	let isAncestor = try await isAncestorOf(gitDir: gitDir.path, ancestorSha: currentSha, descendantSha: branchSha, cache: cache)

	if isAncestor && !(options?.noFastForward ?? false) {
		try await updateBranch(at: gitDir.path, branchName: currentBranch, commitSha: branchSha)
		return MergeResult(
			success: true,
			fastForward: true,
			commitSha: branchSha,
			message: "Fast-forward merge of '\(branchName)' into '\(currentBranch)'"
		)
	}

	let mergeBase = try await findMergeBase(gitDir: gitDir.path, sha1: currentSha, sha2: branchSha, cache: cache)

	if mergeBase == branchSha {
		return MergeResult(
			success: true,
			fastForward: false,
			commitSha: nil,
			message: "Already up to date."
		)
	}

	let mergeMessage = options?.message ?? "Merge branch '\(branchName)' into '\(currentBranch)'"

	let mergeCommitSha = try await createMergeCommit(gitDir: gitDir.path, parent1: currentSha, parent2: branchSha, message: mergeMessage, cache: cache)

	try await updateBranch(at: gitDir.path, branchName: currentBranch, commitSha: mergeCommitSha)

	return MergeResult(
		success: true,
		fastForward: false,
		commitSha: mergeCommitSha,
		message: mergeMessage
	)
}

private func getBranchCommit(at gitDir: String, branchName: String) async throws -> String? {
	let branchPath = URL(fileURLWithPath: gitDir)
		.appendingPathComponent("refs")
		.appendingPathComponent("heads")
		.appendingPathComponent(branchName)

	guard FileManager.default.fileExists(atPath: branchPath.path) else {
		return nil
	}

	return try String(contentsOf: branchPath, encoding: .utf8)
		.trimmingCharacters(in: .whitespacesAndNewlines)
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
		// The commit data includes a header like "commit <size>\0", so we need to skip past the null byte
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
		throw MergeError.couldNotGetTree
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
