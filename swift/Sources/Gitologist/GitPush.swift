import Foundation

enum PushError: Error, LocalizedError {
	case notAGitRepository
	case localBranchDoesNotExist(String)
	case uncommittedChanges

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case .localBranchDoesNotExist(let branch):
			return "Local branch '\(branch)' does not exist"
		case .uncommittedChanges:
			return "You have uncommitted changes. Commit or stash them before pushing."
		}
	}
}

func push(at path: String, remote: String? = nil, branch: String? = nil) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw PushError.notAGitRepository
	}

	let remoteName = remote ?? "origin"
	let branchName: String

	if let customBranch = branch {
		branchName = customBranch
	} else {
		branchName = try await getCurrentBranch(at: gitDir.path)
	}

	let localBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)

	guard FileManager.default.fileExists(atPath: localBranchPath.path) else {
		throw PushError.localBranchDoesNotExist(branchName)
	}

	let currentStatus = try await status(at: path)

	guard currentStatus.modified.isEmpty && currentStatus.untracked.isEmpty else {
		throw PushError.uncommittedChanges
	}

	let commitSha = try String(contentsOf: localBranchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let remoteBranchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent(remoteName).appendingPathComponent(branchName)
	try FileManager.default.createDirectory(at: remoteBranchPath.deletingLastPathComponent(), withIntermediateDirectories: true)

	try "\(commitSha)\n".write(to: remoteBranchPath, atomically: true, encoding: .utf8)
}
