import { existsSync } from "node:fs";
import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { stash, unstash } from "../src/stash";
import { status } from "../src/status";

describe("stash", () => {
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

	it("should stash a modified file", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified content");

		const stashSha = await stash(testDir, "WIP");

		expect(stashSha).toMatch(/^[a-f0-9]{40}$/);

		const result = await status(testDir);
		expect(result.modified).toEqual([]);

		const fileContent = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(fileContent).toBe("initial content");
	});

	it("should stash an untracked file", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "newfile.txt"), "untracked content");

		const stashSha = await stash(testDir, "WIP");

		expect(stashSha).toMatch(/^[a-f0-9]{40}$/);

		const result = await status(testDir);
		expect(result.untracked).toEqual([]);

		const exists = existsSync(join(testDir, "newfile.txt"));
		expect(exists).toBe(false);
	});

	it("should update stash ref", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified");

		const stashSha = await stash(testDir, "Save work");

		const stashRefPath = join(testDir, ".git", "refs", "stash");
		const refContent = await readFile(stashRefPath, "utf-8");

		expect(refContent.trim()).toBe(stashSha);
	});

	it("should reset index to HEAD after stash", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified content");
		await add(testDir, ["test.txt"]);

		const preStashStatus = await status(testDir);
		expect(preStashStatus.staged).toContain("test.txt");

		await stash(testDir, "WIP");

		const postStashStatus = await status(testDir);

		const fileContent = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(fileContent).toBe("initial content");
		expect(postStashStatus.modified).toEqual([]);
	});

	it("should throw error if nothing to stash", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(stash(testDir, "WIP")).rejects.toThrow("Nothing to stash");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(
			tmpdir(),
			`not-a-repo-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(nonGitDir, { recursive: true });

		await expect(stash(nonGitDir, "WIP")).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should handle custom stash message", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified");

		const message = "Work in progress on feature X";
		await stash(testDir, message);

		const stashRefPath = join(testDir, ".git", "refs", "stash");
		const stashSha = (await readFile(stashRefPath, "utf-8")).trim();

		const commitPath = join(testDir, ".git", "objects", stashSha.slice(0, 2), stashSha.slice(2));

		const exists = existsSync(commitPath);
		expect(exists).toBe(true);
	});

	it("should restore stashed modified file", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified content");

		await stash(testDir, "WIP");

		const afterStashContent = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(afterStashContent).toBe("initial content");

		await unstash(testDir);

		const afterUnstashContent = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(afterUnstashContent).toBe("modified content");

		const statusResult = await status(testDir);
		expect(statusResult.modified).toContain("test.txt");
	});

	it("should restore stashed untracked file", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "newfile.txt"), "untracked content");

		await stash(testDir, "WIP");

		const existsAfterStash = existsSync(join(testDir, "newfile.txt"));
		expect(existsAfterStash).toBe(false);

		await unstash(testDir);

		const existsAfterUnstash = existsSync(join(testDir, "newfile.txt"));
		expect(existsAfterUnstash).toBe(true);

		const content = await readFile(join(testDir, "newfile.txt"), "utf-8");
		expect(content).toBe("untracked content");

		const statusResult = await status(testDir);
		expect(statusResult.untracked).toContain("newfile.txt");
	});

	it("should throw error if no stash exists", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(unstash(testDir)).rejects.toThrow("No stash found");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(
			tmpdir(),
			`not-a-repo-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(nonGitDir, { recursive: true });

		await expect(unstash(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should preserve ignored files when stashing", async () => {
		await writeFile(join(testDir, "test.txt"), "initial content");
		await writeFile(join(testDir, ".gitignore"), "*.log\nnode_modules/\n");
		await add(testDir, [".gitignore", "test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified content");
		await writeFile(join(testDir, "debug.log"), "log data");
		await mkdir(join(testDir, "node_modules", "pkg"), { recursive: true });
		await writeFile(join(testDir, "node_modules", "pkg", "index.js"), "module");

		await stash(testDir, "WIP");

		const afterStashContent = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(afterStashContent).toBe("initial content");

		expect(existsSync(join(testDir, "debug.log"))).toBe(true);
		expect(existsSync(join(testDir, "node_modules", "pkg", "index.js"))).toBe(true);

		const logContent = await readFile(join(testDir, "debug.log"), "utf-8");
		expect(logContent).toBe("log data");
	});

	it("should stash multiple files and preserve ignored files", async () => {
		await writeFile(join(testDir, "tracked.txt"), "tracked content");
		await writeFile(join(testDir, ".gitignore"), "*.log\nbuild/\n");
		await add(testDir, [".gitignore", "tracked.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "tracked.txt"), "modified");
		await writeFile(join(testDir, "new.txt"), "new file");
		await mkdir(join(testDir, "build"), { recursive: true });
		await writeFile(join(testDir, "build", "output.js"), "compiled");
		await writeFile(join(testDir, "error.log"), "errors");

		await stash(testDir, "WIP");

		expect(existsSync(join(testDir, "build", "output.js"))).toBe(true);
		expect(existsSync(join(testDir, "error.log"))).toBe(true);

		const buildContent = await readFile(join(testDir, "build", "output.js"), "utf-8");
		expect(buildContent).toBe("compiled");
	});

	it("should restore multiple stashed files", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await add(testDir, ["file1.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "file1.txt"), "modified1");
		await writeFile(join(testDir, "file2.txt"), "content2");

		await stash(testDir, "Multiple files");

		const afterStashContent1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		expect(afterStashContent1).toBe("content1");
		const existsAfterStash = existsSync(join(testDir, "file2.txt"));
		expect(existsAfterStash).toBe(false);

		await unstash(testDir);

		const afterUnstashContent1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		expect(afterUnstashContent1).toBe("modified1");
		const existsAfterUnstash = existsSync(join(testDir, "file2.txt"));
		expect(existsAfterUnstash).toBe(true);
		const afterUnstashContent2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		expect(afterUnstashContent2).toBe("content2");

		const statusResult = await status(testDir);
		expect(statusResult.modified).toContain("file1.txt");
		expect(statusResult.untracked).toContain("file2.txt");
	});

	it("should merge stashed changes with changes to HEAD after stash", async () => {
		await writeFile(join(testDir, "file.txt"), "line1\nline2\nline3\nline4\nline5");
		await add(testDir, ["file.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "file.txt"), "line1\nline2-modified\nline3\nline4\nline5");

		await stash(testDir, "WIP");

		await writeFile(join(testDir, "file.txt"), "line1\nline2\nline3\nline4-pulled\nline5");
		await add(testDir, ["file.txt"]);
		await commit(testDir, "Pulled changes");

		await unstash(testDir);

		const content = await readFile(join(testDir, "file.txt"), "utf-8");
		expect(content).toBe("line1\nline2-modified\nline3\nline4-pulled\nline5");
	});

	it("should detect conflicts when both stash and HEAD modify same lines", async () => {
		await writeFile(join(testDir, "file.txt"), "line1\nline2\nline3");
		await add(testDir, ["file.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "file.txt"), "line1\nline2-local\nline3");

		await stash(testDir, "WIP");

		await writeFile(join(testDir, "file.txt"), "line1\nline2-remote\nline3");
		await add(testDir, ["file.txt"]);
		await commit(testDir, "Remote changes");

		await unstash(testDir);

		const content = await readFile(join(testDir, "file.txt"), "utf-8");
		expect(content).toContain("<<<<<<< Updated upstream");
		expect(content).toContain("line2-remote");
		expect(content).contains("=======");
		expect(content).toContain("line2-local");
		expect(content).toContain(">>>>>>> Stashed changes");
	});

	it("should keep HEAD changes when stash did not modify a file", async () => {
		await writeFile(join(testDir, "a.txt"), "a-original");
		await writeFile(join(testDir, "b.txt"), "b-original");
		await add(testDir, ["a.txt", "b.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "a.txt"), "a-local");

		await stash(testDir, "WIP");

		await writeFile(join(testDir, "b.txt"), "b-remote");
		await add(testDir, ["b.txt"]);
		await commit(testDir, "Remote changes");

		await unstash(testDir);

		const aContent = await readFile(join(testDir, "a.txt"), "utf-8");
		expect(aContent).toBe("a-local");

		const bContent = await readFile(join(testDir, "b.txt"), "utf-8");
		expect(bContent).toBe("b-remote");
	});
});
