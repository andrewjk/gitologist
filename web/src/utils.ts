import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";

import type { IndexEntry } from "./types/IndexEntry.ts";
import type { TreeEntry } from "./types/TreeEntry.ts";

export async function readObject(gitDir: string, sha: string): Promise<string> {
	const zlib = await import("node:zlib");

	const objectPath = join(gitDir, "objects", sha.slice(0, 2), sha.slice(2));
	const compressed = await readFile(objectPath);
	const decompressed = zlib.inflateSync(compressed);

	const nullIndex = decompressed.indexOf(0);
	const header = decompressed.slice(0, nullIndex).toString("utf-8");
	const content = decompressed.slice(nullIndex + 1);

	// For tree objects, we need to return binary content differently
	// Return header as string, but mark it so we know it's binary
	if (header.startsWith("tree ")) {
		// For trees, return a special format that preserves binary SHA data
		// We'll encode the binary content as hex for the string representation
		return `${header}\n${content.toString("hex")}`;
	}

	return `${header}\n${content.toString("utf-8")}`;
}

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

export async function hashFile(filePath: string): Promise<string> {
	const crypto = await import("node:crypto");
	const content = await readFile(filePath);
	const hash = crypto.createHash("sha1");
	hash.update(content);
	return hash.digest("hex");
}

export async function hashFileAsBlob(filePath: string): Promise<string> {
	const crypto = await import("node:crypto");
	const content = await readFile(filePath, "utf-8");
	const header = `blob ${content.length}\0${content}`;
	const hash = crypto.createHash("sha1");
	hash.update(header);
	return hash.digest("hex");
}

export async function getIndex(indexPath: string): Promise<Map<string, IndexEntry>> {
	const index = new Map<string, IndexEntry>();

	if (!existsSync(indexPath)) {
		return index;
	}

	try {
		const buffer = await readFile(indexPath);

		const signature = buffer.toString("ascii", 0, 4);
		if (signature !== "DIRC") {
			return index;
		}

		const numEntries = buffer.readUInt32BE(8);

		let offset = 12;

		for (let i = 0; i < numEntries; i++) {
			const ctimeSeconds = buffer.readUInt32BE(offset);
			const ctimeNanos = buffer.readUInt32BE(offset + 4);
			const mtimeSeconds = buffer.readUInt32BE(offset + 8);
			const mtimeNanos = buffer.readUInt32BE(offset + 12);
			const dev = buffer.readUInt32BE(offset + 16);
			const ino = buffer.readUInt32BE(offset + 20);
			const mode = buffer.readUInt32BE(offset + 24).toString(8);
			const uid = buffer.readUInt32BE(offset + 28);
			const gid = buffer.readUInt32BE(offset + 32);
			const size = buffer.readUInt32BE(offset + 36);

			const sha = buffer.subarray(offset + 40, offset + 60).toString("hex");

			buffer.readUInt16BE(offset + 60);

			let pathEnd = offset + 62;
			while (pathEnd < buffer.length && buffer[pathEnd] !== 0) {
				pathEnd++;
			}

			const path = buffer.toString("utf-8", offset + 62, pathEnd);

			// Calculate entry size with 8-byte alignment
			const entryLength = 62 + path.length + 1;
			const paddingLength = (8 - (entryLength % 8)) % 8;
			offset = pathEnd + 1 + paddingLength;

			index.set(path, {
				path,
				sha,
				mode,
				size,
				ctimeSeconds,
				ctimeNanos,
				mtimeSeconds,
				mtimeNanos,
				dev,
				ino,
				uid,
				gid,
			});
		}
	} catch {
		return index;
	}

	return index;
}

export async function writeIndex(indexPath: string, index: Map<string, IndexEntry>): Promise<void> {
	const entries = Array.from(index.values()).sort((a, b) => a.path.localeCompare(b.path));

	const header = Buffer.alloc(12);
	header.write("DIRC", 0, "ascii");
	header.writeUInt32BE(2, 4);
	header.writeUInt32BE(entries.length, 8);

	const entryBuffers: Buffer[] = [];

	for (const entry of entries) {
		const entryBuf = Buffer.alloc(62 + entry.path.length + 1);

		entryBuf.writeUInt32BE(entry.ctimeSeconds, 0);
		entryBuf.writeUInt32BE(entry.ctimeNanos, 4);
		entryBuf.writeUInt32BE(entry.mtimeSeconds, 8);
		entryBuf.writeUInt32BE(entry.mtimeNanos, 12);
		entryBuf.writeUInt32BE(entry.dev, 16);
		entryBuf.writeUInt32BE(entry.ino, 20);
		entryBuf.writeUInt32BE(parseInt(entry.mode, 8), 24);
		entryBuf.writeUInt32BE(entry.uid, 28);
		entryBuf.writeUInt32BE(entry.gid, 32);
		entryBuf.writeUInt32BE(entry.size, 36);

		const shaBuffer = Buffer.from(entry.sha, "hex");
		shaBuffer.copy(entryBuf, 40);

		const flags = Math.min(entry.path.length, 0xfff);
		entryBuf.writeUInt16BE(flags, 60);

		entryBuf.write(entry.path, 62, "utf-8");
		entryBuf.writeUInt8(0, 62 + entry.path.length);

		const entryLength = 62 + entry.path.length + 1;
		const paddingLength = (8 - (entryLength % 8)) % 8;
		const paddingBuf = Buffer.alloc(paddingLength);
		const paddedEntry = Buffer.concat([entryBuf, paddingBuf]);

		entryBuffers.push(paddedEntry);
	}

	const content = Buffer.concat([header, ...entryBuffers]);

	const crypto = await import("node:crypto");
	const hash = crypto.createHash("sha1");
	hash.update(content);
	const checksum = hash.digest();

	const finalBuffer = Buffer.concat([content, checksum]);

	await writeFile(indexPath, finalBuffer);
}

