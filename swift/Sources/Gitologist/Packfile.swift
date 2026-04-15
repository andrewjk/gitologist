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

	var objects: [PackObject] = []
	var offset = 12

	for _ in 0 ..< numObjects {
		guard offset < dataWithoutChecksum.count else {
			throw PackfileError.invalidPackfileSignature
		}

		let (type, _, newOffset) = try parseObjectHeader(dataWithoutChecksum, offset)
		offset = newOffset

		let (inflated, bytesConsumed) = try decompressStreamData(dataWithoutChecksum, from: offset)

		guard let objectType = getObjectType(type) else {
			throw PackfileError.unknownObjectType(type)
		}

		let objectHeader = "\(objectType.rawValue) \(inflated.count)\0"
		guard let headerData = objectHeader.data(using: .utf8) else {
			continue
		}
		let fullData = headerData + inflated
		let sha = Insecure.SHA1.hash(data: fullData)
			.map { String(format: "%02x", $0) }
			.joined()

		objects.append(PackObject(type: objectType, sha: sha, content: inflated))
		offset += bytesConsumed
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
