import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export async function getCurrentBranch(gitDir: string): Promise<string> {
	const headPath = join(gitDir, "HEAD");
	const headContent = (await readFile(headPath, "utf-8")).trim();

	const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
	if (match) {
		return match[1];
	}

	throw new Error("Not on a branch (detached HEAD)");
}

export async function getCurrentCommit(gitDir: string): Promise<string | null> {
	try {
		const branch = await getCurrentBranch(gitDir);
		const branchPath = join(gitDir, "refs", "heads", branch);

		if (!existsSync(branchPath)) {
			return null;
		}

		return (await readFile(branchPath, "utf-8")).trim();
	} catch {
		return null;
	}
}
