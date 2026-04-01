import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export interface LogEntry {
	sha: string;
	abbreviatedSha: string;
	tree: string;
	parent: string | null;
	author: string;
	committer: string;
	date: Date;
	message: string;
}

export interface LogOptions {
	limit?: number;
	oneline?: boolean;
	branch?: string;
}

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

	while (currentSha !== null && entries.length < limit) {
		const entry = await parseCommitEntry(gitDir, currentSha);
		entries.push(entry);
		currentSha = entry.parent;
	}

	return entries;
}

async function getCurrentBranch(gitDir: string): Promise<string> {
	const headPath = join(gitDir, "HEAD");
	const headContent = (await readFile(headPath, "utf-8")).trim();

	const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
	if (match) {
		return match[1];
	}

	throw new Error("Not on a branch (detached HEAD)");
}

async function parseCommitEntry(gitDir: string, commitSha: string): Promise<LogEntry> {
	const commitData = await readObject(gitDir, commitSha);

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
