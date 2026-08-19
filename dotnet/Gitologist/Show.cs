namespace Gitologist;

public static class Show
{
    public static async Task<string> ShowFile(string path, string filePath, string? commit = null)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        string commitSha;
        if (commit != null)
        {
            commitSha = commit;
        }
        else
        {
            var headSha = await Branch.GetCurrentCommit(gitDir);
            if (headSha == null)
            {
                throw new InvalidOperationException($"Path '{filePath}' does not exist in 'HEAD'");
            }
            commitSha = headSha;
        }

        var cache = new Utils.PackfileCache();

        string commitData;
        if (commit != null)
        {
            string data;
            try
            {
                data = await Utils.ReadObject(gitDir, commitSha, cache);
            }
            catch
            {
                throw new InvalidOperationException($"Commit '{commitSha}' not found");
            }
            if (!data.StartsWith("commit "))
            {
                throw new InvalidOperationException($"Commit '{commitSha}' not found");
            }
            commitData = data;
        }
        else
        {
            commitData = await Utils.ReadObject(gitDir, commitSha, cache);
        }

        var treeSha = Utils.ExtractTreeFromCommit(commitData);

        var blobSha = await ResolveBlobSha(gitDir, treeSha, filePath, cache);
        if (blobSha == null)
        {
            throw new InvalidOperationException($"Path '{filePath}' does not exist in 'HEAD'");
        }

        var blobData = await Utils.ReadObject(gitDir, blobSha, cache);
        return Utils.ExtractContentFromBlob(blobData);
    }

    private static async Task<string?> ResolveBlobSha(
        string gitDir,
        string treeSha,
        string filePath,
        Utils.PackfileCache cache
    )
    {
        var parts = filePath.Split('/');
        var currentSha = treeSha;

        for (int i = 0; i < parts.Length; i++)
        {
            var isLast = i == parts.Length - 1;
            var treeData = await Utils.ReadObject(gitDir, currentSha, cache);
            var entries = Utils.ParseTreeEntries(treeData);

            var entry = entries.FirstOrDefault(e => e.Path == parts[i]);
            if (entry == null)
            {
                return null;
            }

            if (isLast)
            {
                return entry.Type == "blob" ? entry.Sha : null;
            }

            if (entry.Type != "tree")
            {
                return null;
            }

            currentSha = entry.Sha;
        }

        return null;
    }
}
