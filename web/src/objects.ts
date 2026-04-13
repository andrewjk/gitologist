import { existsSync } from "node:fs";
import { join } from "node:path";

import type { PackObject } from "./packfile.ts";
import { readObject } from "./utils.ts";

export async function enumerateObjects(
	gitDir: string,
	sha: string,
	visited: Set<string> = new Set(),
): Promise<PackObject[]> {
	if (visited.has(sha)) {
		return [];
	}
	visited.add(sha);

	const objectData = await readObject(gitDir, sha);
	const headerEnd = objectData.indexOf("\n");
	const header = objectData.slice(0, headerEnd);
	const content = objectData.slice(headerEnd + 1);

	const spaceIndex = header.indexOf(" ");
	const type = header.slice(0, spaceIndex) as PackObject["type"];

	const objects: PackObject[] = [
		{
			type,
			sha,
			content: Buffer.from(content, "utf-8"),
		},
	];

	if (type === "commit") {
		// Parse parent commits and tree
		const lines = content.split("\n");
		for (const line of lines) {
			if (line.startsWith("parent ")) {
				const parentSha = line.slice(7);
				const parentObjects = await enumerateObjects(gitDir, parentSha, visited);
				objects.push(...parentObjects);
			} else if (line.startsWith("tree ")) {
				const treeSha = line.slice(5);
				const treeObjects = await enumerateObjects(gitDir, treeSha, visited);
				objects.push(...treeObjects);
			}
		}
	} else if (type === "tree") {
		// Parse tree entries
		const entries = parseTreeEntries(content);
		for (const entry of entries) {
			const entryObjects = await enumerateObjects(gitDir, entry.sha, visited);
			objects.push(...entryObjects);
		}
	}

	return objects;
}

function parseTreeEntries(content: string): Array<{ sha: string; type: string }> {
	const entries: Array<{ sha: string; type: string }> = [];
	const lines = content.split("\n").filter((line) => line.trim());

	for (const line of lines) {
		const parts = line.split(" ");
		if (parts.length >= 3) {
			const mode = parts[0];
			const sha = parts[2];
			const entryType = mode === "040000" ? "tree" : "blob";
			entries.push({ sha, type: entryType });
		}
	}

	return entries;
}

export async function getAllObjects(gitDir: string): Promise<PackObject[]> {
	const objectsDir = join(gitDir, "objects");
	const objects: PackObject[] = [];

	if (!existsSync(objectsDir)) {
		return objects;
	}

	const { readdir } = await import("node:fs/promises");
	const dirs = await readdir(objectsDir);

	for (const dir of dirs) {
		if (dir.length !== 2) continue;

		const dirPath = join(objectsDir, dir);
		const files = await readdir(dirPath);

		for (const file of files) {
			const sha = dir + file;
			try {
				const objectData = await readObject(gitDir, sha);
				const headerEnd = objectData.indexOf("\n");
				const header = objectData.slice(0, headerEnd);
				const content = objectData.slice(headerEnd + 1);

				const spaceIndex = header.indexOf(" ");
				const type = header.slice(0, spaceIndex) as PackObject["type"];

				objects.push({
					type,
					sha,
					content: Buffer.from(content, "utf-8"),
				});
			} catch {
				// Skip invalid objects
			}
		}
	}

	return objects;
}
