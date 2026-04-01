import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add, addAll } from "../src/add";
import { init } from "../src/init";
import { status } from "../src/status";

describe("add", () => {
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

	it("should add a single file to the index", async () => {
		await writeFile(join(testDir, "test.txt"), "content");

		await add(testDir, ["test.txt"]);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should add multiple files to the index", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await writeFile(join(testDir, "file3.txt"), "content3");

		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should update a modified file in the index", async () => {
		await writeFile(join(testDir, "test.txt"), "original");
		await add(testDir, ["test.txt"]);
		await writeFile(join(testDir, "test.txt"), "modified");

		await add(testDir, ["test.txt"]);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should throw error for non-existent file", async () => {
		await expect(add(testDir, ["nonexistent.txt"])).rejects.toThrow("File not found");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(add(nonGitDir, ["test.txt"])).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should add all untracked files with addAll", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await mkdir(join(testDir, "src"), { recursive: true });
		await writeFile(join(testDir, "src", "index.ts"), "console.log('hello')");

		await addAll(testDir);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should add all modified files with addAll", async () => {
		await writeFile(join(testDir, "test.txt"), "original");
		await add(testDir, ["test.txt"]);
		await writeFile(join(testDir, "test.txt"), "modified");

		await addAll(testDir);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should add both untracked and modified files with addAll", async () => {
		await writeFile(join(testDir, "tracked.txt"), "original");
		await add(testDir, ["tracked.txt"]);
		await writeFile(join(testDir, "tracked.txt"), "modified");
		await writeFile(join(testDir, "new.txt"), "new content");

		await addAll(testDir);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should handle empty repository with addAll", async () => {
		await addAll(testDir);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});

	it("should throw error with addAll if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(addAll(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should verify file hash in index", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		const indexPath = join(testDir, ".git", "index");
		const indexContent = await readFile(indexPath, "utf-8");
		const crypto = await import("node:crypto");
		const expectedHash = crypto.createHash("sha1").update("content").digest("hex");

		expect(indexContent).toContain(`test.txt ${expectedHash} 100644`);
	});

	it("should preserve existing index entries when adding new files", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await add(testDir, ["file1.txt"]);
		await writeFile(join(testDir, "file2.txt"), "content2");

		await add(testDir, ["file2.txt"]);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);
		expect(result.modified).toEqual([]);
	});
});
