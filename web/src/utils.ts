import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import type { IndexEntry } from "./types/IndexEntry.ts";
import type { TreeEntry } from "./types/TreeEntry.ts";

export async function readObject(gitDir: string, sha: string): Promise<string> {
	const zlib = await import("node:zlib");

	const objectPath = join(gitDir, "objects", sha.slice(0, 2), sha.slice(2));
	const compressed = await readFile(objectPath);
	const decompressed = zlib.inflateSync(compressed).toString("utf-8");

	const nullIndex = decompressed.indexOf("\0");
	const header = decompressed.slice(0, nullIndex);
	const content = decompressed.slice(nullIndex + 1);

	return `${header}\n${content}`;
}

export async function getCurrentBranch(gitDir: string): Promise<string> {
	const headPath = join(gitDir, "HEAD");
	const headContent = (await readFile(headPath, "utf-8")).trim();

	const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
	if (match) {
		return match[1];
	}

	throw new Error("Not on a branch (detached HEAD)");
}

export async function getCurrentCommit(gitDir: string): Promise<string | null> {
	try {
		const branch = await getCurrentBranch(gitDir);
		const branchPath = join(gitDir, "refs", "heads", branch);

		if (!existsSync(branchPath)) {
			return null;
		}

		return (await readFile(branchPath, "utf-8")).trim();
	} catch {
		return null;
	}
}

export async function hashFile(filePath: string): Promise<string> {
	const crypto = await import("node:crypto");
	const content = await readFile(filePath);
	const hash = crypto.createHash("sha1");
	hash.update(content);
	return hash.digest("hex");
}

export async function getIndex(indexPath: string): Promise<Map<string, IndexEntry>> {
	const index = new Map<string, IndexEntry>();

	if (!existsSync(indexPath)) {
		return index;
	}

	try {
		const content = await readFile(indexPath, "utf-8");
		const lines = content.trim().split("\n");

		for (const line of lines) {
			if (!line) continue;
			const parts = line.split(" ");
			if (parts.length >= 2) {
				const [path, sha, mode = "100644"] = parts;
				index.set(path, { path, sha, mode });
			}
		}
	} catch {
		// If we can't read the index, return empty
	}

	return index;
}

export async function writeIndex(indexPath: string, index: Map<string, IndexEntry>): Promise<void> {
	const lines: string[] = [];

	for (const entry of index.values()) {
		lines.push(`${entry.path} ${entry.sha} ${entry.mode}`);
	}

	await writeFile(indexPath, lines.join("\n") + "\n", "utf-8");
}

export async function hashObject(
	gitDir: string,
	content: string,
	type: "blob" | "tree" | "commit",
): Promise<string> {
	const crypto = await import("node:crypto");
	const zlib = await import("node:zlib");

	const header = `${type} ${content.length}\0${content}`;
	const hash = crypto.createHash("sha1");
	hash.update(header);
	const sha = hash.digest("hex");

	const objectDir = join(gitDir, "objects", sha.slice(0, 2));
	const objectPath = join(objectDir, sha.slice(2));

	if (!existsSync(objectPath)) {
		await mkdir(objectDir, { recursive: true });
		const compressed = zlib.deflateSync(Buffer.from(header));
		await writeFile(objectPath, compressed);
	}

	return sha;
}

export function extractTreeFromCommit(commitData: string): string {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith("tree ")) {
			return line.slice(5);
		}
	}
	throw new Error("Invalid commit object");
}

export function parseTreeEntries(treeData: string): TreeEntry[] {
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

export function extractContentFromBlob(blobData: string): string {
	const lines = blobData.split("\n");
	const header = lines[0];

	if (!header.startsWith("blob ")) {
		throw new Error("Invalid blob object");
	}

	const contentStart = header.length + 1;
	return blobData.slice(contentStart);
}

export async function updateBranch(
	gitDir: string,
	branchName: string,
	commitSha: string,
): Promise<void> {
	const branchPath = join(gitDir, "refs", "heads", branchName);
	await mkdir(dirname(branchPath), { recursive: true });
	await writeFile(branchPath, commitSha + "\n", "utf-8");
}
