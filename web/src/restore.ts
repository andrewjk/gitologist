import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { status } from "./status.js";

interface TreeEntry {
	path: string;
	sha: string;
	mode: string;
	type: "blob" | "tree";
}

export async function restore(path: string, files: string[]): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	for (const file of files) {
		const filePath = join(path, file);

		if (!existsSync(filePath)) {
			throw new Error(`File not found: ${file}`);
		}
	}

	const branchPath = join(gitDir, "refs", "heads", "master");
	const commitSha = (await readFile(branchPath, "utf-8")).trim();

	const commitData = await readObject(gitDir, commitSha);
	const treeSha = extractTreeFromCommit(commitData);

	for (const file of files) {
		const blobSha = await findBlobInTree(gitDir, treeSha, file);
		if (blobSha === null) {
			throw new Error(`File not in commit: ${file}`);
		}

		const blobData = await readObject(gitDir, blobSha);
		const content = extractContentFromBlob(blobData);
		const filePath = join(path, file);
		await writeFile(filePath, content, "utf-8");
	}
}

export async function restoreAll(path: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentStatus = await status(path);
	const filesToRestore = [...currentStatus.modified];

	if (filesToRestore.length === 0) {
		return;
	}

	await restore(path, filesToRestore);
}

async function readObject(gitDir: string, sha: string): Promise<string> {
	const zlib = await import("node:zlib");

	const objectPath = join(gitDir, "objects", sha.slice(0, 2), sha.slice(2));
	const compressed = await readFile(objectPath);
	const decompressed = zlib.inflateSync(compressed).toString("utf-8");

	const nullIndex = decompressed.indexOf("\0");
	const header = decompressed.slice(0, nullIndex);
	const content = decompressed.slice(nullIndex + 1);

	return `${header}\n${content}`;
}

function extractTreeFromCommit(commitData: string): string {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith("tree ")) {
			return line.slice(5);
		}
	}
	throw new Error("Invalid commit object");
}

function extractContentFromBlob(blobData: string): string {
	const lines = blobData.split("\n");
	const header = lines[0];

	if (!header.startsWith("blob ")) {
		throw new Error("Invalid blob object");
	}

	const contentStart = header.length + 1;
	return blobData.slice(contentStart);
}

async function findBlobInTree(
	gitDir: string,
	treeSha: string,
	filePath: string,
): Promise<string | null> {
	const parts = filePath.split("/");
	const [name, ...rest] = parts;

	const treeData = await readObject(gitDir, treeSha);
	const entries = parseTreeEntries(treeData);

	for (const entry of entries) {
		if (entry.path === name) {
			if (entry.type === "blob") {
				if (rest.length === 0) {
					return entry.sha;
				}
				return null;
			}
			if (entry.type === "tree") {
				if (rest.length > 0) {
					return findBlobInTree(gitDir, entry.sha, rest.join("/"));
				}
				return null;
			}
		}
	}

	return null;
}

function parseTreeEntries(treeData: string): TreeEntry[] {
	const entries: TreeEntry[] = [];
	let contentStart = treeData.indexOf("\n") + 1;

	while (contentStart < treeData.length) {
		const firstSpaceIndex = treeData.indexOf(" ", contentStart);
		const secondSpaceIndex = treeData.indexOf(" ", firstSpaceIndex + 1);
		const tabIndex = treeData.indexOf("\t", secondSpaceIndex + 1);
		const nullIndex = treeData.indexOf("\0", tabIndex);

		if (firstSpaceIndex === -1 || secondSpaceIndex === -1 || tabIndex === -1 || nullIndex === -1) {
			break;
		}

		const mode = treeData.slice(contentStart, firstSpaceIndex);
		const type = treeData.slice(firstSpaceIndex + 1, secondSpaceIndex);
		const sha = treeData.slice(secondSpaceIndex + 1, tabIndex);
		const path = treeData.slice(tabIndex + 1, nullIndex);

		if (type !== "blob" && type !== "tree") {
			break;
		}

		entries.push({
			path,
			sha,
			mode,
			type: type as "blob" | "tree",
		});

		contentStart = nullIndex + 1;
	}

	return entries;
}
