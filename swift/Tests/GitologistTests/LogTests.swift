import Foundation
@testable import Gitologist
import Testing

struct LogTests {
	var testDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldReturnEmptyLogForEmptyRepository() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let result = try await log(at: testDirPath.path)
		#expect(result.isEmpty)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldLogSingleCommit() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Initial commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)
		#expect(result[0].message == "Initial commit")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldLogMultipleCommitsInReverseOrder() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try "content2".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try "content3".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Third commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 3)
		#expect(result[0].message == "Third commit")
		#expect(result[1].message == "Second commit")
		#expect(result[2].message == "First commit")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldLimitNumberOfCommits() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content1".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		try "content2".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		try "content3".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Third commit")

		let options = LogOptions(limit: 2, oneline: nil, branch: nil)
		let result = try await log(at: testDirPath.path, options: options)

		#expect(result.count == 2)
		#expect(result[0].message == "Third commit")
		#expect(result[1].message == "Second commit")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeCommitSHA() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Test commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)

		let shaPattern = /^[a-f0-9]{40}$/
		#expect(result[0].sha.wholeMatch(of: shaPattern) != nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeAbbreviatedSHA() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Test commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)

		let abbreviatedPattern = /^[a-f0-9]{7}$/
		#expect(result[0].abbreviatedSha.wholeMatch(of: abbreviatedPattern) != nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldThrowErrorIfNotAGitRepository() async throws {
		let tempDir = FileManager.default.temporaryDirectory
		let nonGitDir = tempDir.appendingPathComponent("not-a-repo-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: nonGitDir, withIntermediateDirectories: true)

		await #expect(throws: LogError.self) {
			try await log(at: nonGitDir.path)
		}

		try? fileManager.removeItem(at: nonGitDir)
	}

	@Test func shouldThrowErrorIfBranchNotFound() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		let options = LogOptions(limit: nil, oneline: nil, branch: "nonexistent")
		await #expect(throws: LogError.self) {
			try await log(at: testDirPath.path, options: options)
		}

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeAuthor() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Test commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)
		#expect(!result[0].author.isEmpty)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeCommitDate() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Test commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)
		// Date should be within the last minute
		let timeInterval = Date().timeIntervalSince(result[0].date)
		#expect(timeInterval < 60)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldHandleMultiLineCommitMessages() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Multi-line\ncommit\nmessage")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 1)
		#expect(result[0].message == "Multi-line\ncommit\nmessage")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeParentCommitReference() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		let firstSha = try await commit(at: testDirPath.path, message: "First commit")

		try "modified".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second commit")

		let result = try await log(at: testDirPath.path)

		#expect(result.count == 2)
		#expect(result[0].parent == firstSha)
		#expect(result[1].parent == nil)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnEmptyWhenFileNeverExisted() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content".write(to: testDirPath.appendingPathComponent("test.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["test.txt"])
		_ = try await commit(at: testDirPath.path, message: "First commit")

		let options = LogOptions(file: "nonexistent.txt")
		let result = try await log(at: testDirPath.path, options: options)

		#expect(result.isEmpty)

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldReturnOnlyCommitsThatTouchedFile() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "content a".write(to: testDirPath.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		try "content b".write(to: testDirPath.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["a.txt", "b.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add both files")

		try "modified a".write(to: testDirPath.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["a.txt"])
		_ = try await commit(at: testDirPath.path, message: "Modify a.txt")

		try "modified b".write(to: testDirPath.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["b.txt"])
		_ = try await commit(at: testDirPath.path, message: "Modify b.txt")

		let optionsA = LogOptions(file: "a.txt")
		let resultA = try await log(at: testDirPath.path, options: optionsA)
		#expect(resultA.count == 2)
		#expect(resultA[0].message == "Modify a.txt")
		#expect(resultA[1].message == "Add both files")

		let optionsB = LogOptions(file: "b.txt")
		let resultB = try await log(at: testDirPath.path, options: optionsB)
		#expect(resultB.count == 2)
		#expect(resultB[0].message == "Modify b.txt")
		#expect(resultB[1].message == "Add both files")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldWorkWithNestedFilePaths() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "outer".write(to: testDirPath.appendingPathComponent("outer.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["outer.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add outer.txt")

		let subDir = testDirPath.appendingPathComponent("sub")
		try fileManager.createDirectory(at: subDir, withIntermediateDirectories: true)
		try "inner".write(to: subDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["sub/inner.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add sub/inner.txt")

		try "modified".write(to: subDir.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["sub/inner.txt"])
		_ = try await commit(at: testDirPath.path, message: "Modify sub/inner.txt")

		let options = LogOptions(file: "sub/inner.txt")
		let result = try await log(at: testDirPath.path, options: options)

		#expect(result.count == 2)
		#expect(result[0].message == "Modify sub/inner.txt")
		#expect(result[1].message == "Add sub/inner.txt")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldRespectLimitWithFileFilter() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "v1".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		_ = try await commit(at: testDirPath.path, message: "First")

		try "v2".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Second")

		try "v3".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Third")

		let options = LogOptions(limit: 2, file: "file.txt")
		let result = try await log(at: testDirPath.path, options: options)

		#expect(result.count == 2)
		#expect(result[0].message == "Third")
		#expect(result[1].message == "Second")

		try? fileManager.removeItem(at: testDirPath)
	}

	@Test func shouldIncludeInitialCommitWhenFileWasAdded() async throws {
		let testDirPath = testDir
		try fileManager.createDirectory(at: testDirPath, withIntermediateDirectories: true)
		try await initRepo(at: testDirPath.path)

		try "initial".write(to: testDirPath.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["file.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add file.txt")

		try "other".write(to: testDirPath.appendingPathComponent("other.txt"), atomically: true, encoding: .utf8)
		try await add(at: testDirPath.path, files: ["other.txt"])
		_ = try await commit(at: testDirPath.path, message: "Add other.txt")

		let options = LogOptions(file: "file.txt")
		let result = try await log(at: testDirPath.path, options: options)

		#expect(result.count == 1)
		#expect(result[0].message == "Add file.txt")

		try? fileManager.removeItem(at: testDirPath)
	}
}
