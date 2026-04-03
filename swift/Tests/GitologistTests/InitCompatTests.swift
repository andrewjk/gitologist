import Foundation
@testable import Gitologist
import Testing

struct InitCompatTests {
	var baseDir: URL {
		let tempDir = FileManager.default.temporaryDirectory
		let testName = "gitologist-compat-test-\(Date().timeIntervalSince1970)-\(UUID().uuidString.prefix(8))"
		return tempDir.appendingPathComponent(testName)
	}

	let fileManager = FileManager.default

	init() {}

	@Test func shouldCreateSameDirectoryStructureAsGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		let ourGitDir = testDir.appendingPathComponent(".git")
		let theirGitDir = gitDir.appendingPathComponent(".git")

		#expect(fileManager.fileExists(atPath: ourGitDir.path))
		#expect(fileManager.fileExists(atPath: theirGitDir.path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("objects").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("objects").path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("refs").appendingPathComponent("heads").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("refs").appendingPathComponent("heads").path))

		#expect(fileManager.fileExists(atPath: ourGitDir.appendingPathComponent("refs").appendingPathComponent("tags").path))
		#expect(fileManager.fileExists(atPath: theirGitDir.appendingPathComponent("refs").appendingPathComponent("tags").path))

		try? fileManager.removeItem(at: baseDirPath)
	}

	@Test func shouldCreateHEADPointingToSameBranchAsGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		let ourHead = try String(contentsOf: testDir.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)
		let theirHead = try String(contentsOf: gitDir.appendingPathComponent(".git").appendingPathComponent("HEAD"), encoding: .utf8)

		#expect(ourHead.hasPrefix("ref: refs/heads/"))
		#expect(theirHead.hasPrefix("ref: refs/heads/"))

		try? fileManager.removeItem(at: baseDirPath)
	}

	@Test func shouldCreateValidConfigFile() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		let ourConfig = try String(contentsOf: testDir.appendingPathComponent(".git").appendingPathComponent("config"), encoding: .utf8)
		let theirConfig = try String(contentsOf: gitDir.appendingPathComponent(".git").appendingPathComponent("config"), encoding: .utf8)

		#expect(ourConfig.contains("[core]"))
		#expect(ourConfig.contains("repositoryformatversion"))
		#expect(theirConfig.contains("[core]"))
		#expect(theirConfig.contains("repositoryformatversion"))

		try? fileManager.removeItem(at: baseDirPath)
	}

	@Test func shouldCreateEmptyObjectsDirectoryLikeGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		let ourObjects = try fileManager.contentsOfDirectory(atPath: testDir.appendingPathComponent(".git").appendingPathComponent("objects").path)
		let theirObjects = try fileManager.contentsOfDirectory(atPath: gitDir.appendingPathComponent(".git").appendingPathComponent("objects").path)

		#expect(Array(ourObjects) is [String])
		#expect(Array(theirObjects) is [String])

		try? fileManager.removeItem(at: baseDirPath)
	}

	@Test func shouldCreateEmptyRefsHeadsDirectoryLikeGitInit() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		let ourRefsHeads = try fileManager.contentsOfDirectory(atPath: testDir.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").path)
		let theirRefsHeads = try fileManager.contentsOfDirectory(atPath: gitDir.appendingPathComponent(".git").appendingPathComponent("refs").appendingPathComponent("heads").path)

		#expect(ourRefsHeads.count == 0)
		#expect(theirRefsHeads.count == 0)

		try? fileManager.removeItem(at: baseDirPath)
	}

	@Test func shouldCreateDescriptionFile() async throws {
		let baseDirPath = baseDir
		try fileManager.createDirectory(at: baseDirPath, withIntermediateDirectories: true)

		let testDir = baseDirPath.appendingPathComponent("ours")
		let gitDir = baseDirPath.appendingPathComponent("theirs")

		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)
		try fileManager.createDirectory(at: gitDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		let pipe = Pipe()
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		process.arguments = ["init"]
		process.currentDirectoryURL = gitDir
		process.standardOutput = pipe
		try process.run()
		process.waitUntilExit()

		#expect(fileManager.fileExists(atPath: testDir.appendingPathComponent(".git").appendingPathComponent("description").path))
		#expect(fileManager.fileExists(atPath: gitDir.appendingPathComponent(".git").appendingPathComponent("description").path))

		try? fileManager.removeItem(at: baseDirPath)
	}
}
