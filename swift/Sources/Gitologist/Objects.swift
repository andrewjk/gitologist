import Foundation

func enumerateObjects(at gitDir: String, sha: String, visited: Set<String> = Set()) async throws -> [PackObject] {
	var newVisited = visited
	if newVisited.contains(sha) {
		return []
	}
	newVisited.insert(sha)

	let objectData = try await readObject(at: gitDir, sha: sha)
	guard let headerEnd = objectData.firstIndex(of: "\n") else {
		return []
	}
	let header = String(objectData[..<headerEnd])
	guard let spaceIndex = header.firstIndex(of: " ") else {
		return []
	}
	let typeString = String(header[..<spaceIndex])
	guard let type = ObjectType(rawValue: typeString) else {
		return []
	}

	let content = String(objectData[objectData.index(after: headerEnd)...])

	var objects: [PackObject] = [
		PackObject(type: type, sha: sha, content: content.data(using: .utf8)!),
	]

	if type == .commit {
		let lines = content.split(separator: "\n")
		for line in lines {
			if line.hasPrefix("parent ") {
				let parentSha = String(line.dropFirst(7))
				let parentObjects = try await enumerateObjects(at: gitDir, sha: parentSha, visited: newVisited)
				objects.append(contentsOf: parentObjects)
			} else if line.hasPrefix("tree ") {
				let treeSha = String(line.dropFirst(5))
				let treeObjects = try await enumerateObjects(at: gitDir, sha: treeSha, visited: newVisited)
				objects.append(contentsOf: treeObjects)
			}
		}
	} else if type == .tree {
		let entries = try parseTreeEntries(objectData)
		for entry in entries {
			let entryObjects = try await enumerateObjects(at: gitDir, sha: entry.sha, visited: newVisited)
			objects.append(contentsOf: entryObjects)
		}
	}

	return objects
}

func getAllObjects(at gitDir: String) async throws -> [PackObject] {
	let objectsDir = URL(fileURLWithPath: gitDir).appendingPathComponent("objects")
	var objects: [PackObject] = []

	guard FileManager.default.fileExists(atPath: objectsDir.path) else {
		return objects
	}

	let dirs = try FileManager.default.contentsOfDirectory(at: objectsDir, includingPropertiesForKeys: nil)

	for dir in dirs {
		guard dir.lastPathComponent.count == 2 else {
			continue
		}

		let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)

		for file in files {
			let sha = dir.lastPathComponent + file.lastPathComponent
			do {
				let objectData = try await readObject(at: gitDir, sha: sha)
				guard let headerEnd = objectData.firstIndex(of: "\n") else {
					continue
				}
				let header = String(objectData[..<headerEnd])
				guard let spaceIndex = header.firstIndex(of: " ") else {
					continue
				}
				let typeString = String(header[..<spaceIndex])
				guard let type = ObjectType(rawValue: typeString) else {
					continue
				}

				let content = String(objectData[objectData.index(after: headerEnd)...])

				objects.append(PackObject(type: type, sha: sha, content: content.data(using: .utf8)!))
			} catch {
				// Skip invalid objects
			}
		}
	}

	return objects
}
