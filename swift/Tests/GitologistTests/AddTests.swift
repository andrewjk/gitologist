import CryptoKit
import Foundation
@testable import Gitologist
import Testing

struct AddTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldAddSingleFileToIndex() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["test.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddMultipleFilesToIndex() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try "content3".write(to: testDirPath.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file1.txt", "file2.txt", "file3.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateModifiedFileInIndex() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["test.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorForNonExistentFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		await #expect(throws: AddError.self) {
			try await add(at: testDirPath.path, files: ["nonexistent.txt"])
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: AddError.self) {
			try await add(at: nonGitDir.path, files: ["test.txt"])
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldAddAllUntrackedFilesWithAddAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		let srcDir = testDirPath.appendingPathComponent("src")
		try fileManager.createDirectory(at: srcDir, withIntermediateDirectories: true)
		try "console.log('hello')".write(to: srcDir.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddAllModifiedFilesWithAddAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddBothUntrackedAndModifiedFilesWithAddAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["tracked.txt"])
		try "modified".write(to: testDirPath.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
		try "new content".write(to: testDirPath.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleEmptyRepositoryWithAddAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await addAll(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorWithAddAllIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: AddError.self) {
			try await addAll(at: nonGitDir.path)
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldVerifyFileHashInIndex() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let indexPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("index")
		let index = try await getIndex(at: indexPath.path)
		// The index stores the git blob hash (with "blob <size>\0" header)
		let blobContent = "blob 7\0content"
		let expectedHash = sha1Hash(of: blobContent)

		#expect(index["test.txt"] != nil)
		#expect(index["test.txt"]?.sha == expectedHash)
		#expect(index["test.txt"]?.mode == "100644")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPreserveExistingIndexEntriesWhenAddingNewFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file1.txt"])
		try "content2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file2.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	private func sha1Hash(of string: String) -> String {
		let data = string.data(using: .utf8)!
		let sha1 = Insecure.SHA1.hash(data: data)
		return sha1.compactMap { String(format: "%02x", $0) }.joined()
	}
}
