import Foundation

enum GitError: Error, LocalizedError {
	case notAGitRepository
	case invalidIndexFile(String)
	case fileReadError(String)
	case notOnABranch

	var errorDescription: String? {
		switch self {
		case .notAGitRepository:
			return "Not a git repository"
		case let .invalidIndexFile(message):
			return "Invalid index file: \(message)"
		case let .fileReadError(message):
			return "File read error: \(message)"
		case .notOnABranch:
			return "Not on a branch (detached HEAD)"
		}
	}
}

func status(at path: String) async throws -> StatusInfo {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw GitError.notAGitRepository
	}

	let headPath = gitDir.appendingPathComponent("HEAD")
	var branch = ""

	do {
		let headContent = try String(contentsOf: headPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

		let regex = /^ref: refs\/heads\/(.+)$/
		if let match = headContent.firstMatch(of: regex) {
			branch = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
		} else {
			branch = "(detached HEAD)"
		}
	} catch {
		branch = "(detached HEAD)"
	}

	let indexPath = gitDir.appendingPathComponent("index")
	let index = try await getIndex(at: indexPath.path)

	var staged: [String] = []
	var modified: [String] = []
	var untracked: [String] = []
	var deleted: [String] = []

	// Load gitignore patterns
	let gitignore = IgnoreParser()
	await gitignore.loadGitignore(repoPath: path)

	let workingFiles = await getWorkingFiles(at: path, gitignore: gitignore)

	for filePath in index.keys {
		staged.append(filePath)
	}

	for file in workingFiles {
		if !index.keys.contains(file) {
			untracked.append(file)
		}
	}

	for (filePath, entry) in index {
		let fullPath = URL(fileURLWithPath: path).appendingPathComponent(filePath)

		if !FileManager.default.fileExists(atPath: fullPath.path) {
			deleted.append(filePath)
		} else if FileManager.default.fileExists(atPath: fullPath.path) {
			var isDirectory: ObjCBool = false
			FileManager.default.fileExists(atPath: fullPath.path, isDirectory: &isDirectory)
			if !isDirectory.boolValue {
				let currentHash = try await hashFileAsBlob(at: fullPath.path)
				if entry.sha != currentHash {
					modified.append(filePath)
				}
			}
		}
	}

	return StatusInfo(
		branch: branch,
		upToDate: "Your branch is up to date with 'origin/\(branch)'.",
		staged: staged.sorted(),
		modified: modified.sorted(),
		untracked: untracked.sorted(),
		deleted: deleted.sorted()
	)
}

private func getWorkingFiles(at path: String, gitignore: IgnoreParser) async -> [String] {
	var files: [String] = []
	let baseURL = URL(fileURLWithPath: path).standardizedFileURL

	func scan(_ dir: URL) async {
		let standardizedDir = dir.standardizedFileURL
		guard let entries = try? FileManager.default.contentsOfDirectory(at: standardizedDir, includingPropertiesForKeys: nil) else {
			return
		}

		for entry in entries {
			if entry.lastPathComponent == ".git" { continue }

			guard let resourceValues = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey]),
			      let isDirectory = resourceValues.isDirectory,
			      let isFile = resourceValues.isRegularFile
			else {
				continue
			}

			let standardizedEntry = entry.standardizedFileURL
			let relPath = standardizedEntry.pathComponents.dropFirst(baseURL.pathComponents.count).joined(separator: "/")

			// Check if this path is ignored
			if await gitignore.isIgnored(filePath: relPath, isDirectory: isDirectory) {
				continue
			}

			if isDirectory {
				await scan(entry)
			} else if isFile {
				files.append(relPath)
			}
		}
	}

	await scan(baseURL)
	return files
}
