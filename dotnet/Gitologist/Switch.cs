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

        var branchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        if (!File.Exists(branchPath))
        {
            throw new InvalidOperationException($"Branch '{branchName}' not found");
        }

        var headPath = Path.Combine(gitDir, "HEAD");
        await File.WriteAllTextAsync(headPath, $"ref: refs/heads/{branchName}\n");
    }
}
