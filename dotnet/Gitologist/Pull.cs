using Gitologist.Types;

namespace Gitologist;

public static class Pull
{
    public static async Task PullFromRemote(
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

        await Fetch.FetchFromRemote(path, remoteName);

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

        var localBranchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        if (!File.Exists(localBranchPath))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(localBranchPath)!);
        }

        await File.WriteAllTextAsync(localBranchPath, remoteCommitSha + "\n");

        var commitData = await Utils.ReadObject(gitDir, remoteCommitSha);
        var treeSha = Utils.ExtractTreeFromCommit(commitData);

        await ExtractTreeToWorkingDirectory(gitDir, path, treeSha);

        await UpdateIndex(gitDir, path, treeSha);
    }

    private static async Task ExtractTreeToWorkingDirectory(
        string gitDir,
        string workingPath,
        string treeSha
    )
    {
        await ExtractTreeRecursive(gitDir, workingPath, treeSha, "");
    }

    private static async Task ExtractTreeRecursive(
        string gitDir,
        string workingPath,
        string treeSha,
        string prefix
    )
    {
        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            var entryPath = string.IsNullOrEmpty(prefix)
                ? Path.Combine(workingPath, entry.Path)
                : Path.Combine(workingPath, prefix, entry.Path);

            if (entry.Type == "blob")
            {
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
                    newPrefix
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
}
