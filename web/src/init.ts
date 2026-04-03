import { existsSync } from "node:fs";
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";

const HEAD_FILE = "ref: refs/heads/main\n";
const CONFIG_FILE = `[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
`;

export async function init(path: string): Promise<void> {
  const gitDir = join(path, ".git");

  if (existsSync(gitDir)) {
    return;
  }

  await mkdir(join(gitDir, "objects"), { recursive: true });
  await mkdir(join(gitDir, "refs", "heads"), { recursive: true });
  await mkdir(join(gitDir, "refs", "tags"), { recursive: true });
  await mkdir(join(gitDir, "info"), { recursive: true });

  await writeFile(join(gitDir, "HEAD"), HEAD_FILE);
  await writeFile(join(gitDir, "config"), CONFIG_FILE);
  await writeFile(
    join(gitDir, "description"),
    "Unnamed repository; edit this file 'description' to name the repository.\n",
  );
}
