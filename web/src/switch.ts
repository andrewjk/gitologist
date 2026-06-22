import { existsSync } from "node:fs";
import { writeFile } from "node:fs/promises";
import { join } from "node:path";

export async function switchBranch(path: string, branchName: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const branchPath = join(gitDir, "refs", "heads", branchName);
	if (!existsSync(branchPath)) {
		throw new Error(`Branch '${branchName}' not found`);
	}

	const headPath = join(gitDir, "HEAD");
	await writeFile(headPath, `ref: refs/heads/${branchName}\n`, "utf-8");
}
