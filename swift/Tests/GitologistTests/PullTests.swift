import Foundation
@testable import Gitologist
import Testing

struct PullTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldPullFromDefaultRemoteAndBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path)

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		try await pull(at: testDirPath.path)

		let content = try String(contentsOf: testDirPath.appendingPathComponent("test.txt"), encoding: .utf8)
		#expect(content == "modified")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPullFromSpecifiedRemote() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path, remote: "upstream")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path, remote: "upstream")

		try await pull(at: testDirPath.path, remote: "upstream")

		let content = try String(contentsOf: testDirPath.appendingPathComponent("test.txt"), encoding: .utf8)
		#expect(content == "modified")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPullFromSpecifiedBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let headPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		try "ref: refs/heads/main\n".write(to: headPath, atomically: true, encoding: .utf8)

		try fileManager.createDirectory(
			at: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads"),
			withIntermediateDirectories: true
		)
		try "abc123\n".write(
			to: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main"),
			atomically: true,
			encoding: .utf8
		)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path, branch: "main")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path, branch: "main")

		try await pull(at: testDirPath.path, branch: "main")

		let content = try String(contentsOf: testDirPath.appendingPathComponent("test.txt"), encoding: .utf8)
		#expect(content == "modified")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: PullError.self) {
			try await pull(at: nonGitDir.path)
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorIfRemoteBranchDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: PullError.self) {
			try await pull(at: testDirPath.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateLocalBranchReference() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path)

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		let secondSha = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		try await pull(at: testDirPath.path)

		let localBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main")
		let localBranchContent = try String(contentsOf: localBranchPath, encoding: .utf8)

		#expect(localBranchContent.trimmingCharacters(in: .whitespacesAndNewlines) == secondSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleDirectories() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try fileManager.createDirectory(at: testDirPath.appendingPathComponent("src"), withIntermediateDirectories: true)
		try "console.log('hello')".write(to: testDirPath.appendingPathComponent("src").appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["src/index.ts"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path)

		try "console.log('world')".write(to: testDirPath.appendingPathComponent("src").appendingPathComponent("index.ts"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["src/index.ts"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		try await pull(at: testDirPath.path)

		let content = try String(contentsOf: testDirPath.appendingPathComponent("src").appendingPathComponent("index.ts"), encoding: .utf8)
		#expect(content == "console.log('world')")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultipleFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try "content3".write(to: testDirPath.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file1.txt", "file2.txt", "file3.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path)

		try "modified1".write(to: testDirPath.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "modified2".write(to: testDirPath.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try "modified3".write(to: testDirPath.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file1.txt", "file2.txt", "file3.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		try await pull(at: testDirPath.path)

		let content1 = try String(contentsOf: testDirPath.appendingPathComponent("file1.txt"), encoding: .utf8)
		let content2 = try String(contentsOf: testDirPath.appendingPathComponent("file2.txt"), encoding: .utf8)
		let content3 = try String(contentsOf: testDirPath.appendingPathComponent("file3.txt"), encoding: .utf8)

		#expect(content1 == "modified1")
		#expect(content2 == "modified2")
		#expect(content3 == "modified3")

		try? fileManager.removeItem(at: testDirPath)
	}
}
