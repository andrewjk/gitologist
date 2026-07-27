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

	@Test func shouldSwitchToExistingLocalBranchAndUpdateHEADAndTree() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		// First commit on main (file.txt = "A")
		try "A".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		let firstSha = try await commit(at: testDirPath.path, message: "First commit")

		// Create a "feature" branch pointing at the first commit
		let refsHeadsDir = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads")
		try firstSha.write(to: refsHeadsDir.appendingPathComponent("feature"), atomically: true, encoding: .utf8)

		// Second commit on main changes the working tree (file.txt = "B")
		try "B".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await switchBranch(at: testDirPath.path, to: "feature")

		let headContent = try String(contentsOf: testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)
		#expect(headContent == "ref: refs/heads/feature\n")

		// Working tree should now reflect the feature branch (file.txt = "A")
		let content = try String(contentsOf: testDirPath.appendingPathComponent("file.txt"), encoding: .utf8)
		#expect(content == "A")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateLocalBranchFromSingleRemoteTrackingBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		let sha = try await commit(at: testDirPath.path, message: "Initial commit")

		// Simulate a fetched remote-tracking branch with no local branch yet
		let remoteBranchDir = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("origin")
		try fileManager.createDirectory(at: remoteBranchDir, withIntermediateDirectories: true)
		try sha.write(to: remoteBranchDir.appendingPathComponent("feature"), atomically: true, encoding: .utf8)

		try await switchBranch(at: testDirPath.path, to: "feature")

		// Local branch created at the same SHA
		let localBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("feature")
		let localSha = try String(contentsOf: localBranchPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
		#expect(localSha == sha)

		// HEAD points at the new local branch
		let headContent = try String(contentsOf: testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)
		#expect(headContent == "ref: refs/heads/feature\n")

		// Tracking config written
		let config = try String(contentsOf: testDirPath.appendingPathComponent(".git").appendingPathComponent("config"), encoding: .utf8)
		#expect(config.contains("[branch \"feature\"]"))
		#expect(config.contains("remote = origin"))
		#expect(config.contains("merge = refs/heads/feature"))

		// Tree checked out
		let content = try String(contentsOf: testDirPath.appendingPathComponent("file.txt"), encoding: .utf8)
		#expect(content == "content")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowIfBranchDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		await #expect(throws: SwitchError.self) {
			try await switchBranch(at: testDirPath.path, to: "nonexistent")
		}

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
}
