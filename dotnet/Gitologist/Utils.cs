using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.IO.Compression;
using System.Linq;
using Gitologist.Types;

namespace Gitologist;

public static class Utils
{
    public static async Task<string> HashFile(string filePath)
    {
        var content = await File.ReadAllTextAsync(filePath);
        return HashString(content);
    }

    public static async Task<string> HashFileAsBlob(string filePath)
    {
        var content = await File.ReadAllTextAsync(filePath);
        var contentBytes = Encoding.UTF8.GetBytes(content);
        var blobContent = $"blob {contentBytes.Length}\0{content}";
        return HashString(blobContent);
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
            var data = await File.ReadAllBytesAsync(indexPath);

            if (data.Length < 12)
            {
                return index;
            }

            var signature = Encoding.ASCII.GetString(data, 0, 4);
            if (signature != "DIRC")
            {
                return index;
            }

            var numEntries = BitConverter.ToUInt32(data.Skip(8).Take(4).Reverse().ToArray(), 0);

            var offset = 12;

            for (var i = 0; i < numEntries; i++)
            {
                if (offset + 62 > data.Length)
                {
                    break;
                }

                var ctimeSeconds = BitConverter.ToUInt32(data.Skip(offset).Take(4).Reverse().ToArray(), 0);
                var ctimeNanos = BitConverter.ToUInt32(data.Skip(offset + 4).Take(4).Reverse().ToArray(), 0);
                var mtimeSeconds = BitConverter.ToUInt32(data.Skip(offset + 8).Take(4).Reverse().ToArray(), 0);
                var mtimeNanos = BitConverter.ToUInt32(data.Skip(offset + 12).Take(4).Reverse().ToArray(), 0);
                var dev = BitConverter.ToUInt32(data.Skip(offset + 16).Take(4).Reverse().ToArray(), 0);
                var ino = BitConverter.ToUInt32(data.Skip(offset + 20).Take(4).Reverse().ToArray(), 0);
                var modeValue = BitConverter.ToUInt32(data.Skip(offset + 24).Take(4).Reverse().ToArray(), 0);
                var mode = Convert.ToString(modeValue, 8);
                var uid = BitConverter.ToUInt32(data.Skip(offset + 28).Take(4).Reverse().ToArray(), 0);
                var gid = BitConverter.ToUInt32(data.Skip(offset + 32).Take(4).Reverse().ToArray(), 0);
                var size = BitConverter.ToUInt32(data.Skip(offset + 36).Take(4).Reverse().ToArray(), 0);

                var shaBytes = data.Skip(offset + 40).Take(20).ToArray();
                var sha = Convert.ToHexString(shaBytes).ToLowerInvariant();

                var flags = BitConverter.ToUInt16(data.Skip(offset + 60).Take(2).Reverse().ToArray(), 0);
                var pathLength = flags & 0x0FFF;

                if (offset + 62 + pathLength > data.Length)
                {
                    break;
                }

                var path = Encoding.UTF8.GetString(data, offset + 62, pathLength);

                var entryLength = 62 + pathLength + 1;
                var paddingLength = (8 - (entryLength % 8)) % 8;
                offset += entryLength + paddingLength;

                index[path] = new IndexEntry
                {
                    Path = path,
                    Sha = sha,
                    Mode = mode,
                    Size = size,
                    CtimeSeconds = ctimeSeconds,
                    CtimeNanos = ctimeNanos,
                    MtimeSeconds = mtimeSeconds,
                    MtimeNanos = mtimeNanos,
                    Dev = dev,
                    Ino = ino,
                    Uid = uid,
                    Gid = gid
                };
            }
        }
        catch
        {
        }

