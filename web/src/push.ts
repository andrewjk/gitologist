import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import { enumerateObjects } from "./objects.ts";
import { encodePktLine, decodePktLines, createPackfile } from "./packfile.ts";
import { status } from "./status.ts";
import type { RemoteOptions } from "./types/RemoteOptions.ts";
import { getCurrentBranch } from "./utils.ts";

type FetchHeaders = Record<string, string>;

export async function push(
	path: string,
	remote?: string,
	branch?: string,
	options?: RemoteOptions,
): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const remoteName = remote || "origin";
	const branchName = branch || (await getCurrentBranch(gitDir));

	const localBranchPath = join(gitDir, "refs", "heads", branchName);
	if (!existsSync(localBranchPath)) {
		throw new Error(`Local branch '${branchName}' does not exist`);
	}

	const currentStatus = await status(path);

	if (
		currentStatus.modified.length > 0 ||
		currentStatus.untracked.length > 0 ||
		currentStatus.deleted.length > 0
	) {
		throw new Error("You have uncommitted changes. Commit or stash them before pushing.");
	}

	const commitSha = (await readFile(localBranchPath, "utf-8")).trim();
	const remoteUrl = await getRemoteUrl(gitDir, remoteName);

	if (remoteUrl && (remoteUrl.startsWith("http://") || remoteUrl.startsWith("https://"))) {
		await pushToRemote(remoteUrl, commitSha, branchName, gitDir, options);
	}

	const remoteBranchPath = join(gitDir, "refs", "remotes", remoteName, branchName);
	await mkdir(dirname(remoteBranchPath), { recursive: true });
	await writeFile(remoteBranchPath, commitSha + "\n", "utf-8");
}

async function pushToRemote(
	remoteUrl: string,
	commitSha: string,
	branchName: string,
	gitDir: string,
	options?: RemoteOptions,
): Promise<void> {
	let oldSha = "0".repeat(40);

	try {
		const remoteRefs = await discoverRefsForPush(remoteUrl, options);
		const remoteRef = remoteRefs.find((r) => r.ref === `refs/heads/${branchName}`);
		if (remoteRef) {
			oldSha = remoteRef.sha;
		}
	} catch {
		// If we can't discover refs, assume it's a new branch
	}

	// Enumerate all objects we need to send
	const objects = await enumerateObjects(gitDir, commitSha);

	// Build packfile
	const packfile = createPackfile(objects);

	// Build and send push request
	await sendPush(remoteUrl, oldSha, commitSha, branchName, packfile, options);
}

async function discoverRefsForPush(
	remoteUrl: string,
	options?: RemoteOptions,
): Promise<Array<{ sha: string; ref: string }>> {
	const url = new URL("info/refs", remoteUrl);
	url.searchParams.set("service", "git-receive-pack");

	const headers: FetchHeaders = {
		Accept: "application/x-git-receive-pack-advertisement",
		"Git-Protocol": "version=2",
	};

	if (options?.credentials) {
		const auth = Buffer.from(
			`${options.credentials.username}:${options.credentials.token}`,
		).toString("base64");
		headers["Authorization"] = `Basic ${auth}`;
	}

	const response = await fetch(url.toString(), {
		method: "GET",
		headers,
	});

	if (response.status !== 200) {
		return [];
	}

	const buffer = Buffer.from(await response.arrayBuffer());
	const lines = decodePktLines(buffer);

	const refs: Array<{ sha: string; ref: string }> = [];
	let started = false;

	for (const line of lines) {
		if (line.includes("# service=git-receive-pack")) {
			started = true;
			continue;
		}

		if (!started) continue;
		if (line === "") continue;

		const parts = line.split(" ");
		if (parts.length >= 2 && parts[0].match(/^[0-9a-f]{40}$/)) {
			refs.push({
				sha: parts[0],
				ref: parts[1].split("\0")[0],
			});
		}
	}

	return refs;
}

