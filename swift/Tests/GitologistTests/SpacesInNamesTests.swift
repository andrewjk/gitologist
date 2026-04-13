import CryptoKit
import Foundation
@testable import Gitologist
import Testing

struct SpacesInNamesTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	// MARK: - Add Tests

	@Test func shouldAddFileWithSingleSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["test file.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFileWithMultipleSpacesInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test  multiple  spaces.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["test  multiple  spaces.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFileWithLeadingSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent(" leading.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: [" leading.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFileWithTrailingSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("trailing .txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["trailing .txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFilesInFolderWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "content".write(to: myFolder.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["my folder/file.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFilesInFolderWithMultipleSpacesInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let myFolder = testDirPath.appendingPathComponent("my  test  folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "content".write(to: myFolder.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["my  test  folder/file.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddFileWithSpaceInNameInFolderWithSpace() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "content".write(to: myFolder.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["my folder/test file.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddMultipleFilesWithSpacesInNames() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)
		try "content3".write(to: testDirPath.appendingPathComponent("file three.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file one.txt", "file two.txt", "file three.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateModifiedFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		try "modified".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["test file.txt"])

		let result = try await status(at: testDirPath.path)
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldAddAllFilesWithSpacesUsingAddAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "console.log('hello')".write(to: myFolder.appendingPathComponent("test file.ts"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Commit Tests

	@Test func shouldCommitFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Add file with space")

		#expect(commitSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCommitMultipleFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file one.txt", "file two.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Add multiple files with spaces")

		#expect(commitSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldCommitFilesInFolderWithSpace() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "content".write(to: myFolder.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["my folder/test file.txt"])

		let commitSha = try await commit(at: testDirPath.path, message: "Add file in folder with space")

		#expect(commitSha.count == 40)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultipleCommitsWithFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])

		let firstSha = try await commit(at: testDirPath.path, message: "First commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])

		let secondSha = try await commit(at: testDirPath.path, message: "Second commit")

		#expect(firstSha != secondSha)

		let result = try await status(at: testDirPath.path)
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Status Tests

	@Test func shouldDetectUntrackedFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked.contains("test file.txt"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectMultipleUntrackedFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "console.log('hello')".write(to: myFolder.appendingPathComponent("test file.ts"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked.contains("file one.txt"))
		#expect(result.untracked.contains("file two.txt"))
		#expect(result.untracked.contains("my folder/test file.ts"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectModifiedFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		try "modified".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDirPath.path)
		#expect(result.modified.contains("test file.txt"))

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldDetectDeletedFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add file")

		try? fileManager.removeItem(at: testDirPath.appendingPathComponent("test file.txt"))

		let result = try await status(at: testDirPath.path)
		#expect(result.deleted.contains("test file.txt"))

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Restore Tests

	@Test func shouldRestoreModifiedFileWithSpaceInName() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await restore(at: testDirPath.path, files: ["test file.txt"])

		let content = try String(contentsOf: testDirPath.appendingPathComponent("test file.txt"), encoding: .utf8)
		#expect(content == "original")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldRestoreMultipleFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "original2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file one.txt", "file two.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "modified2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		try await restore(at: testDirPath.path, files: ["file one.txt", "file two.txt"])

		let content1 = try String(contentsOf: testDirPath.appendingPathComponent("file one.txt"), encoding: .utf8)
		let content2 = try String(contentsOf: testDirPath.appendingPathComponent("file two.txt"), encoding: .utf8)
		#expect(content1 == "original1")
		#expect(content2 == "original2")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldRestoreFileInFolderWithSpace() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)
		try "original".write(to: myFolder.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["my folder/test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: myFolder.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		try await restore(at: testDirPath.path, files: ["my folder/test file.txt"])

		let content = try String(contentsOf: myFolder.appendingPathComponent("test file.txt"), encoding: .utf8)
		#expect(content == "original")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldRestoreAllModifiedFilesWithSpacesUsingRestoreAll() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "original2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		try await add(at: testDirPath.path, files: ["file one.txt", "file two.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "modified2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		try await restoreAll(at: testDirPath.path)

		let content1 = try String(contentsOf: testDirPath.appendingPathComponent("file one.txt"), encoding: .utf8)
		let content2 = try String(contentsOf: testDirPath.appendingPathComponent("file two.txt"), encoding: .utf8)
		#expect(content1 == "original1")
		#expect(content2 == "original2")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldUpdateStatusAfterRestoringFileWithSpace() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "original".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)

		var result = try await status(at: testDirPath.path)
		#expect(result.modified.contains("test file.txt"))

		try await restore(at: testDirPath.path, files: ["test file.txt"])

		result = try await status(at: testDirPath.path)
		#expect(result.modified == [])

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Log Tests

	@Test func shouldLogCommitsForFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add file with space")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)
		#expect(result[0].message == "Add file with space")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldLogMultipleCommitsWithFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try "content2".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try "content3".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Third commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 3)
		#expect(result[0].message == "Third commit")
		#expect(result[1].message == "Second commit")
		#expect(result[2].message == "First commit")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldLimitCommitsForFilesWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try "content2".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try "content3".write(to: testDirPath.appendingPathComponent("test file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Third commit")

		let result = try await log(at: testDirPath.path, options: LogOptions(limit: 2, oneline: nil, branch: nil))

		#expect(result.count == 2)
		#expect(result[0].message == "Third commit")
		#expect(result[1].message == "Second commit")

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Remote Tests

	@Test func shouldAddRemoteWithSpaceInURLPath() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try await remoteAdd(at: testDirPath.path, name: "origin", url: "https://example.com/path with spaces/repo.git")

		let configPath = testDirPath.appendingPathComponent(".git").appendingPathComponent("config")
		let configContent = try String(contentsOf: configPath, encoding: .utf8)

		#expect(configContent.contains("https://example.com/path with spaces/repo.git"))

		try? fileManager.removeItem(at: testDirPath)
	}

	// MARK: - Complex Scenarios

	@Test func shouldHandleCompleteWorkflowWithFilesAndFoldersWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: testDirPath.appendingPathComponent("file two.txt"), atomically: true, encoding: .utf8)

		let myFolder = testDirPath.appendingPathComponent("my folder")
		try fileManager.createDirectory(at: myFolder, withIntermediateDirectories: true)

		let anotherFolder = testDirPath.appendingPathComponent("another  folder")
		try fileManager.createDirectory(at: anotherFolder, withIntermediateDirectories: true)

		try "console.log('hello')".write(to: myFolder.appendingPathComponent("test file.ts"), atomically: true, encoding: .utf8)
		try "{\"key\": \"value\"}".write(to: anotherFolder.appendingPathComponent("data  file.json"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)

		var result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		_ = try await commit(at: testDirPath.path, message: "Initial commit with spaced files")

		result = try await status(at: testDirPath.path)
		#expect(result.modified == [])

		try "modified1".write(to: testDirPath.appendingPathComponent("file one.txt"), atomically: true, encoding: .utf8)
		try "console.log('modified')".write(to: myFolder.appendingPathComponent("test file.ts"), atomically: true, encoding: .utf8)

		result = try await status(at: testDirPath.path)
		#expect(result.modified.contains("file one.txt"))
		#expect(result.modified.contains("my folder/test file.ts"))

		try await restore(at: testDirPath.path, files: ["file one.txt"])

		let content1 = try String(contentsOf: testDirPath.appendingPathComponent("file one.txt"), encoding: .utf8)
		#expect(content1 == "content1")

		let logResult = try await log(at: testDirPath.path)
		#expect(logResult.count == 1)
		#expect(logResult[0].message == "Initial commit with spaced files")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleFilesWithVariousSpacePatterns() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let files = [
			"single space.txt",
			"double  space.txt",
			"triple   space.txt",
			"trailing .txt",
		]

		for file in files {
			try "content".write(to: testDirPath.appendingPathComponent(file), atomically: true, encoding: .utf8)
		}

		try await addAll(at: testDirPath.path)
		_ = try await commit(at: testDirPath.path, message: "Add files with various space patterns")

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])
		#expect(result.modified == [])

		let logResult = try await log(at: testDirPath.path)
		#expect(logResult.count == 1)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleNestedFoldersWithSpaces() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let folderOne = testDirPath.appendingPathComponent("folder one")
		try fileManager.createDirectory(at: folderOne, withIntermediateDirectories: true)

		let folderTwo = folderOne.appendingPathComponent("folder two")
		try fileManager.createDirectory(at: folderTwo, withIntermediateDirectories: true)

		let folderThree = folderTwo.appendingPathComponent("folder three")
		try fileManager.createDirectory(at: folderThree, withIntermediateDirectories: true)

		try "content1".write(to: folderOne.appendingPathComponent("file1.txt"), atomically: true, encoding: .utf8)
		try "content2".write(to: folderTwo.appendingPathComponent("file2.txt"), atomically: true, encoding: .utf8)
		try "content3".write(to: folderThree.appendingPathComponent("file3.txt"), atomically: true, encoding: .utf8)

		try await addAll(at: testDirPath.path)
		_ = try await commit(at: testDirPath.path, message: "Add nested folders with spaces")

		let result = try await status(at: testDirPath.path)
		#expect(result.untracked == [])

		let logResult = try await log(at: testDirPath.path)
		#expect(logResult.count == 1)

		try? fileManager.removeItem(at: testDirPath)
	}
}
