import Foundation

public enum AddError: Error, LocalizedError {
	case fileNotFound(String)
	case notAGitRepository

	public var errorDescription: String? {
		switch self {
		case let .fileNotFound(file):
			return "File not found: \(file)"
		case .notAGitRepository:
			return "Not a git repository"
		}
	}
}

public func add(at path: String, files: [String]) async throws {
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

		if await gitignore.isIgnored(filePath: file) {
			continue
		}

		let content = try String(contentsOf: fullPath, encoding: .utf8)
		// Write blob object to .git/objects and get hash
		let hash = try await hashObject(at: gitDir.path, content: content, type: "blob")
		let attributes = try FileManager.default.attributesOfItem(atPath: fullPath.path)

		let fileSize = attributes[.size] as! UInt32
		let modificationDate = attributes[.modificationDate] as! Date
		let creationDate = attributes[.creationDate] as! Date
		let fileSystemFileNumber = attributes[.systemFileNumber] as! UInt32
		let fileSystemNumber = attributes[.systemNumber] as! UInt32
		let ownerAccountID = attributes[.ownerAccountID] as! UInt32
		let groupOwnerAccountID = attributes[.groupOwnerAccountID] as! UInt32

		let ctimeSeconds = UInt32(creationDate.timeIntervalSince1970)
		let ctimeNanos = UInt32((creationDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1_000_000_000)
		let mtimeSeconds = UInt32(modificationDate.timeIntervalSince1970)
		let mtimeNanos = UInt32((modificationDate.timeIntervalSince1970.truncatingRemainder(dividingBy: 1)) * 1_000_000_000)

		index[file] = IndexEntry(
			path: file,
			sha: hash,
			mode: "100644",
			size: fileSize,
			ctimeSeconds: ctimeSeconds,
			ctimeNanos: ctimeNanos,
			mtimeSeconds: mtimeSeconds,
			mtimeNanos: mtimeNanos,
			dev: fileSystemNumber,
			ino: fileSystemFileNumber,
			uid: ownerAccountID,
			gid: groupOwnerAccountID
		)
	}

	try await writeIndex(at: indexPath.path, index: index)
}

public func addAll(at path: String) async throws {
	let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")

	guard FileManager.default.fileExists(atPath: gitDir.path) else {
		throw AddError.notAGitRepository
	}

	let currentStatus = try await status(at: path)
	let filesToAdd = currentStatus.untracked + currentStatus.modified

	if !filesToAdd.isEmpty {
		try await add(at: path, files: filesToAdd)
	}

	if !currentStatus.deleted.isEmpty {
		let indexPath = gitDir.appendingPathComponent("index")
		var index = try await getIndex(at: indexPath.path)
		for file in currentStatus.deleted {
			index.removeValue(forKey: file)
		}
		try await writeIndex(at: indexPath.path, index: index)
	}
}
