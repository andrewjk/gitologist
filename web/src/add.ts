import { existsSync } from "node:fs";
import { stat } from "node:fs/promises";
import { join } from "node:path";

import { IgnoreParser } from "./IgnoreParser.ts";
import { status } from "./status.ts";
import { getIndex, hashFile, writeIndex } from "./utils.ts";

export async function add(path: string, files: string[]): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const indexPath = join(gitDir, "index");
	const index = await getIndex(indexPath);

	// Load gitignore patterns
	const gitignore = new IgnoreParser();
	await gitignore.loadGitignore(path);

	for (const file of files) {
		if (gitignore.isIgnored(file)) {
			continue;
		}

		const fullPath = join(path, file);

		if (!existsSync(fullPath)) {
			throw new Error(`File not found: ${file}`);
		}

		const hash = await hashFile(fullPath);
		const stats = await stat(fullPath);

		index.set(file, {
			path: file,
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
