using Gitologist.Types;

namespace Gitologist;

public static class Pull
{
public static async Task PullFromRemote(
    string path,
    string? remote = null,
    string? branch = null,
    RemoteOptions? options = null
)
{
    var gitDir = Path.Combine(path, ".git");

    if (!Directory.Exists(gitDir))
    {
        throw new InvalidOperationException("Not a git repository");
    }

    var remoteName = remote ?? "origin";
    var branchName = branch ?? await Utils.GetCurrentBranch(gitDir);

    await Fetch.FetchFromRemote(path, remoteName, options);

        var remoteBranchPath = Path.Combine(
            gitDir,
            "refs",
            "remotes",
            remoteName,
            branchName
        );
        if (!File.Exists(remoteBranchPath))
        {
            throw new InvalidOperationException(
                $"Remote branch '{remoteName}/{branchName}' does not exist"
            );
        }

        var remoteCommitSha = (await File.ReadAllTextAsync(remoteBranchPath)).Trim();
        var currentCommitSha = await Utils.GetCurrentCommit(gitDir);

        if (string.IsNullOrEmpty(currentCommitSha))
        {
            await Utils.UpdateBranch(gitDir, branchName, remoteCommitSha);
            var commitData = await Utils.ReadObject(gitDir, remoteCommitSha);
            var treeSha = Utils.ExtractTreeFromCommit(commitData);

            await ExtractTreeToWorkingDirectory(gitDir, path, treeSha, new Dictionary<string, string>());
            await UpdateIndex(gitDir, path, treeSha);
            return;
        }

        if (currentCommitSha == remoteCommitSha)
        {
            return;
        }

        var isAncestor = await IsAncestorOf(gitDir, currentCommitSha, remoteCommitSha);

        var currentTreeSha = await GetTree(gitDir, currentCommitSha);
        var currentBlobs = currentTreeSha != null
            ? await GetTreeBlobs(gitDir, currentTreeSha)
            : new Dictionary<string, string>();

        if (isAncestor)
        {
            await Utils.UpdateBranch(gitDir, branchName, remoteCommitSha);
            var commitData = await Utils.ReadObject(gitDir, remoteCommitSha);
            var treeSha = Utils.ExtractTreeFromCommit(commitData);

            await CheckForLocalChanges(gitDir, path, currentBlobs, treeSha);
            await ExtractTreeToWorkingDirectory(gitDir, path, treeSha, currentBlobs);
            await UpdateIndex(gitDir, path, treeSha);
            return;
        }

        var mergeBase = await FindMergeBase(gitDir, currentCommitSha, remoteCommitSha);

        if (mergeBase == remoteCommitSha)
        {
            return;
        }

        var mergeCommitSha = await CreateMergeCommit(
            gitDir,
            currentCommitSha,
            remoteCommitSha,
            $"Merge branch '{branchName}' of {remoteName}"
        );

        await Utils.UpdateBranch(gitDir, branchName, mergeCommitSha);
        var mergeCommitData = await Utils.ReadObject(gitDir, mergeCommitSha);
        var mergeTreeSha = Utils.ExtractTreeFromCommit(mergeCommitData);

        await CheckForLocalChanges(gitDir, path, currentBlobs, mergeTreeSha);
        await ExtractTreeToWorkingDirectory(gitDir, path, mergeTreeSha, currentBlobs);
        await UpdateIndex(gitDir, path, mergeTreeSha);
    }

    private static async Task<Dictionary<string, string>> GetTreeBlobs(
        string gitDir,
        string treeSha,
        string prefix = ""
    )
    {
        var blobs = new Dictionary<string, string>();
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            var path = string.IsNullOrEmpty(prefix) ? entry.Path : $"{prefix}/{entry.Path}";
            if (entry.Type == "blob")
            {
                blobs[path] = entry.Sha;
            }
            else if (entry.Type == "tree")
            {
                var childBlobs = await GetTreeBlobs(gitDir, entry.Sha, path);
                foreach (var childBlob in childBlobs)
                {
                    blobs[childBlob.Key] = childBlob.Value;
                }
            }
        }

