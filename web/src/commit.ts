import { existsSync } from "node:fs";
import { join } from "node:path";

import { status } from "./status.ts";
import type { IndexEntry } from "./types/IndexEntry.ts";
import type { TreeEntry } from "./types/TreeEntry.ts";
import {
	getCurrentBranch,
	getCurrentCommit,
	getIndex,
	hashObject,
	hashObjectBuffer,
	updateBranch,
} from "./utils.ts";

export async function commit(path: string, message: string): Promise<string> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentStatus = await status(path);

	if (
		currentStatus.staged.length === 0 &&
		currentStatus.modified.length === 0 &&
		currentStatus.untracked.length === 0 &&
		currentStatus.deleted.length === 0
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

	const branchName = await getCurrentBranch(gitDir);
	await updateBranch(gitDir, branchName, commitSha);

	return commitSha;
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
		// Use the SHA from the index entry directly - it was computed during add
		treeEntries.push({
			path: prefix === "" ? path : path.slice(prefix.length + 1),
			sha: entry.sha,
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

	// Sort entries by path (Git requires this)
	treeEntries.sort((a, b) => a.path.localeCompare(b.path));

	// Build tree content as binary buffer
	// Format: <mode> <name>\0<20-byte SHA> for each entry
	const entryBuffers: Buffer[] = [];
	for (const entry of treeEntries) {
		const mode = entry.mode;
		const name = entry.path;
		const shaBuffer = Buffer.from(entry.sha, "hex");
		const entryStr = `${mode} ${name}\0`;
		entryBuffers.push(Buffer.from(entryStr, "utf-8"));
		entryBuffers.push(shaBuffer);
	}

	const treeContent = Buffer.concat(entryBuffers);

	// Use a special version of hashObject that accepts Buffer
	return hashObjectBuffer(gitDir, treeContent, "tree");
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
