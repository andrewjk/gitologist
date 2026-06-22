import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

import { getCurrentBranch, getCurrentCommit } from "./branch.ts";
import type { MergeResult } from "./types/MergeResult.ts";
import { hashObject, readObject, updateBranch, type PackfileCache } from "./utils.ts";

export async function merge(
	path: string,
	branchName: string,
	options?: { message?: string; noFastForward?: boolean },
): Promise<MergeResult> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const currentBranch = await getCurrentBranch(gitDir);
	if (currentBranch === branchName) {
		throw new Error("Cannot merge a branch into itself");
	}

	const currentSha = await getCurrentCommit(gitDir);
	const branchSha = await getBranchCommit(gitDir, branchName);

	if (!branchSha) {
		throw new Error(`Branch '${branchName}' not found`);
	}

	if (!currentSha) {
		throw new Error("Cannot merge into an empty branch");
	}

	if (currentSha === branchSha) {
		return {
			success: true,
			fastForward: false,
			message: "Already up to date.",
		};
	}

	let cache = new Map();

	const isAncestor = await isAncestorOf(gitDir, currentSha, branchSha, cache);

	if (isAncestor && !options?.noFastForward) {
		await updateBranch(gitDir, currentBranch, branchSha);
		return {
			success: true,
			fastForward: true,
			commitSha: branchSha,
			message: `Fast-forward merge of '${branchName}' into '${currentBranch}'`,
		};
	}

	const mergeBase = await findMergeBase(gitDir, currentSha, branchSha, cache);

	if (mergeBase === branchSha) {
		return {
			success: true,
			fastForward: false,
			message: "Already up to date.",
		};
	}

	const mergeMessage = options?.message || `Merge branch '${branchName}' into '${currentBranch}'`;

	const mergeCommitSha = await createMergeCommit(
		gitDir,
		currentSha,
		branchSha,
		mergeMessage,
		cache,
	);

	await updateBranch(gitDir, currentBranch, mergeCommitSha);

	return {
		success: true,
		fastForward: false,
		commitSha: mergeCommitSha,
		message: mergeMessage,
	};
}

async function getBranchCommit(gitDir: string, branchName: string): Promise<string | null> {
	const branchPath = join(gitDir, "refs", "heads", branchName);

	if (!existsSync(branchPath)) {
		return null;
	}

	return (await readFile(branchPath, "utf-8")).trim();
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
