using Gitologist.Types;

namespace Gitologist;

public static class Restore
{
    public static async Task RestoreFiles(string path, string[] files)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        foreach (var file in files)
        {
            var filePath = Path.Combine(path, file);

            if (!File.Exists(filePath))
            {
                throw new FileNotFoundException($"File not found: {file}");
            }
        }

        var branchPath = Path.Combine(gitDir, "refs", "heads", "main");
        var commitSha = (await File.ReadAllTextAsync(branchPath)).Trim();

        var commitData = await Utils.ReadObject(gitDir, commitSha);
        var treeSha = Utils.ExtractTreeFromCommit(commitData);

        foreach (var file in files)
        {
            var blobSha = await FindBlobInTree(gitDir, treeSha, file);
            if (blobSha == null)
            {
                throw new InvalidOperationException($"File not in commit: {file}");
            }

            var blobData = await Utils.ReadObject(gitDir, blobSha);
            var content = Utils.ExtractContentFromBlob(blobData);
            var filePath = Path.Combine(path, file);
            await File.WriteAllTextAsync(filePath, content);
        }
    }

    public static async Task RestoreAll(string path)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var currentStatus = await Status.GetStatus(path);
        var filesToRestore = currentStatus.Modified.ToList();

        if (filesToRestore.Count == 0)
        {
            return;
        }

        await RestoreFiles(path, filesToRestore.ToArray());
    }

    private static async Task<string?> FindBlobInTree(
        string gitDir,
        string treeSha,
        string filePath
    )
    {
        var parts = filePath.Split('/');
        var name = parts[0];
        var rest = parts.Skip(1).ToArray();

        var treeData = await Utils.ReadObject(gitDir, treeSha);
        var entries = Utils.ParseTreeEntries(treeData);

        foreach (var entry in entries)
        {
            if (entry.Path == name)
            {
                if (entry.Type == "blob")
                {
                    if (rest.Length == 0)
                    {
                        return entry.Sha;
                    }

                    return null;
                }

                if (entry.Type == "tree")
                {
                    if (rest.Length > 0)
                    {
                        return await FindBlobInTree(
                                gitDir,
                                entry.Sha,
                                string.Join("/", rest)
                            );
                    }

                    return null;
                }
            }
        }

        return null;
    }
}
