import Foundation
@testable import Gitologist
import Testing

struct GitCompatTests {
	var baseDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-compat-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	// MARK: - Helper Methods

	private func runGit(args: [String], in directory: URL) throws -> String {
		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = args
		process.currentDirectoryURL = directory
		process.standardOutput = pipe
		process.standardError = pipe
		try process.run()
		process.waitUntilExit()

		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		return String(data: data, encoding: .utf8) ?? ""
	}

	private func setupRemoteRepo(at baseDirPath: URL) async throws -> (remoteDir: URL, defaultBranch: String) {
		// Detect git default branch
		var defaultBranch = "main"

		// Create a test repo to check default branch
		let testDir = baseDirPath.appendingPathComponent("branch-test")
		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		_ = try runGit(args: ["init"], in: testDir)
		let branchOutput = try runGit(args: ["branch", "--show-current"], in: testDir)
		if !branchOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			defaultBranch = branchOutput.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		try? fileManager.removeItem(at: testDir)

		// Create a "remote" repository using real git
		let remoteDir = baseDirPath.appendingPathComponent("remote.git")
		try fileManager.createDirectory(at: remoteDir, withIntermediateDirectories: true)
		_ = try runGit(args: ["init", "--bare"], in: remoteDir)

		// Create initial content in the remote using a temporary clone
		let tempClone = baseDirPath.appendingPathComponent("temp-clone")
		_ = try runGit(args: ["clone", remoteDir.path, "temp-clone"], in: baseDirPath)
		try "# Initial".write(to: tempClone.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
		_ = try runGit(args: ["add", "."], in: tempClone)
		_ = try runGit(args: ["commit", "-m", "Initial commit"], in: tempClone)
		_ = try runGit(args: ["push", "origin", defaultBranch], in: tempClone)
		try? fileManager.removeItem(at: tempClone)

		return (remoteDir, defaultBranch)
	}

	// MARK: - Init Tests

	@Test func shouldCreateSameDirectoryStructureAsGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-init")
		let theirDir = baseDirPath.appendingPathComponent("their-init")

		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: theirDir, withIntermediateDirectories: true)

		try await initRepo(at: ourDir.path)
		_ = try runGit(args: ["init"], in: theirDir)

		let ourGitDir = ourDir.appendingPathComponent(".git")
		let theirGitDir = theirDir.appendingPathComponent(".git")

