import { existsSync } from "node:fs";
import { join } from "node:path";

import { getCurrentCommit } from "./branch.ts";
import {
	extractContentFromBlob,
	extractTreeFromCommit,
	parseTreeEntries,
	readObject,
	type PackfileCache,
} from "./utils.ts";

export async function show(path: string, filePath: string): Promise<string> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const commitSha = await getCurrentCommit(gitDir);
	if (commitSha === null) {
		throw new Error(`Path '${filePath}' does not exist in 'HEAD'`);
	}

	const cache: PackfileCache = new Map();
	const commitData = await readObject(gitDir, commitSha, cache);
	const treeSha = extractTreeFromCommit(commitData);

	const blobSha = await resolveBlobSha(gitDir, treeSha, filePath, cache);
	if (blobSha === null) {
		throw new Error(`Path '${filePath}' does not exist in 'HEAD'`);
	}

	const blobData = await readObject(gitDir, blobSha, cache);
	return extractContentFromBlob(blobData);
}

async function resolveBlobSha(
	gitDir: string,
	treeSha: string,
	filePath: string,
	cache: PackfileCache,
): Promise<string | null> {
	const parts = filePath.split("/");
	let currentSha = treeSha;

	for (let i = 0; i < parts.length; i++) {
		const isLast = i === parts.length - 1;
		const treeData = await readObject(gitDir, currentSha, cache);
		const entries = parseTreeEntries(treeData);
		const entry = entries.find((e) => e.path === parts[i]);
		if (!entry) {
			return null;
		}
		if (isLast) {
			return entry.type === "blob" ? entry.sha : null;
		}
		if (entry.type !== "tree") {
			return null;
		}
		currentSha = entry.sha;
	}

	return null;
}
