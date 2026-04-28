import { existsSync } from "node:fs";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import { status } from "./status.ts";
import type { IndexEntry } from "./types/IndexEntry.ts";
import type { TreeEntry } from "./types/TreeEntry.ts";
import {
	extractContentFromBlob,
	extractTreeFromCommit,
	getCurrentCommit,
	getIndex,
	hashObject,
	hashObjectBuffer,
	parseTreeEntries,
	readObject,
	updateIndex,
} from "./utils.ts";

export async function stash(path: string, message: string = "WIP"): Promise<string> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentStatus = await status(path);

	const headCommitSha = await getCurrentCommit(gitDir);
	if (!headCommitSha) {
		throw new Error("HEAD not found");
	}

	const indexPath = join(gitDir, "index");
	let index = await getIndex(indexPath);

	const headCommitData = await readObject(gitDir, headCommitSha);
	const headTreeSha = extractTreeFromCommit(headCommitData);
	const headTreeEntries = new Map<string, string>();

	const headEntries = parseTreeEntries(await readObject(gitDir, headTreeSha));
	for (const entry of headEntries) {
		headTreeEntries.set(entry.path, entry.sha);
	}

	let hasStagedChanges = false;

	for (const [filePath, entry] of index) {
		const headSha = headTreeEntries.get(filePath);
		if (headSha !== entry.sha) {
			hasStagedChanges = true;
			break;
		}
	}

	if (
		!hasStagedChanges &&
		currentStatus.modified.length === 0 &&
		currentStatus.untracked.length === 0 &&
		currentStatus.deleted.length === 0
	) {
		throw new Error("Nothing to stash");
	}

	for (const file of currentStatus.modified) {
		await stageFile(path, gitDir, file, index);
	}

	for (const file of currentStatus.untracked) {
		await stageFile(path, gitDir, file, index);
	}

	for (const file of currentStatus.deleted) {
		index.delete(file);
	}

	const treeSha = await createTree(gitDir, index);

	const stashCommitSha = await createCommit(gitDir, treeSha, message, headCommitSha);

	const stashRefPath = join(gitDir, "refs", "stash");
	await mkdir(dirname(stashRefPath), { recursive: true });
	await writeFile(stashRefPath, `${stashCommitSha}\n`, "utf-8");

	await resetHard(path, gitDir, headCommitSha);

	return stashCommitSha;
}

async function stageFile(
	repoPath: string,
	gitDir: string,
	filePath: string,
	index: Map<string, IndexEntry>,
): Promise<void> {
	const fullPath = join(repoPath, filePath);
	const { readFile, stat } = await import("node:fs/promises");

	const content = await readFile(fullPath, "utf-8");
	const hash = await hashObject(gitDir, content, "blob");
	const stats = await stat(fullPath);

	index.set(filePath, {
		path: filePath,
		sha: hash,
		mode: "100644",
		size: stats.size,
		ctimeSeconds: Math.floor(stats.ctimeMs / 1000),
		ctimeNanos: (stats.ctimeMs % 1000) * 1000000,
		mtimeSeconds: Math.floor(stats.mtimeMs / 1000),
		mtimeNanos: (stats.mtimeMs % 1000) * 1000000,
		dev: stats.dev,
		ino: stats.ino,
		uid: stats.uid,
		gid: stats.gid,
	});
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

	treeEntries.sort((a, b) => a.path.localeCompare(b.path));

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

async function resetHard(path: string, gitDir: string, commitSha: string): Promise<void> {
	const commitData = await readObject(gitDir, commitSha);
	const treeSha = extractTreeFromCommit(commitData);

	const { readdir } = await import("node:fs/promises");
	const entries = await readdir(path, { withFileTypes: true });

	for (const entry of entries) {
		if (entry.name === ".git") continue;

		const fullPath = join(path, entry.name);
		try {
			await rm(fullPath, { recursive: true, force: true });
		} catch {
			// Ignore errors
		}
	}

	await restoreTree(path, gitDir, treeSha, "");

	await updateIndex(gitDir, path, treeSha);
}

async function restoreTree(
	path: string,
	gitDir: string,
	treeSha: string,
	prefix: string,
): Promise<void> {
	const treeData = await readObject(gitDir, treeSha);
	const entries = parseTreeEntries(treeData);

	for (const entry of entries) {
		const entryPath = prefix === "" ? entry.path : `${prefix}/${entry.path}`;

		if (entry.type === "blob") {
			const blobData = await readObject(gitDir, entry.sha);
			const content = extractContentFromBlob(blobData);
			const fullPath = join(path, entryPath);
			const { mkdir } = await import("node:fs/promises");
			await mkdir(dirname(fullPath), { recursive: true });
			await writeFile(fullPath, content, "utf-8");
		} else if (entry.type === "tree") {
			await restoreTree(path, gitDir, entry.sha, entryPath);
		}
	}
}

export async function unstash(path: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const stashRefPath = join(gitDir, "refs", "stash");

	if (!existsSync(stashRefPath)) {
		throw new Error("No stash found");
	}

	const stashCommitSha = (await readFile(stashRefPath, "utf-8")).trim();

	const stashCommitData = await readObject(gitDir, stashCommitSha);
	const stashTreeSha = extractTreeFromCommit(stashCommitData);

	await restoreTree(path, gitDir, stashTreeSha, "");
}
