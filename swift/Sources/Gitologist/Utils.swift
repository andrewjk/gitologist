import CryptoKit
import Foundation
import zlib

func hashFile(at path: String) async throws -> String {
	let data = try Data(contentsOf: URL(fileURLWithPath: path))
	let sha1 = Insecure.SHA1.hash(data: data)
	return sha1.compactMap { String(format: "%02x", $0) }.joined()
}

func getIndex(at path: String) async throws -> [String: IndexEntry] {
	var index: [String: IndexEntry] = [:]

	guard FileManager.default.fileExists(atPath: path) else {
		return index
	}

	guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
		return index
	}

	guard data.count >= 12 else {
		return index
	}

	let signature = String(data: data[0 ..< 4], encoding: .ascii)
	guard signature == "DIRC" else {
		return index
	}

	let numEntries = data.withUnsafeBytes { rawPtr in
		rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
	}

	var offset = 12

	for _ in 0 ..< numEntries {
		guard offset + 62 <= data.count else {
			break
		}

		let ctimeSeconds = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
		}
		let ctimeNanos = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 4, as: UInt32.self).bigEndian
		}
		let mtimeSeconds = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 8, as: UInt32.self).bigEndian
		}
		let mtimeNanos = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 12, as: UInt32.self).bigEndian
		}
		let dev = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 16, as: UInt32.self).bigEndian
		}
		let ino = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 20, as: UInt32.self).bigEndian
		}
		let modeValue = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 24, as: UInt32.self).bigEndian
		}
		let mode = String(format: "%o", modeValue)
		let uid = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 28, as: UInt32.self).bigEndian
		}
		let gid = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 32, as: UInt32.self).bigEndian
		}
		let size = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 36, as: UInt32.self).bigEndian
		}

		let shaData = data.subdata(in: offset + 40 ..< (offset + 60))
		let sha = shaData.map { String(format: "%02x", $0) }.joined()

		let flags = data.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: offset + 60, as: UInt16.self).bigEndian
		}

		let pathLength = Int(flags & 0x0FFF)
		guard offset + 62 + pathLength <= data.count else {
			break
		}

		let pathData = data.subdata(in: offset + 62 ..< (offset + 62 + pathLength))
		guard let path = String(data: pathData, encoding: .utf8) else {
			break
		}

		let entryLength = 62 + pathLength + 1
		let paddingLength = (8 - (entryLength % 8)) % 8
		offset = offset + entryLength + paddingLength

		index[path] = IndexEntry(
			path: path,
			sha: sha,
			mode: mode,
			size: size,
			ctimeSeconds: ctimeSeconds,
			ctimeNanos: ctimeNanos,
			mtimeSeconds: mtimeSeconds,
			mtimeNanos: mtimeNanos,
			dev: dev,
			ino: ino,
			uid: uid,
			gid: gid
		)
	}

	return index
}

func writeIndex(at path: String, index: [String: IndexEntry]) async throws {
	let entries = index.values.sorted { $0.path < $1.path }

	var header = Data()
	header.append("DIRC".data(using: .ascii)!)
	header.append(withUnsafeBytes(of: UInt32(2).bigEndian) { Data($0) })
	header.append(withUnsafeBytes(of: UInt32(entries.count).bigEndian) { Data($0) })

	var entryBuffers: [Data] = []

	for entry in entries {
		var entryData = Data(count: 62 + entry.path.count + 1)

		entryData.withUnsafeMutableBytes { rawPtr in
			rawPtr.storeBytes(of: entry.ctimeSeconds.bigEndian, toByteOffset: 0, as: UInt32.self)
			rawPtr.storeBytes(of: entry.ctimeNanos.bigEndian, toByteOffset: 4, as: UInt32.self)
			rawPtr.storeBytes(of: entry.mtimeSeconds.bigEndian, toByteOffset: 8, as: UInt32.self)
			rawPtr.storeBytes(of: entry.mtimeNanos.bigEndian, toByteOffset: 12, as: UInt32.self)
			rawPtr.storeBytes(of: entry.dev.bigEndian, toByteOffset: 16, as: UInt32.self)
			rawPtr.storeBytes(of: entry.ino.bigEndian, toByteOffset: 20, as: UInt32.self)

			let modeValue = UInt32(strtoul(entry.mode, nil, 8))
			rawPtr.storeBytes(of: modeValue.bigEndian, toByteOffset: 24, as: UInt32.self)

			rawPtr.storeBytes(of: entry.uid.bigEndian, toByteOffset: 28, as: UInt32.self)
			rawPtr.storeBytes(of: entry.gid.bigEndian, toByteOffset: 32, as: UInt32.self)
			rawPtr.storeBytes(of: entry.size.bigEndian, toByteOffset: 36, as: UInt32.self)
		}

		var shaBytes: [UInt8] = []
		for i in stride(from: 0, to: entry.sha.count, by: 2) {
			let start = entry.sha.index(entry.sha.startIndex, offsetBy: i)
			let end = entry.sha.index(entry.sha.startIndex, offsetBy: i + 2)
			let byteString = String(entry.sha[start ..< end])
			if let byte = UInt8(byteString, radix: 16) {
				shaBytes.append(byte)
			}
		}
		let shaData = Data(shaBytes)
		entryData.replaceSubrange(40 ..< 60, with: shaData)

		let flags = UInt16(min(entry.path.count, 0x0FFF))
		entryData.withUnsafeMutableBytes { rawPtr in
			rawPtr.storeBytes(of: flags.bigEndian, toByteOffset: 60, as: UInt16.self)
		}

		entryData.replaceSubrange(62 ..< (62 + entry.path.count), with: entry.path.data(using: .utf8)!)
		entryData[62 + entry.path.count] = 0

		let entryLength = 62 + entry.path.count + 1
		let paddingLength = (8 - (entryLength % 8)) % 8
		let padding = Data(count: paddingLength)

		entryBuffers.append(entryData + padding)
	}

	let content = header + entryBuffers.reduce(Data(), +)

	let sha1 = Insecure.SHA1.hash(data: content)
	let checksum = Data(sha1)

	try (content + checksum).write(to: URL(fileURLWithPath: path))
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
	let compressedData = try compressData(data)
	try compressedData.write(to: objectPath)

	return sha
}

