using System.Text.RegularExpressions;
using Gitologist.Types;

namespace Gitologist;

public static class Status
{
    public static async Task<StatusInfo> GetStatus(string path)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var headPath = Path.Combine(gitDir, "HEAD");
        var branch = "";

        try
        {
            var headContent = (await File.ReadAllTextAsync(headPath)).Trim();
            var match = Regex.Match(headContent, @"^ref: refs\/heads\/(.+)$");
            if (match.Success)
            {
                branch = match.Groups[1].Value.Trim();
            }
            else
            {
                branch = "(detached HEAD)";
            }
        }
        catch
        {
            branch = "(detached HEAD)";
        }

        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);

        var staged = new List<string>();
        var modified = new List<string>();
        var untracked = new List<string>();
        var deleted = new List<string>();

        // Load gitignore patterns
        var gitignore = new IgnoreParser();
        await gitignore.LoadGitignore(path);

        var workingFiles = Utils.GetWorkingFiles(path, gitignore);

        foreach (var filePath in index.Keys)
        {
            staged.Add(filePath);
        }

        foreach (var file in workingFiles)
        {
            if (!index.ContainsKey(file))
            {
                untracked.Add(file);
            }
        }

        foreach (var (filePath, entry) in index)
        {
            var fullPath = Path.Combine(path, filePath);
            if (!File.Exists(fullPath))
            {
                deleted.Add(filePath);
            }
            else if (!Directory.Exists(fullPath))
            {
                var currentHash = await Utils.HashFileAsBlob(fullPath);
                if (entry.Sha != currentHash)
                {
                    modified.Add(filePath);
                }
            }
        }

        return new StatusInfo
        {
            Branch = branch,
            UpToDate = $"Your branch is up to date with 'origin/{branch}'.",
            Staged = staged.ToArray(),
            Modified = modified.ToArray(),
            Untracked = untracked.ToArray(),
            Deleted = deleted.ToArray(),
        };
    }
}
