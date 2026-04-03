import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { init } from "../src/init";
import { status } from "../src/status";

describe("status", () => {
	let testDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(testDir, { recursive: true });
		await init(testDir);
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	it("should return current branch", async () => {
		const result = await status(testDir);
		expect(result.branch).toBe("main");
	});

	it("should return up to date message", async () => {
		const result = await status(testDir);
		expect(result.upToDate).toContain("Your branch is up to date with");
	});

	it("should return empty arrays for changes when no files exist", async () => {
		const result = await status(testDir);
		expect(result.staged).toEqual([]);
		expect(result.modified).toEqual([]);
		expect(result.untracked).toEqual([]);
	});

	it("should detect untracked files", async () => {
		await writeFile(join(testDir, "test.txt"), "content");

		const result = await status(testDir);
		expect(result.untracked).toContain("test.txt");
		expect(result.modified).toEqual([]);
		expect(result.staged).toEqual([]);
	});

	it("should detect multiple untracked files", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await writeFile(join(testDir, "README.md"), "# Test");
		await mkdir(join(testDir, "src"), { recursive: true });
		await writeFile(join(testDir, "src", "index.ts"), "console.log('hello')");

		const result = await status(testDir);
		expect(result.untracked).toContain("test.txt");
		expect(result.untracked).toContain("README.md");
		expect(result.untracked).toContain(join("src", "index.ts"));
	});

	it("should detect modified files", async () => {
		const indexPath = join(testDir, ".git", "index");
		const crypto = await import("node:crypto");
		const originalHash = crypto.createHash("sha1").update("original").digest("hex");
		await writeFile(indexPath, `test.txt\t${originalHash}\t100644\n`, "utf-8");

		await writeFile(join(testDir, "test.txt"), "modified content");

		const result = await status(testDir);
		expect(result.modified).toContain("test.txt");
		expect(result.untracked).toEqual([]);
	});

	it("should detect deleted files as modified", async () => {
		const indexPath = join(testDir, ".git", "index");
		const crypto = await import("node:crypto");
		const hash = crypto.createHash("sha1").update("content").digest("hex");
		await writeFile(indexPath, `test.txt\t${hash}\t100644\n`, "utf-8");

		await writeFile(join(testDir, "test.txt"), "content");
		await rm(join(testDir, "test.txt"));

		const result = await status(testDir);
		expect(result.deleted).toContain("test.txt");
	});

	it("should handle detached HEAD", async () => {
		const headPath = join(testDir, ".git", "HEAD");
		await writeFile(headPath, "deadbeef\n", "utf-8");

		const result = await status(testDir);
		expect(result.branch).toBe("(detached HEAD)");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(status(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should handle custom branch name", async () => {
		const headPath = join(testDir, ".git", "HEAD");
		await writeFile(headPath, "ref: refs/heads/main\n", "utf-8");

		const result = await status(testDir);
		expect(result.branch).toBe("main");
	});

	it("should not detect .git directory as untracked", async () => {
		await mkdir(join(testDir, ".git", "other"), { recursive: true });
		await writeFile(join(testDir, ".git", "other", "file.txt"), "content");

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
	});

	it("should correctly identify files matching index", async () => {
		const indexPath = join(testDir, ".git", "index");
		const crypto = await import("node:crypto");
		const hash = crypto.createHash("sha1").update("content").digest("hex");
		await writeFile(indexPath, `test.txt\t${hash}\t100644\n`, "utf-8");

		await writeFile(join(testDir, "test.txt"), "content");

		const result = await status(testDir);
		expect(result.modified).toEqual([]);
		expect(result.untracked).toEqual([]);
	});
});