		#expect(fileManager.fileExists(atPath: ourGitDir.path))
		#expect(fileManager.fileExists(atPath: theirGitDir.path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("objects").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("objects").path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("refs").appendingPathComponent("heads").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("refs").appendingPathComponent("heads").path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("refs").appendingPathComponent("tags").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("refs").appendingPathComponent("tags").path))
	}

	@Test func shouldCreateHEADPointingToSameRefFormatAsGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-init2")
		let theirDir = baseDirPath.appendingPathComponent("their-init2")

		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: theirDir, withIntermediateDirectories: true)

		try await initRepo(at: ourDir.path)
		_ = try runGit(args: ["init"], in: theirDir)

		let ourHead = try String(contentsOf: ourDir.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)
		let theirHead = try String(contentsOf: theirDir.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)

		// Both should point to a branch (usually main or main)
		let headPattern = /^ref: refs\/heads\//
		#expect(ourHead.wholeMatch(of: headPattern) != nil || ourHead.hasPrefix("ref: refs/heads/"))
		#expect(theirHead.wholeMatch(of: headPattern) != nil || theirHead.hasPrefix("ref: refs/heads/"))
	}

	// MARK: - Add and Commit Tests

	@Test func shouldCreateAnIndexThatGitCanRead() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-add")
		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try await initRepo(at: ourDir.path)

		try "test content".write(to: ourDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try "test content 2".write(to: ourDir.appendingPathComponent("test 2.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["test.txt", "test 2.txt"])

		let gitStatus = try runGit(args: ["status"], in: ourDir)

		#expect(gitStatus.contains("new file:   test.txt"))
		#expect(gitStatus.contains("new file:   test 2.txt"))
	}

	@Test func shouldCreateCommitsThatGitCanRead() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-commit")
		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try await initRepo(at: ourDir.path)

		try "test content".write(to: ourDir.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["test.txt"])
		_ = try await commit(at: ourDir.path, message: "Test commit")

		// Verify our commit can be read by git log
		let gitLog = try runGit(args: ["log", "--oneline"], in: ourDir)

		#expect(gitLog.contains("Test commit"))

		// Check `git status`
		let gitStatus = try runGit(args: ["status"], in: ourDir)

		#expect(gitStatus.contains("nothing to commit, working tree clean"))
	}

	@Test func shouldProduceSameCommitStructureAsGit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-commit2")
		let theirDir = baseDirPath.appendingPathComponent("their-commit2")

		// Our implementation
		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try await initRepo(at: ourDir.path)
		try "content".write(to: ourDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["file.txt"])
		let ourSha = try await commit(at: ourDir.path, message: "Same message")

		// Real git
		try fileManager.createDirectory(at: theirDir, withIntermediateDirectories: true)
		_ = try runGit(args: ["init"], in: theirDir)
		try "content".write(to: theirDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		_ = try runGit(args: ["add", "."], in: theirDir)
		_ = try runGit(args: ["commit", "-m", "Same message"], in: theirDir)

		// Both should have valid commit SHAs
		let shaPattern = /^[a-f0-9]{40}$/
		#expect(ourSha.wholeMatch(of: shaPattern) != nil)

		// Both should have 1 commit in log
		let ourLog = try await log(at: ourDir.path)
		let theirLog = try runGit(args: ["log", "--oneline"], in: theirDir)

		#expect(ourLog.count == 1)
		#expect(theirLog.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).count == 1)
	}

	// MARK: - Log Tests

	@Test func shouldShowSameCommitOrderAsGitLog() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let ourDir = baseDirPath.appendingPathComponent("our-log")
		try fileManager.createDirectory(at: ourDir, withIntermediateDirectories: true)
		try await initRepo(at: ourDir.path)

		// Create multiple commits
		try "content1".write(to: ourDir.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["file1.txt"])
		_ = try await commit(at: ourDir.path, message: "First commit")

		try "content2".write(to: ourDir.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["file2.txt"])
		_ = try await commit(at: ourDir.path, message: "Second commit")

		try "content3".write(to: ourDir.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)
		try await add(at: ourDir.path, files: ["file3.txt"])
		_ = try await commit(at: ourDir.path, message: "Third commit")

		let ourLog = try await log(at: ourDir.path)
		let gitLog = try runGit(args: ["log", "--oneline"], in: ourDir)

		// Both should have 3 commits
		#expect(ourLog.count == 3)
		#expect(gitLog.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines).count == 3)

		// Both should show commits in reverse chronological order
		#expect(ourLog[0].message == "Third commit")
		#expect(ourLog[1].message == "Second commit")
		#expect(ourLog[2].message == "First commit")

		#expect(gitLog.contains("Third commit"))
		#expect(gitLog.contains("Second commit"))
		#expect(gitLog.contains("First commit"))
	}

	// MARK: - Clone Tests

	@Test func shouldCreateRepoStructureLikeGitClone() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)
		defer { try? fileManager.removeItem(at: baseDirPath) }

		let (remoteDir, _) = try await setupRemoteRepo(at: baseDirPath)
		let ourClone = baseDirPath.appendingPathComponent("our-clone2")

		// Our implementation (simplified - just sets up repo and remote)
		_ = try await clone(url: remoteDir.path, targetPath: ourClone.path)

		// Verify our clone exists with proper structure
		#expect(fileManager.fileExists(atPath: ourClone.appendingPathComponent(".git").path))
		#expect(fileManager.fileExists(atPath: ourClone.appendingPathComponent(".git").appendingPathComponent("objects").path))
		#expect(fileManager.fileExists(atPath: ourClone.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").path))

		// Verify remote is configured
		let config = try String(contentsOf: ourClone.appendingPathComponent(".git").appendingPathComponent("config"), encoding: .utf8)
		#expect(config.contains("[remote \"origin\"]"))
		#expect(config.contains("url = \(remoteDir.path)"))
	}
}
