import Foundation
import CryptoKit
import Compression

func hashFile(at path: String) async throws -> String {
	let data = try Data(contentsOf: URL(fileURLWithPath: path))
	let sha1 = Insecure.SHA1.hash(data: data)
	return sha1.compactMap { String(format: "%02x", $0) }.joined()
}

func getIndex(at path: String) async throws -> [String: IndexEntry] {
	guard FileManager.default.fileExists(atPath: path) else {
		return [:]
	}

	let content = try String(contentsOfFile: path, encoding: .utf8)
	var index: [String: IndexEntry] = [:]

	let lines = content.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)

	for line in lines where !line.isEmpty {
		let parts = line.components(separatedBy: .whitespaces)
		guard parts.count >= 2 else { continue }

		let filePath = parts[0]
		let sha = parts[1]
		let mode = parts.count >= 3 ? parts[2] : "100644"

		index[filePath] = IndexEntry(path: filePath, sha: sha, mode: mode)
	}

	return index
}

func writeIndex(at path: String, index: [String: IndexEntry]) async throws {
	var lines: [String] = []

	for entry in index.values {
		lines.append("\(entry.path) \(entry.sha) \(entry.mode)")
	}

	let content = lines.joined(separator: "\n") + "\n"
	try content.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
}

func getCurrentBranch(at gitDir: String) async throws -> String {
	let headPath = URL(fileURLWithPath: gitDir).appendingPathComponent("HEAD")
	let headContent = try String(contentsOf: headPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

	let regex = /^ref: refs\/heads\/(.+)$/
	guard let match = headContent.firstMatch(of: regex) else {
		throw GitError.notOnABranch
	}

	return String(match.1)
}

func getCurrentCommit(at gitDir: String) async throws -> String? {
	do {
		let branch = try await getCurrentBranch(at: gitDir)
		let branchPath = URL(fileURLWithPath: gitDir).appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branch)

		guard FileManager.default.fileExists(atPath: branchPath.path) else {
			return nil
		}

		return try String(contentsOf: branchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
	} catch {
		return nil
	}
}

func hashObject(at gitDir: String, content: String, type: String) async throws -> String {
	let header = "\(type) \(content.utf8.count)\0\(content)"
	let data = header.data(using: .utf8)!
	let sha1 = Insecure.SHA1.hash(data: data)
	let sha = sha1.compactMap { String(format: "%02x", $0) }.joined()

	let objectDir = URL(fileURLWithPath: gitDir).appendingPathComponent("objects").appendingPathComponent(String(sha.prefix(2)))
	let objectPath = objectDir.appendingPathComponent(String(sha.dropFirst(2)))

	guard !FileManager.default.fileExists(atPath: objectPath.path) else {
		return sha
	}

	try FileManager.default.createDirectory(at: objectDir, withIntermediateDirectories: true)
	try data.write(to: objectPath)

	return sha
}

private func compressData(_ data: Data) throws -> Data {
	return data
}

func updateBranch(at gitDir: String, branchName: String, commitSha: String) async throws {
	let branchPath = URL(fileURLWithPath: gitDir).appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent(branchName)
	try FileManager.default.createDirectory(at: branchPath.deletingLastPathComponent(), withIntermediateDirectories: true)
	try "\(commitSha)\n".write(to: branchPath, atomically: true, encoding: .utf8)
}

func readObject(at gitDir: String, sha: String) async throws -> String {
	let objectPath = URL(fileURLWithPath: gitDir)
		.appendingPathComponent("objects")
		.appendingPathComponent(String(sha.prefix(2)))
		.appendingPathComponent(String(sha.dropFirst(2)))

	let data = try Data(contentsOf: objectPath)
	return String(data: data, encoding: .utf8)!
}

func extractContentFromBlob(_ blobData: String) throws -> String {
	guard let nullIndex = blobData.firstIndex(of: "\0") else {
		throw GitError.invalidIndexFile("Invalid blob object")
	}

	let contentIndex = blobData.index(after: nullIndex)
	guard contentIndex < blobData.endIndex else {
		return ""
	}

	return String(blobData[contentIndex...])
}

func extractTreeFromCommit(_ commitData: String) throws -> String {
	// Try to find "tree " directly in the data
	guard let treeLineRange = commitData.range(of: "tree ") else {
		throw GitError.invalidIndexFile("Invalid commit object - no tree found")
	}

	// The SHA starts after "tree " (5 chars)
	let shaStart = commitData.index(treeLineRange.lowerBound, offsetBy: 5)
	guard shaStart < commitData.endIndex else {
		throw GitError.invalidIndexFile("Invalid commit object - no tree found")
	}

	// SHA is 40 chars
	let shaEnd = commitData.index(shaStart, offsetBy: 40)
	guard shaEnd <= commitData.endIndex else {
		throw GitError.invalidIndexFile("Invalid commit object - no tree found")
	}

	return String(commitData[shaStart..<shaEnd])
}

func parseTreeEntries(_ treeData: String) throws -> [TreeEntry] {
	guard let nullIndex = treeData.firstIndex(of: "\0") else {
		return []
	}

	var entries: [TreeEntry] = []

	// Skip header by starting after first null
	var currentIndex = treeData.index(after: nullIndex)

	while currentIndex < treeData.endIndex {
		// Find mode end (space)
		guard let spaceIndex = treeData[currentIndex...].firstIndex(of: " ") else {
			break
		}

		// Find type end (next space)
		guard spaceIndex > currentIndex else { break }
		let afterSpaceIndex = treeData.index(after: spaceIndex)
		guard afterSpaceIndex < treeData.endIndex else { break }

		guard let nextSpaceIndex = treeData[afterSpaceIndex...].firstIndex(of: " ") else {
			break
		}
		guard nextSpaceIndex > afterSpaceIndex else { break }

		// Find tab before path
		let afterNextSpaceIndex = treeData.index(after: nextSpaceIndex)
		guard afterNextSpaceIndex < treeData.endIndex else { break }

		guard let tabIndex = treeData[afterNextSpaceIndex...].firstIndex(of: "\t") else {
			break
		}
		guard tabIndex > afterNextSpaceIndex else { break }

		// Find null after path
		let afterTabIndex = treeData.index(after: tabIndex)
		guard afterTabIndex < treeData.endIndex else { break }

		guard let nextNullIndex = treeData[afterTabIndex...].firstIndex(of: "\0") else {
			break
		}
		guard nextNullIndex > afterTabIndex else { break }

		// Extract components
		let modeEnd = spaceIndex
		let mode = String(treeData[currentIndex..<modeEnd])

		let typeEnd = nextSpaceIndex
		let type = String(treeData[afterSpaceIndex..<typeEnd])

		let shaStart = afterNextSpaceIndex
		let shaEnd = tabIndex
		let sha = String(treeData[shaStart..<shaEnd])

		let pathStart = afterTabIndex
		let pathEnd = nextNullIndex
		let path = String(treeData[pathStart..<pathEnd])

		guard type == "blob" || type == "tree" else {
			break
		}

		entries.append(TreeEntry(
			path: path,
			sha: sha,
			mode: mode,
			type: type == "blob" ? .blob : .tree
		))

		// Move to next entry
		let afterNextNullIndex = treeData.index(after: nextNullIndex)
		guard afterNextNullIndex <= treeData.endIndex else { break }

		currentIndex = afterNextNullIndex
	}

	return entries
}
