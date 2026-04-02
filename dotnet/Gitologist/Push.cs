using System.Text.RegularExpressions;

namespace Gitologist;

public static class Push
{
    public static async Task PushToRemote(
        string path,
        string? remote = null,
        string? branch = null
    )
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var remoteName = remote ?? "origin";
        var branchName = branch ?? await Utils.GetCurrentBranch(gitDir);

        var localBranchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        if (!File.Exists(localBranchPath))
        {
            throw new InvalidOperationException(
                $"Local branch '{branchName}' does not exist"
            );
        }

        var currentStatus = await Status.GetStatus(path);

        if (currentStatus.Modified.Length > 0 || currentStatus.Untracked.Length > 0)
        {
            throw new InvalidOperationException(
                "You have uncommitted changes. Commit or stash them before pushing."
            );
        }

        var commitSha = (await File.ReadAllTextAsync(localBranchPath)).Trim();

        var remoteBranchPath = Path.Combine(
            gitDir,
            "refs",
            "remotes",
            remoteName,
            branchName
        );
        Directory.CreateDirectory(
            Path.GetDirectoryName(remoteBranchPath)!
        );
        await File.WriteAllTextAsync(remoteBranchPath, commitSha + "\n");
    }
}
