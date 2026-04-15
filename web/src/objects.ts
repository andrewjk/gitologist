import { existsSync } from "node:fs";
import { join } from "node:path";

import type { PackObject } from "./packfile.ts";
import { parseTreeEntriesFromData, readObject, readObjectData } from "./utils.ts";

export async function enumerateObjects(
	gitDir: string,
	sha: string,
	visited: Set<string> = new Set(),
): Promise<PackObject[]> {
	if (visited.has(sha)) {
		return [];
	}
	visited.add(sha);

	const objectData = await readObjectData(gitDir, sha);
	const nullIndex = objectData.indexOf(0);

	if (nullIndex === -1) {
		return [];
	}

	const headerData = objectData.subarray(0, nullIndex);
	const contentData = objectData.subarray(nullIndex + 1);

	const header = headerData.toString("utf-8");
	const spaceIndex = header.indexOf(" ");

	if (spaceIndex === -1) {
		return [];
	}

	const typeString = header.slice(0, spaceIndex);
	const type = typeString as PackObject["type"];

	const objects: PackObject[] = [
		{
			type,
			sha,
			content: contentData,
		},
	];

	if (type === "commit") {
		const content = contentData.toString("utf-8");
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
		const entries = parseTreeEntriesFromData(contentData);
		for (const entry of entries) {
			const entryObjects = await enumerateObjects(gitDir, entry.sha, visited);
			objects.push(...entryObjects);
		}
	}

	return objects;
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
