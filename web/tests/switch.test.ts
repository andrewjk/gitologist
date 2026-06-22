import { mkdir, rm, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { switchBranch } from "../src/switch";

describe("switch", () => {
	let testDir: string;
	let gitDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		gitDir = join(testDir, ".git");
		await mkdir(gitDir, { recursive: true });
		await mkdir(join(gitDir, "refs", "heads"), { recursive: true });
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	describe("switchBranch", () => {
		it("should write branch name to HEAD", async () => {
			await writeFile(join(gitDir, "refs", "heads", "feature-branch"), "abc123\n");
			await switchBranch(testDir, "feature-branch");
			const head = await readFile(join(gitDir, "HEAD"), "utf-8");
			expect(head).toBe("ref: refs/heads/feature-branch\n");
		});

		it("should throw if not a git repository", async () => {
			await rm(gitDir, { recursive: true, force: true });
			await expect(switchBranch(testDir, "feature-branch")).rejects.toThrow("Not a git repository");
		});

		it("should throw if branch does not exist", async () => {
			await expect(switchBranch(testDir, "nonexistent")).rejects.toThrow(
				"Branch 'nonexistent' not found",
			);
		});
	});
});
