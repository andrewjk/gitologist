import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { getCurrentBranch, getCurrentCommit } from "./branch.ts";
import { fetchOrigin } from "./fetch.ts";
import type { RemoteOptions } from "./types/RemoteOptions.ts";
import {
	extractContentFromBlob,
	extractTreeFromCommit,
	getIndex,
	hashFileAsBlob,
	hashObject,
	parseTreeEntries,
	readObject,
	updateBranch,
	type PackfileCache,
} from "./utils.ts";

export async function pull(
	path: string,
	remote?: string,
	branch?: string,
	options?: RemoteOptions,
): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	await fetchOrigin(path, remote, options);

	const remoteName = remote || "origin";
	const branchName = branch || (await getCurrentBranch(gitDir));

	const remoteBranchPath = join(gitDir, "refs", "remotes", remoteName, branchName);
	if (!existsSync(remoteBranchPath)) {
		throw new Error(`Remote branch '${remoteName}/${branchName}' does not exist`);
	}

	const remoteCommitSha = (await readFile(remoteBranchPath, "utf-8")).trim();
	const currentCommitSha = await getCurrentCommit(gitDir);

	let cache = new Map();

	if (!currentCommitSha) {
		await updateBranch(gitDir, branchName, remoteCommitSha);
		const commitData = await readObject(gitDir, remoteCommitSha, cache);
		const treeSha = extractTreeFromCommit(commitData);

		await extractTreeToWorkingDirectory(gitDir, path, treeSha, new Map(), cache);
		await updateIndex(gitDir, path, treeSha, cache);
		return;
	}

	if (currentCommitSha === remoteCommitSha) {
		return;
	}

	const isAncestor = await isAncestorOf(gitDir, currentCommitSha, remoteCommitSha, cache);

	const currentTreeSha = await getTree(gitDir, currentCommitSha, cache);
	const currentBlobs = currentTreeSha
		? await getTreeBlobs(gitDir, currentTreeSha, undefined, cache)
		: new Map();

	if (isAncestor) {
		await updateBranch(gitDir, branchName, remoteCommitSha);
		const commitData = await readObject(gitDir, remoteCommitSha, cache);
		const treeSha = extractTreeFromCommit(commitData);

		await checkForLocalChanges(gitDir, path, currentBlobs, treeSha, cache);
		await extractTreeToWorkingDirectory(gitDir, path, treeSha, currentBlobs, cache);
		await updateIndex(gitDir, path, treeSha, cache);
		return;
	}

	const mergeBase = await findMergeBase(gitDir, currentCommitSha, remoteCommitSha, cache);

	if (mergeBase === remoteCommitSha) {
		return;
	}

	const mergeCommitSha = await createMergeCommit(
		gitDir,
		currentCommitSha,
		remoteCommitSha,
		`Merge branch '${branchName}' of ${remoteName}`,
		cache,
	);

	await updateBranch(gitDir, branchName, mergeCommitSha);
	const commitData = await readObject(gitDir, mergeCommitSha, cache);
	const treeSha = extractTreeFromCommit(commitData);

	await checkForLocalChanges(gitDir, path, currentBlobs, treeSha, cache);
	await extractTreeToWorkingDirectory(gitDir, path, treeSha, currentBlobs, cache);
	await updateIndex(gitDir, path, treeSha, cache);
}

/**
 * Checks out the tree of `commitSha` into the working directory and index,
 * guarding against overwriting uncommitted changes. Shared by `pull` and `switchBranch`.
 */
export async function checkoutTree(
	gitDir: string,
	workingPath: string,
	commitSha: string,
	cache: PackfileCache,
): Promise<void> {
	const commitData = await readObject(gitDir, commitSha, cache);
	const treeSha = extractTreeFromCommit(commitData);

	const currentBlobs = new Map<string, string>();
	const currentCommitSha = await getCurrentCommit(gitDir);
	if (currentCommitSha) {
		const currentTreeSha = await getTree(gitDir, currentCommitSha, cache);
		if (currentTreeSha) {
			const blobs = await getTreeBlobs(gitDir, currentTreeSha, undefined, cache);
			for (const [path, sha] of blobs) {
				currentBlobs.set(path, sha);
			}
		}
	}

	await checkForLocalChanges(gitDir, workingPath, currentBlobs, treeSha, cache);
	await extractTreeToWorkingDirectory(gitDir, workingPath, treeSha, currentBlobs, cache);
	await updateIndex(gitDir, workingPath, treeSha, cache);
}