async function sendPush(
	remoteUrl: string,
	oldSha: string,
	newSha: string,
	branchName: string,
	packfile: Buffer,
	options?: RemoteOptions,
): Promise<void> {
	const url = new URL("git-receive-pack", remoteUrl);

	const requestBody = buildPushRequest(oldSha, newSha, branchName, packfile);

	const headers: FetchHeaders = {
		"Content-Type": "application/x-git-receive-pack-request",
		Accept: "application/x-git-receive-pack-result",
		"Git-Protocol": "version=2",
	};

	if (options?.credentials) {
		const auth = Buffer.from(
			`${options.credentials.username}:${options.credentials.token}`,
		).toString("base64");
		headers["Authorization"] = `Basic ${auth}`;
	}

	const response = await fetch(url.toString(), {
		method: "POST",
		headers,
		body: requestBody,
	});

	if (!response.ok) {
		const errorText = await response.text();
		throw new Error(`Push failed: ${response.status} ${errorText || response.statusText}`);
	}

	// Parse response for errors
	const buffer = Buffer.from(await response.arrayBuffer());
	const lines = decodePktLines(buffer);

	for (const line of lines) {
		if (line.startsWith("ng ")) {
			throw new Error(`Push rejected: ${line.slice(3)}`);
		}
	}
}

function buildPushRequest(
	oldSha: string,
	newSha: string,
	branchName: string,
	packfile: Buffer,
): Buffer {
	const lines: Buffer[] = [];

	// Update command with capabilities
	lines.push(
		encodePktLine(
			`${oldSha} ${newSha} refs/heads/${branchName}\0report-status agent=gitologist/1.0`,
		),
	);

	// Flush packet to end commands
	lines.push(encodePktLine(null));

	// Packfile
	lines.push(packfile);

	return Buffer.concat(lines);
}

export async function setUpstreamBranch(
	path: string,
	remoteName: string,
	branchName: string,
): Promise<void> {
	const configPath = join(path, ".git", "config");

	let configContent = "";
	if (existsSync(configPath)) {
		configContent = await readFile(configPath, "utf-8");
	}

	const lines = configContent.split("\n");
	let inBranchSection = false;
	let foundBranchSection = false;
	let insertIndex = -1;

	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		const trimmed = line.trim();

		const sectionMatch = trimmed.match(/^\[branch\s+"([^"]+)"\]$/);
		if (sectionMatch) {
			if (sectionMatch[1] === branchName) {
				inBranchSection = true;
				foundBranchSection = true;
			} else {
				inBranchSection = false;
			}
			continue;
		}

		if (inBranchSection) {
			if (trimmed.startsWith("remote =") || trimmed.startsWith("merge =")) {
				continue;
			}
			if (insertIndex === -1) {
				insertIndex = i;
			}
		} else {
			if (trimmed.startsWith("[") && insertIndex === -1) {
				insertIndex = i;
			}
		}
	}

	if (!foundBranchSection) {
		lines.push("");
		lines.push(`[branch "${branchName}"]`);
		lines.push(`\tremote = ${remoteName}`);
		lines.push(`\tmerge = refs/heads/${branchName}`);
	} else {
		if (insertIndex === -1) {
			insertIndex = lines.length;
		}
		lines.splice(insertIndex, 0, `\tremote = ${remoteName}`, `\tmerge = refs/heads/${branchName}`);
	}

	await writeFile(configPath, lines.join("\n"), "utf-8");
}

async function getRemoteUrl(gitDir: string, remoteName: string): Promise<string | null> {
	const configPath = join(gitDir, "config");

	if (!existsSync(configPath)) {
		return null;
	}

	const configContent = await readFile(configPath, "utf-8");
	const lines = configContent.split("\n");

	let inRemoteSection = false;
	let currentRemote = "";

	for (const line of lines) {
		const trimmed = line.trim();

		const sectionMatch = trimmed.match(/^\[remote\s+"([^"]+)"\]$/);
		if (sectionMatch) {
			inRemoteSection = true;
			currentRemote = sectionMatch[1];
			continue;
		}

		if (inRemoteSection && currentRemote === remoteName) {
			const urlMatch = trimmed.match(/^url\s*=\s*(.+)$/);
			if (urlMatch) {
				return urlMatch[1].trim();
			}
		}

		if (trimmed.startsWith("[") && !trimmed.startsWith("[remote")) {
			inRemoteSection = false;
		}
	}

	return null;
}
