import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

import {
	extractContentFromBlob,
	extractTreeFromCommit,
	getCurrentBranch,
	parseTreeEntries,
	readObject,
} from "./utils.ts";

export async function pull(path: string, remote?: string, branch?: string): Promise<void> {
	const gitDir = join(path, ".git");

	if (!existsSync(gitDir)) {
		throw new Error("Not a git repository");
	}

	const remoteName = remote || "origin";
	const branchName = branch || (await getCurrentBranch(gitDir));

	const remoteBranchPath = join(gitDir, "refs", "remotes", remoteName, branchName);
	if (!existsSync(remoteBranchPath)) {
		throw new Error(`Remote branch '${remoteName}/${branchName}' does not exist`);
	}

	const remoteCommitSha = (await readFile(remoteBranchPath, "utf-8")).trim();

	const localBranchPath = join(gitDir, "refs", "heads", branchName);
	if (!existsSync(localBranchPath)) {
		await mkdir(dirname(localBranchPath), { recursive: true });
	}

	await writeFile(localBranchPath, remoteCommitSha + "\n", "utf-8");

	const commitData = await readObject(gitDir, remoteCommitSha);
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