async function getTreeBlobs(
	gitDir: string,
	treeSha: string,
	prefix: string = "",
	cache: PackfileCache,
): Promise<Map<string, string>> {
	const blobs = new Map<string, string>();
	const treeData = await readObject(gitDir, treeSha, cache);
	const entries = parseTreeEntries(treeData);

	for (const entry of entries) {
		const path = prefix ? `${prefix}/${entry.path}` : entry.path;
		if (entry.type === "blob") {
			blobs.set(path, entry.sha);
		} else if (entry.type === "tree") {
			const childBlobs = await getTreeBlobs(gitDir, entry.sha, path, cache);
			for (const [childPath, childSha] of childBlobs) {
				blobs.set(childPath, childSha);
			}
		}
	}

	return blobs;
}

async function checkForLocalChanges(
	gitDir: string,
	workingPath: string,
	currentBlobs: Map<string, string>,
	newTreeSha: string,
	cache: PackfileCache,
): Promise<void> {
	const indexPath = join(gitDir, "index");
	const index = await getIndex(indexPath);
	const newBlobs = await getTreeBlobs(gitDir, newTreeSha, undefined, cache);

	// Check if any files that will be changed have uncommitted modifications
	for (const [path, newSha] of newBlobs) {
		const currentSha = currentBlobs.get(path);

		// Only check files that will be updated (currentSha != newSha)
		if (currentSha === newSha) {
			continue;
		}

		const fullPath = join(workingPath, path);
		if (!existsSync(fullPath)) {
			continue;
		}

		const indexEntry = index.get(path);
		if (indexEntry) {
			const currentHash = await hashFileAsBlob(fullPath);
			// If the file has uncommitted changes (different from index) and will be updated, throw error
			if (currentHash !== indexEntry.sha) {
				throw new Error(
					`Your local changes to '${path}' would be overwritten by merge. Please commit or stash them.`,
				);
			}
		}
	}
}

async function extractTreeToWorkingDirectory(
	gitDir: string,
	workingPath: string,
	treeSha: string,
	currentBlobs: Map<string, string>,
	cache: PackfileCache,
): Promise<void> {
	await extractTreeRecursive(gitDir, workingPath, treeSha, "", currentBlobs, cache);
}

async function extractTreeRecursive(
	gitDir: string,
	workingPath: string,
	treeSha: string,
	prefix: string,
	currentBlobs: Map<string, string>,
	cache: PackfileCache,
): Promise<void> {
	const treeData = await readObject(gitDir, treeSha, cache);
	const entries = parseTreeEntries(treeData);

	for (const entry of entries) {
		const entryPath = join(workingPath, prefix, entry.path);
		const path = prefix ? `${prefix}/${entry.path}` : entry.path;

		if (entry.type === "blob") {
			const currentSha = currentBlobs.get(path);
			if (currentSha === entry.sha) {
				continue;
			}
			const blobData = await readObject(gitDir, entry.sha, cache);
			const content = extractContentFromBlob(blobData);
			await writeFile(entryPath, content, "utf-8");
		} else if (entry.type === "tree") {
			if (!existsSync(entryPath)) {
				await mkdir(entryPath, { recursive: true });
			}
			await extractTreeRecursive(
				gitDir,
				workingPath,
				entry.sha,
				prefix ? `${prefix}/${entry.path}` : entry.path,
				currentBlobs,
				cache,
			);
		}
	}
}

async function updateIndex(
	gitDir: string,
	workingPath: string,
	treeSha: string,
	cache: PackfileCache,
): Promise<void> {
	const indexPath = join(gitDir, "index");

	let indexContent = "";
	indexContent = await updateIndexRecursive(gitDir, treeSha, "", indexContent, cache);

	await writeFile(indexPath, indexContent + "\n", "utf-8");
}

