import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { getCurrentBranch, getCurrentCommit } from "../src/branch";

describe("branch", () => {
	let testDir: string;
	let gitDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		gitDir = join(testDir, ".git");
		await mkdir(gitDir, { recursive: true });
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	describe("getCurrentBranch", () => {
		it("should return branch name from HEAD", async () => {
			await writeFile(join(gitDir, "HEAD"), "ref: refs/heads/main\n", "utf-8");
			const branch = await getCurrentBranch(gitDir);
			expect(branch).toBe("main");
		});

		it("should throw if HEAD is detached", async () => {
			await writeFile(join(gitDir, "HEAD"), "a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n", "utf-8");
			await expect(getCurrentBranch(gitDir)).rejects.toThrow("Not on a branch");
		});
	});

	describe("getCurrentCommit", () => {
		it("should return current commit SHA", async () => {
			await writeFile(join(gitDir, "HEAD"), "ref: refs/heads/main\n", "utf-8");
			const refsHeads = join(gitDir, "refs", "heads");
			await mkdir(refsHeads, { recursive: true });
			await writeFile(
				join(refsHeads, "main"),
				"a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2\n",
				"utf-8",
			);
			const commitSha = await getCurrentCommit(gitDir);
			expect(commitSha).toBe("a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2");
		});

		it("should return null if no commit exists", async () => {
			await writeFile(join(gitDir, "HEAD"), "ref: refs/heads/main\n", "utf-8");
			const commitSha = await getCurrentCommit(gitDir);
			expect(commitSha).toBeNull();
		});
	});
});
