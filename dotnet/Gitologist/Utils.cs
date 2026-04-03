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

                var parts = line.Split('\t');
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
            lines.Add($"{entry.Path}\t{entry.Sha}\t{entry.Mode}");
        }

        await File.WriteAllTextAsync(indexPath, string.Join('\n', lines) + '\n');
    }

    public static List<string> GetWorkingFiles(string path, IgnoreParser? gitignore = null)
    {
        var files = new List<string>();
        ScanDirectory(path, path, files, gitignore);
        return files;
    }

    private static void ScanDirectory(string basePath, string currentPath, List<string> files, IgnoreParser? gitignore)
    {
        var entries = Directory.GetFileSystemEntries(currentPath);

        foreach (var entry in entries)
        {
            var entryName = Path.GetFileName(entry);

            if (entryName == ".git")
                continue;

            var relativePath = Path.GetRelativePath(basePath, entry);
            var isDirectory = Directory.Exists(entry);

            // Check if this path is ignored
            if (gitignore != null && gitignore.IsIgnored(relativePath, isDirectory))
            {
                continue;
            }

            if (isDirectory)
            {
                ScanDirectory(basePath, entry, files, gitignore);
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
        using (var zlib = new ZLibStream(output, CompressionLevel.Optimal))
        {
            zlib.Write(bytes, 0, bytes.Length);
        }
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

    public static async Task<string> ReadObject(string gitDir, string sha)
    {
        var objectPath = Path.Combine(gitDir, "objects", sha.Substring(0, 2), sha.Substring(2));
        var compressed = await File.ReadAllBytesAsync(objectPath);
        var decompressed = Decompress(compressed);
        return Encoding.UTF8.GetString(decompressed);
    }

    public static byte[] Decompress(byte[] compressed)
    {
        using var input = new MemoryStream(compressed);
        using var output = new MemoryStream();
        using (var zlib = new ZLibStream(input, CompressionMode.Decompress))
        {
            zlib.CopyTo(output);
        }
        return output.ToArray();
    }

    public static string ExtractTreeFromCommit(string commitData)
    {
        // Git object format: "commit <size>\0<content>"
        // Find the null terminator after the header
        var nullIndex = commitData.IndexOf('\0');
        if (nullIndex == -1)
        {
            throw new InvalidOperationException("Invalid commit object: no null terminator");
        }

        // Get content after the null terminator
        var content = commitData.Substring(nullIndex + 1);
        var lines = content.Split('\n');

        foreach (var line in lines)
        {
            if (line.StartsWith("tree "))
            {
                return line.Substring(5).Trim();
            }
        }

        throw new InvalidOperationException("Invalid commit object: no tree line found");
    }

    public static List<TreeEntry> ParseTreeEntries(string treeData)
    {
        var entries = new List<TreeEntry>();
        // Git object format: "tree <size>\0<content>"
        var headerEnd = treeData.IndexOf('\0');
        if (headerEnd == -1)
        {
            return entries;
        }

        var contentStart = headerEnd + 1;

        while (contentStart < treeData.Length)
        {
            var firstSpaceIndex = treeData.IndexOf(' ', contentStart);
            if (firstSpaceIndex == -1) break;

            var secondSpaceIndex = treeData.IndexOf(' ', firstSpaceIndex + 1);
            if (secondSpaceIndex == -1) break;

            var tabIndex = treeData.IndexOf('\t', secondSpaceIndex + 1);
            if (tabIndex == -1) break;

            var entryNullIndex = treeData.IndexOf('\0', tabIndex);
            if (entryNullIndex == -1) break;

            var mode = treeData.Substring(contentStart, firstSpaceIndex - contentStart);
            var type = treeData.Substring(firstSpaceIndex + 1, secondSpaceIndex - firstSpaceIndex - 1);
            var sha = treeData.Substring(secondSpaceIndex + 1, tabIndex - secondSpaceIndex - 1);
            var path = treeData.Substring(tabIndex + 1, entryNullIndex - tabIndex - 1);

            if (type != "blob" && type != "tree")
            {
                break;
            }

            entries.Add(
                new TreeEntry
                {
                    Path = path,
                    Sha = sha,
                    Mode = mode,
                    Type = type,
                }
            );

            contentStart = entryNullIndex + 1;
        }

        return entries;
    }

    public static string ExtractContentFromBlob(string blobData)
    {
        // Git object format: "blob <size>\0<content>"
        var nullIndex = blobData.IndexOf('\0');
        if (nullIndex == -1)
        {
            throw new InvalidOperationException("Invalid blob object: no null terminator");
        }

        // Verify header starts with "blob "
        var header = blobData.Substring(0, nullIndex);
        if (!header.StartsWith("blob "))
        {
            throw new InvalidOperationException("Invalid blob object: incorrect header");
        }

        // Return content after the null terminator
        return blobData.Substring(nullIndex + 1);
    }
}
