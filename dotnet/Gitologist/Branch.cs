using System.Text.RegularExpressions;

namespace Gitologist;

internal static class Branch
{
    internal static async Task<string> GetCurrentBranch(string gitDir)
    {
        var headPath = Path.Combine(gitDir, "HEAD");
        var headContent = (await File.ReadAllTextAsync(headPath)).Trim();

        var match = Regex.Match(headContent, @"^ref: refs\/heads\/(.+)$");
        if (match.Success)
        {
            return match.Groups[1].Value;
        }

        throw new InvalidOperationException("Not on a branch (detached HEAD)");
    }

    internal static async Task<string?> GetCurrentCommit(string gitDir)
    {
        try
        {
            var branch = await GetCurrentBranch(gitDir);
            var branchPath = Path.Combine(gitDir, "refs", "heads", branch);

            if (!File.Exists(branchPath))
            {
                return null;
            }

            return (await File.ReadAllTextAsync(branchPath)).Trim();
        }
        catch
        {
            return null;
        }
    }
}
