import { existsSync } from "node:fs";
import { mkdir, readFile, rm, unlink, writeFile } from "node:fs/promises";
import { dirname, join, relative } from "node:path";

import { IgnoreParser } from "./IgnoreParser.ts";
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

	const gitignore = new IgnoreParser();
	await gitignore.loadGitignore(path);

	const targetEntries = await flattenTree(gitDir, treeSha);

	await resetHardRecursive(path, path, gitDir, gitignore, targetEntries);

	// Create any remaining target files
	for (const [filePath, sha] of targetEntries) {
		const blobData = await readObject(gitDir, sha);
		const content = extractContentFromBlob(blobData);
		const fullPath = join(path, filePath);
		const { mkdir: mkdirAsync } = await import("node:fs/promises");
		await mkdirAsync(dirname(fullPath), { recursive: true });
		await writeFile(fullPath, content, "utf-8");
	}

	await updateIndex(gitDir, path, treeSha);
}

async function resetHardRecursive(
	repoPath: string,
	currentDir: string,
	gitDir: string,
	gitignore: IgnoreParser,
	targetEntries: Map<string, string>,
): Promise<void> {
	const { readdir } = await import("node:fs/promises");
	const entries = await readdir(currentDir, { withFileTypes: true });

	for (const entry of entries) {
		if (entry.name === ".git") continue;

		const fullPath = join(currentDir, entry.name);
		const relPath = relative(repoPath, fullPath);

		if (gitignore.isIgnored(relPath, entry.isDirectory())) {
			continue;
		}

		if (entry.isDirectory()) {
			// Check if any target file is under this directory
			let hasTargetFiles = false;
			for (const targetPath of targetEntries.keys()) {
				if (targetPath === relPath || targetPath.startsWith(`${relPath}/`)) {
					hasTargetFiles = true;
					break;
				}
			}

			if (!hasTargetFiles) {
				try {
					await rm(fullPath, { recursive: true, force: true });
				} catch {
					// Ignore errors
				}
				continue;
			}

			await resetHardRecursive(repoPath, fullPath, gitDir, gitignore, targetEntries);
		} else {
			const targetSha = targetEntries.get(relPath);
			if (targetSha) {
				const currentContent = await readFile(fullPath, "utf-8");
				const currentHash = await hashObject(gitDir, currentContent, "blob");

				if (currentHash !== targetSha) {
					const blobData = await readObject(gitDir, targetSha);
					const content = extractContentFromBlob(blobData);
					await writeFile(fullPath, content, "utf-8");
				}

				targetEntries.delete(relPath);
			} else {
				try {
					await rm(fullPath, { recursive: true, force: true });
				} catch {
					// Ignore errors
				}
			}
		}
	}
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

	const mergeBaseSha = extractParentFromCommit(stashCommitData);

	if (!mergeBaseSha) {
		await restoreTree(path, gitDir, stashTreeSha, "");
		return;
	}

	const mergeBaseTreeData = await readObject(gitDir, mergeBaseSha);
	const mergeBaseTreeSha = extractTreeFromCommit(mergeBaseTreeData);
	const mergeBaseEntries = await flattenTree(gitDir, mergeBaseTreeSha);

	const currentHeadSha = await getCurrentCommit(gitDir);

	const currentHeadData = currentHeadSha ? await readObject(gitDir, currentHeadSha) : null;
	const currentHeadTreeSha = currentHeadData ? extractTreeFromCommit(currentHeadData) : null;
	const currentHeadEntries = currentHeadTreeSha
		? await flattenTree(gitDir, currentHeadTreeSha)
		: new Map<string, string>();

	const stashEntries = await flattenTree(gitDir, stashTreeSha);

	if (currentHeadSha === mergeBaseSha) {
		await restoreTree(path, gitDir, stashTreeSha, "");

		// Delete files that exist in HEAD but not in stash
		for (const [filePath] of currentHeadEntries) {
			if (stashEntries.has(filePath)) continue;
			const fullPath = join(path, filePath);
			try {
				await unlink(fullPath);
			} catch {
				// Ignore errors
			}
		}
		return;
	}

	const mergedEntries = new Map<string, string>();

	for (const [filePath, sha] of stashEntries) {
		const baseSha = mergeBaseEntries.get(filePath);
		const currentSha = currentHeadEntries.get(filePath);

		if (!currentSha || currentSha === baseSha) {
			mergedEntries.set(filePath, sha);
			continue;
		}

		if (sha === baseSha) {
			mergedEntries.set(filePath, currentSha);
			continue;
		}

		const baseContent = baseSha ? await readBlobContent(gitDir, baseSha) : "";
		const stashContent = await readBlobContent(gitDir, sha);
		const currentContent = await readBlobContent(gitDir, currentSha);

		const merged = threeWayMerge(baseContent, stashContent, currentContent);
		const mergedSha = await hashObject(gitDir, merged, "blob");
		mergedEntries.set(filePath, mergedSha);
	}

	for (const [filePath, sha] of currentHeadEntries) {
		if (mergedEntries.has(filePath)) continue;

		const baseSha = mergeBaseEntries.get(filePath);
		if (baseSha && baseSha !== sha) {
			mergedEntries.set(filePath, sha);
		}
	}

	for (const [filePath, sha] of mergedEntries) {
		const content = await readBlobContent(gitDir, sha);
		const fullPath = join(path, filePath);
		const { mkdir: mkdirAsync } = await import("node:fs/promises");
		await mkdirAsync(dirname(fullPath), { recursive: true });
		await writeFile(fullPath, content, "utf-8");
	}

	// Delete files that were deleted in stash and not modified in current HEAD
	for (const [filePath, baseSha] of mergeBaseEntries) {
		if (stashEntries.has(filePath)) continue;
		if (mergedEntries.has(filePath)) continue;

		const currentSha = currentHeadEntries.get(filePath);
		if (!currentSha || currentSha === baseSha) {
			const fullPath = join(path, filePath);
			try {
				await unlink(fullPath);
			} catch {
				// Ignore errors
			}
		}
	}
}

