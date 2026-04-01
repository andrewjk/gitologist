import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import { status } from "./status.js";
import { getCurrentBranch, getCurrentCommit, getIndex } from "./utils.js";

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

async function updateBranch(gitDir: string, commitSha: string): Promise<void> {
	const branch = await getCurrentBranch(gitDir);
	const branchPath = join(gitDir, "refs", "heads", branch);

	await mkdir(dirname(branchPath), { recursive: true });
	await writeFile(branchPath, commitSha + "\n", "utf-8");
}

async function createTree(gitDir: string, index: Map<string, IndexEntry>): Promise<string> {
	return createTreeRecursive(gitDir, index, "");
}

async function createTreeRecursive(
	gitDir: string,
	index: Map<string, IndexEntry>,
	prefix: string,
): Promise<string> {
	const paths = Array.from(index.keys())
		.filter((path) => {
			if (prefix === "") {
				return !path.includes("/");
			}
			if (path.startsWith(prefix + "/")) {
				const remaining = path.slice(prefix.length + 1);
				return !remaining.includes("/");
			}
			return false;
		})
		.sort();

	const treeEntries: TreeEntry[] = [];

	for (const path of paths) {
		const entry = index.get(path)!;
		const content = await readFile(join(gitDir, "..", path), "utf-8");
		const blobSha = await hashObject(gitDir, content, "blob");
		treeEntries.push({
			path: prefix === "" ? path : path.slice(prefix.length + 1),
			sha: blobSha,
			mode: entry.mode,
			type: "blob",
		});
	}

	const subdirs = new Map<string, string[]>();
	for (const path of index.keys()) {
		if (path.includes("/")) {
			const parts = path.split("/");
			if (prefix === "") {
				const dir = parts[0];
				if (!subdirs.has(dir)) {
					subdirs.set(dir, []);
				}
				subdirs.get(dir)!.push(path);
			} else if (path.startsWith(prefix + "/")) {
				const remaining = path.slice(prefix.length + 1);
				if (remaining.includes("/")) {
					const parts2 = remaining.split("/");
					const dir = parts2[0];
					if (!subdirs.has(dir)) {
						subdirs.set(dir, []);
					}
					subdirs.get(dir)!.push(path);
				}
			}
		}
	}

	for (const [dir] of subdirs) {
		const dirSha = await createTreeRecursive(
			gitDir,
			index,
			prefix === "" ? dir : `${prefix}/${dir}`,
		);
		treeEntries.push({
			path: dir,
			sha: dirSha,
			mode: "040000",
			type: "tree",
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
