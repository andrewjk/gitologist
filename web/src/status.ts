import { existsSync, readdirSync, statSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join, relative } from "node:path";

import { IgnoreParser } from "./IgnoreParser.ts";
import type { StatusInfo } from "./types/StatusInfo.ts";
import { getIndex, hashFileAsBlob } from "./utils.ts";

export async function status(path: string): Promise<StatusInfo> {
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
	const deleted: string[] = [];

	// Load gitignore patterns
	const gitignore = new IgnoreParser();
	await gitignore.loadGitignore(path);

	const workingFiles = getWorkingFiles(path, gitignore);

	for (const filePath of index.keys()) {
		staged.push(filePath);
	}

	for (const file of workingFiles) {
		if (!index.has(file)) {
			untracked.push(file);
		}
	}

	for (const [filePath, entry] of index) {
		const fullPath = join(path, filePath);

		if (!existsSync(fullPath)) {
			deleted.push(filePath);
		} else if (statSync(fullPath).isFile()) {
			const currentHash = await hashFileAsBlob(fullPath);
			if (entry.sha !== currentHash) {
				modified.push(filePath);
			}
		}
	}

	return {
		branch,
		upToDate: `Your branch is up to date with 'origin/${branch}'.`,
		staged: staged.sort(),
		modified: modified.sort(),
		untracked: untracked.sort(),
		deleted: deleted.sort(),
	};
}

function getWorkingFiles(path: string, gitignore: IgnoreParser): string[] {
	const files: string[] = [];

	function scan(dir: string) {
		const entries = readdirSync(dir);

		for (const entry of entries) {
			if (entry === ".git") continue;

			const fullPath = join(dir, entry);
			const stat = statSync(fullPath);
			const relPath = relative(path, fullPath);

			// Check if this path is ignored
			if (gitignore.isIgnored(relPath, stat.isDirectory())) {
				continue;
			}

			if (stat.isDirectory()) {
				scan(fullPath);
			} else if (stat.isFile()) {
				files.push(relPath);
			}
		}
	}

	scan(path);
	return files;
}
