import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { status } from "./status.js";

interface IndexEntry {
	path: string;
	sha: string;
	mode: string;
}

export async function add(path: string, files: string[]): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const indexPath = join(gitDir, "index");
	const index = await getIndex(indexPath);

	for (const file of files) {
		const fullPath = join(path, file);

		if (!existsSync(fullPath)) {
			throw new Error(`File not found: ${file}`);
		}

		const hash = await hashFile(fullPath);

		index.set(file, {
			path: file,
			sha: hash,
			mode: "100644",
		});
	}

	await writeIndex(indexPath, index);
}

export async function addAll(path: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentStatus = await status(path);
	const filesToAdd = [...currentStatus.untracked, ...currentStatus.modified];

	if (filesToAdd.length === 0) {
		return;
	}

	await add(path, filesToAdd);
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

async function writeIndex(indexPath: string, index: Map<string, IndexEntry>): Promise<void> {
	const lines: string[] = [];

	for (const entry of index.values()) {
		lines.push(`${entry.path} ${entry.sha} ${entry.mode}`);
	}

	await writeFile(indexPath, lines.join("\n") + "\n", "utf-8");
}

async function hashFile(filePath: string): Promise<string> {
	const crypto = await import("node:crypto");
	const content = await readFile(filePath);
	const hash = crypto.createHash("sha1");
	hash.update(content);
	return hash.digest("hex");
}
