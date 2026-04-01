import { existsSync } from "node:fs";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";

interface TreeEntry {
	path: string;
	sha: string;
	mode: string;
	type: "blob" | "tree";
}

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

async function getCurrentBranch(gitDir: string): Promise<string> {
	const headPath = join(gitDir, "HEAD");
	const headContent = (await readFile(headPath, "utf-8")).trim();

	const match = headContent.match(/^ref: refs\/heads\/(.+)$/);
	if (match) {
		return match[1];
	}

	throw new Error("Not on a branch (detached HEAD)");
}

async function readObject(gitDir: string, sha: string): Promise<string> {
	const zlib = await import("node:zlib");

	const objectPath = join(gitDir, "objects", sha.slice(0, 2), sha.slice(2));
	const compressed = await readFile(objectPath);
	const decompressed = zlib.inflateSync(compressed).toString("utf-8");

	const nullIndex = decompressed.indexOf("\0");
	const header = decompressed.slice(0, nullIndex);
	const content = decompressed.slice(nullIndex + 1);

	return `${header}\n${content}`;
}

function extractTreeFromCommit(commitData: string): string {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith("tree ")) {
			return line.slice(5);
		}
	}
	throw new Error("Invalid commit object");
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

function extractContentFromBlob(blobData: string): string {
	const lines = blobData.split("\n");
	const header = lines[0];

	if (!header.startsWith("blob ")) {
		throw new Error("Invalid blob object");
	}

	const contentStart = header.length + 1;
	return blobData.slice(contentStart);
}

function parseTreeEntries(treeData: string): TreeEntry[] {
	const entries: TreeEntry[] = [];
	let contentStart = treeData.indexOf("\n") + 1;

	while (contentStart < treeData.length) {
		const firstSpaceIndex = treeData.indexOf(" ", contentStart);
		const secondSpaceIndex = treeData.indexOf(" ", firstSpaceIndex + 1);
		const tabIndex = treeData.indexOf("\t", secondSpaceIndex + 1);
		const nullIndex = treeData.indexOf("\0", tabIndex);

		if (firstSpaceIndex === -1 || secondSpaceIndex === -1 || tabIndex === -1 || nullIndex === -1) {
			break;
		}

		const mode = treeData.slice(contentStart, firstSpaceIndex);
		const type = treeData.slice(firstSpaceIndex + 1, secondSpaceIndex);
		const sha = treeData.slice(secondSpaceIndex + 1, tabIndex);
		const path = treeData.slice(tabIndex + 1, nullIndex);

		if (type !== "blob" && type !== "tree") {
			break;
		}

		entries.push({
			path,
			sha,
			mode,
			type: type as "blob" | "tree",
		});

		contentStart = nullIndex + 1;
	}

	return entries;
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
			const crypto = await import("node:crypto");
			const hash = crypto.createHash("sha1");
			hash.update(fileContent);
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
