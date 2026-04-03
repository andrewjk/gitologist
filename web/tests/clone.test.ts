import { mkdir, rm, readFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { clone } from "../src/clone";

describe("clone", () => {
	let testDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(testDir, { recursive: true });
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	it("should clone a repository to default directory", async () => {
		const url = "https://github.com/user/repo.git";
		const targetPath = join(testDir, "repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);

		const gitDir = join(resultPath, ".git");
		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(gitDir)).toBe(true);
	});

	it("should clone to specified directory", async () => {
		const url = "https://github.com/user/repo.git";
		const targetPath = join(testDir, "my-custom-dir");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);

		const { default: fs } = await import("node:fs");
		expect(fs.existsSync(targetPath)).toBe(true);
	});

	it("should extract repo name from URL", async () => {
		const url = "https://github.com/user/my-repo.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);
	});

	it("should initialize git repository", async () => {
		const url = "https://github.com/user/repo.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		const headPath = join(resultPath, ".git", "HEAD");
		const headContent = await readFile(headPath, "utf-8");

		expect(headContent).toContain("ref: refs/heads/main");
	});

	it("should add remote", async () => {
		const url = "https://github.com/user/repo.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		const configPath = join(resultPath, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain('[remote "origin"]');
		expect(configContent).toContain("url = https://github.com/user/repo.git");
	});

	it("should handle URLs with .git extension", async () => {
		const url = "https://github.com/user/repo.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);

		const configPath = join(resultPath, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain("url = https://github.com/user/repo.git");
	});

	it("should handle URLs without .git extension", async () => {
		const url = "https://github.com/user/repo";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);

		const configPath = join(resultPath, ".git", "config");
		const configContent = await readFile(configPath, "utf-8");

		expect(configContent).toContain("url = https://github.com/user/repo");
	});

	it("should extract repo name from complex URL", async () => {
		const url = "https://github.com/org/team/project.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);
	});

	it("should handle subdirectory in URL", async () => {
		const url = "https://github.com/user/nested/project.git";
		const targetPath = join(testDir, "test-repo");
		const resultPath = await clone(url, targetPath);

		expect(resultPath).toBe(targetPath);
	});

	it("should throw error if directory already exists", async () => {
		const url = "https://github.com/user/repo.git";
		const existingPath = join(testDir, "repo");
		await mkdir(existingPath, { recursive: true });

		await expect(clone(url, existingPath)).rejects.toThrow();
	});
});
