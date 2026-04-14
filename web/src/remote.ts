import { existsSync, readFileSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

export async function remoteAdd(path: string, name: string, url: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const configPath = join(gitDir, "config");
	let configContent = "";

	if (existsSync(configPath)) {
		configContent = await readFile(configPath, "utf-8");
	}

	const remotePattern = new RegExp(`\\[remote\\s+"${name}"\\]`);
	if (remotePattern.test(configContent)) {
		throw new Error(`Remote '${name}' already exists`);
	}

	const remoteConfig = `[remote "${name}"]
	url = ${url}
	fetch = +refs/heads/*:refs/remotes/${name}/*
`;

	configContent = configContent.trim() + "\n\n" + remoteConfig.trim() + "\n";

	await writeFile(configPath, configContent, "utf-8");
}

export function hasRemote(path: string, name: string = "origin"): boolean {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		return false;
	}

	const configPath = join(gitDir, "config");

	if (!existsSync(configPath)) {
		return false;
	}

	try {
		const configContent = readFileSync(configPath, "utf-8");
		const remotePattern = new RegExp(`\\[remote\\s+"${name}"\\]`);
		return remotePattern.test(configContent);
	} catch {
		return false;
	}
}
