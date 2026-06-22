import Foundation

public enum RestoreError: Error, LocalizedError {
	case notAGitRepository
	case fileNotFound(String)
	case fileNotInCommit(String)

	public var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .fileNotFound(file):
			return "File not found: \(file)"
		case let .fileNotInCommit(file):
			return "File not in commit: \(file)"
		}
	}
}

public func restore(at path: String, files: [String]) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw RestoreError.notAGitRepository
	}

	for file in files {
		let filePath = URL(fileURLWithPath: path).appendingPathComponent(file)

		guard FileManager.default.fileExists(atPath: filePath.path) else {
			throw RestoreError.fileNotFound(file)
		}
	}

	let branchPath = gitDir.appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main")
	let commitSha = try String(contentsOf: branchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let cache = PackfileCache()

	let commitData = try await readObject(at: gitDir.path, sha: commitSha, cache: cache)
	let treeSha = try extractTreeFromCommit(commitData)

	for file in files {
		guard let blobSha = try await findBlobInTree(at: gitDir.path, treeSha: treeSha, filePath: file, cache: cache) else {
			throw RestoreError.fileNotInCommit(file)
		}

		let blobData = try await readObject(at: gitDir.path, sha: blobSha, cache: cache)
		let content = try extractContentFromBlob(blobData)
		let filePath = URL(fileURLWithPath: path).appendingPathComponent(file)
		try content.write(to: filePath, atomically: true, encoding: .utf8)
	}
}

public func restoreAll(at path: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw RestoreError.notAGitRepository
	}

	let currentStatus = try await status(at: path)
	let filesToRestore = currentStatus.modified

	guard !filesToRestore.isEmpty else {
		return
	}

	try await restore(at: path, files: filesToRestore)
}

private func findBlobInTree(at gitDir: String, treeSha: String, filePath: String, cache: PackfileCache) async throws -> String? {
	let parts = filePath.components(separatedBy: "/")
	guard let name = parts.first else { return nil }
	let rest = Array(parts.dropFirst())

	let treeData = try await readObject(at: gitDir, sha: treeSha, cache: cache)
	let entries = try parseTreeEntries(treeData)

	for entry in entries {
		if entry.path == name {
			if entry.type == .blob {
				return rest.isEmpty ? entry.sha : nil
			}
			if entry.type == .tree {
				guard !rest.isEmpty else { return nil }
				return try await findBlobInTree(at: gitDir, treeSha: entry.sha, filePath: rest.joined(separator: "/"), cache: cache)
			}
		}
	}

	return nil
}
