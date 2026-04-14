import Foundation
@testable import Gitologist
import Testing

struct PushTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldPushToDefaultRemoteAndBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path)

		let remoteBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("origin").appendingPathComponent("main")
		#expect(fileManager.fileExists(atPath: remoteBranchPath.path))

		let remoteBranchContent = try String(contentsOf: remoteBranchPath, encoding: .utf8)
		let shaPattern = try NSRegularExpression(pattern: "^[a-f0-9]{40}$")
		let range = NSRange(location: 0, length: remoteBranchContent.utf16.count)
		#expect(shaPattern.firstMatch(in: remoteBranchContent, options: [], range: range) != nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPushToSpecifiedRemote() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path, remote: "upstream")

		let remoteBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("upstream").appendingPathComponent("main")
		#expect(fileManager.fileExists(atPath: remoteBranchPath.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPushToSpecifiedBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let headPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		try "ref: refs/heads/main\n".write(to: headPath, atomically: true, encoding: .utf8)

		try fileManager.createDirectory(at: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads"), withIntermediateDirectories: true)
		try "abc123\n".write(to: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main"), atomically: true, encoding: .utf8)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path, branch: "main")

		let remoteBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("origin").appendingPathComponent("main")
		#expect(fileManager.fileExists(atPath: remoteBranchPath.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: PushError.self) {
			try await push(at: nonGitDir.path)
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorIfThereAreUncommittedChanges() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)

		await #expect(throws: PushError.self) {
			try await push(at: testDirPath.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfThereAreUntrackedFiles() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "untracked".write(to: testDirPath.appendingPathComponent("test2.txt"), atomically: true, encoding: .utf8)

		await #expect(throws: PushError.self) {
			try await push(at: testDirPath.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfLocalBranchDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let headPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		try "ref: refs/heads/nonexistent\n".write(to: headPath, atomically: true, encoding: .utf8)

		await #expect(throws: PushError.self) {
			try await push(at: testDirPath.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateExistingRemoteBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try await push(at: testDirPath.path)

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		let secondSha = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		let remoteBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("origin").appendingPathComponent("main")
		let remoteBranchContent = try String(contentsOf: remoteBranchPath, encoding: .utf8)

		#expect(remoteBranchContent.trimmingCharacters(in: .whitespacesAndNewlines) == secondSha)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateRemoteDirectoryIfItDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try await push(at: testDirPath.path, remote: "myremote")

		let remoteDir = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("myremote")
		#expect(fileManager.fileExists(atPath: remoteDir.path))

		let remoteBranchPath = remoteDir.appendingPathComponent("main")
		#expect(fileManager.fileExists(atPath: remoteBranchPath.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultiplePushesToSameBranch() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try await push(at: testDirPath.path)

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try await push(at: testDirPath.path)

		let remoteBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("remotes").appendingPathComponent("origin").appendingPathComponent("main")
		let remoteBranchContent = try String(contentsOf: remoteBranchPath, encoding: .utf8)
		let remoteSha = remoteBranchContent.trimmingCharacters(in: .whitespacesAndNewlines)

		let localBranchPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").appendingPathComponent("main")
		let localBranchContent = try String(contentsOf: localBranchPath, encoding: .utf8)
		let localSha = localBranchContent.trimmingCharacters(in: .whitespacesAndNewlines)

		#expect(remoteSha == localSha)

		try? fileManager.removeItem(at: testDirPath)
	}
}

struct SetUpstreamBranchTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldCreateNewBranchSectionWithRemoteAndMergeSettings() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "origin", branchName: "feature")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"feature\"]"))
		#expect(configContent.contains("remote = origin"))
		#expect(configContent.contains("merge = refs/heads/feature"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddRemoteAndMergeSettingsToExistingBranchSection() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try "[branch \"feature\"]\n\tdescription = test branch\n".write(to: configPath, atomically: true, encoding: .utf8)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "upstream", branchName: "feature")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"feature\"]"))
		#expect(configContent.contains("description = test branch"))
		#expect(configContent.contains("remote = upstream"))
		#expect(configContent.contains("merge = refs/heads/feature"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateExistingRemoteAndMergeSettings() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try "[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n".write(to: configPath, atomically: true, encoding: .utf8)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "upstream", branchName: "main")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"main\"]"))
		#expect(configContent.contains("remote = upstream"))
		#expect(configContent.contains("merge = refs/heads/main"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultipleBranchesCorrectly() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try "[branch \"main\"]\n\tremote = origin\n\tmerge = refs/heads/main\n".write(to: configPath, atomically: true, encoding: .utf8)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "upstream", branchName: "feature")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"main\"]"))
		#expect(configContent.contains("remote = origin"))
		#expect(configContent.contains("[branch \"feature\"]"))
		#expect(configContent.contains("remote = upstream"))
		#expect(configContent.contains("merge = refs/heads/feature"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPreserveOtherConfigSections() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try "[core]\n\trepositoryformatversion = 0\n\n[remote \"origin\"]\n\turl = test.git\n".write(to: configPath, atomically: true, encoding: .utf8)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "origin", branchName: "main")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[core]"))
		#expect(configContent.contains("repositoryformatversion = 0"))
		#expect(configContent.contains("[remote \"origin\"]"))
		#expect(configContent.contains("url = test.git"))
		#expect(configContent.contains("[branch \"main\"]"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleEmptyConfigFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try "".write(to: configPath, atomically: true, encoding: .utf8)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "origin", branchName: "main")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"main\"]"))
		#expect(configContent.contains("remote = origin"))
		#expect(configContent.contains("merge = refs/heads/main"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMissingConfigFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		try? fileManager.removeItem(at: configPath)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "origin", branchName: "main")

		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[branch \"main\"]"))
		#expect(configContent.contains("remote = origin"))
		#expect(configContent.contains("merge = refs/heads/main"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUseTabsForIndentation() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await setUpstreamBranch(at: testDirPath.path, remoteName: "origin", branchName: "main")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("\tremote = origin"))
		#expect(configContent.contains("\tmerge = refs/heads/main"))

		try? fileManager.removeItem(at: testDirPath)
	}
}
