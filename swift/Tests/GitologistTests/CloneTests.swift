import Foundation
@testable import Gitologist
import Testing

struct CloneTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldCloneRepositoryToDefaultDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let targetPath = testDirPath.appendingPathComponent("repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		let gitDir = targetPath.appendingPathComponent(".git")
		#expect(fileManager.fileExists(atPath: gitDir.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCloneToSpecifiedDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let targetPath = testDirPath.appendingPathComponent("my-custom-dir")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)
		#expect(fileManager.fileExists(atPath: targetPath.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldExtractRepoNameFromURL() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/my-repo.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldInitializeGitRepository() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		let headPath = targetPath.appendingPathComponent(".git").appendingPathComponent("HEAD")
		let headContent = try String(contentsOf: headPath, encoding: .utf8)

		#expect(headContent.contains("ref: refs/heads/main"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddRemote() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		let configPath = targetPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("[remote \"origin\"]"))
		#expect(configContent.contains("url = https://github.com/user/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleURLsWithGitExtension() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		let configPath = targetPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("url = https://github.com/user/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleURLsWithoutGitExtension() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		let configPath = targetPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("url = https://github.com/user/repo"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldExtractRepoNameFromComplexURL() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/org/team/project.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleSubdirectoryInURL() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/nested/project.git"
		let targetPath = testDirPath.appendingPathComponent("test-repo")
		let resultPath = try await clone(url: url, targetPath: targetPath.path)

		#expect(resultPath == targetPath.path)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfDirectoryAlreadyExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let url = "https://github.com/user/repo.git"
		let existingPath = testDirPath.appendingPathComponent("repo")
		try fileManager.createDirectory(at: existingPath, withIntermediateDirectories: true)

		await #expect(throws: CloneError.self) {
			try await clone(url: url, targetPath: existingPath.path)
		}

		try? fileManager.removeItem(at: testDirPath)
	}
}
