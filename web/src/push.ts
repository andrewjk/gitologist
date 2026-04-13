import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import { enumerateObjects } from "./objects.ts";
import { encodePktLine, decodePktLines, createPackfile } from "./packfile.ts";
import { status } from "./status.ts";
import { getCurrentBranch } from "./utils.ts";

export async function push(path: string, remote?: string, branch?: string): Promise<void> {
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

	if (currentStatus.modified.length > 0 || currentStatus.untracked.length > 0) {
		throw new Error("You have uncommitted changes. Commit or stash them before pushing.");
	}

	const commitSha = (await readFile(localBranchPath, "utf-8")).trim();
	const remoteUrl = await getRemoteUrl(gitDir, remoteName);

	if (remoteUrl && (remoteUrl.startsWith("http://") || remoteUrl.startsWith("https://"))) {
		await pushToRemote(remoteUrl, commitSha, branchName, gitDir);
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
): Promise<void> {
	// Get remote refs to determine what they have
	const remoteRefs = await discoverRefsForPush(remoteUrl);
	const remoteRef = remoteRefs.find((r) => r.ref === `refs/heads/${branchName}`);
	const oldSha = remoteRef?.sha || "0".repeat(40);

	// Enumerate all objects we need to send
	const objects = await enumerateObjects(gitDir, commitSha);

	// Build packfile
	const packfile = createPackfile(objects);

	// Build and send push request
	await uploadPackfile(remoteUrl, oldSha, commitSha, branchName, packfile);
}

async function discoverRefsForPush(
	remoteUrl: string,
): Promise<Array<{ sha: string; ref: string }>> {
	const url = new URL("info/refs", remoteUrl);
	url.searchParams.set("service", "git-receive-pack");

	const response = await fetch(url.toString(), {
		method: "GET",
		headers: {
			Accept: "application/x-git-receive-pack-advertisement",
			"Git-Protocol": "version=2",
		},
	});

	if (!response.ok) {
		throw new Error(`Failed to discover refs: ${response.status} ${response.statusText}`);
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

async function uploadPackfile(
	remoteUrl: string,
	oldSha: string,
	newSha: string,
	branchName: string,
	packfile: Buffer,
): Promise<void> {
	const url = new URL("git-receive-pack", remoteUrl);

	const requestBody = buildPushRequest(oldSha, newSha, branchName, packfile);

	const response = await fetch(url.toString(), {
		method: "POST",
		headers: {
			"Content-Type": "application/x-git-receive-pack-request",
			Accept: "application/x-git-receive-pack-result",
		},
		body: requestBody,
	});

	if (!response.ok) {
		throw new Error(`Push failed: ${response.status} ${response.statusText}`);
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

	// Update command
	lines.push(encodePktLine(`${oldSha} ${newSha} refs/heads/${branchName}`));

	// Flush packet to end commands
	lines.push(encodePktLine(null));

	// Packfile
	lines.push(packfile);

	return Buffer.concat(lines);
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
