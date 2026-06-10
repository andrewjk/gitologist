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

        var cache = new Utils.PackfileCache();

        var currentStatus = await Status.GetStatus(path);

        var headCommitSha = await Utils.GetCurrentCommit(gitDir);
        if (headCommitSha == null)
        {
            throw new InvalidOperationException("HEAD not found");
        }

        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);

        var headCommitData = await Utils.ReadObject(gitDir, headCommitSha, cache);
        var headTreeSha = Utils.ExtractTreeFromCommit(headCommitData);
        var headTreeEntries = new Dictionary<string, string>();

        var headEntries = Utils.ParseTreeEntries(await Utils.ReadObject(gitDir, headTreeSha, cache));
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

        await ResetHard(path, gitDir, headCommitSha, cache);

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

    private static async Task ResetHard(string path, string gitDir, string commitSha, Utils.PackfileCache cache)
    {
        var commitData = await Utils.ReadObject(gitDir, commitSha, cache);
        var treeSha = Utils.ExtractTreeFromCommit(commitData);

        var gitignore = new IgnoreParser();
        await gitignore.LoadGitignore(path);

        var targetEntries = await FlattenTree(gitDir, treeSha, cache: cache);

        await ResetHardRecursive(path, path, gitDir, gitignore, targetEntries, cache);

        // Create any remaining target files
        foreach (var (filePath, sha) in targetEntries)
        {
            var blobData = await Utils.ReadObject(gitDir, sha, cache);
            var content = Utils.ExtractContentFromBlob(blobData);
            var fullPath = Path.Combine(path, filePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            await File.WriteAllTextAsync(fullPath, content);
        }

        await UpdateIndexFromTree(gitDir, path, treeSha, cache);
    }

    private static async Task ResetHardRecursive(
        string repoPath,
        string currentDir,
        string gitDir,
        IgnoreParser gitignore,
        Dictionary<string, string> targetEntries,
        Utils.PackfileCache cache
    )
    {
        var entries = Directory.GetFileSystemEntries(currentDir);

        foreach (var entry in entries)
        {
            if (Path.GetFileName(entry) == ".git")
            {
                continue;
            }

            var relPath = Path.GetRelativePath(repoPath, entry).Replace("\\", "/");
            var isDir = Directory.Exists(entry);

            if (gitignore.IsIgnored(relPath, isDir))
            {
                continue;
            }

            if (isDir)
            {
                // Check if any target file is under this directory
                var hasTargetFiles = false;
                foreach (var targetPath in targetEntries.Keys)
                {
                    if (targetPath == relPath || targetPath.StartsWith(relPath + "/"))
                    {
                        hasTargetFiles = true;
                        break;
                    }
                }

                if (!hasTargetFiles)
                {
                    try
                    {
                        Directory.Delete(entry, true);
                    }
                    catch
                    {
                        // Ignore errors
                    }
                    continue;
                }

                await ResetHardRecursive(repoPath, entry, gitDir, gitignore, targetEntries, cache);
            }
            else
            {
                if (targetEntries.TryGetValue(relPath, out var targetSha))
                {
                    var currentContent = await File.ReadAllTextAsync(entry);
                    var currentHash = await Utils.HashObject(gitDir, currentContent, "blob");

                    if (currentHash != targetSha)
                    {
                        var blobData = await Utils.ReadObject(gitDir, targetSha, cache);
                        var content = Utils.ExtractContentFromBlob(blobData);
                        await File.WriteAllTextAsync(entry, content);
                    }

                    targetEntries.Remove(relPath);
                }
                else
                {
                    try
                    {
                        File.Delete(entry);
                    }
                    catch
                    {
                        // Ignore errors
                    }
                }
            }
        }
    }

    private static async Task RestoreTree(string path, string gitDir, string treeSha, string prefix, Utils.PackfileCache cache)
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha, cache);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            var entryPath = string.IsNullOrEmpty(prefix)
                ? entry.Path
                : Path.Combine(prefix, entry.Path).Replace("\\", "/");

            if (entry.Type == "blob")
            {
                var blobData = await Utils.ReadObject(gitDir, entry.Sha, cache);
                var content = Utils.ExtractContentFromBlob(blobData);
                var fullPath = Path.Combine(path, entryPath);
                Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
                await File.WriteAllTextAsync(fullPath, content);
            }
            else if (entry.Type == "tree")
            {
                await RestoreTree(path, gitDir, entry.Sha, entryPath, cache);
            }
        }
    }

    private static async Task UpdateIndexFromTree(string gitDir, string workingPath, string treeSha, Utils.PackfileCache cache)
    {
        var indexPath = Path.Combine(gitDir, "index");
        var index = new Dictionary<string, IndexEntry>();

        index = await UpdateIndexRecursive(gitDir, treeSha, "", index, workingPath, cache);

        await Utils.WriteIndex(indexPath, index);
    }

    private static async Task<Dictionary<string, IndexEntry>> UpdateIndexRecursive(
        string gitDir,
        string treeSha,
        string prefix,
        Dictionary<string, IndexEntry> index,
        string workingPath,
        Utils.PackfileCache cache
    )
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha, cache);
        var entries = Utils.ParseTreeEntries(treeData);
        var newIndex = index;

        foreach (var entry in entries)
        {
            if (entry.Type == "blob")
            {
                var blobData = await Utils.ReadObject(gitDir, entry.Sha, cache);
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
                    workingPath,
                    cache
                );
            }
        }

        return newIndex;
    }

    public static async Task Unstash(string path)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var cache = new Utils.PackfileCache();

        var stashRefPath = Path.Combine(gitDir, "refs", "stash");

        if (!File.Exists(stashRefPath))
        {
            throw new InvalidOperationException("No stash found");
        }

        var stashCommitSha = (await File.ReadAllTextAsync(stashRefPath)).Trim();

        var stashCommitData = await Utils.ReadObject(gitDir, stashCommitSha, cache);
        var stashTreeSha = Utils.ExtractTreeFromCommit(stashCommitData);

        var mergeBaseSha = ExtractParentFromCommit(stashCommitData);

        if (mergeBaseSha == null)
        {
            await RestoreTree(path, gitDir, stashTreeSha, "", cache);
            return;
        }

        var currentHeadSha = await Utils.GetCurrentCommit(gitDir);

        var mergeBaseTreeData = await Utils.ReadObject(gitDir, mergeBaseSha, cache);
        var mergeBaseTreeSha = Utils.ExtractTreeFromCommit(mergeBaseTreeData);
        var mergeBaseEntries = await FlattenTree(gitDir, mergeBaseTreeSha, cache: cache);

        var currentHeadData = currentHeadSha != null ? await Utils.ReadObject(gitDir, currentHeadSha, cache) : null;
        var currentHeadTreeSha = currentHeadData != null ? Utils.ExtractTreeFromCommit(currentHeadData) : null;
        var currentHeadEntries = currentHeadTreeSha != null ? await FlattenTree(gitDir, currentHeadTreeSha, cache: cache) : new Dictionary<string, string>();

        var stashEntries = await FlattenTree(gitDir, stashTreeSha, cache: cache);

        if (currentHeadSha == mergeBaseSha)
        {
            await RestoreTree(path, gitDir, stashTreeSha, "", cache);

            // Delete files that exist in HEAD but not in stash
            foreach (var (filePath, _) in currentHeadEntries)
            {
                if (stashEntries.ContainsKey(filePath)) continue;
                var fullPath = Path.Combine(path, filePath);
                try
                {
                    File.Delete(fullPath);
                }
                catch
                {
                    // Ignore errors
                }
            }
            return;
        }

        var mergedEntries = new Dictionary<string, string>();

        foreach (var (filePath, sha) in stashEntries)
        {
            mergeBaseEntries.TryGetValue(filePath, out var baseSha);
            var currentSha = currentHeadEntries.TryGetValue(filePath, out var cs) ? cs : null;

            if (currentSha == null || currentSha == baseSha)
            {
                mergedEntries[filePath] = sha;
                continue;
            }

            if (sha == baseSha)
            {
                mergedEntries[filePath] = currentSha;
                continue;
            }

            var baseContent = baseSha != null
                ? await ReadBlobContent(gitDir, baseSha, cache)
                : "";
            var stashContent = await ReadBlobContent(gitDir, sha, cache);
            var currentContent = await ReadBlobContent(gitDir, currentSha, cache);

            var merged = ThreeWayMerge(baseContent, stashContent, currentContent);
            var mergedSha = await Utils.HashObject(gitDir, merged, "blob");
            mergedEntries[filePath] = mergedSha;
        }

        foreach (var (filePath, sha) in currentHeadEntries)
        {
            if (mergedEntries.ContainsKey(filePath)) continue;

            if (mergeBaseEntries.TryGetValue(filePath, out var baseSha) && baseSha != sha)
            {
                mergedEntries[filePath] = sha;
            }
        }

        foreach (var (filePath, sha) in mergedEntries)
        {
            var content = await ReadBlobContent(gitDir, sha, cache);
            var fullPath = Path.Combine(path, filePath);
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            await File.WriteAllTextAsync(fullPath, content);
        }

        // Delete files that were deleted in stash and not modified in current HEAD
        foreach (var (filePath, baseSha) in mergeBaseEntries)
        {
            if (stashEntries.ContainsKey(filePath)) continue;
            if (mergedEntries.ContainsKey(filePath)) continue;

            var currentSha = currentHeadEntries.TryGetValue(filePath, out var cs) ? cs : null;
            if (currentSha == null || currentSha == baseSha)
            {
                var fullPath = Path.Combine(path, filePath);
                try
                {
                    File.Delete(fullPath);
                }
                catch
                {
                    // Ignore errors
                }
            }
        }
    }

    private static string? ExtractParentFromCommit(string commitData)
    {
        var lines = commitData.Split('\n');
        foreach (var line in lines)
        {
            if (line.StartsWith("parent "))
            {
                return line[7..];
            }
            if (string.IsNullOrEmpty(line))
            {
                break;
            }
        }
        return null;
    }

    private static async Task<Dictionary<string, string>> FlattenTree(
        string gitDir,
        string treeSha,
        string prefix = "",
        Utils.PackfileCache? cache = null
    )
    {
        var entries = new Dictionary<string, string>();
        var treeData = await Utils.ReadObject(gitDir, treeSha, cache ?? new Utils.PackfileCache());
        var treeEntries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in treeEntries)
        {
            var entryPath = string.IsNullOrEmpty(prefix) ? entry.Path : $"{prefix}/{entry.Path}";

            if (entry.Type == "blob")
            {
                entries[entryPath] = entry.Sha;
            }
            else if (entry.Type == "tree")
            {
                var subEntries = await FlattenTree(gitDir, entry.Sha, entryPath, cache);
                foreach (var (subPath, subSha) in subEntries)
                {
                    entries[subPath] = subSha;
                }
            }
        }

        return entries;
    }

    private static async Task<string> ReadBlobContent(string gitDir, string sha, Utils.PackfileCache cache)
    {
        var blobData = await Utils.ReadObject(gitDir, sha, cache);
        return Utils.ExtractContentFromBlob(blobData);
    }

    private static string ThreeWayMerge(string @base, string theirs, string ours)
    {
        var baseLines = @base.Split('\n');
        var theirsLines = theirs.Split('\n');
        var oursLines = ours.Split('\n');

        if (@base == ours) return theirs;
        if (@base == theirs) return ours;

        var baseToTheirs = DiffLines(baseLines, theirsLines);
        var baseToOurs = DiffLines(baseLines, oursLines);

        var result = new List<string>();
        var bi = 0;
        var ti = 0;
        var oi = 0;

        while (bi < baseLines.Length)
        {
            baseToTheirs.TryGetValue(bi, out var theirsChange);
            baseToOurs.TryGetValue(bi, out var oursChange);

            if (theirsChange != null && oursChange != null)
            {
                if (theirsChange.Type == "replace" && oursChange.Type == "replace")
                {
                    if (theirsChange.Lines.SequenceEqual(oursChange.Lines))
                    {
                        result.AddRange(theirsChange.Lines);
                    }
                    else
                    {
                        result.Add("<<<<<<< Updated upstream");
                        result.AddRange(oursChange.Lines);
                        result.Add("=======");
                        result.AddRange(theirsChange.Lines);
                        result.Add(">>>>>>> Stashed changes");
                    }
                }
                else if (theirsChange.Type == "delete" && oursChange.Type == "delete")
                {
                    // Both deleted
                }
                else if (theirsChange.Type == "insert" && oursChange.Type == "insert")
                {
                    if (theirsChange.Lines.SequenceEqual(oursChange.Lines))
                    {
                        result.AddRange(theirsChange.Lines);
                    }
                    else
                    {
                        result.AddRange(oursChange.Lines);
                        result.AddRange(theirsChange.Lines);
                    }
                }
                else
                {
                    result.Add("<<<<<<< Updated upstream");
                    result.AddRange(oursChange.Lines);
                    result.Add("=======");
                    result.AddRange(theirsChange.Lines);
                    result.Add(">>>>>>> Stashed changes");
                }
            }
            else if (theirsChange != null)
            {
                result.AddRange(theirsChange.Lines);
            }
            else if (oursChange != null)
            {
                result.AddRange(oursChange.Lines);
            }
            else
            {
                result.Add(baseLines[bi]);
            }

            bi++;
            ti += (theirsChange?.Skip ?? 0) + 1;
            oi += (oursChange?.Skip ?? 0) + 1;
        }

        while (ti < theirsLines.Length)
        {
            result.Add(theirsLines[ti]);
            ti++;
        }
        while (oi < oursLines.Length)
        {
            result.Add(oursLines[oi]);
            oi++;
        }

        return string.Join("\n", result);
    }

    private class DiffChange
    {
        public string Type { get; set; } = "";
        public List<string> Lines { get; set; } = new();
        public int Skip { get; set; }
    }

    private static Dictionary<int, DiffChange> DiffLines(string[] @base, string[] modified)
    {
        var changes = new Dictionary<int, DiffChange>();
        var lcs = LongestCommonSubsequence(@base, modified);

        var bi = 0;
        var mi = 0;
        var lcsIdx = 0;

        while (bi < @base.Length || mi < modified.Length)
        {
            if (lcsIdx < lcs.Count && bi < @base.Length && mi < modified.Length)
            {
                if (@base[bi] == lcs[lcsIdx] && modified[mi] == lcs[lcsIdx])
                {
                    bi++;
                    mi++;
                    lcsIdx++;
                    continue;
                }
            }

            var startBi = bi;
            while (bi < @base.Length && (lcsIdx >= lcs.Count || @base[bi] != lcs[lcsIdx]))
            {
                bi++;
            }
            var baseCount = bi - startBi;

            var startMi = mi;
            while (mi < modified.Length && (lcsIdx >= lcs.Count || modified[mi] != lcs[lcsIdx]))
            {
                mi++;
            }
            var modCount = mi - startMi;

            if (baseCount > 0 || modCount > 0)
            {
                var modLines = modified[startMi..mi].ToList();
                if (baseCount == 0 && modCount > 0)
                {
                    changes[startBi] = new DiffChange { Type = "insert", Lines = modLines, Skip = 0 };
                }
                else if (baseCount > 0 && modCount == 0)
                {
                    changes[startBi] = new DiffChange { Type = "delete", Lines = new List<string>(), Skip = baseCount - 1 };
                }
                else
                {
                    changes[startBi] = new DiffChange { Type = "replace", Lines = modLines, Skip = baseCount - 1 };
                }
            }

            if (lcsIdx < lcs.Count && bi < @base.Length && @base[bi] == lcs[lcsIdx])
            {
                bi++;
                mi++;
                lcsIdx++;
            }
        }

        return changes;
    }

    private static List<string> LongestCommonSubsequence(string[] a, string[] b)
    {
        var m = a.Length;
        var n = b.Length;
        var dp = new int[m + 1, n + 1];

        for (var i = 1; i <= m; i++)
        {
            for (var j = 1; j <= n; j++)
            {
                if (a[i - 1] == b[j - 1])
                {
                    dp[i, j] = dp[i - 1, j - 1] + 1;
                }
                else
                {
                    dp[i, j] = Math.Max(dp[i - 1, j], dp[i, j - 1]);
                }
            }
        }

        var result = new List<string>();
        var ii = m;
        var jj = n;
        while (ii > 0 && jj > 0)
        {
            if (a[ii - 1] == b[jj - 1])
            {
                result.Insert(0, a[ii - 1]);
                ii--;
                jj--;
            }
            else if (dp[ii - 1, jj] > dp[ii, jj - 1])
            {
                ii--;
            }
            else
            {
                jj--;
            }
        }

        return result;
    }
}
