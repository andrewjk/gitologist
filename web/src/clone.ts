import { existsSync } from "node:fs";
import { mkdir } from "node:fs/promises";
import { join } from "node:path";

import { init } from "./init.ts";
import { remoteAdd } from "./remote.ts";

export async function clone(url: string, targetPath?: string): Promise<string> {
	const repoName = extractRepoName(url);
	const path = targetPath || join(process.cwd(), repoName);

	if (existsSync(path)) {
		throw new Error("Destination path already exists");
	}

	await mkdir(path, { recursive: true });

	await init(path);

	await remoteAdd(path, "origin", url);

	return path;
}

function extractRepoName(url: string): string {
	let cleanUrl = url;

	cleanUrl = cleanUrl.replace(/\.git$/, "");

	const parts = cleanUrl.split("/");
	const name = parts[parts.length - 1];

	if (name.includes("@")) {
		const atParts = name.split("@");
		return atParts[atParts.length - 1];
	}

	return name;
}
