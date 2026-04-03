import { existsSync } from "node:fs";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

import { status } from "./status.js";
import {
  extractContentFromBlob,
  extractTreeFromCommit,
  parseTreeEntries,
  readObject,
} from "./utils.ts";

export async function restore(path: string, files: string[]): Promise<void> {
  const gitDir = join(path, ".git");

  if (!existsSync(gitDir)) {
    throw new Error("Not a git repository");
  }

  for (const file of files) {
    const filePath = join(path, file);

    if (!existsSync(filePath)) {
      throw new Error(`File not found: ${file}`);
    }
  }

  const branchPath = join(gitDir, "refs", "heads", "main");
  const commitSha = (await readFile(branchPath, "utf-8")).trim();

  const commitData = await readObject(gitDir, commitSha);
  const treeSha = extractTreeFromCommit(commitData);

  for (const file of files) {
    const blobSha = await findBlobInTree(gitDir, treeSha, file);
    if (blobSha === null) {
      throw new Error(`File not in commit: ${file}`);
    }

    const blobData = await readObject(gitDir, blobSha);
    const content = extractContentFromBlob(blobData);
    const filePath = join(path, file);
    await writeFile(filePath, content, "utf-8");
  }
}

export async function restoreAll(path: string): Promise<void> {
  const gitDir = join(path, ".git");

  if (!existsSync(gitDir)) {
    throw new Error("Not a git repository");
  }

  const currentStatus = await status(path);
  const filesToRestore = [...currentStatus.modified];

  if (filesToRestore.length === 0) {
    return;
  }

  await restore(path, filesToRestore);
}

async function findBlobInTree(
  gitDir: string,
  treeSha: string,
  filePath: string,
): Promise<string | null> {
  const parts = filePath.split("/");
  const [name, ...rest] = parts;

  const treeData = await readObject(gitDir, treeSha);
  const entries = parseTreeEntries(treeData);

  for (const entry of entries) {
    if (entry.path === name) {
      if (entry.type === "blob") {
        if (rest.length === 0) {
          return entry.sha;
        }
        return null;
      }
      if (entry.type === "tree") {
        if (rest.length > 0) {
          return findBlobInTree(gitDir, entry.sha, rest.join("/"));
        }
        return null;
      }
    }
  }

  return null;
}
