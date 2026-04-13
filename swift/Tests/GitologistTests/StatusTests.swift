import CryptoKit
import Foundation
@testable import Gitologist
import Testing

struct StatusTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldReturnCurrentBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.branch == "main")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnUpToDateMessage() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.upToDate.contains("Your branch is up to date with"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnEmptyArraysForChangesWhenNoFilesExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.staged == [])
		#expect(result.modified == [])
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectUntrackedFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked.contains("test.txt"))
		#expect(result.modified == [])
		#expect(result.staged == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectMultipleUntrackedFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try "# Test".write(to: testDirPath.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
		let srcDir = testDirPath.appendingPathComponent("src")
		try fileManager.createDirectory(at: srcDir, withIntermediateDirectories: true)
		try "console.log('hello')".write(to: srcDir.appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked.contains("test.txt"))
		#expect(result.untracked.contains("README.md"))
		#expect(result.untracked.contains("src/index.ts"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectModifiedFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		try "modified content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.modified.contains("test.txt"))
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectDeletedFilesAsModified() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let testFile = testDirPath.appendingPathComponent("test.txt")
		try? fileManager.removeItem(at: testFile)

		let result = try await status(at: testDirPath.path)
		#expect(result.deleted.contains("test.txt"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleDetachedHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let headPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		try "deadbeef\n".write(to: headPath, atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.branch == "(detached HEAD)")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: GitError.self) {
			try await status(at: nonGitDir.path)
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldHandleCustomBranchName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let headPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		try "ref: refs/heads/main\n".write(to: headPath, atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.branch == "main")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldNotDetectGitDirectoryAsUntracked() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let otherDir = testDirPath.appendingPathComponent(".git").appendingPathComponent("other")
		try fileManager.createDirectory(at: otherDir, withIntermediateDirectories: true)
		try "content".write(to: otherDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCorrectlyIdentifyFilesMatchingIndex() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.modified == [])
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	private func sha1Hash(of string: String) -> String {
		let data = string.data(using: .utf8)!
		let sha1 = Insecure.SHA1.hash(data: data)
		return sha1.compactMap { String(format: "%02x", $0) }.joined()
	}
}
