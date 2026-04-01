import { mkdir, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { init } from "../src/init";
import { remoteAdd } from "../src/remote";

describe("remote", () => {
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

	it("should add a remote", async () => {
		await remoteAdd(testDir, "origin", "https://github.com/user/repo.git");

		const configPath = join(testDir, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain('[remote "origin"]');
		expect(configContent).toContain("url = https://github.com/user/repo.git");
	});

	it("should add fetch refspec", async () => {
		await remoteAdd(testDir, "origin", "https://github.com/user/repo.git");

		const configPath = join(testDir, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain("fetch = +refs/heads/*:refs/remotes/origin/*");
	});

	it("should add remote with custom name", async () => {
		await remoteAdd(testDir, "upstream", "https://github.com/original/repo.git");

		const configPath = join(testDir, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain('[remote "upstream"]');
		expect(configContent).toContain("url = https://github.com/original/repo.git");
		expect(configContent).toContain("fetch = +refs/heads/*:refs/remotes/upstream/*");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(
			remoteAdd(nonGitDir, "origin", "https://github.com/user/repo.git"),
		).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if remote already exists", async () => {
		await remoteAdd(testDir, "origin", "https://github.com/user/repo.git");

		await expect(remoteAdd(testDir, "origin", "https://github.com/other/repo.git")).rejects.toThrow(
			"Remote 'origin' already exists",
		);
	});

	it("should preserve existing config", async () => {
		await remoteAdd(testDir, "origin", "https://github.com/user/repo.git");
		await remoteAdd(testDir, "upstream", "https://github.com/original/repo.git");

		const configPath = join(testDir, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain('[remote "origin"]');
		expect(configContent).toContain('[remote "upstream"]');
		expect(configContent).toContain("url = https://github.com/user/repo.git");
		expect(configContent).toContain("url = https://github.com/original/repo.git");
	});

	it("should append to existing config file", async () => {
		const configPath = join(testDir, ".git", "config");
		const originalConfig = await readFile(configPath, "utf-8");

		await remoteAdd(testDir, "origin", "https://github.com/user/repo.git");

		const newConfig = await readFile(configPath, "utf-8");

		expect(newConfig).toContain(originalConfig.trim());
		expect(newConfig).toContain('[remote "origin"]');
	});
});
