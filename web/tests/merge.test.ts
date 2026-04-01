import { existsSync } from "node:fs";
import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { merge } from "../src/merge";

describe("merge", () => {
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

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(merge(nonGitDir, "feature")).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error when merging a branch into itself", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(merge(testDir, "master")).rejects.toThrow("Cannot merge a branch into itself");
	});

	it("should throw error if branch not found", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(merge(testDir, "nonexistent")).rejects.toThrow("not found");
	});

	it("should throw error when merging into empty branch", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");
		await checkoutBranch(testDir, "feature");

		await writeFile(join(testDir, "feature.txt"), "feature content");
		await add(testDir, ["feature.txt"]);
		await commit(testDir, "Feature commit");

		await checkoutBranch(testDir, "master");
		await deleteBranchCommit(testDir);

		await expect(merge(testDir, "feature")).rejects.toThrow("Cannot merge into an empty branch");
	});

	it("should perform fast-forward merge when possible", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");
		await checkoutBranch(testDir, "feature");

		await writeFile(join(testDir, "feature.txt"), "feature content");
		await add(testDir, ["feature.txt"]);
		const featureSha = await commit(testDir, "Feature commit");

		await checkoutBranch(testDir, "master");

		const result = await merge(testDir, "feature");

		expect(result.success).toBe(true);
		expect(result.fastForward).toBe(true);
		expect(result.commitSha).toBe(featureSha);
	});

	it("should create merge commit when not fast-forward", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");
		await checkoutBranch(testDir, "feature");

		await writeFile(join(testDir, "feature.txt"), "feature content");
		await add(testDir, ["feature.txt"]);
		await commit(testDir, "Feature commit");

		await checkoutBranch(testDir, "master");

		await writeFile(join(testDir, "master.txt"), "master content");
		await add(testDir, ["master.txt"]);
		await commit(testDir, "Master commit");

		const result = await merge(testDir, "feature");

		expect(result.success).toBe(true);
		expect(result.fastForward).toBe(false);
		expect(result.commitSha).toMatch(/^[a-f0-9]{40}$/);
	});

	it("should allow non-fast-forward merge with option", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");
		await checkoutBranch(testDir, "feature");

		await writeFile(join(testDir, "feature.txt"), "feature content");
		await add(testDir, ["feature.txt"]);
		await commit(testDir, "Feature commit");

		await checkoutBranch(testDir, "master");

		const result = await merge(testDir, "feature", { noFastForward: true });

		expect(result.success).toBe(true);
		expect(result.fastForward).toBe(false);
		expect(result.commitSha).toMatch(/^[a-f0-9]{40}$/);
	});

	it("should report already up to date when branches are same", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");

		const result = await merge(testDir, "feature");

		expect(result.success).toBe(true);
		expect(result.message).toBe("Already up to date.");
	});

	it("should use custom merge message", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await createBranch(testDir, "feature");
		await checkoutBranch(testDir, "feature");

		await writeFile(join(testDir, "feature.txt"), "feature content");
		await add(testDir, ["feature.txt"]);
		await commit(testDir, "Feature commit");

		await checkoutBranch(testDir, "master");

		await writeFile(join(testDir, "master.txt"), "master content");
		await add(testDir, ["master.txt"]);
		await commit(testDir, "Master commit");

		const result = await merge(testDir, "feature", {
			message: "Custom merge message",
		});

		expect(result.success).toBe(true);
		expect(result.message).toBe("Custom merge message");
	});
});

async function createBranch(path: string, branchName: string): Promise<void> {
	const gitDir = join(path, ".git");
	const headPath = join(gitDir, "HEAD");
	const currentHead = (await readFile(headPath, "utf-8")).trim();
	const match = currentHead.match(/^ref: refs\/heads\/(.+)$/);

	if (!match) {
		throw new Error("Not on a branch");
	}

	const currentBranch = match[1];
	const currentBranchPath = join(gitDir, "refs", "heads", currentBranch);

	if (!existsSync(currentBranchPath)) {
		throw new Error("Current branch has no commits");
	}

	const currentCommit = await readFile(currentBranchPath, "utf-8");

	const newBranchPath = join(gitDir, "refs", "heads", branchName);
	await mkdir(dirname(newBranchPath), { recursive: true });
	await writeFile(newBranchPath, currentCommit);
}

async function checkoutBranch(path: string, branchName: string): Promise<void> {
	const gitDir = join(path, ".git");
	const headPath = join(gitDir, "HEAD");
	await writeFile(headPath, `ref: refs/heads/${branchName}\n`);
}

async function deleteBranchCommit(path: string): Promise<void> {
	const gitDir = join(path, ".git");
	const headPath = join(gitDir, "HEAD");
	const currentHead = (await readFile(headPath, "utf-8")).trim();
	const match = currentHead.match(/^ref: refs\/heads\/(.+)$/);

	if (!match) {
		throw new Error("Not on a branch");
	}

	const currentBranch = match[1];
	const currentBranchPath = join(gitDir, "refs", "heads", currentBranch);

	if (existsSync(currentBranchPath)) {
		await rm(currentBranchPath);
	}
}