export async function hashObject(
	gitDir: string,
	content: string,
	type: "blob" | "tree" | "commit",
): Promise<string> {
	const crypto = await import("node:crypto");
	const zlib = await import("node:zlib");

	const header = `${type} ${content.length}\0${content}`;
	const hash = crypto.createHash("sha1");
	hash.update(header);
	const sha = hash.digest("hex");

	const objectDir = join(gitDir, "objects", sha.slice(0, 2));
	const objectPath = join(objectDir, sha.slice(2));

	if (!existsSync(objectPath)) {
		await mkdir(objectDir, { recursive: true });
		const compressed = zlib.deflateSync(Buffer.from(header));
		await writeFile(objectPath, compressed);
	}

	return sha;
}

export async function hashObjectBuffer(
	gitDir: string,
	content: Buffer,
	type: "blob" | "tree" | "commit",
): Promise<string> {
	const crypto = await import("node:crypto");
	const zlib = await import("node:zlib");

	const header = Buffer.from(`${type} ${content.length}\0`, "utf-8");
	const fullContent = Buffer.concat([header, content]);
	const hash = crypto.createHash("sha1");
	hash.update(fullContent);
	const sha = hash.digest("hex");

	const objectDir = join(gitDir, "objects", sha.slice(0, 2));
	const objectPath = join(objectDir, sha.slice(2));

	if (!existsSync(objectPath)) {
		await mkdir(objectDir, { recursive: true });
		const compressed = zlib.deflateSync(fullContent);
		await writeFile(objectPath, compressed);
	}

	return sha;
}

export function extractTreeFromCommit(commitData: string): string {
	const lines = commitData.split("\n");
	for (const line of lines) {
		if (line.startsWith("tree ")) {
			return line.slice(5);
		}
	}
	throw new Error("Invalid commit object");
}

export function parseTreeEntries(treeData: string): TreeEntry[] {
	const entries: TreeEntry[] = [];
	const lines = treeData.split("\n");
	if (lines.length < 2 || !lines[0].startsWith("tree ")) {
		return entries;
	}

	// Get the hex-encoded binary content
	const hexContent = lines.slice(1).join("\n");
	if (!hexContent) {
		return entries;
	}

	// Convert hex back to buffer
	const content = Buffer.from(hexContent, "hex");
	let offset = 0;

	while (offset < content.length) {
		// Find space after mode
		const spaceIndex = content.indexOf(0x20, offset);
		if (spaceIndex === -1) break;

		// Find null after filename
		const nullIndex = content.indexOf(0x00, spaceIndex + 1);
		if (nullIndex === -1) break;

		// Extract mode (e.g., "100644")
		const mode = content.slice(offset, spaceIndex).toString("utf-8");

		// Extract filename
		const name = content.slice(spaceIndex + 1, nullIndex).toString("utf-8");

		// Extract 20-byte SHA
		const shaStart = nullIndex + 1;
		const shaEnd = shaStart + 20;
		if (shaEnd > content.length) break;
		const sha = content.slice(shaStart, shaEnd).toString("hex");

		// Determine type from mode
		const type = mode === "040000" ? "tree" : "blob";

		entries.push({
			path: name,
			sha,
			mode,
			type,
		});

		offset = shaEnd;
	}

	return entries;
}

export function extractContentFromBlob(blobData: string): string {
	const lines = blobData.split("\n");
	const header = lines[0];

	if (!header.startsWith("blob ")) {
		throw new Error("Invalid blob object");
	}

	const contentStart = header.length + 1;
	return blobData.slice(contentStart);
}

export async function updateBranch(
	gitDir: string,
	branchName: string,
	commitSha: string,
): Promise<void> {
	const branchPath = join(gitDir, "refs", "heads", branchName);
	await mkdir(dirname(branchPath), { recursive: true });
	await writeFile(branchPath, commitSha + "\n", "utf-8");
}
