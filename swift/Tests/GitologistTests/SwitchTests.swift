import Foundation
@testable import Gitologist
import Testing

struct SwitchTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	func createBranchRef(at gitDir: URL, name: String) throws {
		let refsHeadsDir = gitDir.appendingPathComponent("refs").appendingPathComponent("heads")
		try fileManager.createDirectory(at: refsHeadsDir, withIntermediateDirectories: true)
		try "abc123\n".write(to: refsHeadsDir.appendingPathComponent(name), atomically: true, encoding: .utf8)
	}

	@Test func shouldWriteBranchNameToHEAD() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)
		try createBranchRef(at: gitDir, name: "feature-branch")

		try await switchBranch(at: testDirPath.path, to: "feature-branch")

		let headContent = try String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
		#expect(headContent == "ref: refs/heads/feature-branch\n")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowIfNotAGitRepository() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		await #expect(throws: SwitchError.self) {
			try await switchBranch(at: testDirPath.path, to: "feature-branch")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowIfBranchDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		await #expect(throws: SwitchError.self) {
			try await switchBranch(at: testDirPath.path, to: "nonexistent")
		}

		try? fileManager.removeItem(at: testDirPath)
	}
}
