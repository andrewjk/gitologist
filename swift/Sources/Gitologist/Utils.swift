import Foundation
import CryptoKit

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
