import Foundation

enum SwitchError: Error, LocalizedError {
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

func switchBranch(at path: String, to branchName: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw SwitchError.notAGitRepository
	}

	let branchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)
	guard FileManager.default.fileExists(atPath: branchPath.path) else {
		throw SwitchError.branchNotFound(branchName)
	}

	let headFile = gitDir.appendingPathComponent("HEAD")
	try "ref: refs/heads/\(branchName)\n".write(to: headFile, atomically: true, encoding: .utf8)
}
