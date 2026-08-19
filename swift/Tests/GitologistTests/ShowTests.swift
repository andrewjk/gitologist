import Foundation
@testable import Gitologist
import Testing

struct ShowTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldReadFileContentAtHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		let content = try await show(at: testDirPath.path, filePath: "test.txt")

		#expect(content == "content")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReadNestedFileContentAtHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let subDir = testDirPath.appendingPathComponent("sub")
		try fileManager.createDirectory(at: subDir, withIntermediateDirectories: true)
		try "inner content".write(to: subDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["sub/inner.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add nested file")

		let content = try await show(at: testDirPath.path, filePath: "sub/inner.txt")

		#expect(content == "inner content")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReflectLatestCommittedContentAfterUpdates() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "v1".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First")

		try #expect(await show(at: testDirPath.path, filePath: "test.txt") == "v1")

		try "v2".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second")

		try #expect(await show(at: testDirPath.path, filePath: "test.txt") == "v2")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldNotReflectUncommittedWorkingChanges() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "committed".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "uncommitted".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let content = try await show(at: testDirPath.path, filePath: "test.txt")

		#expect(content == "committed")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: ShowError.self) {
			try await show(at: nonGitDir.path, filePath: "test.txt")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorIfFileDoesNotExistInHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: ShowError.self) {
			try await show(at: testDirPath.path, filePath: "nonexistent.txt")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReadFileContentAtSpecificCommit() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "v1".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		let firstSha = try await commit(at: testDirPath.path, message: "First")

		try "v2".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		let secondSha = try await commit(at: testDirPath.path, message: "Second")

		try #expect(await show(at: testDirPath.path, filePath: "test.txt", commit: firstSha) == "v1")
		try #expect(await show(at: testDirPath.path, filePath: "test.txt", commit: secondSha) == "v2")
		try #expect(await show(at: testDirPath.path, filePath: "test.txt") == "v2")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowPathNotFoundAtOlderCommitForFileAddedLater() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "first".write(to: testDirPath.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["first.txt"])
		let firstSha = try await commit(at: testDirPath.path, message: "First")

		try "later".write(to: testDirPath.appendingPathComponent("later.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["later.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add later file")

		await #expect(throws: ShowError.pathNotFound("later.txt")) {
			try await show(at: testDirPath.path, filePath: "later.txt", commit: firstSha)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfCommitNotFound() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: ShowError.commitNotFound("0000000000000000000000000000000000000000")) {
			try await show(
				at: testDirPath.path,
				filePath: "test.txt",
				commit: "0000000000000000000000000000000000000000"
			)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfPathPointsToADirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let subDir = testDirPath.appendingPathComponent("sub")
		try fileManager.createDirectory(at: subDir, withIntermediateDirectories: true)
		try "inner".write(to: subDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["sub/inner.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add nested file")

		await #expect(throws: ShowError.self) {
			try await show(at: testDirPath.path, filePath: "sub")
		}

		try? fileManager.removeItem(at: testDirPath)
	}
}
