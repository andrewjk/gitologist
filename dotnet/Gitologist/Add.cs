using Gitologist.Types;

namespace Gitologist;

public static class Add
{
    public static async Task AddFiles(string path, string[] files)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        // Load gitignore patterns
        var gitignore = new IgnoreParser();
        await gitignore.LoadGitignore(path);

        var indexPath = Path.Combine(gitDir, "index");
        var index = await Utils.GetIndex(indexPath);

        foreach (var file in files)
        {
            var fullPath = Path.Combine(path, file);

            if (!File.Exists(fullPath))
            {
                throw new FileNotFoundException($"File not found: {file}");
            }

            if (gitignore.IsIgnored(file))
            {
                continue;
            }

            var content = await File.ReadAllTextAsync(fullPath);
            // Write blob object to .git/objects and get hash
            var hash = await Utils.HashObject(gitDir, content, "blob");
            var fileInfo = new FileInfo(fullPath);

            var ctimeSeconds = (uint)fileInfo.CreationTime.ToUniversalTime().Subtract(DateTime.UnixEpoch).TotalSeconds;
            var ctimeNanos = (uint)((fileInfo.CreationTime.ToUniversalTime().Subtract(DateTime.UnixEpoch).TotalSeconds % 1) * 1_000_000_000);
            var mtimeSeconds = (uint)fileInfo.LastWriteTime.ToUniversalTime().Subtract(DateTime.UnixEpoch).TotalSeconds;
            var mtimeNanos = (uint)((fileInfo.LastWriteTime.ToUniversalTime().Subtract(DateTime.UnixEpoch).TotalSeconds % 1) * 1_000_000_000);

            var normalizedFile = file.Replace('\\', '/');
            index[normalizedFile] = new IndexEntry
            {
                Path = normalizedFile,
                Sha = hash,
                Mode = "100644",
                Size = (uint)fileInfo.Length,
                CtimeSeconds = ctimeSeconds,
                CtimeNanos = ctimeNanos,
                MtimeSeconds = mtimeSeconds,
                MtimeNanos = mtimeNanos,
                Dev = 0,
                Ino = 0,
                Uid = 0,
                Gid = 0
            };
        }

        await Utils.WriteIndex(indexPath, index);
    }

    public static async Task AddAll(string path)
    {
        var gitDir = Path.Combine(path, ".git");

        if (!Directory.Exists(gitDir))
        {
            throw new InvalidOperationException("Not a git repository");
        }

        var currentStatus = await Status.GetStatus(path);
        var filesToAdd = new List<string>();
        filesToAdd.AddRange(currentStatus.Untracked);
        filesToAdd.AddRange(currentStatus.Modified);

        if (filesToAdd.Count > 0)
        {
            await AddFiles(path, filesToAdd.ToArray());
        }

        if (currentStatus.Deleted.Length > 0)
        {
            var indexPath = Path.Combine(gitDir, "index");
            var index = await Utils.GetIndex(indexPath);
            foreach (var file in currentStatus.Deleted)
            {
                index.Remove(file);
            }
            await Utils.WriteIndex(indexPath, index);
        }
    }
}
