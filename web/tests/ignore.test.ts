import { mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, expect, it } from "vite-plus/test";

import { add, addAll } from "../src/add.ts";
import { IgnoreParser } from "../src/IgnoreParser.ts";
import { init } from "../src/init.ts";
import { status } from "../src/status.ts";

describe("IgnoreParser", () => {
	describe("should parse gitignore patterns", () => {
		it("should ignore simple patterns", async () => {
			const parser = new IgnoreParser();
			parser["patterns"].set(".", [
				{ pattern: "node_modules", isNegated: false, isDirectoryOnly: true, pathPrefix: "." },
				{ pattern: "*.log", isNegated: false, isDirectoryOnly: false, pathPrefix: "." },
			]);

			expect(parser.isIgnored("node_modules", true)).toBe(true);
			expect(parser.isIgnored("app.log")).toBe(true);
			expect(parser.isIgnored("src/main.ts")).toBe(false);
		});

		it("should handle negation patterns", async () => {
			const parser = new IgnoreParser();
			parser["patterns"].set(".", [
				{ pattern: "*.log", isNegated: false, isDirectoryOnly: false, pathPrefix: "." },
				{ pattern: "important.log", isNegated: true, isDirectoryOnly: false, pathPrefix: "." },
			]);

			expect(parser.isIgnored("debug.log")).toBe(true);
			expect(parser.isIgnored("important.log")).toBe(false);
		});

		it("should handle directory-only patterns", async () => {
			const parser = new IgnoreParser();
			parser["patterns"].set(".", [
				{ pattern: "build", isNegated: false, isDirectoryOnly: true, pathPrefix: "." },
			]);

			expect(parser.isIgnored("build", true)).toBe(true);
			expect(parser.isIgnored("build", false)).toBe(false);
			expect(parser.isIgnored("build/output.txt")).toBe(false);
		});
	});
	describe("integration tests", () => {
		it("should load gitignore from repository", async () => {
			const testDir = join(tmpdir(), `gitignore-test-${Date.now()}`);
			mkdirSync(testDir, { recursive: true });

			// Create a .gitignore file
			writeFileSync(join(testDir, ".gitignore"), "node_modules/\n*.log\n.env\n");

			const parser = new IgnoreParser();
			await parser.loadGitignore(testDir);

			expect(parser.isIgnored("node_modules", true)).toBe(true);
			expect(parser.isIgnored("app.log")).toBe(true);
			expect(parser.isIgnored(".env")).toBe(true);
			expect(parser.isIgnored("src/main.ts")).toBe(false);
		});

		it("should respect gitignore in status command", async () => {
			const testDir = join(tmpdir(), `gitignore-status-test-${Date.now()}`);
			mkdirSync(testDir, { recursive: true });

			await init(testDir);

			// Create files
			writeFileSync(join(testDir, "main.ts"), "console.log('hello');");
			writeFileSync(join(testDir, "debug.log"), "debug info");
			mkdirSync(join(testDir, "node_modules"), { recursive: true });
			writeFileSync(join(testDir, "node_modules/package.json"), "{}");

			// Create .gitignore
			writeFileSync(join(testDir, ".gitignore"), "node_modules/\n*.log\n");

			const result = await status(testDir);

			// Should only see main.ts, not debug.log or node_modules/
			expect(result.untracked).toContain("main.ts");
			expect(result.untracked).not.toContain("debug.log");
			expect(result.untracked).not.toContain("node_modules/package.json");
		});

		it("should respect gitignore in addAll command", async () => {
			const testDir = join(tmpdir(), `gitignore-add-test-${Date.now()}`);
			mkdirSync(testDir, { recursive: true });

			await init(testDir);

			// Create files
			writeFileSync(join(testDir, "main.ts"), "console.log('hello');");
			writeFileSync(join(testDir, "debug.log"), "debug info");

			// Create .gitignore
			writeFileSync(join(testDir, ".gitignore"), "*.log\n");

			await addAll(testDir);

			const result = await status(testDir);

			// Should have staged main.ts but not debug.log
			expect(result.staged).toContain("main.ts");
			expect(result.staged).not.toContain("debug.log");
		});

		it("should respect gitignore in add command for specific files", async () => {
			const testDir = join(tmpdir(), `gitignore-add-specific-test-${Date.now()}`);
			mkdirSync(testDir, { recursive: true });

			await init(testDir);

			// Create files
			writeFileSync(join(testDir, "main.ts"), "console.log('hello');");
			writeFileSync(join(testDir, "debug.log"), "debug info");

			// Create .gitignore
			writeFileSync(join(testDir, ".gitignore"), "*.log\n");

			// Try to add both files
			await add(testDir, ["main.ts", "debug.log"]);

			const result = await status(testDir);

			// Should have staged main.ts but not debug.log
			expect(result.staged).toContain("main.ts");
			expect(result.staged).not.toContain("debug.log");
		});
	});
});