        return index;
    }

    public static async Task WriteIndex(string indexPath, Dictionary<string, IndexEntry> index)
    {
        var entries = index.Values.OrderBy(e => e.Path).ToList();

        var header = new List<byte>();
        header.AddRange(Encoding.ASCII.GetBytes("DIRC"));
        header.AddRange(BitConverter.GetBytes(2).Reverse());
        header.AddRange(BitConverter.GetBytes(entries.Count).Reverse());

        var entryBuffers = new List<byte[]>();

        foreach (var entry in entries)
        {
            var entryData = new byte[62 + entry.Path.Length + 1];

            var ctimeSecondsBytes = BitConverter.GetBytes(entry.CtimeSeconds).Reverse().ToArray();
            var ctimeNanosBytes = BitConverter.GetBytes(entry.CtimeNanos).Reverse().ToArray();
            var mtimeSecondsBytes = BitConverter.GetBytes(entry.MtimeSeconds).Reverse().ToArray();
            var mtimeNanosBytes = BitConverter.GetBytes(entry.MtimeNanos).Reverse().ToArray();
            var devBytes = BitConverter.GetBytes(entry.Dev).Reverse().ToArray();
            var inoBytes = BitConverter.GetBytes(entry.Ino).Reverse().ToArray();
            var modeValue = Convert.ToUInt32(entry.Mode, 8);
            var modeBytes = BitConverter.GetBytes(modeValue).Reverse().ToArray();
            var uidBytes = BitConverter.GetBytes(entry.Uid).Reverse().ToArray();
            var gidBytes = BitConverter.GetBytes(entry.Gid).Reverse().ToArray();
            var sizeBytes = BitConverter.GetBytes(entry.Size).Reverse().ToArray();

            Array.Copy(ctimeSecondsBytes, 0, entryData, 0, 4);
            Array.Copy(ctimeNanosBytes, 0, entryData, 4, 4);
            Array.Copy(mtimeSecondsBytes, 0, entryData, 8, 4);
            Array.Copy(mtimeNanosBytes, 0, entryData, 12, 4);
            Array.Copy(devBytes, 0, entryData, 16, 4);
            Array.Copy(inoBytes, 0, entryData, 20, 4);
            Array.Copy(modeBytes, 0, entryData, 24, 4);
            Array.Copy(uidBytes, 0, entryData, 28, 4);
            Array.Copy(gidBytes, 0, entryData, 32, 4);
            Array.Copy(sizeBytes, 0, entryData, 36, 4);

            var shaBytes = Convert.FromHexString(entry.Sha);
            Array.Copy(shaBytes, 0, entryData, 40, 20);

            var flags = (ushort)Math.Min(entry.Path.Length, 0x0FFF);
            var flagsBytes = BitConverter.GetBytes(flags).Reverse().ToArray();
            Array.Copy(flagsBytes, 0, entryData, 60, 2);

            var pathBytes = Encoding.UTF8.GetBytes(entry.Path);
            Array.Copy(pathBytes, 0, entryData, 62, pathBytes.Length);
            entryData[62 + pathBytes.Length] = 0;

            var entryLength = 62 + entry.Path.Length + 1;
            var paddingLength = (8 - (entryLength % 8)) % 8;
            var padding = new byte[paddingLength];

            var paddedEntry = new byte[entryData.Length + padding.Length];
            Array.Copy(entryData, 0, paddedEntry, 0, entryData.Length);
            Array.Copy(padding, 0, paddedEntry, entryData.Length, padding.Length);

            entryBuffers.Add(paddedEntry);
        }

        var content = header.Concat(entryBuffers.SelectMany(b => b)).ToArray();

        using var sha1 = SHA1.Create();
        var checksum = sha1.ComputeHash(content);

        var finalBuffer = new byte[content.Length + checksum.Length];
        Array.Copy(content, 0, finalBuffer, 0, content.Length);
        Array.Copy(checksum, 0, finalBuffer, content.Length, checksum.Length);

        await File.WriteAllBytesAsync(indexPath, finalBuffer);
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
        var contentBytes = Encoding.UTF8.GetBytes(content);
        var header = $"{type} {contentBytes.Length}\0{content}";
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

    public static async Task<string> HashObject(string gitDir, byte[] data, string type)
    {
        var headerBytes = Encoding.UTF8.GetBytes($"{type} {data.Length}\0");
        var fullData = headerBytes.Concat(data).ToArray();
        var hash = HashBytes(fullData);
        var sha = hash;

        var objectDir = Path.Combine(gitDir, "objects", sha.Substring(0, 2));
        var objectPath = Path.Combine(objectDir, sha.Substring(2));

        if (!File.Exists(objectPath))
        {
            Directory.CreateDirectory(objectDir);
            var compressed = CompressBytes(fullData);
            await File.WriteAllBytesAsync(objectPath, compressed);
        }

        return sha;
    }

    public static string HashBytes(byte[] data)
    {
        using var sha1 = SHA1.Create();
        var hashBytes = sha1.ComputeHash(data);
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
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

    public static byte[] CompressBytes(byte[] data)
    {
        using var output = new MemoryStream();
        using (var zlib = new ZLibStream(output, CompressionLevel.Optimal))
        {
            zlib.Write(data, 0, data.Length);
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

        // Find the null byte separating header from content
        var nullIndex = Array.IndexOf(decompressed, (byte)0);
        if (nullIndex == -1)
        {
            throw new InvalidOperationException("Invalid object format: no null byte");
        }

        var header = Encoding.UTF8.GetString(decompressed, 0, nullIndex);

        // For tree objects, return hex-encoded binary content
        if (header.StartsWith("tree "))
        {
            var contentData = decompressed[(nullIndex + 1)..];
            var hexContent = Convert.ToHexString(contentData).ToLowerInvariant();
            return $"{header}\n{hexContent}";
        }

        // For blobs, preserve the null byte
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

        // Split by first newline to get header and hex content
        var lines = treeData.Split(new[] { '\n' }, 2);
        if (lines.Length < 2)
        {
            return entries;
        }

        var header = lines[0];
        if (!header.StartsWith("tree "))
        {
            return entries;
        }

        var hexContent = lines[1];
        if (string.IsNullOrEmpty(hexContent))
        {
            return entries;
        }

        // Convert hex back to bytes
        var content = Convert.FromHexString(hexContent);

        var offset = 0;
        while (offset < content.Length)
        {
            // Find space after mode
            var spaceIndex = Array.IndexOf(content, (byte)' ', offset);
            if (spaceIndex == -1 || spaceIndex < offset)
            {
                break;
            }

            // Find null after filename
            var afterSpaceIndex = spaceIndex + 1;
            var nullIndex = Array.IndexOf(content, (byte)0, afterSpaceIndex);
            if (nullIndex == -1 || nullIndex < afterSpaceIndex)
            {
                break;
            }

            // Extract mode
            var mode = Encoding.UTF8.GetString(content, offset, spaceIndex - offset);

            // Extract filename
            var nameLength = nullIndex - afterSpaceIndex;
            var name = Encoding.UTF8.GetString(content, afterSpaceIndex, nameLength);

            // Extract 20-byte SHA
            var shaStart = nullIndex + 1;
            var shaEnd = shaStart + 20;
            if (shaEnd > content.Length)
            {
                break;
            }
            var shaBytes = new byte[20];
            Array.Copy(content, shaStart, shaBytes, 0, 20);
            var sha = Convert.ToHexString(shaBytes).ToLowerInvariant();

            // Determine type from mode
            var type = mode == "040000" ? "tree" : "blob";

            entries.Add(
                new TreeEntry
                {
                    Path = name,
                    Sha = sha,
                    Mode = mode,
                    Type = type,
                }
            );

            offset = shaEnd;
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
