import { mkdir, rm, writeFile, readFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { status } from "../src/status";

describe("commit", () => {
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

	it("should commit staged files", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		const commitSha = await commit(testDir, "Initial commit");

		expect(commitSha).toMatch(/^[a-f0-9]{40}$/);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should throw error if nothing to commit", async () => {
		await expect(commit(testDir, "Empty commit")).rejects.toThrow("Nothing to commit");
	});

	it("should throw error if no files staged", async () => {
		await writeFile(join(testDir, "test.txt"), "content");

		await expect(commit(testDir, "Test commit")).rejects.toThrow("No files staged");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(commit(nonGitDir, "Test commit")).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should create commit object in .git/objects", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		await commit(testDir, "Test commit");

		const objectsDir = join(testDir, ".git", "objects");
		const dirs = await readdir(objectsDir);

		expect(dirs.length).toBeGreaterThan(0);
	});

	it("should update branch reference", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		const commitSha = await commit(testDir, "Test commit");

		const branchPath = join(testDir, ".git", "refs", "heads", "main");
		const branchRef = await readFile(branchPath, "utf-8");

		expect(branchRef.trim()).toBe(commitSha);
	});

	it("should handle multiple commits", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		const firstSha = await commit(testDir, "First commit");

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);

		const secondSha = await commit(testDir, "Second commit");

		expect(firstSha).not.toBe(secondSha);

		const branchPath = join(testDir, ".git", "refs", "heads", "main");
		const branchRef = await readFile(branchPath, "utf-8");

		expect(branchRef.trim()).toBe(secondSha);
	});

	it("should handle commit with message containing newlines", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		const message = "Multi-line\ncommit\nmessage";
		const commitSha = await commit(testDir, message);

		expect(commitSha).toMatch(/^[a-f0-9]{40}$/);
	});

	it("should commit multiple files", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await writeFile(join(testDir, "file3.txt"), "content3");

		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);

		const commitSha = await commit(testDir, "Add multiple files");

		expect(commitSha).toMatch(/^[a-f0-9]{40}$/);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});
});
