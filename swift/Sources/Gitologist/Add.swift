import Foundation

enum AddError: Error, LocalizedError {
	case fileNotFound(String)
	case notAGitRepository

	var errorDescription: String? {
		switch self {
		case let .fileNotFound(file):
			return "File not found: \(file)"
		case .notAGitRepository:
			return "Not a git repository"
		}
	}
}

func add(at path: String, files: [String]) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw AddError.notAGitRepository
	}

	// Load gitignore patterns
	let gitignore = IgnoreParser()
	await gitignore.loadGitignore(repoPath: path)

	let indexPath = gitDir.appendingPathComponent("index")
	var index = try await getIndex(at: indexPath.path)

	for file in files {
		let fullPath = URL(fileURLWithPath: path).appendingPathComponent(file)

		guard FileManager.default.fileExists(atPath: fullPath.path) else {
			throw AddError.fileNotFound(file)
		}

		// Skip ignored files
		if await gitignore.isIgnored(filePath: file) {
			continue
		}

		let hash = try await hashFile(at: fullPath.path)

		index[file] = IndexEntry(path: file, sha: hash, mode: "100644")
	}

	try await writeIndex(at: indexPath.path, index: index)
}

func addAll(at path: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw AddError.notAGitRepository
	}

	let currentStatus = try await status(at: path)
	let filesToAdd = currentStatus.untracked + currentStatus.modified

	guard !filesToAdd.isEmpty else {
		return
	}

	try await add(at: path, files: filesToAdd)
}