async function updateIndexRecursive(
	gitDir: string,
	treeSha: string,
	prefix: string,
	indexContent: string,
	cache: PackfileCache,
): Promise<string> {
	const treeData = await readObject(gitDir, treeSha, cache);
	const entries = parseTreeEntries(treeData);
	let content = indexContent;

	for (const entry of entries) {
		if (entry.type === "blob") {
			const blobData = await readObject(gitDir, entry.sha, cache);
			const fileContent = extractContentFromBlob(blobData);
			// Use git blob hash format (with "blob <size>\0" header)
			const crypto = await import("node:crypto");
			const blobHeader = `blob ${fileContent.length}\0${fileContent}`;
			const hash = crypto.createHash("sha1");
			hash.update(blobHeader);
			const sha = hash.digest("hex");
			content += `${prefix ? `${prefix}/${entry.path}` : entry.path} ${sha}\n`;
		} else if (entry.type === "tree") {
			content = await updateIndexRecursive(
				gitDir,
				entry.sha,
				prefix ? `${prefix}/${entry.path}` : entry.path,
				content,
				cache,
			);
		}
	}

	return content;
}

async function isAncestorOf(
	gitDir: string,
	ancestorSha: string,
	descendantSha: string,
	cache: PackfileCache,
): Promise<boolean> {
	const visited = new Set<string>();
	const queue: string[] = [descendantSha];

	while (queue.length > 0) {
		const current = queue.shift()!;

		if (current === ancestorSha) {
			return true;
		}

		if (visited.has(current)) {
			continue;
		}
		visited.add(current);

		const parents = await getParents(gitDir, current, cache);
		queue.push(...parents);
	}

	return false;
}

async function findMergeBase(
	gitDir: string,
	sha1: string,
	sha2: string,
	cache: PackfileCache,
): Promise<string | null> {
	if (sha1 === sha2) {
		return sha1;
	}

	const ancestors1 = await getAllAncestors(gitDir, sha1, cache);
	const ancestors2 = await getAllAncestors(gitDir, sha2, cache);

	ancestors1.add(sha1);
	ancestors2.add(sha2);

	for (const ancestor of ancestors1) {
		if (ancestors2.has(ancestor)) {
			return ancestor;
		}
	}

	return null;
}

async function getAllAncestors(
	gitDir: string,
	sha: string,
	cache: PackfileCache,
): Promise<Set<string>> {
	const ancestors = new Set<string>();
	const queue: string[] = [sha];

	while (queue.length > 0) {
		const current = queue.shift()!;

		if (ancestors.has(current)) {
			continue;
		}

		const parents = await getParents(gitDir, current, cache);
		for (const parent of parents) {
			ancestors.add(parent);
			queue.push(parent);
		}
	}

	return ancestors;
}

async function getParents(gitDir: string, sha: string, cache: PackfileCache): Promise<string[]> {
	try {
		const commitData = await readObject(gitDir, sha, cache);
		const parents: string[] = [];
		const lines = commitData.split("\n");

		for (const line of lines) {
			if (line.startsWith("parent ")) {
				parents.push(line.slice(7));
			}
		}

		return parents;
	} catch {
		return [];
	}
}

async function getTree(gitDir: string, sha: string, cache: PackfileCache): Promise<string | null> {
	try {
		const commitData = await readObject(gitDir, sha, cache);
		const lines = commitData.split("\n");

		for (const line of lines) {
			if (line.startsWith("tree ")) {
				return line.slice(5);
			}
		}
		return null;
	} catch {
		return null;
	}
}

async function createMergeCommit(
	gitDir: string,
	parent1: string,
	parent2: string,
	message: string,
	cache: PackfileCache,
): Promise<string> {
	const treeSha = await getTree(gitDir, parent1, cache);

	if (!treeSha) {
		throw new Error("Could not get tree for merge commit");
	}

	const now = new Date();
	const timestamp = Math.floor(now.getTime() / 1000);
	const offset = now.getTimezoneOffset() * -60;
	const hours = Math.floor(Math.abs(offset) / 60)
		.toString()
		.padStart(2, "0");
	const minutes = (Math.abs(offset) % 60).toString().padStart(2, "0");
	const sign = offset >= 0 ? "+" : "-";

	const author = `User <user@example.com> ${timestamp} ${sign}${hours}${minutes}`;

	let commitContent = `tree ${treeSha}\n`;
	commitContent += `parent ${parent1}\n`;
	commitContent += `parent ${parent2}\n`;
	commitContent += `author ${author}\n`;
	commitContent += `committer ${author}\n`;
	commitContent += `\n${message}\n`;

	return hashObject(gitDir, commitContent, "commit");
}
