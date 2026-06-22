import Foundation
@testable import Gitologist
import Testing

struct BranchTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	@Test func shouldReturnBranchNameFromHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
		try "ref: refs/heads/main\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

		let branch = try await getCurrentBranch(at: gitDir.path)
		#expect(branch == "main")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowIfHEADIsDetached() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
		try "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

		await #expect(throws: GitError.self) {
			try await getCurrentBranch(at: gitDir.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnCurrentCommitSHA() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
		try "ref: refs/heads/main\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

		let refsHeads = gitDir.appendingPathComponent("refs").appendingPathComponent("heads")
		try fileManager.createDirectory(at: refsHeads, withIntermediateDirectories: true)
		try "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n".write(to: refsHeads.appendingPathComponent("main"), atomically: true, encoding: .utf8)

		let commitSha = try await getCurrentCommit(at: gitDir.path)
		#expect(commitSha == "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnNilIfNoCommitExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
		try "ref: refs/heads/main\n".write(to: gitDir.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)

		let commitSha = try await getCurrentCommit(at: gitDir.path)
		#expect(commitSha == nil)

		try? fileManager.removeItem(at: testDirPath)
	}
}
