import { existsSync } from "node:fs";
import { mkdir, rm, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { init } from "../src/init";

describe("init", () => {
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

	it("should create .git directory", async () => {
		await init(testDir);
		const gitDir = join(testDir, ".git");
		expect(existsSync(gitDir)).toBe(true);
	});

	it("should not create .git if it already exists", async () => {
		const gitDir = join(testDir, ".git");
		await mkdir(gitDir, { recursive: true });
		await writeFile(join(gitDir, "custom-file"), "test");

		await init(testDir);

		const customFile = await readFile(join(gitDir, "custom-file"), "utf-8");
		expect(customFile).toBe("test");
	});

	it("should create HEAD file", async () => {
		await init(testDir);
		const head = await readFile(join(testDir, ".git", "HEAD"), "utf-8");
		expect(head).toBe("ref: refs/heads/main\n");
	});

	it("should create config file", async () => {
		await init(testDir);
		const config = await readFile(join(testDir, ".git", "config"), "utf-8");
		expect(config).toContain("[core]");
		expect(config).toContain("repositoryformatversion = 0");
	});

	it("should create objects directory", async () => {
		await init(testDir);
		expect(existsSync(join(testDir, ".git", "objects"))).toBe(true);
	});

	it("should create refs/heads directory", async () => {
		await init(testDir);
		expect(existsSync(join(testDir, ".git", "refs", "heads"))).toBe(true);
	});

	it("should create refs/tags directory", async () => {
		await init(testDir);
		expect(existsSync(join(testDir, ".git", "refs", "tags"))).toBe(true);
	});

	it("should create info directory", async () => {
		await init(testDir);
		expect(existsSync(join(testDir, ".git", "info"))).toBe(true);
	});
});
