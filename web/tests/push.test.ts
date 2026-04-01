import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { push } from "../src/push";

describe("push", () => {
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

	it("should push to default remote and branch", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir);

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "master");
		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(remoteBranchPath)).toBe(true);

		const remoteBranchContent = await readFile(remoteBranchPath, "utf-8");
		expect(remoteBranchContent).toMatch(/^[a-f0-9]{40}/);
	});

	it("should push to specified remote", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir, "upstream");

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "upstream", "master");
		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(remoteBranchPath)).toBe(true);
	});

	it("should push to specified branch", async () => {
		const headPath = join(testDir, ".git", "HEAD");
		await writeFile(headPath, "ref: refs/heads/main\n", "utf-8");

		await mkdir(join(testDir, ".git", "refs", "heads"), { recursive: true });
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), "abc123\n", "utf-8");

		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir, "origin", "main");

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "main");
		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(remoteBranchPath)).toBe(true);
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(push(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if there are uncommitted changes", async () => {
		await writeFile(join(testDir, "test.txt"), "initial");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test.txt"), "modified");

		await expect(push(testDir)).rejects.toThrow("uncommitted changes");
	});

	it("should throw error if there are untracked files", async () => {
		await writeFile(join(testDir, "test.txt"), "initial");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await writeFile(join(testDir, "test2.txt"), "untracked");

		await expect(push(testDir)).rejects.toThrow("uncommitted changes");
	});

	it("should throw error if local branch does not exist", async () => {
		const headPath = join(testDir, ".git", "HEAD");
		await writeFile(headPath, "ref: refs/heads/nonexistent\n", "utf-8");

		await expect(push(testDir)).rejects.toThrow("does not exist");
	});

	it("should update existing remote branch", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "First commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		const secondSha = await commit(testDir, "Second commit");

		await push(testDir);

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "master");
		const remoteBranchContent = await readFile(remoteBranchPath, "utf-8");

		expect(remoteBranchContent.trim()).toBe(secondSha);
	});

	it("should create remote directory if it does not exist", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir, "myremote");

		const remoteDir = join(testDir, ".git", "refs", "remotes", "myremote");
		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(remoteDir)).toBe(true);

		const remoteBranchPath = join(remoteDir, "master");
		expect(fs.existsSync(remoteBranchPath)).toBe(true);
	});

	it("should handle multiple pushes to same branch", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "First commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await push(testDir);

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "master");
		const remoteBranchContent = await readFile(remoteBranchPath, "utf-8");

		const remoteSha = remoteBranchContent.trim();

		const localBranchPath = join(testDir, ".git", "refs", "heads", "master");
		const localBranchContent = await readFile(localBranchPath, "utf-8");
		const localSha = localBranchContent.trim();

		expect(remoteSha).toBe(localSha);
	});
});
