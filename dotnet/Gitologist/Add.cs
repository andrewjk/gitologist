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

            // Skip ignored files
            if (gitignore.IsIgnored(file))
            {
                continue;
            }

            var hash = await Utils.HashFile(fullPath);

            index[file] = new IndexEntry { Path = file, Sha = hash, Mode = "100644" };
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

        if (filesToAdd.Count == 0)
        {
            return;
        }

        await AddFiles(path, filesToAdd.ToArray());
    }
}
