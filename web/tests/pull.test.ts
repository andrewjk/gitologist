import { mkdir, rm, writeFile, readFile, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { add, addAll } from "../src/add";
import { commit } from "../src/commit";
import { init } from "../src/init";
import { pull } from "../src/pull";
import { push } from "../src/push";

describe("pull", () => {
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

	it("should pull from default remote and branch", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await push(testDir);

		await pull(testDir);

		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("modified");
	});

	it("should pull from specified remote", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir, "upstream");

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await push(testDir, "upstream");

		await pull(testDir, "upstream");

		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("modified");
	});

	it("should pull from specified branch", async () => {
		const headPath = join(testDir, ".git", "HEAD");
		await writeFile(headPath, "ref: refs/heads/main\n", "utf-8");

		await mkdir(join(testDir, ".git", "refs", "heads"), { recursive: true });
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), "abc123\n", "utf-8");

		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir, "origin", "main");

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Second commit");

		await push(testDir, "origin", "main");

		await pull(testDir, "origin", "main");

		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("modified");
	});

	it("should throw error if not a git repository", async () => {
		const nonGitDir = join(tmpdir(), `not-a-repo-${Date.now()}`);
		await mkdir(nonGitDir, { recursive: true });

		await expect(pull(nonGitDir)).rejects.toThrow("Not a git repository");

		await rm(nonGitDir, { recursive: true, force: true });
	});

	it("should throw error if remote branch does not exist", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await expect(pull(testDir)).rejects.toThrow("does not exist");
	});

	it("should update local branch reference", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		const secondSha = await commit(testDir, "Second commit");

		await push(testDir);

		await pull(testDir);

		const localBranchPath = join(testDir, ".git", "refs", "heads", "main");
		const localBranchContent = await readFile(localBranchPath, "utf-8");

		expect(localBranchContent.trim()).toBe(secondSha);
	});

	it("should handle directories", async () => {
		await mkdir(join(testDir, "src"), { recursive: true });
		await writeFile(join(testDir, "src", "index.ts"), "console.log('hello')");
		await add(testDir, ["src/index.ts"]);
		await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "src", "index.ts"), "console.log('world')");
		await add(testDir, ["src/index.ts"]);
		await commit(testDir, "Second commit");

		await push(testDir);

		await pull(testDir);

		const content = await readFile(join(testDir, "src", "index.ts"), "utf-8");
		expect(content).toBe("console.log('world')");
	});

	it("should handle multiple files", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await writeFile(join(testDir, "file3.txt"), "content3");
		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);
		await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "file1.txt"), "modified1");
		await writeFile(join(testDir, "file2.txt"), "modified2");
		await writeFile(join(testDir, "file3.txt"), "modified3");
		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);
		await commit(testDir, "Second commit");

		await push(testDir);

		await pull(testDir);

		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		const content2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		const content3 = await readFile(join(testDir, "file3.txt"), "utf-8");

		expect(content1).toBe("modified1");
		expect(content2).toBe("modified2");
		expect(content3).toBe("modified3");
	});

	it("should fast-forward when remote is ahead", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		const firstSha = await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		const secondSha = await commit(testDir, "Second commit");
		await push(testDir);

		// Reset local branch back to first commit to simulate another clone
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), firstSha + "\n");
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		await pull(testDir);

		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("modified");

		const localBranchPath = join(testDir, ".git", "refs", "heads", "main");
		const localBranchContent = await readFile(localBranchPath, "utf-8");
		expect(localBranchContent.trim()).toBe(secondSha);
	});

	it("should throw error when local changes would be overwritten", async () => {
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);
		const firstSha = await commit(testDir, "Initial commit");

		await push(testDir);

		await writeFile(join(testDir, "test.txt"), "modified");
		await add(testDir, ["test.txt"]);
		/*const secondSha =*/ await commit(testDir, "Second commit");
		await push(testDir);

		// Reset local branch back to first commit
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), firstSha + "\n");
		await writeFile(join(testDir, "test.txt"), "content");
		await add(testDir, ["test.txt"]);

		// Make uncommitted local change
		await writeFile(join(testDir, "test.txt"), "local changes");

		await expect(pull(testDir)).rejects.toThrow("would be overwritten by merge");

		// Verify local changes are preserved
		const content = await readFile(join(testDir, "test.txt"), "utf-8");
		expect(content).toBe("local changes");
	});

	it("should delete files removed on remote", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await writeFile(join(testDir, "file3.txt"), "content3");
		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);
		const firstSha = await commit(testDir, "Initial commit");

		await push(testDir);

		// Remove file2 on the remote
		await rm(join(testDir, "file2.txt"));
		await addAll(testDir);
		await commit(testDir, "Remove file2");

		await push(testDir);

		// Reset local branch back to first commit to simulate another clone
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), firstSha + "\n");
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await writeFile(join(testDir, "file3.txt"), "content3");
		await add(testDir, ["file1.txt", "file2.txt", "file3.txt"]);

		await pull(testDir);

		// file2 should be deleted from the working tree
		await expect(access(join(testDir, "file2.txt"))).rejects.toThrow();

		// surviving files should be untouched
		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		const content3 = await readFile(join(testDir, "file3.txt"), "utf-8");
		expect(content1).toBe("content1");
		expect(content3).toBe("content3");
	});

	it("should preserve locally modified file deleted on remote", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await add(testDir, ["file1.txt", "file2.txt"]);
		const firstSha = await commit(testDir, "Initial commit");

		await push(testDir);

		// Remove file2 on the remote
		await rm(join(testDir, "file2.txt"));
		await addAll(testDir);
		await commit(testDir, "Remove file2");

		await push(testDir);

		// Reset local branch back to first commit to simulate another clone
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), firstSha + "\n");
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await add(testDir, ["file1.txt", "file2.txt"]);

		// Make uncommitted local edits to file2, which was deleted on the remote
		await writeFile(join(testDir, "file2.txt"), "local changes");

		await pull(testDir);

		// file2 should be preserved because it has uncommitted local edits
		const content2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		expect(content2).toBe("local changes");

		// file1 should be untouched
		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		expect(content1).toBe("content1");
	});

	it("should not overwrite unchanged files with local modifications", async () => {
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await add(testDir, ["file1.txt", "file2.txt"]);
		const firstSha = await commit(testDir, "Initial commit");

		await push(testDir);

		// Commit a change only to file1
		await writeFile(join(testDir, "file1.txt"), "modified1");
		await add(testDir, ["file1.txt"]);
		/*const secondSha =*/ await commit(testDir, "Second commit");
		await push(testDir);

		// Reset local branch back to first commit
		await writeFile(join(testDir, ".git", "refs", "heads", "main"), firstSha + "\n");
		await writeFile(join(testDir, "file1.txt"), "content1");
		await writeFile(join(testDir, "file2.txt"), "content2");
		await add(testDir, ["file1.txt", "file2.txt"]);

		// Make uncommitted change to file2 (which did not change in the pull)
		await writeFile(join(testDir, "file2.txt"), "local changes to file2");

		await pull(testDir);

		// file1 should be updated
		const content1 = await readFile(join(testDir, "file1.txt"), "utf-8");
		expect(content1).toBe("modified1");

		// file2 local changes should be preserved since it wasn't changed in the pull
		const content2 = await readFile(join(testDir, "file2.txt"), "utf-8");
		expect(content2).toBe("local changes to file2");
	});
});