private func compressData(_ data: Data) throws -> Data {
	// Use zlib compression for git object format compatibility
	var compressedData = Data()

	// Initialize zlib stream
	var stream = z_stream()
	stream.zalloc = nil
	stream.zfree = nil
	stream.opaque = nil

	// Initialize for compression - use the underlying function directly
	let initResult = deflateInit_(&stream, Z_DEFAULT_COMPRESSION, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
	guard initResult == Z_OK else {
		throw GitError.invalidIndexFile("Failed to initialize compression")
	}
	defer { deflateEnd(&stream) }

	// Compress the data
	var outputBuffer = [UInt8](repeating: 0, count: 1024)

	let compressResult = data.withUnsafeBytes { sourceBytes in
		stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourceBytes.bindMemory(to: Bytef.self).baseAddress!)
		stream.avail_in = uInt(data.count)

		var result: Int32 = Z_OK
		repeat {
			outputBuffer.withUnsafeMutableBufferPointer { buffer in
				stream.next_out = buffer.baseAddress!
				stream.avail_out = uInt(buffer.count)
			}

			result = deflate(&stream, Z_FINISH)

			let bytesWritten = outputBuffer.count - Int(stream.avail_out)
			if bytesWritten > 0 {
				compressedData.append(contentsOf: outputBuffer[0 ..< bytesWritten])
			}
		} while result == Z_OK

		return result
	}

	guard compressResult == Z_STREAM_END else {
		throw GitError.invalidIndexFile("Failed to compress data")
	}

	return compressedData
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

	let compressedData = try Data(contentsOf: objectPath)
	let data = try decompressData(compressedData)
	return String(data: data, encoding: .utf8)!
}

private func decompressData(_ data: Data) throws -> Data {
	// Use zlib decompression for git object format compatibility
	var decompressedData = Data()

	// Initialize zlib stream
	var stream = z_stream()
	stream.zalloc = nil
	stream.zfree = nil
	stream.opaque = nil

	// Initialize for decompression - use the underlying function directly
	let initResult = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
	guard initResult == Z_OK else {
		throw GitError.invalidIndexFile("Failed to initialize decompression")
	}
	defer { inflateEnd(&stream) }

	// Decompress the data
	var outputBuffer = [UInt8](repeating: 0, count: 4096)

	let decompressResult = data.withUnsafeBytes { sourceBytes in
		stream.next_in = UnsafeMutablePointer<Bytef>(mutating: sourceBytes.bindMemory(to: Bytef.self).baseAddress!)
		stream.avail_in = uInt(data.count)

		var result: Int32 = Z_OK
		repeat {
			outputBuffer.withUnsafeMutableBufferPointer { buffer in
				stream.next_out = buffer.baseAddress!
				stream.avail_out = uInt(buffer.count)
			}

			result = inflate(&stream, Z_NO_FLUSH)

			let bytesWritten = outputBuffer.count - Int(stream.avail_out)
			if bytesWritten > 0 {
				decompressedData.append(contentsOf: outputBuffer[0 ..< bytesWritten])
			}
		} while result == Z_OK

		return result
	}

	guard decompressResult == Z_STREAM_END || decompressResult == Z_OK else {
		throw GitError.invalidIndexFile("Failed to decompress data")
	}

	return decompressedData
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

	return String(commitData[shaStart ..< shaEnd])
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
		let mode = String(treeData[currentIndex ..< modeEnd])

		let typeEnd = nextSpaceIndex
		let type = String(treeData[afterSpaceIndex ..< typeEnd])

		let shaStart = afterNextSpaceIndex
		let shaEnd = tabIndex
		let sha = String(treeData[shaStart ..< shaEnd])

		let pathStart = afterTabIndex
		let pathEnd = nextNullIndex
		let path = String(treeData[pathStart ..< pathEnd])

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
