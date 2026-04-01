import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import { status } from "./status.js";

interface IndexEntry {
	path: string;
	sha: string;
	mode: string;
}

interface TreeEntry {
	path: string;
	sha: string;
	mode: string;
	type: "blob" | "tree";
}

export async function commit(path: string, message: string): Promise<string> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentStatus = await status(path);

	if (
		currentStatus.staged.length === 0 &&
		currentStatus.modified.length === 0 &&
		currentStatus.untracked.length === 0
	) {
		throw new Error("Nothing to commit");
	}

	const indexPath = join(gitDir, "index");
	const index = await getIndex(indexPath);

	if (index.size === 0) {
		throw new Error("No files staged");
	}

	const treeSha = await createTree(gitDir, index);
	const parentSha = await getCurrentCommit(gitDir);
	const commitSha = await createCommit(gitDir, treeSha, message, parentSha);

	await updateBranch(gitDir, commitSha);

	return commitSha;
}

async function getIndex(indexPath: string): Promise<Map<string, IndexEntry>> {
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

async function getHeadRef(gitDir: string): Promise<string> {
	const headPath = join(gitDir, "HEAD");
	const headContent = (await readFile(headPath, "utf-8")).trim();

	const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
	if (match) {
		return match[1];
	}

	throw new Error("Not on a branch (detached HEAD)");
}

async function getCurrentCommit(gitDir: string): Promise<string | null> {
	try {
		const branch = await getHeadRef(gitDir);
		const branchPath = join(gitDir, "refs", "heads", branch);

		if (!existsSync(branchPath)) {
			return null;
		}

		return (await readFile(branchPath, "utf-8")).trim();
	} catch {
		return null;
	}
}

async function updateBranch(gitDir: string, commitSha: string): Promise<void> {
	const branch = await getHeadRef(gitDir);
	const branchPath = join(gitDir, "refs", "heads", branch);

	await mkdir(dirname(branchPath), { recursive: true });
	await writeFile(branchPath, commitSha + "\n", "utf-8");
}

async function createTree(gitDir: string, index: Map<string, IndexEntry>): Promise<string> {
	const paths = Array.from(index.keys()).sort();

	const treeEntries: TreeEntry[] = [];

	for (const path of paths) {
		const entry = index.get(path)!;
		treeEntries.push({
			path: entry.path,
			sha: entry.sha,
			mode: entry.mode,
			type: "blob",
		});
	}

	let treeContent = "";
	for (const entry of treeEntries) {
		treeContent += `${entry.mode} ${entry.type} ${entry.sha}\t${entry.path}\0`;
	}

	return hashObject(gitDir, treeContent, "tree");
}

async function createCommit(
	gitDir: string,
	treeSha: string,
	message: string,
	parentSha: string | null,
): Promise<string> {
	const now = new Date();
	const timestamp = Math.floor(now.getTime() / 1000);
	const offset = now.getTimezoneOffset() * -60;
	const hours = Math.floor(Math.abs(offset) / 60)
		.toString()
		.padStart(2, "0");
	const minutes = (Math.abs(offset) % 60).toString().padStart(2, "0");
	const sign = offset >= 0 ? "+" : "-";

	const author = `User <user@example.com> ${timestamp} ${sign}${hours}${minutes}`;

	let commitContent = `tree ${treeSha}\n`;
	if (parentSha) {
		commitContent += `parent ${parentSha}\n`;
	}
	commitContent += `author ${author}\n`;
	commitContent += `committer ${author}\n`;
	commitContent += `\n${message}\n`;

	return hashObject(gitDir, commitContent, "commit");
}

async function hashObject(
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
