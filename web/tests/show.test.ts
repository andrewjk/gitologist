import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { show } from "../src/show";

describe("show", () => {
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

	it("should read file content at HEAD", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		const content = await show(testDir, "test.txt");

		expect(content).toBe("content");
	});

	it("should read nested file content at HEAD", async () => {
		await mkdir(join(testDir, "sub"), { recursive: true });
		await writeFile(join(testDir, "sub", "inner.txt"), "inner content");
		await add(testDir, ["sub/inner.txt"]);
		await commit(testDir, "Add nested file");

		const content = await show(testDir, "sub/inner.txt");

		expect(content).toBe("inner content");
	});

	it("should reflect latest committed content after updates", async () => {
		await writeFile(join(testDir, "test.txt"), "v1");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "First");

		expect(await show(testDir, "test.txt")).toBe("v1");

		await writeFile(join(testDir, "test.txt"), "v2");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second");

		expect(await show(testDir, "test.txt")).toBe("v2");
	});

	it("should not reflect uncommitted working changes", async () => {
		await writeFile(join(testDir, "test.txt"), "committed");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "uncommitted");

		const content = await show(testDir, "test.txt");

		expect(content).toBe("committed");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(show(nonGitDir, "test.txt")).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if file does not exist in HEAD", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(show(testDir, "nonexistent.txt")).rejects.toThrow("does not exist in 'HEAD'");
	});

	it("should throw error if path points to a directory", async () => {
		await mkdir(join(testDir, "sub"), { recursive: true });
		await writeFile(join(testDir, "sub", "inner.txt"), "inner");
		await add(testDir, ["sub/inner.txt"]);
		await commit(testDir, "Add nested file");

		await expect(show(testDir, "sub")).rejects.toThrow("does not exist in 'HEAD'");
	});
});
