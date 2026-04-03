import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add, addAll } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { log } from "../src/log";
import { remoteAdd } from "../src/remote";
import { restore, restoreAll } from "../src/restore";
import { status } from "../src/status";

describe("files and folders with spaces", () => {
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

	describe("add", () => {
		it("should add file with single space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");

			await add(testDir, ["test file.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add file with multiple spaces in name", async () => {
			await writeFile(join(testDir, "test  multiple  spaces.txt"), "content");

			await add(testDir, ["test  multiple  spaces.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add file with leading space in name", async () => {
			await writeFile(join(testDir, " leading.txt"), "content");

			await add(testDir, [" leading.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add file with trailing space in name", async () => {
			await writeFile(join(testDir, "trailing .txt"), "content");

			await add(testDir, ["trailing .txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add files in folder with space in name", async () => {
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "file.txt"), "content");

			await add(testDir, ["my folder/file.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add files in folder with multiple spaces in name", async () => {
			await mkdir(join(testDir, "my  test  folder"), { recursive: true });
			await writeFile(join(testDir, "my  test  folder", "file.txt"), "content");

			await add(testDir, ["my  test  folder/file.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add file with space in name in folder with space", async () => {
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "test file.txt"), "content");

			await add(testDir, ["my folder/test file.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should add multiple files with spaces in names", async () => {
			await writeFile(join(testDir, "file one.txt"), "content1");
			await writeFile(join(testDir, "file two.txt"), "content2");
			await writeFile(join(testDir, "file three.txt"), "content3");

			await add(testDir, ["file one.txt", "file two.txt", "file three.txt"]);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});

		it("should update modified file with space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "original");
			await add(testDir, ["test file.txt"]);
			await writeFile(join(testDir, "test file.txt"), "modified");

			await add(testDir, ["test file.txt"]);

			const result = await status(testDir);
			expect(result.modified).toEqual([]);
		});

		it("should add all files with spaces using addAll", async () => {
			await writeFile(join(testDir, "file one.txt"), "content1");
			await writeFile(join(testDir, "file two.txt"), "content2");
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "test file.ts"), "console.log('hello')");

			await addAll(testDir);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
		});
	});

	describe("commit", () => {
		it("should commit file with space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");
			await add(testDir, ["test file.txt"]);

			const commitSha = await commit(testDir, "Add file with space");

			expect(commitSha).toMatch(/^[a-f0-9]{40}$/);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
			expect(result.modified).toEqual([]);
		});

		it("should commit multiple files with spaces", async () => {
			await writeFile(join(testDir, "file one.txt"), "content1");
			await writeFile(join(testDir, "file two.txt"), "content2");

			await add(testDir, ["file one.txt", "file two.txt"]);

			const commitSha = await commit(testDir, "Add multiple files with spaces");

			expect(commitSha).toMatch(/^[a-f0-9]{40}$/);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
			expect(result.modified).toEqual([]);
		});

		it("should commit files in folder with space", async () => {
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "test file.txt"), "content");

			await add(testDir, ["my folder/test file.txt"]);

			const commitSha = await commit(testDir, "Add file in folder with space");

			expect(commitSha).toMatch(/^[a-f0-9]{40}$/);

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
			expect(result.modified).toEqual([]);
		});

		it("should handle multiple commits with files with spaces", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");
			await add(testDir, ["test file.txt"]);

			const firstSha = await commit(testDir, "First commit");

			await writeFile(join(testDir, "test file.txt"), "modified");
			await add(testDir, ["test file.txt"]);

			const secondSha = await commit(testDir, "Second commit");

			expect(firstSha).not.toBe(secondSha);

			const result = await status(testDir);
			expect(result.modified).toEqual([]);
		});
	});

	describe("status", () => {
		it("should detect untracked file with space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");

			const result = await status(testDir);
			expect(result.untracked).toContain("test file.txt");
		});

		it("should detect multiple untracked files with spaces", async () => {
			await writeFile(join(testDir, "file one.txt"), "content1");
			await writeFile(join(testDir, "file two.txt"), "content2");
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "test file.ts"), "console.log('hello')");

			const result = await status(testDir);
			expect(result.untracked).toContain("file one.txt");
			expect(result.untracked).toContain("file two.txt");
			expect(result.untracked).toContain(join("my folder", "test file.ts"));
		});

		it("should detect modified file with space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "original");
			await add(testDir, ["test file.txt"]);
			await writeFile(join(testDir, "test file.txt"), "modified");

			const result = await status(testDir);
			expect(result.modified).toContain("test file.txt");
		});

		it("should detect deleted file with space in name as modified", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Add file");
			await rm(join(testDir, "test file.txt"));

			const result = await status(testDir);
			expect(result.deleted).toContain("test file.txt");
		});
	});

	describe("restore", () => {
		it("should restore modified file with space in name", async () => {
			await writeFile(join(testDir, "test file.txt"), "original");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Initial commit");

			await writeFile(join(testDir, "test file.txt"), "modified");

			await restore(testDir, ["test file.txt"]);

			const content = await readFile(join(testDir, "test file.txt"), "utf-8");
			expect(content).toBe("original");
		});

		it("should restore multiple files with spaces", async () => {
			await writeFile(join(testDir, "file one.txt"), "original1");
			await writeFile(join(testDir, "file two.txt"), "original2");

			await add(testDir, ["file one.txt", "file two.txt"]);
			await commit(testDir, "Initial commit");

			await writeFile(join(testDir, "file one.txt"), "modified1");
			await writeFile(join(testDir, "file two.txt"), "modified2");

			await restore(testDir, ["file one.txt", "file two.txt"]);

			const content1 = await readFile(join(testDir, "file one.txt"), "utf-8");
			const content2 = await readFile(join(testDir, "file two.txt"), "utf-8");
			expect(content1).toBe("original1");
			expect(content2).toBe("original2");
		});

		it("should restore file in folder with space", async () => {
			await mkdir(join(testDir, "my folder"), { recursive: true });
			await writeFile(join(testDir, "my folder", "test file.txt"), "original");

			await add(testDir, ["my folder/test file.txt"]);
			await commit(testDir, "Initial commit");

			await writeFile(join(testDir, "my folder", "test file.txt"), "modified");

			await restore(testDir, ["my folder/test file.txt"]);

			const content = await readFile(join(testDir, "my folder", "test file.txt"), "utf-8");
			expect(content).toBe("original");
		});

		it("should restore all modified files with spaces using restoreAll", async () => {
			await writeFile(join(testDir, "file one.txt"), "original1");
			await writeFile(join(testDir, "file two.txt"), "original2");

			await add(testDir, ["file one.txt", "file two.txt"]);
			await commit(testDir, "Initial commit");

			await writeFile(join(testDir, "file one.txt"), "modified1");
			await writeFile(join(testDir, "file two.txt"), "modified2");

			await restoreAll(testDir);

			const content1 = await readFile(join(testDir, "file one.txt"), "utf-8");
			const content2 = await readFile(join(testDir, "file two.txt"), "utf-8");

			expect(content1).toBe("original1");
			expect(content2).toBe("original2");
		});

		it("should update status after restoring file with space", async () => {
			await writeFile(join(testDir, "test file.txt"), "original");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Initial commit");

			await writeFile(join(testDir, "test file.txt"), "modified");

			let result = await status(testDir);
			expect(result.modified).toContain("test file.txt");

			await restore(testDir, ["test file.txt"]);

			result = await status(testDir);
			expect(result.modified).toEqual([]);
		});
	});

	describe("log", () => {
		it("should log commits for files with spaces", async () => {
			await writeFile(join(testDir, "test file.txt"), "content");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Add file with space");

			const result = await log(testDir);

			expect(result.length).toBe(1);
			expect(result[0].message).toBe("Add file with space");
		});

		it("should log multiple commits with files with spaces", async () => {
			await writeFile(join(testDir, "test file.txt"), "content1");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "First commit");

			await writeFile(join(testDir, "test file.txt"), "content2");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Second commit");

			await writeFile(join(testDir, "test file.txt"), "content3");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Third commit");

			const result = await log(testDir);

			expect(result.length).toBe(3);
			expect(result[0].message).toBe("Third commit");
			expect(result[1].message).toBe("Second commit");
			expect(result[2].message).toBe("First commit");
		});

		it("should limit commits for files with spaces", async () => {
			await writeFile(join(testDir, "test file.txt"), "content1");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "First commit");

			await writeFile(join(testDir, "test file.txt"), "content2");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Second commit");

			await writeFile(join(testDir, "test file.txt"), "content3");
			await add(testDir, ["test file.txt"]);
			await commit(testDir, "Third commit");

			const result = await log(testDir, { limit: 2 });

			expect(result.length).toBe(2);
			expect(result[0].message).toBe("Third commit");
			expect(result[1].message).toBe("Second commit");
		});
	});

	describe("remote", () => {
		it("should add remote with space in URL path", async () => {
			await remoteAdd(testDir, "origin", "https://example.com/path with spaces/repo.git");

			const configPath = join(testDir, ".git", "config");
			const configContent = await readFile(configPath, "utf-8");

			expect(configContent).toContain("https://example.com/path with spaces/repo.git");
		});
	});

	describe("complex scenarios", () => {
		it("should handle complete workflow with files and folders with spaces", async () => {
			await writeFile(join(testDir, "file one.txt"), "content1");
			await writeFile(join(testDir, "file two.txt"), "content2");

			await mkdir(join(testDir, "my folder"), { recursive: true });
			await mkdir(join(testDir, "another  folder"), { recursive: true });

			await writeFile(join(testDir, "my folder", "test file.ts"), "console.log('hello')");
			await writeFile(join(testDir, "another  folder", "data  file.json"), '{"key": "value"}');

			await addAll(testDir);

			let result = await status(testDir);
			expect(result.untracked).toEqual([]);

			await commit(testDir, "Initial commit with spaced files");

			result = await status(testDir);
			expect(result.modified).toEqual([]);

			await writeFile(join(testDir, "file one.txt"), "modified1");
			await writeFile(join(testDir, "my folder", "test file.ts"), "console.log('modified')");

			result = await status(testDir);
			expect(result.modified).toContain("file one.txt");
			expect(result.modified).toContain(join("my folder", "test file.ts"));

			await restore(testDir, ["file one.txt"]);

			const content1 = await readFile(join(testDir, "file one.txt"), "utf-8");
			expect(content1).toBe("content1");

			const logResult = await log(testDir);
			expect(logResult.length).toBe(1);
			expect(logResult[0].message).toBe("Initial commit with spaced files");
		});

		it("should handle files with various space patterns", async () => {
			const files = [
				"single space.txt",
				"double  space.txt",
				"triple   space.txt",
				" leading.txt",
				"trailing .txt",
				" both .txt ",
				" file name .txt ",
			];

			for (const file of files) {
				await writeFile(join(testDir, file), "content");
			}

			await addAll(testDir);
			await commit(testDir, "Add files with various space patterns");

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);
			expect(result.modified).toEqual([]);

			const logResult = await log(testDir);
			expect(logResult.length).toBe(1);
		});

		it("should handle nested folders with spaces", async () => {
			await mkdir(join(testDir, "folder one"), { recursive: true });
			await mkdir(join(testDir, "folder one", "folder two"), { recursive: true });
			await mkdir(join(testDir, "folder one", "folder two", "folder three"), { recursive: true });

			await writeFile(join(testDir, "folder one", "file1.txt"), "content1");
			await writeFile(join(testDir, "folder one", "folder two", "file2.txt"), "content2");
			await writeFile(
				join(testDir, "folder one", "folder two", "folder three", "file3.txt"),
				"content3",
			);

			await addAll(testDir);
			await commit(testDir, "Add nested folders with spaces");

			const result = await status(testDir);
			expect(result.untracked).toEqual([]);

			const logResult = await log(testDir);
			expect(logResult.length).toBe(1);
		});
	});
});
