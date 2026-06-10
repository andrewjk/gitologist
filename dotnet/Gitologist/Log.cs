using System.Text.RegularExpressions;
using Gitologist.Types;

namespace Gitologist;

public static class Log
{
    public static async Task<List<LogEntry>> GetLog(string path, LogOptions? options = null)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var branchName = options?.Branch ?? await Utils.GetCurrentBranch(gitDir);
        var branchPath = Path.Combine(gitDir, "refs", "heads", branchName);

        if (!File.Exists(branchPath))
        {
            if (!string.IsNullOrEmpty(options?.Branch))
            {
                throw new InvalidOperationException($"Branch '{branchName}' not found");
            }
            return new List<LogEntry>();
        }

        var commitSha = (await File.ReadAllTextAsync(branchPath)).Trim();

        var entries = new List<LogEntry>();
        string? currentSha = commitSha;

        var limit = options?.Limit ?? int.MaxValue;

        if (!string.IsNullOrEmpty(options?.File))
        {
            var treeCache = new Dictionary<string, string?>();

            while (currentSha != null)
            {
                var entry = await ParseCommitEntry(gitDir, currentSha);
                var currentBlobSha = await GetFileBlobSha(gitDir, entry.Tree, options.File!, treeCache);

                if (entry.Parent == null)
                {
                    if (currentBlobSha != null)
                    {
                        entries.Add(entry);
                    }
                }
                else
                {
                    var parentEntry = await ParseCommitEntry(gitDir, entry.Parent);
                    var parentBlobSha = await GetFileBlobSha(gitDir, parentEntry.Tree, options.File!, treeCache);
                    if (currentBlobSha != parentBlobSha)
                    {
                        entries.Add(entry);
                    }
                }

                if (entries.Count >= limit) break;
                currentSha = entry.Parent;
            }

            return entries;
        }

        while (currentSha != null && entries.Count < limit)
        {
            var entry = await ParseCommitEntry(gitDir, currentSha);
            entries.Add(entry);
            currentSha = entry.Parent;
        }

        return entries;
    }

    private static async Task<string?> GetFileBlobSha(string gitDir, string treeSha, string filePath, Dictionary<string, string?> cache)
    {
        if (cache.ContainsKey(treeSha))
        {
            return cache[treeSha];
        }

        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var hexContent = treeData.Split('\n').Skip(1).Aggregate("", (a, b) => a + b);
        var content = Convert.FromHexString(hexContent);
        var entries = Utils.ParseTreeEntriesFromData(content);

        var parts = filePath.Split('/');
        var current = entries.FirstOrDefault(e => e.Path == parts[0]);

        if (current == null)
        {
            cache[treeSha] = null;
            return null;
        }

        for (int i = 1; i < parts.Length; i++)
        {
            if (current.Type != "tree")
            {
                cache[treeSha] = null;
                return null;
            }

            var subTreeData = await Utils.ReadObject(gitDir, current.Sha);
            var subHexContent = subTreeData.Split('\n').Skip(1).Aggregate("", (a, b) => a + b);
            var subContent = Convert.FromHexString(subHexContent);
            var subEntries = Utils.ParseTreeEntriesFromData(subContent);
            current = subEntries.FirstOrDefault(e => e.Path == parts[i]);

            if (current == null)
            {
                cache[treeSha] = null;
                return null;
            }
        }

        cache[treeSha] = current.Sha;
        return current.Sha;
    }

    private static async Task<LogEntry> ParseCommitEntry(string gitDir, string commitSha)
    {
        var commitData = await Utils.ReadObject(gitDir, commitSha);

        var tree = ExtractField(commitData, "tree") ?? "";
        var parent = ExtractField(commitData, "parent");
        var author = ExtractField(commitData, "author") ?? "";
        var committer = ExtractField(commitData, "committer") ?? "";
        var message = ExtractMessage(commitData);
        var timestamp = ExtractTimestamp(string.IsNullOrEmpty(author) ? committer : author);

        return new LogEntry
        {
            Sha = commitSha,
            AbbreviatedSha = commitSha.Substring(0, 7),
            Tree = tree,
            Parent = parent,
            Author = FormatAuthor(string.IsNullOrEmpty(author) ? committer : author),
            Committer = FormatAuthor(string.IsNullOrEmpty(committer) ? author : committer),
            Date = timestamp,
            Message = message,
        };
    }

    private static string? ExtractField(string commitData, string fieldName)
    {
        var content = commitData;
        var nullIndex = content.IndexOf('\0');
        if (nullIndex != -1)
        {
            content = content.Substring(nullIndex + 1);
        }

        var lines = content.Split('\n');
        foreach (var line in lines)
        {
            if (line.StartsWith($"{fieldName} "))
            {
                return line.Substring(fieldName.Length + 1);
            }
        }
        return null;
    }

    private static string ExtractMessage(string commitData)
    {
        var emptyLineIndex = commitData.IndexOf("\n\n", StringComparison.Ordinal);

        if (emptyLineIndex == -1)
        {
            return "";
        }

        return commitData.Substring(emptyLineIndex + 2).TrimEnd();
    }

    private static DateTime ExtractTimestamp(string author)
    {
        var match = Regex.Match(author, @"(\d+) ([+-]\d{4})$");
        if (!match.Success)
        {
            return DateTime.Now;
        }

        var timestamp = long.Parse(match.Groups[1].Value);
        return DateTimeOffset.FromUnixTimeSeconds(timestamp).UtcDateTime;
    }

    private static string FormatAuthor(string author)
    {
        var match = Regex.Match(author, @"^(.+?) (<.+>)\s+\d+");
        if (match.Success)
        {
            return match.Groups[1].Value.Trim();
        }

        return author.Trim();
    }
}
