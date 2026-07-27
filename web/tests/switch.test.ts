import { mkdir, rm, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { switchBranch } from "../src/switch";

describe("switch", () => {
	let testDir: string;
	let gitDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		await mkdir(testDir, { recursive: true });
		await init(testDir);
		gitDir = join(testDir, ".git");
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	describe("switchBranch", () => {
		it("should switch to an existing local branch and update HEAD and tree", async () => {
			await writeFile(join(testDir, "file.txt"), "A");
			await add(testDir, ["file.txt"]);
			const firstSha = await commit(testDir, "First commit");

			// Create a feature branch pointing at the first commit
			await writeFile(join(gitDir, "refs", "heads", "feature"), firstSha);

			// Second commit on main changes the working tree (file.txt = "B")
			await writeFile(join(testDir, "file.txt"), "B");
			await add(testDir, ["file.txt"]);
			await commit(testDir, "Second commit");

			await switchBranch(testDir, "feature");

			const head = await readFile(join(gitDir, "HEAD"), "utf-8");
			expect(head).toBe("ref: refs/heads/feature\n");

			// Working tree should now reflect the feature branch (file.txt = "A")
			const content = await readFile(join(testDir, "file.txt"), "utf-8");
			expect(content).toBe("A");
		});

		it("should create a local branch from a single remote tracking branch", async () => {
			await writeFile(join(testDir, "file.txt"), "content");
			await add(testDir, ["file.txt"]);
			const sha = await commit(testDir, "Initial commit");

			// Simulate a fetched remote-tracking branch with no local branch yet
			await mkdir(join(gitDir, "refs", "remotes", "origin"), { recursive: true });
			await writeFile(join(gitDir, "refs", "remotes", "origin", "feature"), sha);

			await switchBranch(testDir, "feature");

			// Local branch created at the same SHA
			const localSha = (await readFile(join(gitDir, "refs", "heads", "feature"), "utf-8")).trim();
			expect(localSha).toBe(sha);

			// HEAD points at the new local branch
			const head = await readFile(join(gitDir, "HEAD"), "utf-8");
			expect(head).toBe("ref: refs/heads/feature\n");

			// Tracking config written
			const config = await readFile(join(gitDir, "config"), "utf-8");
			expect(config).toContain('[branch "feature"]');
			expect(config).toContain("remote = origin");
			expect(config).toContain("merge = refs/heads/feature");

			// Tree checked out
			const content = await readFile(join(testDir, "file.txt"), "utf-8");
			expect(content).toBe("content");
		});

		it("should throw if branch does not exist", async () => {
			await expect(switchBranch(testDir, "nonexistent")).rejects.toThrow(
				"Branch 'nonexistent' not found",
			);
		});

		it("should throw if not a git repository", async () => {
			await rm(gitDir, { recursive: true, force: true });
			await expect(switchBranch(testDir, "feature-branch")).rejects.toThrow("Not a git repository");
		});
	});
});
