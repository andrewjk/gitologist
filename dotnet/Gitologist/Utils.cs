using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.IO.Compression;
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

    public static async Task<string> HashObject(string gitDir, string content, string type)
    {
        var header = $"{type} {content.Length}\0{content}";
        var hash = HashString(header);
        var sha = hash;

        var objectDir = Path.Combine(gitDir, "objects", sha.Substring(0, 2));
        var objectPath = Path.Combine(objectDir, sha.Substring(2));

        if (!File.Exists(objectPath))
        {
            Directory.CreateDirectory(objectDir);
            var compressed = Compress(header);
            await File.WriteAllBytesAsync(objectPath, compressed);
        }

        return sha;
    }

    public static byte[] Compress(string content)
    {
        var bytes = Encoding.UTF8.GetBytes(content);
        using var output = new MemoryStream();
        using var deflate = new DeflateStream(output, CompressionLevel.Optimal);
        deflate.Write(bytes, 0, bytes.Length);
        deflate.Close();
        return output.ToArray();
    }

    public static async Task<string> GetCurrentBranch(string gitDir)
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

    public static async Task<string?> GetCurrentCommit(string gitDir)
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

    public static async Task UpdateBranch(string gitDir, string branchName, string commitSha)
    {
        var branchPath = Path.Combine(gitDir, "refs", "heads", branchName);
        Directory.CreateDirectory(Path.GetDirectoryName(branchPath)!);
        await File.WriteAllTextAsync(branchPath, commitSha + "\n");
    }
}
