import CryptoKit
import Foundation
@testable import Gitologist
import Testing

struct PackfileTests {
	@Test func shouldCreatePackfileWithBlobObject() {
		let blobContent = Data("hello world".utf8)
		let objects: [PackObject] = [
			PackObject(
				type: .blob,
				sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
				content: blobContent
			),
		]

		let packfile = createPackfile(objects)

		#expect(String(data: packfile[0 ..< 4], encoding: .utf8) == "PACK")

		let version = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian
		}
		#expect(version == 2)

		let numObjects = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
		}
		#expect(numObjects == 1)

		#expect(packfile.count > 12)
	}

	@Test func shouldCreatePackfileWithMultipleObjects() {
		var treeContent = Data("100644 file.txt".utf8)
		treeContent.append(0x00)
		treeContent.append(Data("b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0".utf8))

		let objects: [PackObject] = [
			PackObject(
				type: .blob,
				sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
				content: Data("hello world".utf8)
			),
			PackObject(
				type: .blob,
				sha: "8d0e41234f23b8da1c8cc8e5a6d5da1b5c5e1234",
				content: Data("another file".utf8)
			),
			PackObject(
				type: .tree,
				sha: "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
				content: treeContent
			),
		]

		let packfile = createPackfile(objects)

		let numObjects = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
		}
		#expect(numObjects == 3)
	}

	@Test func shouldCreatePackfileWithCommitObject() {
		let commitContent = Data(
			"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n".utf8
		)
		let objects: [PackObject] = [
			PackObject(
				type: .commit,
				sha: "c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0",
				content: commitContent
			),
		]

		let packfile = createPackfile(objects)

		#expect(String(data: packfile[0 ..< 4], encoding: .utf8) == "PACK")

		let version = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian
		}
		#expect(version == 2)

		let numObjects = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
		}
		#expect(numObjects == 1)
	}

	@Test func shouldCreatePackfileWithTagObject() {
		let tagContent = Data(
			"object c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0\ntype commit\ntag v1.0.0\ntagger Test <test@example.com> 1234567890 +0000\n\nVersion 1.0.0\n".utf8
		)
		let objects: [PackObject] = [
			PackObject(
				type: .tag,
				sha: "a1b2c3d4e5f6789012345678901234567890abcd",
				content: tagContent
			),
		]

		let packfile = createPackfile(objects)

		#expect(String(data: packfile[0 ..< 4], encoding: .utf8) == "PACK")

		let version = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 4, as: UInt32.self).bigEndian
		}
		#expect(version == 2)

		let numObjects = packfile.withUnsafeBytes { rawPtr in
			rawPtr.loadUnaligned(fromByteOffset: 8, as: UInt32.self).bigEndian
		}
		#expect(numObjects == 1)
	}

	@Test func shouldIncludeValidChecksumAtEnd() {
		let objects: [PackObject] = [
			PackObject(
				type: .blob,
				sha: "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
				content: Data("hello world".utf8)
			),
		]

		let packfile = createPackfile(objects)

		#expect(packfile.count > 12)

		let dataWithoutChecksum = packfile.prefix(packfile.count - 20)
		let checksum = packfile.suffix(20)

		let expectedChecksum = Insecure.SHA1.hash(data: dataWithoutChecksum)
		#expect(Data(expectedChecksum) == checksum)
	}

	@Test func shouldThrowErrorForInvalidPackfileSignature() {
		let invalidPackfile = Data("INVALID".utf8)

		#expect(throws: PackfileError.self) {
			try parsePackfile(invalidPackfile)
		}
	}

	@Test func shouldThrowErrorForUnsupportedPackfileVersion() throws {
		var buffer = Data(count: 12)
		try buffer.replaceSubrange(0 ..< 4, with: #require("PACK".data(using: .utf8)))

		buffer.withUnsafeMutableBytes { rawPtr in
			rawPtr.storeBytes(of: UInt32(99).bigEndian, toByteOffset: 4, as: UInt32.self)
		}

		#expect(throws: PackfileError.self) {
			try parsePackfile(buffer)
		}
	}

	@Test func shouldEncodeAndDecodePktLine() {
		let line = "hello world"
		let encoded = encodePktLine(line)
		let decoded = decodePktLines(encoded)

		#expect(decoded == [line])
	}

	@Test func shouldEncodeAndDecodeNullPktLine() {
		let encoded = encodePktLine(nil)
		// Null pkt-line is a special case that marks the end of a stream
		// It encodes as "0000" but may not be included in decoded output
		let decoded = decodePktLines(encoded)

		// The null pkt-line is a flush packet, which may or may not be included
		// depending on the implementation
		#expect(decoded.isEmpty || decoded == [""])
	}

	@Test func shouldEncodeAndDecodeMultiplePktLines() {
		let lines = ["first line", "second line", "third line"]
		let encoded = lines.reduce(Data()) { result, line in
			result + encodePktLine(line)
		}
		let decoded = decodePktLines(encoded)

		#expect(decoded == lines)
	}

	@Test func shouldHandleEmptyStringPktLine() {
		let line = ""
		let encoded = encodePktLine(line)
		let decoded = decodePktLines(encoded)

		#expect(decoded == [""])
	}

	@Test func shouldReturnCorrectTypeForCommit() {
		#expect(getObjectType(1) == .commit)
	}

	@Test func shouldReturnCorrectTypeForTree() {
		#expect(getObjectType(2) == .tree)
	}

	@Test func shouldReturnCorrectTypeForBlob() {
		#expect(getObjectType(3) == .blob)
	}

	@Test func shouldReturnCorrectTypeForTag() {
		#expect(getObjectType(4) == .tag)
	}

	@Test func shouldReturnNilForUnknownType() {
		#expect(getObjectType(99) == nil)
	}

	func computeSha(type: String, content: Data) -> String {
		let header = "\(type) \(content.count)\0"
		let data = header.data(using: .utf8)! + content
		let sha = Insecure.SHA1.hash(data: data)
		return sha.map { String(format: "%02x", $0) }.joined()
	}

	@Test func shouldReadLooseObject() async throws {
		let testDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("gitologist-test-\(UUID().uuidString.prefix(8))")
		let gitDir = testDir.appendingPathComponent(".git")
		try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: testDir) }

		let content = "hello world"
		let sha = try await hashObject(at: gitDir.path, content: content, type: "blob")

		let data = try await readObjectData(at: gitDir.path, sha: sha)
		let nullIndex = try #require(data.firstIndex(of: 0))
		let header = try #require(String(data: data.prefix(upTo: nullIndex), encoding: .utf8))
		let body = try #require(String(data: data.suffix(from: data.index(after: nullIndex)), encoding: .utf8))

		#expect(header == "blob \(content.count)")
		#expect(body == content)
	}

	@Test func shouldReadObjectFromPackfile() async throws {
		let testDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("gitologist-test-\(UUID().uuidString.prefix(8))")
		let gitDir = testDir.appendingPathComponent(".git")
		try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects").appendingPathComponent("pack"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: testDir) }

		let blobContent = Data("packfile content".utf8)
		let sha = computeSha(type: "blob", content: blobContent)
		let objects: [PackObject] = [
			PackObject(type: .blob, sha: sha, content: blobContent),
		]

		let packfile = createPackfile(objects)
		let packDir = gitDir.appendingPathComponent("objects").appendingPathComponent("pack")
		try packfile.write(to: packDir.appendingPathComponent("test.pack"))

		let data = try await readObjectData(at: gitDir.path, sha: sha)
		let nullIndex = try #require(data.firstIndex(of: 0))
		let header = try #require(String(data: data.prefix(upTo: nullIndex), encoding: .utf8))
		let body = data.suffix(from: data.index(after: nullIndex))

		#expect(header == "blob \(blobContent.count)")
		#expect(body == blobContent)
	}

	@Test func shouldThrowWhenObjectNotFound() async throws {
		let testDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("gitologist-test-\(UUID().uuidString.prefix(8))")
		let gitDir = testDir.appendingPathComponent(".git")
		try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: testDir) }

		do {
			_ = try await readObjectData(at: gitDir.path, sha: "0000000000000000000000000000000000000000")
			fatalError("Should have thrown")
		} catch {
			#expect(error.localizedDescription.contains("Object not found") || (error as? GitError) != nil)
		}
	}

	@Test func shouldReadObjectViaPackfile() async throws {
		let testDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("gitologist-test-\(UUID().uuidString.prefix(8))")
		let gitDir = testDir.appendingPathComponent(".git")
		try FileManager.default.createDirectory(at: gitDir.appendingPathComponent("objects").appendingPathComponent("pack"), withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: testDir) }

		let commitContent = Data(
			"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n".utf8
		)
		let sha = computeSha(type: "commit", content: commitContent)
		let objects: [PackObject] = [
			PackObject(type: .commit, sha: sha, content: commitContent),
		]

		let packfile = createPackfile(objects)
		let packDir = gitDir.appendingPathComponent("objects").appendingPathComponent("pack")
		try packfile.write(to: packDir.appendingPathComponent("commits.pack"))

		let data = try await readObject(at: gitDir.path, sha: sha)
		#expect(data.contains("commit"))
		#expect(data.contains("Initial commit"))
	}
}
