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

export async function setRemoteUrl(path: string, name: string, url: string): Promise<void> {
	const gitDir = join(path, ".git");
	const configPath = join(gitDir, "config");

	if (!existsSync(configPath)) {
		throw new Error("Not a git repository");
	}

	const configContent = await readFile(configPath, "utf-8");
	const lines = configContent.split("\n");

	let inRemoteSection = false;
	let currentRemote = "";
	const updatedLines: string[] = [];

	for (const line of lines) {
		const trimmed = line.trim();

		const sectionMatch = trimmed.match(/^\[remote\s+"([^"]+)"\]$/);
		if (sectionMatch) {
			inRemoteSection = true;
			currentRemote = sectionMatch[1] as string;
			updatedLines.push(line);
			continue;
		}

		if (inRemoteSection && currentRemote === name) {
			if (trimmed.startsWith("url")) {
				updatedLines.push(`\turl = ${url}`);
				continue;
			}
		}

		if (trimmed.startsWith("[") && !trimmed.startsWith("[remote")) {
			inRemoteSection = false;
		}

		updatedLines.push(line);
	}

	await writeFile(configPath, updatedLines.join("\n"), "utf-8");
}
