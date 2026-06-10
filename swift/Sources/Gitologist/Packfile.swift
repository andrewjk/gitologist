import CryptoKit
import Foundation
import zlib

enum PackfileError: Error, LocalizedError {
	case invalidPackfileSignature
	case unsupportedPackfileVersion(Int)
	case unknownObjectType(Int)

	var errorDescription: String? {
		switch self {
		case .invalidPackfileSignature:
			return "Invalid packfile signature"
		case let .unsupportedPackfileVersion(version):
			return "Unsupported packfile version: \(version)"
		case let .unknownObjectType(type):
			return "Unknown object type: \(type)"
		}
	}
}

struct PackObject {
	let type: ObjectType
	let sha: String
	let content: Data
}

enum ObjectType: String {
	case commit
	case tree
	case blob
	case tag
}

func encodePktLine(_ line: String?) -> Data {
	guard let line = line else {
		return Data("0000".utf8)
	}
	let length = line.utf8.count + 4
	let hexLength = String(format: "%04x", length)
	if length == 4 {
		return Data(hexLength.utf8)
	}
	return (hexLength + line).data(using: .utf8)!
}

func decodePktLines(_ data: Data) -> [String] {
	var lines: [String] = []
	var offset = 0

	while offset < data.count {
		guard offset + 4 <= data.count else {
			break
		}

		let hexLength = String(data: data[offset ..< (offset + 4)], encoding: .utf8)
		guard let hexLength = hexLength else {
			break
		}

		if hexLength == "0000" {
			lines.append("")
			offset += 4
			continue
		}

		guard let length = Int(hexLength, radix: 16),
		      length > 0,
		      length <= data.count - offset
		else {
			break
		}

		let lineData = data[(offset + 4) ..< (offset + length)]
		guard let line = String(data: lineData, encoding: .utf8) else {
			break
		}
		lines.append(line)
		offset += length
	}

	return lines
}

private struct RawPackEntry {
	let entryType: PackEntryType
	let content: Data
	let packOffset: Int
	let bytesConsumed: Int
}

func parsePackfile(_ data: Data) throws -> [PackObject] {
	let signature = String(data: data[0 ..< 4], encoding: .utf8)
	guard signature == "PACK" else {
		throw PackfileError.invalidPackfileSignature
	}

	let version = data.withUnsafeBytes { rawPtr in
		rawPtr.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian
	}
	guard version == 2 else {
		throw PackfileError.unsupportedPackfileVersion(Int(version))
	}

	let numObjects = data.withUnsafeBytes { rawPtr in
		rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
	}

	// Exclude checksum (last 20 bytes) from parsing
	let dataWithoutChecksum = data.prefix(data.count - 20)

	var rawEntries: [RawPackEntry] = []
	var offsetToIndex: [Int: Int] = [:]
	var offset = 12

	for _ in 0 ..< numObjects {
		guard offset < dataWithoutChecksum.count else {
			throw PackfileError.invalidPackfileSignature
		}

		let (typeNum, _, headerEndOffset) = try parseObjectHeader(dataWithoutChecksum, offset)

		guard let (entryType, dataOffset) = parsePackEntryType(typeNum, data: dataWithoutChecksum, offset: headerEndOffset) else {
			throw PackfileError.unknownObjectType(typeNum)
		}

		let (inflated, bytesConsumed) = try decompressStreamData(dataWithoutChecksum, from: dataOffset)

		rawEntries.append(RawPackEntry(entryType: entryType, content: inflated, packOffset: offset, bytesConsumed: bytesConsumed + (dataOffset - offset)))
		offsetToIndex[offset] = rawEntries.count - 1
		offset = dataOffset + bytesConsumed
	}

	func resolveEntry(at index: Int, resolved: inout [Int: (content: Data, type: ObjectType)]) -> (content: Data, type: ObjectType) {
		if let cached = resolved[index] { return cached }
		let entry = rawEntries[index]
		let content: Data
		let objType: ObjectType
		switch entry.entryType {
		case let .object(type):
			content = entry.content
			objType = type
		case let .ofsDelta(offset: negOffset):
			let basePackOffset = entry.packOffset - negOffset
			let baseIndex = offsetToIndex[basePackOffset]!
			let base = resolveEntry(at: baseIndex, resolved: &resolved)
			content = applyDelta(base: base.content, delta: entry.content)
			objType = base.type
		case let .refDelta(baseSha: baseSha):
			var baseIndex: Int?
			for j in rawEntries.indices {
				let raw = rawEntries[j]
				guard case let .object(objType) = raw.entryType else { continue }
				let header = "\(objType.rawValue) \(raw.content.count)\0"
				let fullData = header.data(using: .utf8)! + raw.content
				let sha = Insecure.SHA1.hash(data: fullData)
					.map { String(format: "%02x", $0) }.joined()
				if sha == baseSha {
					baseIndex = j
					break
				}
			}
			let base = resolveEntry(at: baseIndex!, resolved: &resolved)
			content = applyDelta(base: base.content, delta: entry.content)
			objType = base.type
		}
		let result = (content: content, type: objType)
		resolved[index] = result
		return result
	}

	var resolved: [Int: (content: Data, type: ObjectType)] = [:]
	var objects: [PackObject] = []

	for i in rawEntries.indices {
		let entry = rawEntries[i]
		let content: Data
		let objectType: ObjectType

		switch entry.entryType {
		case let .object(type):
			objectType = type
			content = entry.content
		case .ofsDelta, .refDelta:
			let resolvedResult = resolveEntry(at: i, resolved: &resolved)
			content = resolvedResult.content
			objectType = resolvedResult.type
		}

		let objectHeader = "\(objectType.rawValue) \(content.count)\0"
		guard let headerData = objectHeader.data(using: .utf8) else {
			continue
		}
		let fullData = headerData + content
		let sha = Insecure.SHA1.hash(data: fullData)
			.map { String(format: "%02x", $0) }
			.joined()

		objects.append(PackObject(type: objectType, sha: sha, content: content))
	}

	return objects
}

