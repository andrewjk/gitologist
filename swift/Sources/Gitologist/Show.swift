import Foundation

public enum ShowError: Error, LocalizedError, Equatable {
	case notAGitRepository
	case pathNotFound(String)
	case commitNotFound(String)

	public var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .pathNotFound(path):
			return "Path '\(path)' does not exist in 'HEAD'"
		case let .commitNotFound(commit):
			return "Commit '\(commit)' not found"
		}
	}
}

public func show(at path: String, filePath: String, commit: String? = nil) async throws -> String {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw ShowError.notAGitRepository
	}

	let commitSha: String
	if let commit {
		commitSha = commit
	} else {
		guard let headSha = try await getCurrentCommit(at: gitDir.path) else {
			throw ShowError.pathNotFound(filePath)
		}
		commitSha = headSha
	}

	let cache = PackfileCache()

	let commitData: String
	if commit != nil {
		guard let data = try? await readObject(at: gitDir.path, sha: commitSha, cache: cache),
		      data.hasPrefix("commit ")
		else {
			throw ShowError.commitNotFound(commitSha)
		}
		commitData = data
	} else {
		commitData = try await readObject(at: gitDir.path, sha: commitSha, cache: cache)
	}

	let treeSha = try extractTreeFromCommit(commitData)

	guard let blobSha = try await resolveBlobSha(
		gitDir: gitDir.path, treeSha: treeSha, filePath: filePath, cache: cache
	) else {
		throw ShowError.pathNotFound(filePath)
	}

	let blobData = try await readObject(at: gitDir.path, sha: blobSha, cache: cache)
	return try extractContentFromBlob(blobData)
}

private func resolveBlobSha(
	gitDir: String, treeSha: String, filePath: String, cache: PackfileCache
) async throws -> String? {
	let parts = filePath.split(separator: "/").map(String.init)
	var currentSha = treeSha

	for i in 0 ..< parts.count {
		let isLast = i == parts.count - 1
		let treeData = try await readObject(at: gitDir, sha: currentSha, cache: cache)
		let entries = try parseTreeEntries(treeData)

		guard let entry = entries.first(where: { $0.path == parts[i] }) else {
			return nil
		}

		if isLast {
			return entry.type == .blob ? entry.sha : nil
		}

		guard entry.type == .tree else {
			return nil
		}

		currentSha = entry.sha
	}

	return nil
}
