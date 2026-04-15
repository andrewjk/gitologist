import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import { encodePktLine, decodePktLines, parsePackfile, type PackObject } from "./packfile.ts";
import type { FetchResult } from "./types/FetchResult.ts";
import { hashObjectBuffer } from "./utils.ts";

export async function fetchFromRemote(path: string, remote?: string): Promise<FetchResult> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const remoteName = remote || "origin";
	const remoteUrl = await getRemoteUrl(gitDir, remoteName);

	if (!remoteUrl) {
		return {
			remote: remoteName,
			refs: [],
		};
	}

	const refs = await discoverRefs(remoteUrl);
	const result: FetchResult = {
		remote: remoteName,
		refs: [],
	};

	const wants: string[] = [];
	const haves: string[] = [];

	for (const ref of refs) {
		if (ref.ref.startsWith("refs/heads/")) {
			const branchName = ref.ref.slice("refs/heads/".length);
			const localRefPath = join(gitDir, "refs", "heads", branchName);

			if (existsSync(localRefPath)) {
				const localSha = (await readFile(localRefPath, "utf-8")).trim();
				haves.push(localSha);
			}

			wants.push(ref.sha);
			result.refs.push({
				name: branchName,
				sha: ref.sha,
			});
		}
	}

	if (wants.length > 0) {
		const objects = await fetchPackfile(remoteUrl, wants, haves);
		await storeObjects(gitDir, objects);
	}

	for (const ref of result.refs) {
		const remoteRefPath = join(gitDir, "refs", "remotes", remoteName, ref.name);
		await mkdir(dirname(remoteRefPath), { recursive: true });
		await writeFile(remoteRefPath, ref.sha + "\n", "utf-8");
	}

	return result;
}

async function storeObjects(gitDir: string, objects: PackObject[]): Promise<void> {
	for (const obj of objects) {
		const type = obj.type;
		await hashObjectBuffer(gitDir, obj.content, type);
	}
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

interface DiscoveredRef {
	sha: string;
	ref: string;
}

async function discoverRefs(remoteUrl: string): Promise<DiscoveredRef[]> {
	const url = new URL("info/refs", remoteUrl);
	url.searchParams.set("service", "git-upload-pack");

	const response = await fetch(url.toString(), {
		method: "GET",
		headers: {
			Accept: "application/x-git-upload-pack-advertisement",
			"Git-Protocol": "version=2",
		},
	});

	if (!response.ok) {
		throw new Error(`Failed to discover refs: ${response.status} ${response.statusText}`);
	}

	const buffer = Buffer.from(await response.arrayBuffer());
	const lines = decodePktLines(buffer);

	const refs: DiscoveredRef[] = [];
	let started = false;

	for (const line of lines) {
		if (line.includes("# service=git-upload-pack")) {
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

	if (refs.length > 0) {
		return refs;
	}

	return await discoverRefsV2(remoteUrl);
}

async function discoverRefsV2(remoteUrl: string): Promise<DiscoveredRef[]> {
	const uploadUrl = new URL("git-upload-pack", remoteUrl);

	const requestBody = buildLsRefsRequest();

	const response = await fetch(uploadUrl.toString(), {
		method: "POST",
		headers: {
			"Content-Type": "application/x-git-upload-pack-request",
			Accept: "application/x-git-upload-pack-result",
			"Git-Protocol": "version=2",
		},
		body: requestBody,
	});

	if (!response.ok) {
		throw new Error(`Failed to discover refs v2: ${response.status} ${response.statusText}`);
	}

	const buffer = Buffer.from(await response.arrayBuffer());
	const lines = decodePktLines(buffer);

	const refs: DiscoveredRef[] = [];

	for (const line of lines) {
		const trimmed = line.trim();
		if (trimmed === "") continue;

		const parts = trimmed.split(" ");
		if (parts.length >= 2 && parts[0].match(/^[0-9a-f]{40}$/)) {
			refs.push({
				sha: parts[0],
				ref: parts[1].trim().split("\0")[0],
			});
		}
	}

	return refs;
}

function buildLsRefsRequest(): Buffer {
	const lines: Buffer[] = [];

	lines.push(encodePktLine("command=ls-refs\n"));
	lines.push(encodePktLine("0001"));
	lines.push(encodePktLine("symrefs\n"));
	lines.push(encodePktLine("peel\n"));
	lines.push(encodePktLine("ref-prefix refs/heads/\n"));
	lines.push(encodePktLine(null));

	return Buffer.concat(lines);
}

function extractPackfileFromSideband(data: Buffer): Buffer {
	let offset = 0;
	const packfileData: Buffer[] = [];

	while (offset < data.length) {
		if (offset + 4 > data.length) {
			break;
		}

		const hexLen = data.slice(offset, offset + 4).toString("ascii");

		if (hexLen === "0000") {
			offset += 4;
			continue;
		}

		if (hexLen === "0001") {
			offset += 4;
			continue;
		}

		const length = parseInt(hexLen, 16);
		if (length <= 0 || offset + length > data.length) {
			break;
		}

		const payload = data.slice(offset + 4, offset + length);

		if (payload.length > 0) {
			const channel = payload[0];
			if (channel === 1) {
				packfileData.push(payload.slice(1));
			} else if (channel === 3) {
				const errorMsg = payload.slice(1).toString("utf-8");
				console.error(`Git error: ${errorMsg}`);
			}
		}

		offset += length;
	}

	return Buffer.concat(packfileData);
}

async function fetchPackfile(
	remoteUrl: string,
	wants: string[],
	haves: string[],
): Promise<PackObject[]> {
	const url = new URL("git-upload-pack", remoteUrl);

	const requestBody = buildFetchRequestV2(wants, haves);

	const response = await fetch(url.toString(), {
		method: "POST",
		headers: {
			"Content-Type": "application/x-git-upload-pack-request",
			Accept: "application/x-git-upload-pack-result",
			"Git-Protocol": "version=2",
		},
		body: requestBody,
	});

	if (!response.ok) {
		throw new Error(`Failed to fetch packfile: ${response.status} ${response.statusText}`);
	}

	const buffer = Buffer.from(await response.arrayBuffer());

	const packfileData = extractPackfileFromSideband(buffer);
	if (packfileData.length === 0) {
		return [];
	}

	return parsePackfile(packfileData);
}

function buildFetchRequestV2(wants: string[], haves: string[]): Buffer {
	const lines: Buffer[] = [];

	lines.push(encodePktLine("command=fetch\n"));
	lines.push(encodePktLine("0001"));

	for (const want of wants) {
		lines.push(encodePktLine(`want ${want}\n`));
	}

	for (const have of haves) {
		lines.push(encodePktLine(`have ${have}\n`));
	}

	lines.push(encodePktLine("done\n"));
	lines.push(encodePktLine(null));

	return Buffer.concat(lines);
}
