import Foundation
@testable import Gitologist
import Testing

struct RemoteTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldAddRemote() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[remote \"origin\"]"))
		#expect(configContent.contains("url = https://github.com/user/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFetchRefspec() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("fetch = +refs/heads/*:refs/remotes/origin/*"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddRemoteWithCustomName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "upstream", url: "https://github.com/original/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[remote \"upstream\"]"))
		#expect(configContent.contains("url = https://github.com/original/repo.git"))
		#expect(configContent.contains("fetch = +refs/heads/*:refs/remotes/upstream/*"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: RemoteError.self) {
			try await remoteAdd(at: nonGitDir.path, name: "origin", url: "https://github.com/user/repo.git")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorIfRemoteAlreadyExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		await #expect(throws: RemoteError.self) {
			try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/other/repo.git")
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPreserveExistingConfig() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")
		try await remoteAdd(at: testDirPath.path, name: "upstream", url: "https://github.com/original/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[remote \"origin\"]"))
		#expect(configContent.contains("[remote \"upstream\"]"))
		#expect(configContent.contains("url = https://github.com/user/repo.git"))
		#expect(configContent.contains("url = https://github.com/original/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAppendToExistingConfigFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let originalConfig = try String(contentsOf: configPath, encoding: .utf8)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		let newConfig = try String(contentsOf: configPath, encoding: .utf8)

		#expect(newConfig.contains(originalConfig.trimmingCharacters(in: .whitespacesAndNewlines)))
		#expect(newConfig.contains("[remote \"origin\"]"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnFalseWhenNotAGitRepository() {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		#expect(hasRemote(at: nonGitDir.path) == false)
	}

	@Test func shouldReturnFalseWhenRemoteDoesNotExist() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		#expect(hasRemote(at: testDirPath.path, name: "nonexistent") == false)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnTrueWhenOriginRemoteExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		#expect(hasRemote(at: testDirPath.path) == true)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnTrueWhenCustomNamedRemoteExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "upstream", url: "https://github.com/original/repo.git")

		#expect(hasRemote(at: testDirPath.path, name: "upstream") == true)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnFalseForDifferentRemoteName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")

		#expect(hasRemote(at: testDirPath.path, name: "upstream") == false)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateRemoteUrl() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")
		try setRemoteUrl(at: testDirPath.path, name: "origin", url: "https://github.com/other/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("url = https://github.com/other/repo.git"))
		#expect(!configContent.contains("url = https://github.com/user/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldPreserveOtherRemotePropertiesWhenUpdatingUrl() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://github.com/user/repo.git")
		try setRemoteUrl(at: testDirPath.path, name: "origin", url: "https://github.com/other/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[remote \"origin\"]"))
		#expect(configContent.contains("fetch = +refs/heads/*:refs/remotes/origin/*"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorWhenSettingUrlIfNotAGitRepository() {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try? fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		#expect(throws: RemoteError.self) {
			try setRemoteUrl(at: nonGitDir.path, name: "origin", url: "https://github.com/other/repo.git")
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldUpdateUrlForCustomNamedRemote() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)
		try await remoteAdd(at: testDirPath.path, name: "upstream", url: "https://github.com/original/repo.git")
		try setRemoteUrl(at: testDirPath.path, name: "upstream", url: "https://github.com/fork/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("url = https://github.com/fork/repo.git"))
		#expect(!configContent.contains("url = https://github.com/original/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}
}
