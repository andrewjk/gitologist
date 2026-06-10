import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { log } from "../src/log";

describe("log", () => {
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

	it("should return empty log for empty repository", async () => {
		const result = await log(testDir);

		expect(result).toEqual([]);
	});

	it("should log single commit", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].message).toBe("Initial commit");
	});

	it("should log multiple commits in reverse order", async () => {
		await writeFile(join(testDir, "test.txt"), "content1");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "First commit");

		await writeFile(join(testDir, "test.txt"), "content2");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await writeFile(join(testDir, "test.txt"), "content3");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Third commit");

		const result = await log(testDir);

		expect(result.length).toBe(3);
		expect(result[0].message).toBe("Third commit");
		expect(result[1].message).toBe("Second commit");
		expect(result[2].message).toBe("First commit");
	});

	it("should limit number of commits", async () => {
		await writeFile(join(testDir, "test.txt"), "content1");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "First commit");

		await writeFile(join(testDir, "test.txt"), "content2");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await writeFile(join(testDir, "test.txt"), "content3");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Third commit");

		const result = await log(testDir, { limit: 2 });

		expect(result.length).toBe(2);
		expect(result[0].message).toBe("Third commit");
		expect(result[1].message).toBe("Second commit");
	});

	it("should include commit SHA", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Test commit");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].sha).toMatch(/^[a-f0-9]{40}$/);
	});

	it("should include abbreviated SHA", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Test commit");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].abbreviatedSha).toMatch(/^[a-f0-9]{7}$/);
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(log(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if branch not found", async () => {
		await expect(log(testDir, { branch: "nonexistent" })).rejects.toThrow("not found");
	});

	it("should include author", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Test commit");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].author).toBeTruthy();
	});

	it("should include commit date", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Test commit");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].date).toBeInstanceOf(Date);
	});

	it("should handle multi-line commit messages", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Multi-line\ncommit\nmessage");

		const result = await log(testDir);

		expect(result.length).toBe(1);
		expect(result[0].message).toBe("Multi-line\ncommit\nmessage");
	});

	it("should include parent commit reference", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		const firstSha = await commit(testDir, "First commit");

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		const result = await log(testDir);

		expect(result.length).toBe(2);
		expect(result[0].parent).toBe(firstSha);
		expect(result[1].parent).toBeNull();
	});

	describe("file filter", () => {
		it("should return empty when file never existed", async () => {
			await writeFile(join(testDir, "test.txt"), "content");
			await add(testDir, ["test.txt"]);
			await commit(testDir, "First commit");

			const result = await log(testDir, { file: "nonexistent.txt" });

			expect(result).toEqual([]);
		});

		it("should return only commits that touched the file", async () => {
			await writeFile(join(testDir, "a.txt"), "content a");
			await writeFile(join(testDir, "b.txt"), "content b");
			await add(testDir, ["a.txt", "b.txt"]);
			await commit(testDir, "Add both files");

			await writeFile(join(testDir, "a.txt"), "modified a");
			await add(testDir, ["a.txt"]);
			await commit(testDir, "Modify a.txt");

			await writeFile(join(testDir, "b.txt"), "modified b");
			await add(testDir, ["b.txt"]);
			await commit(testDir, "Modify b.txt");

			const resultA = await log(testDir, { file: "a.txt" });
			expect(resultA.length).toBe(2);
			expect(resultA[0].message).toBe("Modify a.txt");
			expect(resultA[1].message).toBe("Add both files");

			const resultB = await log(testDir, { file: "b.txt" });
			expect(resultB.length).toBe(2);
			expect(resultB[0].message).toBe("Modify b.txt");
			expect(resultB[1].message).toBe("Add both files");
		});

		it("should work with nested file paths", async () => {
			await writeFile(join(testDir, "outer.txt"), "outer");
			await add(testDir, ["outer.txt"]);
			await commit(testDir, "Add outer.txt");

			await mkdir(join(testDir, "sub"), { recursive: true });
			await writeFile(join(testDir, "sub", "inner.txt"), "inner");
			await add(testDir, ["sub/inner.txt"]);
			await commit(testDir, "Add sub/inner.txt");

			await writeFile(join(testDir, "sub", "inner.txt"), "modified");
			await add(testDir, ["sub/inner.txt"]);
			await commit(testDir, "Modify sub/inner.txt");

			const result = await log(testDir, { file: "sub/inner.txt" });

			expect(result.length).toBe(2);
			expect(result[0].message).toBe("Modify sub/inner.txt");
			expect(result[1].message).toBe("Add sub/inner.txt");
		});

		it("should respect limit with file filter", async () => {
			await writeFile(join(testDir, "file.txt"), "v1");
			await add(testDir, ["file.txt"]);
			await commit(testDir, "First");

			await writeFile(join(testDir, "file.txt"), "v2");
			await add(testDir, ["file.txt"]);
			await commit(testDir, "Second");

			await writeFile(join(testDir, "file.txt"), "v3");
			await add(testDir, ["file.txt"]);
			await commit(testDir, "Third");

			const result = await log(testDir, { file: "file.txt", limit: 2 });

			expect(result.length).toBe(2);
			expect(result[0].message).toBe("Third");
			expect(result[1].message).toBe("Second");
		});

		it("should include initial commit when file was added", async () => {
			await writeFile(join(testDir, "file.txt"), "initial");
			await add(testDir, ["file.txt"]);
			await commit(testDir, "Add file.txt");

			await writeFile(join(testDir, "other.txt"), "other");
			await add(testDir, ["other.txt"]);
			await commit(testDir, "Add other.txt");

			const result = await log(testDir, { file: "file.txt" });

			expect(result.length).toBe(1);
			expect(result[0].message).toBe("Add file.txt");
		});
	});
});
