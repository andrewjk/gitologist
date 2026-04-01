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
});
