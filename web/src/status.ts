import { existsSync, readdirSync, statSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, relative } from "node:path";

export interface Status {
	branch: string;
	upToDate: string;
	staged: string[];
	modified: string[];
	untracked: string[];
}

interface IndexEntry {
	path: string;
	sha: string;
	mode: string;
}

export async function status(path: string): Promise<Status> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const headPath = join(gitDir, "HEAD");
	let branch = "";

	try {
		const headContent = (await readFile(headPath, "utf-8")).trim();
		const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
		if (match) {
			branch = match[1].trim();
		} else {
			branch = "(detached HEAD)";
		}
	} catch {
		branch = "(detached HEAD)";
	}

	const indexPath = join(gitDir, "index");
	const index = await getIndex(indexPath);

	const staged: string[] = [];
	const modified: string[] = [];
	const untracked: string[] = [];

	const workingFiles = getWorkingFiles(path);

	for (const filePath of index.keys()) {
		staged.push(filePath);
	}

	for (const file of workingFiles) {
		if (!index.has(file)) {
			untracked.push(file);
		}
	}

	for (const [filePath, entry] of index) {
		if (!existsSync(join(path, filePath))) {
			modified.push(filePath);
		} else {
			const currentHash = await hashFile(join(path, filePath));
			if (entry.sha !== currentHash) {
				modified.push(filePath);
			}
		}
	}

	return {
		branch,
		upToDate: `Your branch is up to date with 'origin/${branch}'.`,
		staged,
		modified,
		untracked,
	};
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

function getWorkingFiles(path: string): string[] {
	const files: string[] = [];

	function scan(dir: string) {
		const entries = readdirSync(dir);

		for (const entry of entries) {
			if (entry === ".git") continue;

			const fullPath = join(dir, entry);
			const stat = statSync(fullPath);

			if (stat.isDirectory()) {
				scan(fullPath);
			} else if (stat.isFile()) {
				const relPath = relative(path, fullPath);
				files.push(relPath);
			}
		}
	}

	scan(path);
	return files;
}

async function hashFile(filePath: string): Promise<string> {
	const crypto = await import("node:crypto");
	const content = await readFile(filePath);
	const hash = crypto.createHash("sha1");
	hash.update(content);
	return hash.digest("hex");
}
