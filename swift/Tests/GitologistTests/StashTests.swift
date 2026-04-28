import Foundation
@testable import Gitologist
import Testing

struct StashTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldStashAModifiedFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let stashSha = try await stash(at: testDirPath.path, message: "WIP")

		#expect(stashSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.modified == [])

		let fileContent = try String(contentsOf: testDirPath.appendingPathComponent("test.txt"), encoding: .utf8)
		#expect(fileContent == "initial content")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldStashAnUntrackedFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "untracked content".write(to: testDirPath.appendingPathComponent("newfile.txt"), atomically: true, encoding: .utf8)

		let stashSha = try await stash(at: testDirPath.path, message: "WIP")

		#expect(stashSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		let exists = fileManager.fileExists(atPath: testDirPath.appendingPathComponent("newfile.txt").path)
		#expect(exists == false)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateStashRef() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let stashSha = try await stash(at: testDirPath.path, message: "Save work")

		let stashRefPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("stash")
		let refContent = try String(contentsOf: stashRefPath, encoding: .utf8)

		#expect(refContent.trimmingCharacters(in: .whitespacesAndNewlines) == stashSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldResetIndexToHEADAfterStash() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])

		let preStashStatus = try await status(at: testDirPath.path)
		#expect(preStashStatus.staged.contains("test.txt"))

		_ = try await stash(at: testDirPath.path, message: "WIP")

		let postStashStatus = try await status(at: testDirPath.path)

		let fileContent = try String(contentsOf: testDirPath.appendingPathComponent("test.txt"), encoding: .utf8)
		#expect(fileContent == "initial content")
		#expect(postStashStatus.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNothingToStash() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: StashError.self) {
			try await stash(at: testDirPath.path, message: "WIP")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: StashError.self) {
			try await stash(at: nonGitDir.path, message: "WIP")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldHandleCustomStashMessage() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		let message = "Work in progress on feature X"
		_ = try await stash(at: testDirPath.path, message: message)

		let stashRefPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("stash")
		let stashSha = try String(contentsOf: stashRefPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)

		let commitPath = testDirPath
			.appendingPathComponent(".git")
			.appendingPathComponent("objects")
			.appendingPathComponent(String(stashSha.prefix(2)))
			.appendingPathComponent(String(stashSha.dropFirst(2)))

		let exists = fileManager.fileExists(atPath: commitPath.path)
		#expect(exists)

		try? fileManager.removeItem(at: testDirPath)
	}
}
