import Foundation
@testable import Gitologist
import Testing

struct IgnoreParserTests {
	let fileManager = FileManager.default

	@Test func shouldIgnoreSimplePatterns() async {
		let parser = IgnoreParser()
		await parser.setPatternsForTesting([
			".": [
				IgnorePattern(pattern: "node_modules", isNegated: false, isDirectoryOnly: true, pathPrefix: "."),
				IgnorePattern(pattern: "*.log", isNegated: false, isDirectoryOnly: false, pathPrefix: "."),
			],
		])

		#expect(await parser.isIgnored(filePath: "node_modules", isDirectory: true) == true)
		#expect(await parser.isIgnored(filePath: "app.log") == true)
		#expect(await parser.isIgnored(filePath: "src/main.ts") == false)
	}

	@Test func shouldHandleNegationPatterns() async {
		let parser = IgnoreParser()
		await parser.setPatternsForTesting([
			".": [
				IgnorePattern(pattern: "*.log", isNegated: false, isDirectoryOnly: false, pathPrefix: "."),
				IgnorePattern(pattern: "important.log", isNegated: true, isDirectoryOnly: false, pathPrefix: "."),
			],
		])

		#expect(await parser.isIgnored(filePath: "debug.log") == true)
		#expect(await parser.isIgnored(filePath: "important.log") == false)
	}

	@Test func shouldHandleDirectoryOnlyPatterns() async {
		let parser = IgnoreParser()
		await parser.setPatternsForTesting([
			".": [
				IgnorePattern(pattern: "build", isNegated: false, isDirectoryOnly: true, pathPrefix: "."),
			],
		])

		#expect(await parser.isIgnored(filePath: "build", isDirectory: true) == true)
		#expect(await parser.isIgnored(filePath: "build", isDirectory: false) == false)
		#expect(await parser.isIgnored(filePath: "build/output.txt") == false)
	}

	@Test func shouldLoadGitignoreFromRepository() async throws {
		let tempDir = fileManager.temporaryDirectory
		let testDir = tempDir.appendingPathComponent("gitignore-test-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

		// Create a .gitignore file
		let gitignoreContent = "node_modules/\n*.log\n.env\n"
		try gitignoreContent.write(to: testDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

		let parser = IgnoreParser()
		await parser.loadGitignore(repoPath: testDir.path)

		#expect(await parser.isIgnored(filePath: "node_modules", isDirectory: true) == true)
		#expect(await parser.isIgnored(filePath: "app.log") == true)
		#expect(await parser.isIgnored(filePath: ".env") == true)
		#expect(await parser.isIgnored(filePath: "src/main.ts") == false)

		try? fileManager.removeItem(at: testDir)
	}

	@Test func shouldRespectGitignoreInStatusCommand() async throws {
		let tempDir = fileManager.temporaryDirectory
		let testDir = tempDir.appendingPathComponent("gitignore-status-test-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		// Create files
		try "console.log('hello');".write(to: testDir.appendingPathComponent("main.ts"), atomically: true, encoding: .utf8)
		try "debug info".write(to: testDir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)
		let nodeModulesDir = testDir.appendingPathComponent("node_modules")
		try fileManager.createDirectory(at: nodeModulesDir, withIntermediateDirectories: true)
		try "{}".write(to: nodeModulesDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

		// Create .gitignore
		try "node_modules/\n*.log\n".write(to: testDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

		let result = try await status(at: testDir.path)

		// Should only see main.ts, not debug.log or node_modules/
		#expect(result.untracked.contains("main.ts"))
		#expect(!result.untracked.contains("debug.log"))
		#expect(!result.untracked.contains("node_modules/package.json"))

		try? fileManager.removeItem(at: testDir)
	}

	@Test func shouldRespectGitignoreInAddAllCommand() async throws {
		let tempDir = fileManager.temporaryDirectory
		let testDir = tempDir.appendingPathComponent("gitignore-add-test-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		// Create files
		try "console.log('hello');".write(to: testDir.appendingPathComponent("main.ts"), atomically: true, encoding: .utf8)
		try "debug info".write(to: testDir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)

		// Create .gitignore
		try "*.log\n".write(to: testDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

		try await addAll(at: testDir.path)

		let result = try await status(at: testDir.path)

		// Should have staged main.ts but not debug.log
		#expect(result.staged.contains("main.ts"))
		#expect(!result.staged.contains("debug.log"))

		try? fileManager.removeItem(at: testDir)
	}

	@Test func shouldRespectGitignoreInAddCommandForSpecificFiles() async throws {
		let tempDir = fileManager.temporaryDirectory
		let testDir = tempDir.appendingPathComponent("gitignore-add-specific-test-\(Date().timeIntervalSince1970)")
		try fileManager.createDirectory(at: testDir, withIntermediateDirectories: true)

		try await initRepo(at: testDir.path)

		// Create files
		try "console.log('hello');".write(to: testDir.appendingPathComponent("main.ts"), atomically: true, encoding: .utf8)
		try "debug info".write(to: testDir.appendingPathComponent("debug.log"), atomically: true, encoding: .utf8)

		// Create .gitignore
		try "*.log\n".write(to: testDir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

		// Try to add both files
		try await add(at: testDir.path, files: ["main.ts", "debug.log"])

		let result = try await status(at: testDir.path)

		// Should have staged main.ts but not debug.log
		#expect(result.staged.contains("main.ts"))
		#expect(!result.staged.contains("debug.log"))

		try? fileManager.removeItem(at: testDir)
	}
}
