import { existsSync } from "node:fs";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { checkoutTree } from "./pull.ts";
import { setUpstreamBranch } from "./push.ts";
import { updateBranch, type PackfileCache } from "./utils.ts";

export async function switchBranch(path: string, branchName: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const cache: PackfileCache = new Map();

	// 1. Local branch exists: check out its tree, then point HEAD at it.
	const localBranchPath = join(gitDir, "refs", "heads", branchName);
	if (existsSync(localBranchPath)) {
		const commitSha = (await readFile(localBranchPath, "utf-8")).trim();

		// Check out the tree first (uses the current HEAD as the baseline for
		// change detection); only move HEAD once the checkout succeeds.
		await checkoutTree(gitDir, path, commitSha, cache);

		const headPath = join(gitDir, "HEAD");
		await writeFile(headPath, `ref: refs/heads/${branchName}\n`, "utf-8");
		return;
	}

	// 2. DWIM: no local branch, but exactly one remote tracking branch exists.
	const dwim = await findRemoteBranch(gitDir, branchName);
	if (dwim) {
		const { remoteName, commitSha } = dwim;

		await updateBranch(gitDir, branchName, commitSha);
		await setUpstreamBranch(path, remoteName, branchName);

		await checkoutTree(gitDir, path, commitSha, cache);

		const headPath = join(gitDir, "HEAD");
		await writeFile(headPath, `ref: refs/heads/${branchName}\n`, "utf-8");
		return;
	}

	// 3. No local branch and zero (or multiple) matching remotes.
	throw new Error(`Branch '${branchName}' not found`);
}

/**
 * Finds a single remote that has `refs/remotes/<remote>/<branchName>`.
 * Returns `{ remoteName, commitSha }` when exactly one match exists, otherwise null.
 */
async function findRemoteBranch(
	gitDir: string,
	branchName: string,
): Promise<{ remoteName: string; commitSha: string } | null> {
	const remotesDir = join(gitDir, "refs", "remotes");
	if (!existsSync(remotesDir)) {
		return null;
	}

	const remoteNames = await readdir(remotesDir);
	let match: { remoteName: string; commitSha: string } | null = null;
	let matchCount = 0;

	for (const remoteName of remoteNames) {
		const branchRef = join(remotesDir, remoteName, branchName);
		if (!existsSync(branchRef)) {
			continue;
		}
		const sha = (await readFile(branchRef, "utf-8")).trim();
		match = { remoteName, commitSha: sha };
		matchCount += 1;
	}

	return matchCount === 1 ? match : null;
}
