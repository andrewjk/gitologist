using Gitologist.Types;

namespace Gitologist;

public static class Merge
{
    public static async Task<MergeResult> MergeBranch(
        string path,
        string branchName,
        MergeOptions? options = null
    )
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var cache = new Utils.PackfileCache();

        var currentBranch = await Branch.GetCurrentBranch(gitDir);
        if (currentBranch == branchName)
        {
            throw new InvalidOperationException("Cannot merge a branch into itself");
        }

        var currentSha = await Branch.GetCurrentCommit(gitDir);
        var branchSha = await GetBranchCommit(gitDir, branchName);

        if (string.IsNullOrEmpty(branchSha))
        {
            throw new InvalidOperationException($"Branch '{branchName}' not found");
        }

        if (string.IsNullOrEmpty(currentSha))
        {
            throw new InvalidOperationException("Cannot merge into an empty branch");
        }

        if (currentSha == branchSha)
        {
            return new MergeResult
            {
                Success = true,
                FastForward = false,
                Message = "Already up to date.",
            };
        }

        var isAncestor = await IsAncestorOf(gitDir, currentSha, branchSha, cache);

        if (isAncestor && !(options?.NoFastForward ?? false))
        {
            await Utils.UpdateBranch(gitDir, currentBranch, branchSha);
            return new MergeResult
            {
                Success = true,
                FastForward = true,
                CommitSha = branchSha,
                Message = $"Fast-forward merge of '{branchName}' into '{currentBranch}'",
            };
        }

        var mergeBase = await FindMergeBase(gitDir, currentSha, branchSha, cache);

        if (mergeBase == branchSha)
        {
            return new MergeResult
            {
                Success = true,
                FastForward = false,
                Message = "Already up to date.",
            };
        }

        var mergeMessage = options?.Message ?? $"Merge branch '{branchName}' into '{currentBranch}'";

        var mergeCommitSha = await CreateMergeCommit(gitDir, currentSha, branchSha, mergeMessage, cache);

        await Utils.UpdateBranch(gitDir, currentBranch, mergeCommitSha);

        return new MergeResult
        {
            Success = true,
            FastForward = false,
            CommitSha = mergeCommitSha,
            Message = mergeMessage,
        };
    }

    private static async Task<string?> GetBranchCommit(string gitDir, string branchName)
    {
        var branchPath = Path.Combine(gitDir, "refs", "heads", branchName);

        if (!File.Exists(branchPath))
        {
            return null;
        }

        return (await File.ReadAllTextAsync(branchPath)).Trim();
    }

    private static async Task<bool> IsAncestorOf(
        string gitDir,
        string ancestorSha,
        string descendantSha,
        Utils.PackfileCache cache
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

            var parents = await GetParents(gitDir, current, cache);
            foreach (var parent in parents)
            {
                queue.Enqueue(parent);
            }
        }

        return false;
    }

    private static async Task<string?> FindMergeBase(string gitDir, string sha1, string sha2, Utils.PackfileCache cache)
    {
        if (sha1 == sha2)
        {
            return sha1;
        }

        var ancestors1 = await GetAllAncestors(gitDir, sha1, cache);
        var ancestors2 = await GetAllAncestors(gitDir, sha2, cache);

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

    private static async Task<HashSet<string>> GetAllAncestors(string gitDir, string sha, Utils.PackfileCache cache)
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

            var parents = await GetParents(gitDir, current, cache);
            foreach (var parent in parents)
            {
                ancestors.Add(parent);
                queue.Enqueue(parent);
            }
        }

        return ancestors;
    }

    private static async Task<List<string>> GetParents(string gitDir, string sha, Utils.PackfileCache cache)
    {
        try
        {
            var commitData = await Utils.ReadObject(gitDir, sha, cache);
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

    private static async Task<string?> GetTree(string gitDir, string sha, Utils.PackfileCache cache)
    {
        try
        {
            var commitData = await Utils.ReadObject(gitDir, sha, cache);
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
        string message,
        Utils.PackfileCache cache
    )
    {
        var treeSha = await GetTree(gitDir, parent1, cache);

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
