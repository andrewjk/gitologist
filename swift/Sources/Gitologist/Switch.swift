import Foundation

public enum SwitchError: Error, LocalizedError {
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

public func switchBranch(at path: String, to branchName: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw SwitchError.notAGitRepository
	}

	let cache = PackfileCache()

	// 1. Local branch exists: check out its tree, then point HEAD at it.
	let localBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)
	if FileManager.default.fileExists(atPath: localBranchPath.path) {
		let commitSha = try String(contentsOf: localBranchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

		// Check out the tree first (uses the current HEAD as the baseline for
		// change detection); only move HEAD once the checkout succeeds.
		try await checkoutTree(gitDir: gitDir.path, workingPath: path, commitSha: commitSha, cache: cache)

		let headFile = gitDir.appendingPathComponent("HEAD")
		try "ref: refs/heads/\(branchName)\n".write(to: headFile, atomically: true, encoding: .utf8)
		return
	}

	// 2. DWIM: no local branch, but exactly one remote tracking branch exists.
	if let (remoteName, commitSha) = try findRemoteBranch(gitDir: gitDir.path, branchName: branchName) {
		try await updateBranch(at: gitDir.path, branchName: branchName, commitSha: commitSha)
		try await setUpstreamBranch(at: path, remoteName: remoteName, branchName: branchName)

		try await checkoutTree(gitDir: gitDir.path, workingPath: path, commitSha: commitSha, cache: cache)

		let headFile = gitDir.appendingPathComponent("HEAD")
		try "ref: refs/heads/\(branchName)\n".write(to: headFile, atomically: true, encoding: .utf8)
		return
	}

	// 3. No local branch and zero (or multiple) matching remotes.
	throw SwitchError.branchNotFound(branchName)
}

/// Finds a single remote that has `refs/remotes/<remote>/<branchName>`.
/// Returns `(remoteName, commitSha)` when exactly one match exists, otherwise nil.
private func findRemoteBranch(gitDir: String, branchName: String) throws -> (remoteName: String, commitSha: String)? {
	let remotesDir = URL(fileURLWithPath: gitDir).appendingPathComponent("refs").appendingPathComponent("remotes")

	guard FileManager.default.fileExists(atPath: remotesDir.path) else {
		return nil
	}

	let remoteDirs = try FileManager.default.contentsOfDirectory(at: remotesDir, includingPropertiesForKeys: nil)
	var match: (remoteName: String, commitSha: String)?
	var matchCount = 0

	for remoteDir in remoteDirs {
		let branchRef = remoteDir.appendingPathComponent(branchName)
		guard FileManager.default.fileExists(atPath: branchRef.path) else {
			continue
		}
		let sha = try String(contentsOf: branchRef, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
		match = (remoteDir.lastPathComponent, sha)
		matchCount += 1
	}

	return matchCount == 1 ? match : nil
}
