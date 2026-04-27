import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { fetchFromRemote } from "./fetch.ts";
import type { RemoteOptions } from "./types/RemoteOptions.ts";
import {
	extractContentFromBlob,
	extractTreeFromCommit,
	getCurrentBranch,
	getCurrentCommit,
	hashObject,
	parseTreeEntries,
	readObject,
	updateBranch,
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

	await fetchFromRemote(path, remote, options);

	const remoteName = remote || "origin";
	const branchName = branch || (await getCurrentBranch(gitDir));

	const remoteBranchPath = join(gitDir, "refs", "remotes", remoteName, branchName);
	if (!existsSync(remoteBranchPath)) {
		throw new Error(`Remote branch '${remoteName}/${branchName}' does not exist`);
	}

	const remoteCommitSha = (await readFile(remoteBranchPath, "utf-8")).trim();
	const currentCommitSha = await getCurrentCommit(gitDir);

	if (!currentCommitSha) {
		await updateBranch(gitDir, branchName, remoteCommitSha);
		const commitData = await readObject(gitDir, remoteCommitSha);
		const treeSha = extractTreeFromCommit(commitData);

		await extractTreeToWorkingDirectory(gitDir, path, treeSha);
		await updateIndex(gitDir, path, treeSha);
		return;
	}

	if (currentCommitSha === remoteCommitSha) {
		return;
	}

	const isAncestor = await isAncestorOf(gitDir, currentCommitSha, remoteCommitSha);

	if (isAncestor) {
		await updateBranch(gitDir, branchName, remoteCommitSha);
		const commitData = await readObject(gitDir, remoteCommitSha);
		const treeSha = extractTreeFromCommit(commitData);

		await extractTreeToWorkingDirectory(gitDir, path, treeSha);
		await updateIndex(gitDir, path, treeSha);
		return;
	}

	const mergeBase = await findMergeBase(gitDir, currentCommitSha, remoteCommitSha);

	if (mergeBase === remoteCommitSha) {
		return;
	}

	const mergeCommitSha = await createMergeCommit(
		gitDir,
		currentCommitSha,
		remoteCommitSha,
		`Merge branch '${branchName}' of ${remoteName}`,
	);

	await updateBranch(gitDir, branchName, mergeCommitSha);
	const commitData = await readObject(gitDir, mergeCommitSha);
	const treeSha = extractTreeFromCommit(commitData);

	await extractTreeToWorkingDirectory(gitDir, path, treeSha);
	await updateIndex(gitDir, path, treeSha);
}

async function extractTreeToWorkingDirectory(
	gitDir: string,
	workingPath: string,
	treeSha: string,
): Promise<void> {
	await extractTreeRecursive(gitDir, workingPath, treeSha, "");
}

async function extractTreeRecursive(
	gitDir: string,
	workingPath: string,
	treeSha: string,
	prefix: string,
): Promise<void> {
	const treeData = await readObject(gitDir, treeSha);
	const entries = parseTreeEntries(treeData);

	for (const entry of entries) {
		const entryPath = join(workingPath, prefix, entry.path);

		if (entry.type === "blob") {
			const blobData = await readObject(gitDir, entry.sha);
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
			);
		}
	}
}

async function updateIndex(gitDir: string, workingPath: string, treeSha: string): Promise<void> {
	const indexPath = join(gitDir, "index");

	let indexContent = "";
	indexContent = await updateIndexRecursive(gitDir, treeSha, "", indexContent);

	await writeFile(indexPath, indexContent + "\n", "utf-8");
}

async function updateIndexRecursive(
	gitDir: string,
	treeSha: string,
	prefix: string,
	indexContent: string,
): Promise<string> {
	const treeData = await readObject(gitDir, treeSha);
	const entries = parseTreeEntries(treeData);
	let content = indexContent;

	for (const entry of entries) {
		if (entry.type === "blob") {
			const blobData = await readObject(gitDir, entry.sha);
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
			);
		}
	}

	return content;
}

async function isAncestorOf(
	gitDir: string,
	ancestorSha: string,
	descendantSha: string,
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

		const parents = await getParents(gitDir, current);
		queue.push(...parents);
	}

	return false;
}

async function findMergeBase(gitDir: string, sha1: string, sha2: string): Promise<string | null> {
	if (sha1 === sha2) {
		return sha1;
	}

	const ancestors1 = await getAllAncestors(gitDir, sha1);
	const ancestors2 = await getAllAncestors(gitDir, sha2);

	ancestors1.add(sha1);
	ancestors2.add(sha2);

	for (const ancestor of ancestors1) {
		if (ancestors2.has(ancestor)) {
			return ancestor;
		}
	}

	return null;
}

async function getAllAncestors(gitDir: string, sha: string): Promise<Set<string>> {
	const ancestors = new Set<string>();
	const queue: string[] = [sha];

	while (queue.length > 0) {
		const current = queue.shift()!;

		if (ancestors.has(current)) {
			continue;
		}

		const parents = await getParents(gitDir, current);
		for (const parent of parents) {
			ancestors.add(parent);
			queue.push(parent);
		}
	}

	return ancestors;
}

async function getParents(gitDir: string, sha: string): Promise<string[]> {
	try {
		const commitData = await readObject(gitDir, sha);
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

async function getTree(gitDir: string, sha: string): Promise<string | null> {
	try {
		const commitData = await readObject(gitDir, sha);
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
): Promise<string> {
	const treeSha = await getTree(gitDir, parent1);

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
