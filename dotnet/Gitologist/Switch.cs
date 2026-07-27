namespace Gitologist;

public static class Switch
{
    public static async Task SwitchBranch(string path, string branchName)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var cache = new Utils.PackfileCache();

        // 1. Local branch exists: check out its tree, then point HEAD at it.
        var localBranchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        if (File.Exists(localBranchPath))
        {
            var commitSha = (await File.ReadAllTextAsync(localBranchPath)).Trim();

            // Check out the tree first (uses the current HEAD as the baseline for
            // change detection); only move HEAD once the checkout succeeds.
            await Pull.CheckoutTree(gitDir, path, commitSha, cache);

            var headPath = Path.Combine(gitDir, "HEAD");
            await File.WriteAllTextAsync(headPath, $"ref: refs/heads/{branchName}\n");
            return;
        }

        // 2. DWIM: no local branch, but exactly one remote tracking branch exists.
        var dwim = FindRemoteBranch(gitDir, branchName);
        if (dwim != null)
        {
            var (remoteName, commitSha) = dwim.Value;

            await Utils.UpdateBranch(gitDir, branchName, commitSha);
            await Push.SetUpstreamBranch(path, remoteName, branchName);

            await Pull.CheckoutTree(gitDir, path, commitSha, cache);

            var headPath = Path.Combine(gitDir, "HEAD");
            await File.WriteAllTextAsync(headPath, $"ref: refs/heads/{branchName}\n");
            return;
        }

        // 3. No local branch and zero (or multiple) matching remotes.
        throw new InvalidOperationException($"Branch '{branchName}' not found");
    }

    /// <summary>
    /// Finds a single remote that has <c>refs/remotes/&lt;remote&gt;/&lt;branchName&gt;</c>.
    /// Returns <c>(remoteName, commitSha)</c> when exactly one match exists, otherwise null.
    /// </summary>
    private static (string remoteName, string commitSha)? FindRemoteBranch(string gitDir, string branchName)
    {
        var remotesDir = Path.Combine(gitDir, "refs", "remotes");
        if (!Directory.Exists(remotesDir))
        {
            return null;
        }

        (string remoteName, string commitSha)? match = null;
        var matchCount = 0;

        foreach (var remoteDir in Directory.GetDirectories(remotesDir))
        {
            var branchRef = Path.Combine(remoteDir, branchName);
            if (!File.Exists(branchRef))
            {
                continue;
            }
            var sha = File.ReadAllText(branchRef).Trim();
            match = (Path.GetFileName(remoteDir), sha);
            matchCount++;
        }

        return matchCount == 1 ? match : null;
    }
}
