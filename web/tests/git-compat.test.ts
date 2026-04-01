import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, rm, writeFile, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeAll } from "vite-plus/test";

import { add } from "../src/add";
import { clone } from "../src/clone";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { log } from "../src/log";

describe("git compatibility", () => {
	let baseDir: string;
	let remoteDir: string;
	let defaultBranch: string;

	beforeAll(async () => {
		baseDir = join(
			tmpdir(),
			`gitologist-compat-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(baseDir, { recursive: true });

		// Detect git default branch
		defaultBranch = "master"; // fallback

		// Create a test repo to check default branch
		const testDir = join(baseDir, "branch-test");
		await mkdir(testDir, { recursive: true });
		execSync("git init", { cwd: testDir, encoding: "utf-8" });
		try {
			const branchOutput = execSync("git branch --show-current", {
				cwd: testDir,
				encoding: "utf-8",
			});
			if (branchOutput.trim()) {
				defaultBranch = branchOutput.trim();
			}
		} catch {
			// Older git versions - use master
		}
		await rm(testDir, { recursive: true, force: true });

		// Create a "remote" repository using real git
		remoteDir = join(baseDir, "remote.git");
		await mkdir(remoteDir, { recursive: true });
		execSync("git init --bare", { cwd: remoteDir, encoding: "utf-8" });

		// Create initial content in the remote using a temporary clone
		const tempClone = join(baseDir, "temp-clone");
		execSync(`git clone ${remoteDir} temp-clone`, {
			cwd: baseDir,
			encoding: "utf-8",
		});
		await writeFile(join(tempClone, "README.md"), "# Initial");
		execSync("git add .", { cwd: tempClone, encoding: "utf-8" });
		execSync('git commit -m "Initial commit"', {
			cwd: tempClone,
			encoding: "utf-8",
		});
		execSync(`git push origin ${defaultBranch}`, {
			cwd: tempClone,
			encoding: "utf-8",
		});
		await rm(tempClone, { recursive: true, force: true });

		return async () => {
			await rm(baseDir, { recursive: true, force: true });
		};
	});

	describe("init", () => {
		it("should create same directory structure as git init", async () => {
			const ourDir = join(baseDir, "our-init");
			const theirDir = join(baseDir, "their-init");

			await mkdir(ourDir, { recursive: true });
			await mkdir(theirDir, { recursive: true });

			await init(ourDir);
			execSync("git init", { cwd: theirDir, encoding: "utf-8" });

			const ourGitDir = join(ourDir, ".git");
			const theirGitDir = join(theirDir, ".git");

			expect(existsSync(ourGitDir)).toBe(true);
			expect(existsSync(theirGitDir)).toBe(true);

			expect(existsSync(join(ourGitDir, "objects"))).toBe(true);
			expect(existsSync(join(theirGitDir, "objects"))).toBe(true);

			expect(existsSync(join(ourGitDir, "refs", "heads"))).toBe(true);
			expect(existsSync(join(theirGitDir, "refs", "heads"))).toBe(true);

			expect(existsSync(join(ourGitDir, "refs", "tags"))).toBe(true);
			expect(existsSync(join(theirGitDir, "refs", "tags"))).toBe(true);
		});

		it("should create HEAD pointing to same ref format as git init", async () => {
			const ourDir = join(baseDir, "our-init2");
			const theirDir = join(baseDir, "their-init2");

			await mkdir(ourDir, { recursive: true });
			await mkdir(theirDir, { recursive: true });

			await init(ourDir);
			execSync("git init", { cwd: theirDir, encoding: "utf-8" });

			const ourHead = await readFile(join(ourDir, ".git", "HEAD"), "utf-8");
			const theirHead = await readFile(join(theirDir, ".git", "HEAD"), "utf-8");

			// Both should point to a branch (usually master or main)
			expect(ourHead).toMatch(/^ref: refs\/heads\//);
			expect(theirHead).toMatch(/^ref: refs\/heads\//);
		});
	});

	describe("add and commit", () => {
		it("should create commits that git can read", async () => {
			const ourDir = join(baseDir, "our-commit");
			await mkdir(ourDir, { recursive: true });
			await init(ourDir);

			await writeFile(join(ourDir, "test.txt"), "test content");
			await add(ourDir, ["test.txt"]);
			await commit(ourDir, "Test commit");

			// Verify our commit can be read by git log
			const gitLog = execSync("git log --oneline", {
				cwd: ourDir,
				encoding: "utf-8",
			});

			expect(gitLog).toContain("Test commit");
		});

		it("should produce same commit structure as git", async () => {
			const ourDir = join(baseDir, "our-commit2");
			const theirDir = join(baseDir, "their-commit2");

			// Our implementation
			await mkdir(ourDir, { recursive: true });
			await init(ourDir);
			await writeFile(join(ourDir, "file.txt"), "content");
			await add(ourDir, ["file.txt"]);
			const ourSha = await commit(ourDir, "Same message");

			// Real git
			await mkdir(theirDir, { recursive: true });
			execSync("git init", { cwd: theirDir, encoding: "utf-8" });
			await writeFile(join(theirDir, "file.txt"), "content");
			execSync("git add .", { cwd: theirDir, encoding: "utf-8" });
			execSync('git commit -m "Same message"', {
				cwd: theirDir,
				encoding: "utf-8",
			});

			// Both should have valid commit SHAs
			expect(ourSha).toMatch(/^[a-f0-9]{40}$/);

			// Both should have 1 commit in log
			const ourLog = await log(ourDir);
			const theirLog = execSync("git log --oneline", {
				cwd: theirDir,
				encoding: "utf-8",
			});

			expect(ourLog.length).toBe(1);
			expect(theirLog.trim().split("\n").length).toBe(1);
		});
	});

	describe("log", () => {
		it("should show same commit order as git log", async () => {
			const ourDir = join(baseDir, "our-log");
			await mkdir(ourDir, { recursive: true });
			await init(ourDir);

			// Create multiple commits
			await writeFile(join(ourDir, "file1.txt"), "content1");
			await add(ourDir, ["file1.txt"]);
			await commit(ourDir, "First commit");

			await writeFile(join(ourDir, "file2.txt"), "content2");
			await add(ourDir, ["file2.txt"]);
			await commit(ourDir, "Second commit");

			await writeFile(join(ourDir, "file3.txt"), "content3");
			await add(ourDir, ["file3.txt"]);
			await commit(ourDir, "Third commit");

			const ourLog = await log(ourDir);
			const gitLog = execSync("git log --oneline", {
				cwd: ourDir,
				encoding: "utf-8",
			});

			// Both should have 3 commits
			expect(ourLog.length).toBe(3);
			expect(gitLog.trim().split("\n").length).toBe(3);

			// Both should show commits in reverse chronological order
			expect(ourLog[0].message).toBe("Third commit");
			expect(ourLog[1].message).toBe("Second commit");
			expect(ourLog[2].message).toBe("First commit");

			expect(gitLog).toContain("Third commit");
			expect(gitLog).toContain("Second commit");
			expect(gitLog).toContain("First commit");
		});
	});

	describe("clone", () => {
		it("should create repo structure like git clone (without fetch)", async () => {
			const ourClone = join(baseDir, "our-clone2");

			// Our implementation (simplified - just sets up repo and remote)
			await clone(remoteDir, ourClone);

			// Verify our clone exists with proper structure
			expect(existsSync(join(ourClone, ".git"))).toBe(true);
			expect(existsSync(join(ourClone, ".git", "objects"))).toBe(true);
			expect(existsSync(join(ourClone, ".git", "refs", "heads"))).toBe(true);

			// Verify remote is configured
			const config = await readFile(join(ourClone, ".git", "config"), "utf-8");
			expect(config).toContain('[remote "origin"]');
			expect(config).toContain(`url = ${remoteDir}`);
		});
	});
});