        return blobs;
    }

    private static async Task CheckForLocalChanges(
        string gitDir,
        string workingPath,
        Dictionary<string, string> currentBlobs,
        string newTreeSha
    )
    {
        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);
        var newBlobs = await GetTreeBlobs(gitDir, newTreeSha);

        foreach (var (path, newSha) in newBlobs)
        {
            currentBlobs.TryGetValue(path, out var currentSha);
            
            // Only check files that will be updated (currentSha != newSha)
            if (currentSha == newSha)
            {
                continue;
            }
            
            var fullPath = Path.Combine(workingPath, path);
            if (!File.Exists(fullPath) || !index.ContainsKey(path))
            {
                continue;
            }

            var currentHash = await Utils.HashFileAsBlob(fullPath);
            var indexEntry = index[path];
            if (currentHash != indexEntry.Sha)
            {
                throw new InvalidOperationException(
                    $"Your local changes to '{path}' would be overwritten by merge. Please commit or stash them."
                );
            }
        }
    }

    private static async Task ExtractTreeToWorkingDirectory(
        string gitDir,
        string workingPath,
        string treeSha,
        Dictionary<string, string> currentBlobs
    )
    {
        await ExtractTreeRecursive(gitDir, workingPath, treeSha, "", currentBlobs);
    }

    private static async Task ExtractTreeRecursive(
        string gitDir,
        string workingPath,
        string treeSha,
        string prefix,
        Dictionary<string, string> currentBlobs
    )
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            var entryPath = string.IsNullOrEmpty(prefix)
                ? Path.Combine(workingPath, entry.Path)
                : Path.Combine(workingPath, prefix, entry.Path);

            var path = string.IsNullOrEmpty(prefix) ? entry.Path : $"{prefix}/{entry.Path}";

            if (entry.Type == "blob")
            {
                currentBlobs.TryGetValue(path, out var currentSha);
                if (currentSha == entry.Sha)
                {
                    continue;
                }

                var blobData = await Utils.ReadObject(gitDir, entry.Sha);
                var content = Utils.ExtractContentFromBlob(blobData);
                await File.WriteAllTextAsync(entryPath, content);
            }
            else if (entry.Type == "tree")
            {
                if (!Directory.Exists(entryPath))
                {
                    Directory.CreateDirectory(entryPath);
                }

                var newPrefix = string.IsNullOrEmpty(prefix)
                    ? entry.Path
                    : Path.Combine(prefix, entry.Path);

                await ExtractTreeRecursive(
                    gitDir,
                    workingPath,
                    entry.Sha,
                    newPrefix,
                    currentBlobs
                );
            }
        }
    }

    private static async Task UpdateIndex(
        string gitDir,
        string workingPath,
        string treeSha
    )
    {
        var indexPath = Path.Combine(gitDir, "index");

        var indexContent = "";
        indexContent = await UpdateIndexRecursive(
            gitDir,
            treeSha,
            "",
            indexContent
        );

        await File.WriteAllTextAsync(indexPath, indexContent + "\n");
    }

    private static async Task<string> UpdateIndexRecursive(
        string gitDir,
        string treeSha,
        string prefix,
        string indexContent
    )
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);
        var content = indexContent;

        foreach (var entry in entries)
        {
            if (entry.Type == "blob")
            {
                var blobData = await Utils.ReadObject(gitDir, entry.Sha);
                var fileContent = Utils.ExtractContentFromBlob(blobData);
                // Use git blob hash format (with "blob <size>\0" header)
                var blobHeader = $"blob {fileContent.Length}\0{fileContent}";
                var hash = Utils.HashString(blobHeader);

                var entryPath = string.IsNullOrEmpty(prefix)
                    ? entry.Path
                    : Path.Combine(prefix, entry.Path).Replace("\\", "/");

                content += $"{entryPath} {hash}\n";
            }
            else if (entry.Type == "tree")
            {
                var newPrefix = string.IsNullOrEmpty(prefix)
                    ? entry.Path
                    : Path.Combine(prefix, entry.Path).Replace("\\", "/");

                content = await UpdateIndexRecursive(
                    gitDir,
                    entry.Sha,
                    newPrefix,
                    content
                );
            }
        }

        return content;
    }

    private static async Task<bool> IsAncestorOf(
        string gitDir,
        string ancestorSha,
        string descendantSha
    )
    {
        var visited = new HashSet<string>();
        var queue = new Queue<string>();
        queue.Enqueue(descendantSha);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();

            if (current == ancestorSha)
            {
                return true;
            }

            if (visited.Contains(current))
            {
                continue;
            }
            visited.Add(current);

            var parents = await GetParents(gitDir, current);
            foreach (var parent in parents)
            {
                queue.Enqueue(parent);
            }
        }

        return false;
    }

    private static async Task<string?> FindMergeBase(string gitDir, string sha1, string sha2)
    {
        if (sha1 == sha2)
        {
            return sha1;
        }

        var ancestors1 = await GetAllAncestors(gitDir, sha1);
        var ancestors2 = await GetAllAncestors(gitDir, sha2);

        ancestors1.Add(sha1);
        ancestors2.Add(sha2);

        foreach (var ancestor in ancestors1)
        {
            if (ancestors2.Contains(ancestor))
            {
                return ancestor;
            }
        }

        return null;
    }

    private static async Task<HashSet<string>> GetAllAncestors(string gitDir, string sha)
    {
        var ancestors = new HashSet<string>();
        var queue = new Queue<string>();
        queue.Enqueue(sha);

        while (queue.Count > 0)
        {
            var current = queue.Dequeue();

            if (ancestors.Contains(current))
            {
                continue;
            }

            var parents = await GetParents(gitDir, current);
            foreach (var parent in parents)
            {
                ancestors.Add(parent);
                queue.Enqueue(parent);
            }
        }

        return ancestors;
    }

    private static async Task<List<string>> GetParents(string gitDir, string sha)
    {
        try
        {
            var commitData = await Utils.ReadObject(gitDir, sha);
            var parents = new List<string>();
            var lines = commitData.Split('\n');

            foreach (var line in lines)
            {
                if (line.StartsWith("parent "))
                {
                    parents.Add(line.Substring(7));
                }
            }

            return parents;
        }
        catch
        {
            return new List<string>();
        }
    }

    private static async Task<string?> GetTree(string gitDir, string sha)
    {
        try
        {
            var commitData = await Utils.ReadObject(gitDir, sha);
            return Utils.ExtractTreeFromCommit(commitData);
        }
        catch
        {
            return null;
        }
    }

    private static async Task<string> CreateMergeCommit(
        string gitDir,
        string parent1,
        string parent2,
        string message
    )
    {
        var treeSha = await GetTree(gitDir, parent1);

        if (string.IsNullOrEmpty(treeSha))
        {
            throw new InvalidOperationException("Could not get tree for merge commit");
        }

        var now = DateTime.Now;
        var timestamp = ((long)(now - DateTime.UnixEpoch).TotalSeconds);
        var offset = TimeZoneInfo.Local.GetUtcOffset(now).TotalMinutes * -1;
        var offsetInt = (int)offset;
        var hours = Math.Abs(offsetInt / 60).ToString().PadLeft(2, '0');
        var minutes = Math.Abs(offsetInt % 60).ToString().PadLeft(2, '0');
        var sign = offsetInt >= 0 ? "+" : "-";

        var author = $"User <user@example.com> {timestamp} {sign}{hours}{minutes}";

        var commitContent = $"tree {treeSha}\n";
        commitContent += $"parent {parent1}\n";
        commitContent += $"parent {parent2}\n";
        commitContent += $"author {author}\n";
        commitContent += $"committer {author}\n";
        commitContent += $"\n{message}\n";

        return await Utils.HashObject(gitDir, commitContent, "commit");
    }
}
