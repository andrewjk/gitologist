import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { push, setUpstreamBranch } from "../src/push";

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

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "main");
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

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "upstream", "main");
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

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "main");
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

		const remoteBranchPath = join(remoteDir, "main");
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

		const remoteBranchPath = join(testDir, ".git", "refs", "remotes", "origin", "main");
		const remoteBranchContent = await readFile(remoteBranchPath, "utf-8");

		const remoteSha = remoteBranchContent.trim();

		const localBranchPath = join(testDir, ".git", "refs", "heads", "main");
		const localBranchContent = await readFile(localBranchPath, "utf-8");
		const localSha = localBranchContent.trim();

		expect(remoteSha).toBe(localSha);
	});
});

describe("setUpstreamBranch", () => {
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

	it("should create new branch section with remote and merge settings", async () => {
		const configPath = join(testDir, ".git", "config");

		await setUpstreamBranch(testDir, "origin", "feature");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "feature"]');
		expect(configContent).toContain("remote = origin");
		expect(configContent).toContain("merge = refs/heads/feature");
	});

	it("should add remote and merge settings to existing branch section", async () => {
		const configPath = join(testDir, ".git", "config");
		await writeFile(configPath, '[branch "feature"]\n\tdescription = test branch\n', "utf-8");

		await setUpstreamBranch(testDir, "upstream", "feature");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "feature"]');
		expect(configContent).toContain("description = test branch");
		expect(configContent).toContain("remote = upstream");
		expect(configContent).toContain("merge = refs/heads/feature");
	});

	it("should update existing remote and merge settings", async () => {
		const configPath = join(testDir, ".git", "config");
		await writeFile(
			configPath,
			'[branch "main"]\n\tremote = origin\n\tmerge = refs/heads/main\n',
			"utf-8",
		);

		await setUpstreamBranch(testDir, "upstream", "main");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "main"]');
		expect(configContent).toContain("remote = upstream");
		expect(configContent).toContain("merge = refs/heads/main");
	});

	it("should handle multiple branches correctly", async () => {
		const configPath = join(testDir, ".git", "config");
		await writeFile(
			configPath,
			'[branch "main"]\n\tremote = origin\n\tmerge = refs/heads/main\n',
			"utf-8",
		);

		await setUpstreamBranch(testDir, "upstream", "feature");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "main"]');
		expect(configContent).toContain("remote = origin");
		expect(configContent).toContain('[branch "feature"]');
		expect(configContent).toContain("remote = upstream");
		expect(configContent).toContain("merge = refs/heads/feature");
	});

	it("should preserve other config sections", async () => {
		const configPath = join(testDir, ".git", "config");
		await writeFile(
			configPath,
			'[core]\n\trepositoryformatversion = 0\n\n[remote "origin"]\n\turl = test.git\n',
			"utf-8",
		);

		await setUpstreamBranch(testDir, "origin", "main");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain("[core]");
		expect(configContent).toContain("repositoryformatversion = 0");
		expect(configContent).toContain('[remote "origin"]');
		expect(configContent).toContain("url = test.git");
		expect(configContent).toContain('[branch "main"]');
	});

	it("should handle empty config file", async () => {
		const configPath = join(testDir, ".git", "config");
		await writeFile(configPath, "", "utf-8");

		await setUpstreamBranch(testDir, "origin", "main");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "main"]');
		expect(configContent).toContain("remote = origin");
		expect(configContent).toContain("merge = refs/heads/main");
	});

	it("should handle missing config file", async () => {
		const configPath = join(testDir, ".git", "config");
		await rm(configPath, { force: true });

		await setUpstreamBranch(testDir, "origin", "main");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain('[branch "main"]');
		expect(configContent).toContain("remote = origin");
		expect(configContent).toContain("merge = refs/heads/main");
	});

	it("should use tabs for indentation", async () => {
		const configPath = join(testDir, ".git", "config");

		await setUpstreamBranch(testDir, "origin", "main");

		const configContent = await readFile(configPath, "utf-8");
		expect(configContent).toContain("\tremote = origin");
		expect(configContent).toContain("\tmerge = refs/heads/main");
	});
});
