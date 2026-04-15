import Foundation

private class ObjectEnumerator {
	var visited = Set<String>()
	var objects: [PackObject] = []

	func enumerate(at gitDir: String, sha: String) async throws {
		if visited.contains(sha) {
			return
		}
		visited.insert(sha)

		let objectData = try await readObjectData(at: gitDir, sha: sha)
		guard let nullIndex = objectData.firstIndex(of: 0) else {
			return
		}

		let headerData = objectData.prefix(upTo: nullIndex)
		let contentData = objectData.suffix(from: objectData.index(after: nullIndex))

		guard let header = String(data: headerData, encoding: .utf8) else {
			return
		}
		guard let spaceIndex = header.firstIndex(of: " ") else {
			return
		}
		let typeString = String(header[..<spaceIndex])
		guard let type = ObjectType(rawValue: typeString) else {
			return
		}

		objects.append(PackObject(type: type, sha: sha, content: contentData))

		if type == .commit {
			guard let content = String(data: contentData, encoding: .utf8) else {
				return
			}
			let lines = content.split(separator: "\n")
			for line in lines {
				if line.hasPrefix("parent ") {
					let parentSha = String(line.dropFirst(7))
					try await enumerate(at: gitDir, sha: parentSha)
				} else if line.hasPrefix("tree ") {
					let treeSha = String(line.dropFirst(5))
					try await enumerate(at: gitDir, sha: treeSha)
				}
			}
		} else if type == .tree {
			let entries = try parseTreeEntriesFromData(contentData)
			for entry in entries {
				try await enumerate(at: gitDir, sha: entry.sha)
			}
		}
	}
}

func enumerateObjects(at gitDir: String, sha: String) async throws -> [PackObject] {
	let enumerator = ObjectEnumerator()
	try await enumerator.enumerate(at: gitDir, sha: sha)
	return enumerator.objects
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