function extractParentFromCommit(commitData: string): string | null {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith("parent ")) {
			return line.slice(7);
		}
		if (line === "") {
			break;
		}
	}
	return null;
}

async function flattenTree(
	gitDir: string,
	treeSha: string,
	prefix: string = "",
): Promise<Map<string, string>> {
	const entries = new Map<string, string>();
	const treeData = await readObject(gitDir, treeSha);
	const treeEntries = parseTreeEntries(treeData);

	for (const entry of treeEntries) {
		const entryPath = prefix === "" ? entry.path : `${prefix}/${entry.path}`;

		if (entry.type === "blob") {
			entries.set(entryPath, entry.sha);
		} else if (entry.type === "tree") {
			const subEntries = await flattenTree(gitDir, entry.sha, entryPath);
			for (const [subPath, subSha] of subEntries) {
				entries.set(subPath, subSha);
			}
		}
	}

	return entries;
}

async function readBlobContent(gitDir: string, sha: string): Promise<string> {
	const blobData = await readObject(gitDir, sha);
	return extractContentFromBlob(blobData);
}

function threeWayMerge(base: string, theirs: string, ours: string): string {
	const baseLines = base.split("\n");
	const theirsLines = theirs.split("\n");
	const oursLines = ours.split("\n");

	if (base === ours) return theirs;
	if (base === theirs) return ours;

	const baseToTheirs = diffLines(baseLines, theirsLines);
	const baseToOurs = diffLines(baseLines, oursLines);

	const result: string[] = [];
	let bi = 0;
	let ti = 0;
	let oi = 0;

	while (bi < baseLines.length) {
		const theirsChange = baseToTheirs.get(bi);
		const oursChange = baseToOurs.get(bi);

		if (theirsChange && oursChange) {
			if (theirsChange.type === "replace" && oursChange.type === "replace") {
				const theirsContent = theirsChange.lines;
				const oursContent = oursChange.lines;

				if (arraysEqual(theirsContent, oursContent)) {
					result.push(...theirsContent);
				} else {
					result.push(
						"<<<<<<< Updated upstream",
						...oursContent,
						"=======",
						...theirsContent,
						">>>>>>> Stashed changes",
					);
				}
			} else if (theirsChange.type === "delete" && oursChange.type === "delete") {
				// Both deleted - skip
			} else if (theirsChange.type === "insert" && oursChange.type === "insert") {
				if (arraysEqual(theirsChange.lines, oursChange.lines)) {
					result.push(...theirsChange.lines);
				} else {
					result.push(...oursChange.lines, ...theirsChange.lines);
				}
			} else {
				result.push(
					"<<<<<<< Updated upstream",
					...(oursChange.lines || []),
					"=======",
					...(theirsChange.lines || []),
					">>>>>>> Stashed changes",
				);
			}
		} else if (theirsChange) {
			result.push(...(theirsChange.lines || []));
		} else if (oursChange) {
			result.push(...(oursChange.lines || []));
		} else {
			result.push(baseLines[bi]);
		}

		bi++;
		ti += (theirsChange?.skip || 0) + 1;
		oi += (oursChange?.skip || 0) + 1;
	}

	while (ti < theirsLines.length) {
		result.push(theirsLines[ti]);
		ti++;
	}
	while (oi < oursLines.length) {
		result.push(oursLines[oi]);
		oi++;
	}

	return result.join("\n");
}

