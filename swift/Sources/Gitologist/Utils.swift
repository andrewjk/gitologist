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
