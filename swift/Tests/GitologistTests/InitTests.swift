import Foundation
@testable import Gitologist
import Testing

struct InitTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldCreateGitDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		let gitDir = testDirPath.appendingPathComponent(".git")
		#expect(fileManager.fileExists(atPath: gitDir.path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldNotCreateGitIfItAlreadyExists() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		let gitDir = testDirPath.appendingPathComponent(".git")
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		let customFile = gitDir.appendingPathComponent("custom-file")
		try "test".write(to: customFile, atomically: true, encoding: .utf8)

		try await initRepo(at: testDirPath.path)

		let customFileContent = try String(contentsOf: customFile, encoding: .utf8)
		#expect(customFileContent == "test")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateHEADFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		let headContent = try String(contentsOf: testDirPath.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)
		#expect(headContent == "ref: refs/heads/main\n")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateConfigFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		let configContent = try String(contentsOf: testDirPath.appendingPathComponent(".git").appendingPathComponent("config"), encoding: .utf8)
		#expect(configContent.contains("[core]"))
		#expect(configContent.contains("repositoryformatversion = 0"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateObjectsDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		#expect(fileManager.fileExists(atPath: testDirPath.appendingPathComponent(".git").appendingPathComponent("objects").path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateRefsHeadsDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		#expect(fileManager.fileExists(atPath: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateRefsTagsDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		#expect(fileManager.fileExists(atPath: testDirPath.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("tags").path))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCreateInfoDirectory() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)

		try await initRepo(at: testDirPath.path)
		#expect(fileManager.fileExists(atPath: testDirPath.appendingPathComponent(".git").appendingPathComponent("info").path))

		try? fileManager.removeItem(at: testDirPath)
	}
}
