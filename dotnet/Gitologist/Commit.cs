using System.Text;
using Gitologist.Types;

namespace Gitologist;

public static class Commit
{
    public static async Task<string> CreateCommit(string path, string message)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var currentStatus = await Status.GetStatus(path);

        if (
            currentStatus.Staged.Length == 0 &&
            currentStatus.Modified.Length == 0 &&
            currentStatus.Untracked.Length == 0 &&
            currentStatus.Deleted.Length == 0
        )
        {
            throw new InvalidOperationException("Nothing to commit");
        }

        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);

        if (index.Count == 0)
        {
            throw new InvalidOperationException("No files staged");
        }

        var treeSha = await CreateTree(gitDir, index);
        var parentSha = await Utils.GetCurrentCommit(gitDir);
        var commitSha = await CreateCommitObject(gitDir, treeSha, message, parentSha);

        var branchName = await Utils.GetCurrentBranch(gitDir);
        await Utils.UpdateBranch(gitDir, branchName, commitSha);

        return commitSha;
    }

    private static async Task<string> CreateTree(
        string gitDir,
        Dictionary<string, IndexEntry> index
    )
    {
        return await CreateTreeRecursive(gitDir, index, "");
    }

    private static async Task<string> CreateTreeRecursive(
        string gitDir,
        Dictionary<string, IndexEntry> index,
        string prefix
    )
    {
        var paths = index
            .Keys.Where(path =>
            {
                if (string.IsNullOrEmpty(prefix))
                {
                    return !path.Contains("/");
                }

                if (path.StartsWith(prefix + "/"))
                {
                    var remaining = path.Substring(prefix.Length + 1);
                    return !remaining.Contains("/");
                }

                return false;
            })
            .OrderBy(p => p)
            .ToList();

        var treeEntries = new List<TreeEntry>();

        foreach (var path in paths)
        {
            var entry = index[path];
            // Use the SHA from the index entry directly - it was computed during add
            treeEntries.Add(
                new TreeEntry
                {
                    Path = string.IsNullOrEmpty(prefix) ? path : path.Substring(prefix.Length + 1),
                    Sha = entry.Sha,
                    Mode = entry.Mode,
                    Type = "blob",
                }
            );
        }

        var subdirs = new Dictionary<string, List<string>>();
        foreach (var path in index.Keys)
        {
            if (path.Contains("/"))
            {
                var parts = path.Split('/');
                if (string.IsNullOrEmpty(prefix))
                {
                    var dir = parts[0];
                    if (!subdirs.ContainsKey(dir))
                    {
                        subdirs[dir] = new List<string>();
                    }

                    subdirs[dir].Add(path);
                }
                else if (path.StartsWith(prefix + "/"))
                {
                    var remaining = path.Substring(prefix.Length + 1);
                    if (remaining.Contains("/"))
                    {
                        var parts2 = remaining.Split('/');
                        var dir = parts2[0];
                        if (!subdirs.ContainsKey(dir))
                        {
                            subdirs[dir] = new List<string>();
                        }

                        subdirs[dir].Add(path);
                    }
                }
            }
        }

        foreach (var dir in subdirs.Keys)
        {
            var dirSha = await CreateTreeRecursive(
                gitDir,
                index,
                string.IsNullOrEmpty(prefix) ? dir : $"{prefix}/{dir}"
            );
            treeEntries.Add(
                new TreeEntry
                {
                    Path = dir,
                    Sha = dirSha,
                    Mode = "040000",
                    Type = "tree",
                }
            );
        }

        // Sort entries by path (Git requires this)
        treeEntries = treeEntries.OrderBy(e => e.Path).ToList();

        // Build tree content as binary data
        // Format: <mode> <name>\0<20-byte SHA> for each entry
        var treeContent = new List<byte>();
        foreach (var entry in treeEntries)
        {
            // Add mode
            treeContent.AddRange(Encoding.UTF8.GetBytes(entry.Mode));
            treeContent.Add((byte)' ');

            // Add name
            treeContent.AddRange(Encoding.UTF8.GetBytes(entry.Path));
            treeContent.Add((byte)0);

            // Add 20-byte SHA
            var shaBytes = Convert.FromHexString(entry.Sha);
            treeContent.AddRange(shaBytes);
        }

        return await Utils.HashObject(
            gitDir,
            treeContent.ToArray(),
            "tree"
        );
    }

    private static async Task<string> CreateCommitObject(
        string gitDir,
        string treeSha,
        string message,
        string? parentSha
    )
    {
        var now = DateTime.Now;
        var timestamp = ((long)(now - DateTime.UnixEpoch).TotalSeconds);
        var offset = TimeZoneInfo.Local.GetUtcOffset(now).TotalMinutes * -1;
        var offsetInt = (int)offset;
        var hours = Math.Abs(offsetInt / 60).ToString().PadLeft(2, '0');
        var minutes = Math.Abs(offsetInt % 60).ToString().PadLeft(2, '0');
        var sign = offsetInt >= 0 ? "+" : "-";

        var author =
            $"User <user@example.com> {timestamp} {sign}{hours}{minutes}";

        var commitContent = $"tree {treeSha}\n";
        if (!string.IsNullOrEmpty(parentSha))
        {
            commitContent += $"parent {parentSha}\n";
        }

        commitContent += $"author {author}\n";
        commitContent += $"committer {author}\n";
        commitContent += $"\n{message}\n";

        return await Utils.HashObject(gitDir, commitContent, "commit");
    }
}
