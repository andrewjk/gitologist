import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

import type { LogEntry } from "./types/LogEntry.ts";
import type { LogOptions } from "./types/LogOptions.ts";
import { getCurrentBranch, parseTreeEntries, readObject, type PackfileCache } from "./utils.ts";

export async function log(path: string, options?: LogOptions): Promise<LogEntry[]> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const branchName = options?.branch || (await getCurrentBranch(gitDir));
	const branchPath = join(gitDir, "refs", "heads", branchName);

	if (!existsSync(branchPath)) {
		if (options?.branch) {
			throw new Error(`Branch '${branchName}' not found`);
		}
		return [];
	}

	const commitSha = (await readFile(branchPath, "utf-8")).trim();

	const entries: LogEntry[] = [];
	let currentSha: string | null = commitSha;

	const limit = options?.limit || Number.POSITIVE_INFINITY;

	const cache = new Map();

	if (options?.file) {
		const treeCache = new Map<string, string | null>();

		while (currentSha !== null) {
			const entry = await parseCommitEntry(gitDir, currentSha, cache);
			const currentBlobSha = await getFileBlobSha(
				gitDir,
				entry.tree,
				options.file,
				cache,
				treeCache,
			);

			if (!entry.parent) {
				if (currentBlobSha !== null) {
					entries.push(entry);
				}
			} else {
				const parentEntry = await parseCommitEntry(gitDir, entry.parent, cache);
				const parentBlobSha = await getFileBlobSha(
					gitDir,
					parentEntry.tree,
					options.file,
					cache,
					treeCache,
				);
				if (currentBlobSha !== parentBlobSha) {
					entries.push(entry);
				}
			}

			if (entries.length >= limit) break;
			currentSha = entry.parent;
		}

		return entries;
	}

	while (currentSha !== null && entries.length < limit) {
		const entry = await parseCommitEntry(gitDir, currentSha, cache);
		entries.push(entry);
		currentSha = entry.parent;
	}

	return entries;
}

async function parseCommitEntry(
	gitDir: string,
	commitSha: string,
	cache: PackfileCache,
): Promise<LogEntry> {
	const commitData = await readObject(gitDir, commitSha, cache);

	const tree = extractField(commitData, "tree") || "";
	const parent = extractField(commitData, "parent") || null;
	const author = extractField(commitData, "author") || "";
	const committer = extractField(commitData, "committer") || "";
	const message = extractMessage(commitData);
	const timestamp = extractTimestamp(author || committer);

	return {
		sha: commitSha,
		abbreviatedSha: commitSha.slice(0, 7),
		tree,
		parent,
		author: formatAuthor(author || committer),
		committer: formatAuthor(committer || author),
		date: timestamp,
		message,
	};
}

function extractField(commitData: string, fieldName: string): string | null {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith(`${fieldName} `)) {
			return line.slice(fieldName.length + 1);
		}
	}
	return null;
}

function extractMessage(commitData: string): string {
	const emptyLineIndex = commitData.indexOf("\n\n");

	if (emptyLineIndex === -1) {
		return "";
	}

	return commitData.slice(emptyLineIndex + 2).trimRight();
}

function extractTimestamp(author: string): Date {
	const match = author.match(/(\d+) ([+-]\d{4})$/);
	if (!match) {
		return new Date();
	}

	const timestamp = parseInt(match[1], 10);
	return new Date(timestamp * 1000);
}

function formatAuthor(author: string): string {
	const match = author.match(/^(.+?) (<.+>)\s+\d+/);
	if (match) {
		return match[1].trim();
	}

	return author.trim();
}

async function getFileBlobSha(
	gitDir: string,
	treeSha: string,
	filePath: string,
	cache: PackfileCache,
	treeCache: Map<string, string | null>,
): Promise<string | null> {
	if (treeCache.has(treeSha)) {
		return treeCache.get(treeSha)!;
	}

	const treeData = await readObject(gitDir, treeSha, cache);
	const entries = parseTreeEntries(treeData);

	const parts = filePath.split("/");
	let current = entries.find((e) => e.path === parts[0]);
	if (!current) {
		treeCache.set(treeSha, null);
		return null;
	}

	for (let i = 1; i < parts.length; i++) {
		if (current.type !== "tree") {
			treeCache.set(treeSha, null);
			return null;
		}
		const subTreeData = await readObject(gitDir, current.sha, cache);
		const subEntries = parseTreeEntries(subTreeData);
		current = subEntries.find((e) => e.path === parts[i]);
		if (!current) {
			treeCache.set(treeSha, null);
			return null;
		}
	}

	treeCache.set(treeSha, current.sha);
	return current.sha;
}
