import Foundation
@testable import Gitologist
import Testing

struct CommitTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldCommitStagedFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Initial commit")

		#expect(commitSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNothingToCommit() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		await #expect(throws: CommitError.self) {
			try await commit(at: testDirPath.path, message: "Empty commit")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNoFilesStaged() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		await #expect(throws: CommitError.self) {
			try await commit(at: testDirPath.path, message: "Test commit")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: CommitError.self) {
			try await commit(at: nonGitDir.path, message: "Test commit")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldCreateCommitObjectInGitObjects() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		_ = try await commit(at: testDirPath.path, message: "Test commit")

		let objectsDir = testDirPath.appendingPathComponent(".git").appendingPathComponent("objects")
		let dirs = try fileManager.contentsOfDirectory(atPath: objectsDir.path)

		#expect(dirs.count > 0)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateBranchReference() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Test commit")

		let branchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main")
		let branchRef = try String(contentsOf: branchPath, encoding: .utf8)

		#expect(branchRef.trimmingCharacters(in: .whitespacesAndNewlines) == commitSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultipleCommits() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let firstSha = try await commit(at: testDirPath.path, message: "First commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let secondSha = try await commit(at: testDirPath.path, message: "Second commit")

		#expect(firstSha != secondSha)

		let branchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main")
		let branchRef = try String(contentsOf: branchPath, encoding: .utf8)

		#expect(branchRef.trimmingCharacters(in: .whitespacesAndNewlines) == secondSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleCommitWithMessageContainingNewlines() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let message = "Multi-line\ncommit\nmessage"
		let commitSha = try await commit(at: testDirPath.path, message: message)

		#expect(commitSha.count == 40)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCommitMultipleFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try "content3".write(to: testDirPath.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file1.txt", "file2.txt", "file3.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Add multiple files")

		#expect(commitSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}
}
