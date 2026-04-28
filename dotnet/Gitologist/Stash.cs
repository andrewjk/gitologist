using Gitologist.Types;

namespace Gitologist;

public static class Stash
{
    public static async Task<string> CreateStash(string path, string message = "WIP")
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var currentStatus = await Status.GetStatus(path);

        var headCommitSha = await Utils.GetCurrentCommit(gitDir);
        if (headCommitSha == null)
        {
            throw new InvalidOperationException("HEAD not found");
        }

        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);

        var headCommitData = await Utils.ReadObject(gitDir, headCommitSha);
        var headTreeSha = Utils.ExtractTreeFromCommit(headCommitData);
        var headTreeEntries = new Dictionary<string, string>();

        var headEntries = Utils.ParseTreeEntries(await Utils.ReadObject(gitDir, headTreeSha));
        foreach (var entry in headEntries)
        {
            headTreeEntries[entry.Path] = entry.Sha;
        }

        var hasStagedChanges = false;

        foreach (var (filePath, entry) in index)
        {
            var headSha = headTreeEntries.TryGetValue(filePath, out var sha) ? sha : null;
            if (headSha != entry.Sha)
            {
                hasStagedChanges = true;
                break;
            }
        }

        if (
            !hasStagedChanges &&
            currentStatus.Modified.Length == 0 &&
            currentStatus.Untracked.Length == 0 &&
            currentStatus.Deleted.Length == 0
        )
        {
            throw new InvalidOperationException("Nothing to stash");
        }

        foreach (var file in currentStatus.Modified)
        {
            await StageFile(path, gitDir, file, index);
        }

        foreach (var file in currentStatus.Untracked)
        {
            await StageFile(path, gitDir, file, index);
        }

        foreach (var file in currentStatus.Deleted)
        {
            index.Remove(file);
        }

        var treeSha = await Commit.CreateTree(gitDir, index);
        var stashCommitSha = await Commit.CreateCommitObject(gitDir, treeSha, message, headCommitSha);

        var stashRefPath = Path.Combine(gitDir, "refs", "stash");
        Directory.CreateDirectory(Path.GetDirectoryName(stashRefPath)!);
        await File.WriteAllTextAsync(stashRefPath, stashCommitSha + "\n");

        await ResetHard(path, gitDir, headCommitSha);

        return stashCommitSha;
    }

    private static async Task StageFile(
        string repoPath,
        string gitDir,
        string filePath,
        Dictionary<string, IndexEntry> index
    )
    {
        var fullPath = Path.Combine(repoPath, filePath);
        var content = await File.ReadAllTextAsync(fullPath);
        var hash = await Utils.HashObject(gitDir, content, "blob");
        var fileInfo = new FileInfo(fullPath);

        index[filePath] = new IndexEntry
        {
            Path = filePath,
            Sha = hash,
            Mode = "100644",
            Size = (uint)fileInfo.Length,
            CtimeSeconds = (uint)new DateTimeOffset(fileInfo.CreationTime).ToUnixTimeSeconds(),
            CtimeNanos = 0,
            MtimeSeconds = (uint)new DateTimeOffset(fileInfo.LastWriteTime).ToUnixTimeSeconds(),
            MtimeNanos = 0,
            Dev = 0,
            Ino = 0,
            Uid = 0,
            Gid = 0
        };
    }

    private static async Task ResetHard(string path, string gitDir, string commitSha)
    {
        var commitData = await Utils.ReadObject(gitDir, commitSha);
        var treeSha = Utils.ExtractTreeFromCommit(commitData);

        var entries = Directory.GetFileSystemEntries(path);

        foreach (var entry in entries)
        {
            if (Path.GetFileName(entry) == ".git")
            {
                continue;
            }

            try
            {
                if (Directory.Exists(entry))
                {
                    Directory.Delete(entry, true);
                }
                else
                {
                    File.Delete(entry);
                }
            }
            catch
            {
                // Ignore errors
            }
        }

        await RestoreTree(path, gitDir, treeSha, "");

        await UpdateIndexFromTree(gitDir, path, treeSha);
    }

    private static async Task RestoreTree(string path, string gitDir, string treeSha, string prefix)
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            var entryPath = string.IsNullOrEmpty(prefix)
                ? entry.Path
                : Path.Combine(prefix, entry.Path).Replace("\\", "/");

            if (entry.Type == "blob")
            {
                var blobData = await Utils.ReadObject(gitDir, entry.Sha);
                var content = Utils.ExtractContentFromBlob(blobData);
                var fullPath = Path.Combine(path, entryPath);
                Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
                await File.WriteAllTextAsync(fullPath, content);
            }
            else if (entry.Type == "tree")
            {
                await RestoreTree(path, gitDir, entry.Sha, entryPath);
            }
        }
    }

    private static async Task UpdateIndexFromTree(string gitDir, string workingPath, string treeSha)
    {
        var indexPath = Path.Combine(gitDir, "index");
        var index = new Dictionary<string, IndexEntry>();

        index = await UpdateIndexRecursive(gitDir, treeSha, "", index, workingPath);

        await Utils.WriteIndex(indexPath, index);
    }

    private static async Task<Dictionary<string, IndexEntry>> UpdateIndexRecursive(
        string gitDir,
        string treeSha,
        string prefix,
        Dictionary<string, IndexEntry> index,
        string workingPath
    )
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);
        var newIndex = index;

        foreach (var entry in entries)
        {
            if (entry.Type == "blob")
            {
                var blobData = await Utils.ReadObject(gitDir, entry.Sha);
                var fileContent = Utils.ExtractContentFromBlob(blobData);

                var path = string.IsNullOrEmpty(prefix)
                    ? entry.Path
                    : Path.Combine(prefix, entry.Path).Replace("\\", "/");

                var fullPath = Path.Combine(workingPath, path);
                uint size = 0;
                if (File.Exists(fullPath))
                {
                    size = (uint)new FileInfo(fullPath).Length;
                }

                newIndex[path] = new IndexEntry
                {
                    Path = path,
                    Sha = entry.Sha,
                    Mode = entry.Mode,
                    Size = size,
                    CtimeSeconds = 0,
                    CtimeNanos = 0,
                    MtimeSeconds = 0,
                    MtimeNanos = 0,
                    Dev = 0,
                    Ino = 0,
                    Uid = 0,
                    Gid = 0
                };
            }
            else if (entry.Type == "tree")
            {
                var newPrefix = string.IsNullOrEmpty(prefix)
                    ? entry.Path
                    : Path.Combine(prefix, entry.Path).Replace("\\", "/");

                newIndex = await UpdateIndexRecursive(
                    gitDir,
                    entry.Sha,
                    newPrefix,
                    newIndex,
                    workingPath
                );
            }
        }

        return newIndex;
    }
}