func parseObjectHeader(_ data: Data, _ offset: Int) throws -> (type: Int, size: Int, newOffset: Int) {
	guard offset < data.count else {
		throw PackfileError.invalidPackfileSignature
	}

	let byte = data[offset]
	let type = Int((byte >> 4) & 0x07)
	var size = Int(byte & 0x0F)
	var shift = 4
	var currentOffset = offset + 1

	while (byte & 0x80) != 0 {
		guard currentOffset < data.count else {
			throw PackfileError.invalidPackfileSignature
		}
		let nextByte = data[currentOffset]
		size |= Int(nextByte & 0x7F) << shift
		shift += 7
		currentOffset += 1
		if (nextByte & 0x80) == 0 {
			break
		}
	}

	return (type, size, currentOffset)
}

private func decompressStreamData(_ data: Data, from offset: Int) throws -> (decompressed: Data, bytesConsumed: Int) {
	var stream = z_stream()
	stream.zalloc = nil
	stream.zfree = nil
	stream.opaque = nil

	let initResult = inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
	guard initResult == Z_OK else {
		throw PackfileError.invalidPackfileSignature
	}
	defer { inflateEnd(&stream) }

	var decompressedData = Data()
	var outputBuffer = [UInt8](repeating: 0, count: 4096)

	let remainingData = data[offset...]
	let result = remainingData.withUnsafeBytes { sourceBytes in
		let base = sourceBytes.bindMemory(to: Bytef.self).baseAddress!
		stream.next_in = UnsafeMutablePointer<Bytef>(mutating: base)
		stream.avail_in = uInt(remainingData.count)

		var res: Int32 = Z_OK
		repeat {
			outputBuffer.withUnsafeMutableBufferPointer { buffer in
				stream.next_out = buffer.baseAddress!
				stream.avail_out = uInt(buffer.count)
			}

			res = inflate(&stream, Z_NO_FLUSH)

			let bytesWritten = outputBuffer.count - Int(stream.avail_out)
			if bytesWritten > 0 {
				decompressedData.append(contentsOf: outputBuffer[0 ..< bytesWritten])
			}
		} while res == Z_OK

		return res
	}

	guard result == Z_STREAM_END else {
		throw PackfileError.invalidPackfileSignature
	}

	let bytesConsumed = remainingData.count - Int(stream.avail_in)
	return (decompressedData, bytesConsumed)
}

func getObjectType(_ typeNum: Int) -> ObjectType? {
	switch typeNum {
	case 1:
		return .commit
	case 2:
		return .tree
	case 3:
		return .blob
	case 4:
		return .tag
	default:
		return nil
	}
}

private enum PackEntryType {
	case object(ObjectType)
	case ofsDelta(offset: Int)
	case refDelta(baseSha: String)
}

