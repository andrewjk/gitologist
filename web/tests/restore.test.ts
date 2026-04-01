import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { restore, restoreAll } from "../src/restore";
import { status } from "../src/status";

describe("restore", () => {
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

	it("should restore a modified file", async () => {
		await writeFile(join(testDir, "test.txt"), "original");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified");

		await restore(testDir, ["test.txt"]);

		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("original");
	});

	it("should restore multiple files", async () => {
		await writeFile(join(testDir, "file1.txt"), "original1");
		await writeFile(join(testDir, "file2.txt"), "original2");
		await add(testDir, ["file1.txt", "file2.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "file1.txt"), "modified1");
		await writeFile(join(testDir, "file2.txt"), "modified2");

		await restore(testDir, ["file1.txt", "file2.txt"]);

		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		const content2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		expect(content1).toBe("original1");
		expect(content2).toBe("original2");
	});

	it("should throw error for non-existent file", async () => {
		await expect(restore(testDir, ["nonexistent.txt"])).rejects.toThrow("File not found");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(restore(nonGitDir, ["test.txt"])).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if file not in commit", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "newfile.txt"), "new content");

		await expect(restore(testDir, ["newfile.txt"])).rejects.toThrow("File not in commit");
	});

	it("should update status after restore", async () => {
		await writeFile(join(testDir, "test.txt"), "original");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified");

		let result = await status(testDir);
		expect(result.modified).toContain("test.txt");

		await restore(testDir, ["test.txt"]);

		result = await status(testDir);
		expect(result.modified).toEqual([]);
	});

	it("should restore all modified files with restoreAll", async () => {
		await writeFile(join(testDir, "file1.txt"), "original1");
		await writeFile(join(testDir, "file2.txt"), "original2");
		await writeFile(join(testDir, "file3.txt"), "original3");
		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "file1.txt"), "modified1");
		await writeFile(join(testDir, "file2.txt"), "modified2");
		await writeFile(join(testDir, "file3.txt"), "modified3");

		await restoreAll(testDir);

		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		const content2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		const content3 = await readFile(join(testDir, "file3.txt"), "utf-8");

		expect(content1).toBe("original1");
		expect(content2).toBe("original2");
		expect(content3).toBe("original3");
	});

	it("should do nothing with restoreAll when no modified files", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(restoreAll(testDir)).resolves.not.toThrow();

		const result = await status(testDir);
		expect(result.modified).toEqual([]);
	});

	it("should throw error with restoreAll if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(restoreAll(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should handle files in subdirectories", async () => {
		await mkdir(join(testDir, "src"), { recursive: true });
		await writeFile(join(testDir, "src", "index.ts"), "original");
		await add(testDir, ["src/index.ts"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "src", "index.ts"), "modified");

		await restore(testDir, ["src/index.ts"]);

		const content = await readFile(join(testDir, "src", "index.ts"), "utf-8");
		expect(content).toBe("original");
	});
});