interface DiffChange {
	type: "insert" | "delete" | "replace";
	lines: string[];
	skip: number;
}

function diffLines(base: string[], modified: string[]): Map<number, DiffChange> {
	const changes = new Map<number, DiffChange>();
	const lcs = longestCommonSubsequence(base, modified);

	let bi = 0;
	let mi = 0;
	let lcsIdx = 0;

	while (bi < base.length || mi < modified.length) {
		if (lcsIdx < lcs.length && bi < base.length && mi < modified.length) {
			if (base[bi] === lcs[lcsIdx] && modified[mi] === lcs[lcsIdx]) {
				bi++;
				mi++;
				lcsIdx++;
				continue;
			}
		}

		let baseCount = 0;
		const startBi = bi;
		while (bi < base.length && (lcsIdx >= lcs.length || base[bi] !== lcs[lcsIdx])) {
			bi++;
			baseCount++;
		}

		let modCount = 0;
		const startMi = mi;
		while (mi < modified.length && (lcsIdx >= lcs.length || modified[mi] !== lcs[lcsIdx])) {
			mi++;
			modCount++;
		}

		if (baseCount > 0 || modCount > 0) {
			const modLines = modified.slice(startMi, mi);
			if (baseCount === 0 && modCount > 0) {
				changes.set(startBi, {
					type: "insert",
					lines: modLines,
					skip: 0,
				});
			} else if (baseCount > 0 && modCount === 0) {
				changes.set(startBi, {
					type: "delete",
					lines: [],
					skip: baseCount - 1,
				});
			} else {
				changes.set(startBi, {
					type: "replace",
					lines: modLines,
					skip: baseCount - 1,
				});
			}
		}

		if (lcsIdx < lcs.length && bi < base.length && base[bi] === lcs[lcsIdx]) {
			bi++;
			mi++;
			lcsIdx++;
		}
	}

	return changes;
}

function longestCommonSubsequence(a: string[], b: string[]): string[] {
	const m = a.length;
	const n = b.length;
	const dp: number[][] = Array.from({ length: m + 1 }, () =>
		Array.from<number>({ length: n + 1 }).fill(0),
	);

	for (let i = 1; i <= m; i++) {
		for (let j = 1; j <= n; j++) {
			if (a[i - 1] === b[j - 1]) {
				dp[i][j] = dp[i - 1][j - 1] + 1;
			} else {
				dp[i][j] = Math.max(dp[i - 1][j], dp[i][j - 1]);
			}
		}
	}

	const result: string[] = [];
	let i = m;
	let j = n;
	while (i > 0 && j > 0) {
		if (a[i - 1] === b[j - 1]) {
			result.unshift(a[i - 1]);
			i--;
			j--;
		} else if (dp[i - 1][j] > dp[i][j - 1]) {
			i--;
		} else {
			j--;
		}
	}

	return result;
}

function arraysEqual(a: string[], b: string[]): boolean {
	if (a.length !== b.length) return false;
	for (let i = 0; i < a.length; i++) {
		if (a[i] !== b[i]) return false;
	}
	return true;
}
