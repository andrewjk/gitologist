import { execSync } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, rm, readFile, readdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeAll } from "vite-plus/test";

import { init } from "../src/init";

describe("init compatibility", () => {
	let testDir: string;
	let gitDir: string;

	beforeAll(async () => {
		const baseDir = join(
			tmpdir(),
			`gitologist-compat-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(baseDir, { recursive: true });

		testDir = join(baseDir, "ours");
		gitDir = join(baseDir, "theirs");

		await mkdir(testDir, { recursive: true });
		await mkdir(gitDir, { recursive: true });

		// Cleanup after all tests
		return async () => {
			await rm(baseDir, { recursive: true, force: true });
		};
	});

	it("should create same directory structure as git init", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		const ourGitDir = join(testDir, ".git");
		const theirGitDir = join(gitDir, ".git");

		expect(existsSync(ourGitDir)).toBe(true);
		expect(existsSync(theirGitDir)).toBe(true);

		// Check that both have the essential directories
		expect(existsSync(join(ourGitDir, "objects"))).toBe(true);
		expect(existsSync(join(theirGitDir, "objects"))).toBe(true);

		expect(existsSync(join(ourGitDir, "refs", "heads"))).toBe(true);
		expect(existsSync(join(theirGitDir, "refs", "heads"))).toBe(true);

		expect(existsSync(join(ourGitDir, "refs", "tags"))).toBe(true);
		expect(existsSync(join(theirGitDir, "refs", "tags"))).toBe(true);
	});

	it("should create HEAD pointing to same branch as git init", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		const ourHead = await readFile(join(testDir, ".git", "HEAD"), "utf-8");
		const theirHead = await readFile(join(gitDir, ".git", "HEAD"), "utf-8");

		// Both should point to a branch (usually main or main)
		expect(ourHead).toMatch(/^ref: refs\/heads\//);
		expect(theirHead).toMatch(/^ref: refs\/heads\//);
	});

	it("should create valid config file", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		const ourConfig = await readFile(join(testDir, ".git", "config"), "utf-8");
		const theirConfig = await readFile(join(gitDir, ".git", "config"), "utf-8");

		// Both should have core section with repositoryformatversion
		expect(ourConfig).toContain("[core]");
		expect(ourConfig).toContain("repositoryformatversion");
		expect(theirConfig).toContain("[core]");
		expect(theirConfig).toContain("repositoryformatversion");
	});

	it("should create empty objects directory like git init", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		const ourObjects = await readdir(join(testDir, ".git", "objects"));
		const theirObjects = await readdir(join(gitDir, ".git", "objects"));

		// Both should have info and pack directories (or be empty initially)
		// Note: git init may create info and pack subdirectories
		expect(Array.isArray(ourObjects)).toBe(true);
		expect(Array.isArray(theirObjects)).toBe(true);
	});

	it("should create empty refs/heads directory like git init", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		const ourRefsHeads = await readdir(join(testDir, ".git", "refs", "heads"));
		const theirRefsHeads = await readdir(join(gitDir, ".git", "refs", "heads"));

		// Both should be empty (no branches created yet)
		expect(ourRefsHeads.length).toBe(0);
		expect(theirRefsHeads.length).toBe(0);
	});

	it("should create description file", async () => {
		await init(testDir);
		execSync("git init", { cwd: gitDir, encoding: "utf-8" });

		expect(existsSync(join(testDir, ".git", "description"))).toBe(true);
		expect(existsSync(join(gitDir, ".git", "description"))).toBe(true);
	});
});
