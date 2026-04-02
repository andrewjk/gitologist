using System.Security.Cryptography;
using System.Text;
using Gitologist.Types;

namespace Gitologist;

public static class Utils
{
    public static async Task<string> HashFile(string filePath)
    {
        var content = await File.ReadAllTextAsync(filePath);
        return HashString(content);
    }

    public static string HashString(string content)
    {
        using var sha1 = SHA1.Create();
        var bytes = Encoding.UTF8.GetBytes(content);
        var hashBytes = sha1.ComputeHash(bytes);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    public static async Task<Dictionary<string, IndexEntry>> GetIndex(string indexPath)
    {
        var index = new Dictionary<string, IndexEntry>();

        if (!File.Exists(indexPath))
        {
            return index;
        }

        try
        {
            var content = await File.ReadAllTextAsync(indexPath);
            var lines = content.Trim().Split('\n');

            foreach (var line in lines)
            {
                if (string.IsNullOrWhiteSpace(line))
                    continue;

                var parts = line.Split(' ');
                if (parts.Length >= 2)
                {
                    var path = parts[0];
                    var sha = parts[1];
                    var mode = parts.Length >= 3 ? parts[2] : "100644";
                    index[path] = new IndexEntry { Path = path, Sha = sha, Mode = mode };
                }
            }
        }
        catch
        {
        }

        return index;
    }

    public static async Task WriteIndex(string indexPath, Dictionary<string, IndexEntry> index)
    {
        var lines = new List<string>();

        foreach (var entry in index.Values)
        {
            lines.Add($"{entry.Path} {entry.Sha} {entry.Mode}");
        }

        await File.WriteAllTextAsync(indexPath, string.Join('\n', lines) + '\n');
    }

    public static List<string> GetWorkingFiles(string path)
    {
        var files = new List<string>();
        ScanDirectory(path, path, files);
        return files;
    }

    private static void ScanDirectory(string basePath, string currentPath, List<string> files)
    {
        var entries = Directory.GetFileSystemEntries(currentPath);

        foreach (var entry in entries)
        {
            var entryName = Path.GetFileName(entry);

            if (entryName == ".git")
                continue;

            var relativePath = Path.GetRelativePath(basePath, entry);

            if (Directory.Exists(entry))
            {
                ScanDirectory(basePath, entry, files);
            }
            else if (File.Exists(entry))
            {
                files.Add(relativePath);
            }
        }
    }
}
