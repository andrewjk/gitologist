import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

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

	const remoteBranchPath = join(gitDir, "refs", "remotes", remoteName, branchName);
	await mkdir(dirname(remoteBranchPath), { recursive: true });
	await writeFile(remoteBranchPath, commitSha + "\n", "utf-8");
}