private func parsePackEntryType(_ typeNum: Int, data: Data, offset: Int) -> (PackEntryType, Int)? {
	switch typeNum {
	case 1: return (.object(.commit), offset)
	case 2: return (.object(.tree), offset)
	case 3: return (.object(.blob), offset)
	case 4: return (.object(.tag), offset)
	case 6:
		var off = offset
		var byte = data[off]
		off += 1
		var negOffset = Int(byte & 0x7F)
		while (byte & 0x80) != 0 {
			byte = data[off]
			off += 1
			negOffset = ((negOffset + 1) << 7) | Int(byte & 0x7F)
		}
		return (.ofsDelta(offset: negOffset), off)
	case 7:
		guard offset + 20 <= data.count else { return nil }
		let shaBytes = data[offset ..< (offset + 20)]
		let sha = shaBytes.map { String(format: "%02x", $0) }.joined()
		return (.refDelta(baseSha: sha), offset + 20)
	default:
		return nil
	}
}

private func applyDelta(base: Data, delta: Data) -> Data {
	var deltaOffset = 0

	func readSize() -> Int {
		var size = 0
		var shift = 0
		while deltaOffset < delta.count {
			let byte = Int(delta[deltaOffset])
			deltaOffset += 1
			size |= (byte & 0x7F) << shift
			shift += 7
			if (byte & 0x80) == 0 { break }
		}
		return size
	}

	let _ = readSize()
	let _ = readSize()

	var result = Data()

	while deltaOffset < delta.count {
		let cmd = Int(delta[deltaOffset])
		deltaOffset += 1

		if (cmd & 0x80) != 0 {
			var copyOffset = 0
			var copySize = 0

			if (cmd & 0x01) != 0 { copyOffset = Int(delta[deltaOffset]); deltaOffset += 1 }
			if (cmd & 0x02) != 0 { copyOffset |= Int(delta[deltaOffset]) << 8; deltaOffset += 1 }
			if (cmd & 0x04) != 0 { copyOffset |= Int(delta[deltaOffset]) << 16; deltaOffset += 1 }
			if (cmd & 0x08) != 0 { copyOffset |= Int(delta[deltaOffset]) << 24; deltaOffset += 1 }

			if (cmd & 0x10) != 0 { copySize = Int(delta[deltaOffset]); deltaOffset += 1 }
			if (cmd & 0x20) != 0 { copySize |= Int(delta[deltaOffset]) << 8; deltaOffset += 1 }
			if (cmd & 0x40) != 0 { copySize |= Int(delta[deltaOffset]) << 16; deltaOffset += 1 }

			if copySize == 0 { copySize = 0x10000 }

			result.append(base[copyOffset ..< (copyOffset + copySize)])
		} else if cmd > 0 {
			let insertData = delta[deltaOffset ..< (deltaOffset + cmd)]
			deltaOffset += cmd
			result.append(insertData)
		}
	}

	return result
}

func getTypeNumber(_ type: ObjectType) -> Int {
	switch type {
	case .commit:
		return 1
	case .tree:
		return 2
	case .blob:
		return 3
	case .tag:
		return 4
	}
}

func createPackfile(_ objects: [PackObject]) -> Data {
	var version = Data(count: 4)
	version.withUnsafeMutableBytes { rawPtr in
		rawPtr.storeBytes(of: UInt32(2).bigEndian, toByteOffset: 0, as: UInt32.self)
	}

	var numObjects = Data(count: 4)
	numObjects.withUnsafeMutableBytes { rawPtr in
		rawPtr.storeBytes(of: UInt32(objects.count).bigEndian, toByteOffset: 0, as: UInt32.self)
	}

	var objectBuffers: [Data] = []

	for obj in objects {
		let typeNum = getTypeNumber(obj.type)
		let header = encodeObjectHeader(typeNum, obj.content.count)
		let compressed = try! compressData(obj.content)
		objectBuffers.append(header + compressed)
	}

	var packfile = Data()
	packfile.append("PACK".data(using: .utf8)!)
	packfile.append(version)
	packfile.append(numObjects)
	for buffer in objectBuffers {
		packfile.append(buffer)
	}

	let checksum = Insecure.SHA1.hash(data: packfile)
	packfile.append(Data(checksum))

	return packfile
}

func encodeObjectHeader(_ type: Int, _ size: Int) -> Data {
	var bytes: [UInt8] = []
	var byte = (type << 4) | (size & 0x0F)
	var sizeRemaining = size >> 4

	while sizeRemaining > 0 {
		bytes.append(UInt8(byte | 0x80))
		byte = sizeRemaining & 0x7F
		sizeRemaining >>= 7
	}

	bytes.append(UInt8(byte))

	return Data(bytes)
}
