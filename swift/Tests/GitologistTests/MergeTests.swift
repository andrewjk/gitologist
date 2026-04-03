import Foundation
@testable import Gitologist
import Testing

struct MergeTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: MergeError.self) {
			try await merge(at: nonGitDir.path, branchName: "feature")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorWhenMergingABranchIntoItself() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: MergeError.self) {
			try await merge(at: testDirPath.path, branchName: "main")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfBranchNotFound() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		await #expect(throws: MergeError.self) {
			try await merge(at: testDirPath.path, branchName: "nonexistent")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorWhenMergingIntoEmptyBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")
		try await checkoutBranch(at: testDirPath.path, branchName: "feature")

		try "feature content".write(to: testDirPath.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["feature.txt"])
		_ = try await commit(at: testDirPath.path, message: "Feature commit")

		try await checkoutBranch(at: testDirPath.path, branchName: "main")
		try await deleteBranchCommit(at: testDirPath.path)

		await #expect(throws: MergeError.self) {
			try await merge(at: testDirPath.path, branchName: "feature")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPerformFastForwardMergeWhenPossible() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")
		try await checkoutBranch(at: testDirPath.path, branchName: "feature")

		try "feature content".write(to: testDirPath.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["feature.txt"])
		let featureSha = try await commit(at: testDirPath.path, message: "Feature commit")

		try await checkoutBranch(at: testDirPath.path, branchName: "main")

		let result = try await merge(at: testDirPath.path, branchName: "feature")

		#expect(result.success == true)
		#expect(result.fastForward == true)
		#expect(result.commitSha == featureSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateMergeCommitWhenNotFastForward() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")
		try await checkoutBranch(at: testDirPath.path, branchName: "feature")

		try "feature content".write(to: testDirPath.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["feature.txt"])
		_ = try await commit(at: testDirPath.path, message: "Feature commit")

		try await checkoutBranch(at: testDirPath.path, branchName: "main")

		try "main content".write(to: testDirPath.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["main.txt"])
		_ = try await commit(at: testDirPath.path, message: "Master commit")

		let result = try await merge(at: testDirPath.path, branchName: "feature")

		#expect(result.success == true)
		#expect(result.fastForward == false)

		let shaPattern = /^[a-f0-9]{40}$/
		#expect(result.commitSha?.wholeMatch(of: shaPattern) != nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAllowNonFastForwardMergeWithOption() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")
		try await checkoutBranch(at: testDirPath.path, branchName: "feature")

		try "feature content".write(to: testDirPath.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["feature.txt"])
		_ = try await commit(at: testDirPath.path, message: "Feature commit")

		try await checkoutBranch(at: testDirPath.path, branchName: "main")

		let options = MergeOptions(message: nil, noFastForward: true)
		let result = try await merge(at: testDirPath.path, branchName: "feature", options: options)

		#expect(result.success == true)
		#expect(result.fastForward == false)

		let shaPattern = /^[a-f0-9]{40}$/
		#expect(result.commitSha?.wholeMatch(of: shaPattern) != nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReportAlreadyUpToDateWhenBranchesAreSame() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")

		let result = try await merge(at: testDirPath.path, branchName: "feature")

		#expect(result.success == true)
		#expect(result.message == "Already up to date.")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUseCustomMergeMessage() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await createBranch(at: testDirPath.path, branchName: "feature")
		try await checkoutBranch(at: testDirPath.path, branchName: "feature")

		try "feature content".write(to: testDirPath.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["feature.txt"])
		_ = try await commit(at: testDirPath.path, message: "Feature commit")

		try await checkoutBranch(at: testDirPath.path, branchName: "main")

		try "main content".write(to: testDirPath.appendingPathComponent("main.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["main.txt"])
		_ = try await commit(at: testDirPath.path, message: "Master commit")

		let options = MergeOptions(message: "Custom merge message", noFastForward: nil)
		let result = try await merge(at: testDirPath.path, branchName: "feature", options: options)

		#expect(result.success == true)
		#expect(result.message == "Custom merge message")

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Helper Functions

	private func createBranch(at path: String, branchName: String) async throws {
		let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
		let headPath = gitDir.appendingPathComponent("HEAD")
		let currentHead = try String(contentsOf: headPath, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		let pattern = /^ref: refs\/heads\/(.+)$/
		guard let match = currentHead.wholeMatch(of: pattern) else {
			throw GitError.notOnABranch
		}

		let currentBranch = String(match.1)
		let currentBranchPath = gitDir
			.appendingPathComponent("refs")
			.appendingPathComponent("heads")
			.appendingPathComponent(currentBranch)

		guard FileManager.default.fileExists(atPath: currentBranchPath.path) else {
			throw GitError.notOnABranch
		}

		let currentCommit = try String(contentsOf: currentBranchPath, encoding: .utf8)

		let newBranchPath = gitDir
			.appendingPathComponent("refs")
			.appendingPathComponent("heads")
			.appendingPathComponent(branchName)

		try FileManager.default.createDirectory(
			at: newBranchPath.deletingLastPathComponent(),
			withIntermediateDirectories: true
		)
		try currentCommit.write(to: newBranchPath, atomically: true, encoding: .utf8)
	}

	private func checkoutBranch(at path: String, branchName: String) async throws {
		let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
		let headPath = gitDir.appendingPathComponent("HEAD")
		try "ref: refs/heads/\(branchName)\n".write(to: headPath, atomically: true, encoding: .utf8)
	}

	private func deleteBranchCommit(at path: String) async throws {
		let gitDir = URL(fileURLWithPath: path).appendingPathComponent(".git")
		let headPath = gitDir.appendingPathComponent("HEAD")
		let currentHead = try String(contentsOf: headPath, encoding: .utf8)
			.trimmingCharacters(in: .whitespacesAndNewlines)

		let pattern = /^ref: refs\/heads\/(.+)$/
		guard let match = currentHead.wholeMatch(of: pattern) else {
			throw GitError.notOnABranch
		}

		let currentBranch = String(match.1)
		let currentBranchPath = gitDir
			.appendingPathComponent("refs")
			.appendingPathComponent("heads")
			.appendingPathComponent(currentBranch)

		if FileManager.default.fileExists(atPath: currentBranchPath.path) {
			try FileManager.default.removeItem(at: currentBranchPath)
		}
	}
}
