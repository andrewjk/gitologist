import { createHash } from "node:crypto";
import { mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { describe, it, expect, beforeEach, afterEach } from "vite-plus/test";

import { createPackfile } from "../src/packfile";
import type { PackObject } from "../src/packfile";
import { readObjectData, readObject, hashObject } from "../src/utils";

function computeSha(type: string, content: Buffer): string {
	const header = `${type} ${content.length}\0`;
	return createHash("sha1").update(header).update(content).digest("hex");
}

describe("utils", () => {
	let testDir: string;
	let gitDir: string;

	beforeEach(async () => {
		testDir = join(
			tmpdir(),
			`gitologist-test-${Date.now()}-${Math.random().toString(36).slice(2)}`,
		);
		gitDir = join(testDir, ".git");
		await mkdir(gitDir, { recursive: true });
		await mkdir(join(gitDir, "objects"), { recursive: true });
	});

	afterEach(async () => {
		await rm(testDir, { recursive: true, force: true });
	});

	describe("readObjectData", () => {
		it("should read loose object", async () => {
			const content = "hello world";
			const sha = await hashObject(gitDir, content, "blob");

			const data = await readObjectData(gitDir, sha, new Map());
			const header = data.slice(0, data.indexOf(0)).toString("utf-8");
			const body = data.slice(data.indexOf(0) + 1).toString("utf-8");

			expect(header).toBe(`blob ${content.length}`);
			expect(body).toBe(content);
		});

		it("should read object from packfile when loose object is missing", async () => {
			const blobContent = Buffer.from("packfile content");
			const sha = computeSha("blob", blobContent);
			const objects: PackObject[] = [
				{
					type: "blob",
					sha,
					content: blobContent,
				},
			];

			const packfile = createPackfile(objects);
			const packDir = join(gitDir, "objects", "pack");
			await mkdir(packDir, { recursive: true });
			await writeFile(join(packDir, "test.pack"), packfile);

			const data = await readObjectData(gitDir, sha, new Map());
			const header = data.slice(0, data.indexOf(0)).toString("utf-8");
			const body = data.slice(data.indexOf(0) + 1);

			expect(header).toBe(`blob ${blobContent.length}`);
			expect(body).toEqual(blobContent);
		});

		it("should throw error when object not found in loose objects or packfiles", async () => {
			await expect(
				readObjectData(gitDir, "0000000000000000000000000000000000000000", new Map()),
			).rejects.toThrow("Object not found");
		});
	});

	describe("readObject", () => {
		it("should read object from packfile with correct formatting", async () => {
			const commitContent = Buffer.from(
				"tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n",
			);
			const sha = computeSha("commit", commitContent);
			const objects: PackObject[] = [
				{
					type: "commit",
					sha,
					content: commitContent,
				},
			];

			const packfile = createPackfile(objects);
			const packDir = join(gitDir, "objects", "pack");
			await mkdir(packDir, { recursive: true });
			await writeFile(join(packDir, "commits.pack"), packfile);

			const data = await readObject(gitDir, sha, new Map());
			expect(data).toContain("commit");
			expect(data).toContain("Initial commit");
		});
	});
});
