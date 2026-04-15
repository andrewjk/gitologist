using System.Security.Cryptography;
using System.Text;
using System.IO.Compression;

namespace Gitologist;

public class PackObject
{
    public string Type { get; set; } = null!;
    public string Sha { get; set; } = null!;
    public byte[] Content { get; set; } = null!;
}

public static class Packfile
{
    public static byte[] EncodePktLine(string? line)
    {
        if (line == null)
        {
            return Encoding.UTF8.GetBytes("0000");
        }

        var length = Encoding.UTF8.GetByteCount(line) + 4;
        var hexLength = length.ToString("x4");
        if (length == 4)
        {
            return Encoding.UTF8.GetBytes(hexLength);
        }

        var hexBytes = Encoding.UTF8.GetBytes(hexLength);
        var lineBytes = Encoding.UTF8.GetBytes(line);

        var result = new byte[hexBytes.Length + lineBytes.Length];
        Array.Copy(hexBytes, 0, result, 0, hexBytes.Length);
        Array.Copy(lineBytes, 0, result, hexBytes.Length, lineBytes.Length);

        return result;
    }

    public static List<string> DecodePktLines(byte[] data)
    {
        var lines = new List<string>();
        var offset = 0;

        while (offset < data.Length)
        {
            if (offset + 4 > data.Length)
            {
                break;
            }

            var hexLength = Encoding.UTF8.GetString(data, offset, 4);
            if (hexLength == "0000")
            {
                lines.Add("");
                offset += 4;
                continue;
            }

            if (!int.TryParse(hexLength, System.Globalization.NumberStyles.HexNumber, null, out var length))
            {
                break;
            }

            if (length == 0 || length > data.Length - offset)
            {
                break;
            }

            var line = Encoding.UTF8.GetString(data, offset + 4, length - 4);
            lines.Add(line);
            offset += length;
        }

        return lines;
    }

    public static List<PackObject> ParsePackfile(byte[] data)
    {
        var signature = Encoding.ASCII.GetString(data, 0, 4);
        if (signature != "PACK")
        {
            throw new InvalidOperationException("Invalid packfile signature");
        }

        var version = BitConverter.ToInt32(data.Skip(4).Take(4).Reverse().ToArray(), 0);
        if (version != 2)
        {
            throw new InvalidOperationException($"Unsupported packfile version: {version}");
        }

        var numObjects = BitConverter.ToInt32(data.Skip(8).Take(4).Reverse().ToArray(), 0);

        // Exclude checksum (last 20 bytes) from parsing
        var dataWithoutChecksum = data.Take(data.Length - 20).ToArray();

        var objects = new List<PackObject>();
        var offset = 12;

        for (var i = 0; i < numObjects; i++)
        {
            if (offset >= dataWithoutChecksum.Length)
            {
                throw new InvalidOperationException("Invalid packfile: offset out of bounds");
            }

            var (type, _, newOffset) = ParseObjectHeader(dataWithoutChecksum, offset);
            offset = newOffset;

            var (inflated, bytesConsumed) = DecompressStreamData(dataWithoutChecksum, offset);

            var objectType = GetObjectType(type);
            var objectHeader = $"{objectType} {inflated.Length}\0";
            var headerBytes = Encoding.UTF8.GetBytes(objectHeader);
            var fullData = headerBytes.Concat(inflated).ToArray();

            using var sha1 = SHA1.Create();
            var hashBytes = sha1.ComputeHash(fullData);
            var sha = Convert.ToHexString(hashBytes).ToLowerInvariant();

            objects.Add(new PackObject
            {
                Type = objectType,
                Sha = sha,
                Content = inflated
            });

            offset += bytesConsumed;
        }

        return objects;
    }

    private static (int type, int size, int newOffset) ParseObjectHeader(byte[] data, int offset)
    {
        var byteVal = data[offset];
        var type = (byteVal >> 4) & 0x07;
        var size = byteVal & 0x0f;
        var shift = 4;
        var currentOffset = offset + 1;

        while ((byteVal & 0x80) != 0)
        {
            byteVal = data[currentOffset];
            size |= (byteVal & 0x7f) << shift;
            shift += 7;
            currentOffset++;

            if ((byteVal & 0x80) == 0)
            {
                break;
            }
        }

        return (type, size, currentOffset);
    }

    private static (byte[] decompressed, int bytesConsumed) DecompressStreamData(byte[] data, int offset)
    {
        using var input = new MemoryStream(data, offset, data.Length - offset);
        using var output = new MemoryStream();
        using var zlib = new ZLibStream(input, CompressionMode.Decompress);

        zlib.CopyTo(output);
        var decompressed = output.ToArray();

        // In a real streaming implementation, we would track bytes consumed
        // For now, we'll return the entire remaining data as consumed
        var bytesConsumed = data.Length - offset;

        return (decompressed, bytesConsumed);
    }

    private static string GetObjectType(int typeNum)
    {
        return typeNum switch
        {
            1 => "commit",
            2 => "tree",
            3 => "blob",
            4 => "tag",
            _ => throw new InvalidOperationException($"Unknown object type: {typeNum}")
        };
    }

    private static int GetTypeNumber(string type)
    {
        return type switch
        {
            "commit" => 1,
            "tree" => 2,
            "blob" => 3,
            "tag" => 4,
            _ => throw new InvalidOperationException($"Unknown object type: {type}")
        };
    }

    public static byte[] CreatePackfile(List<PackObject> objects)
    {
        var version = BitConverter.GetBytes(2).Reverse().ToArray();
        var numObjects = BitConverter.GetBytes(objects.Count).Reverse().ToArray();

        var objectBuffers = new List<byte[]>();

        foreach (var obj in objects)
        {
            var typeNum = GetTypeNumber(obj.Type);
            var header = EncodeObjectHeader(typeNum, obj.Content.Length);
            var compressed = Utils.CompressBytes(obj.Content);
            objectBuffers.Add(header.Concat(compressed).ToArray());
        }

        var packfile = new List<byte>();
        packfile.AddRange(Encoding.ASCII.GetBytes("PACK"));
        packfile.AddRange(version);
        packfile.AddRange(numObjects);
        foreach (var buffer in objectBuffers)
        {
            packfile.AddRange(buffer);
        }

        using var sha1 = SHA1.Create();
        var checksum = sha1.ComputeHash(packfile.ToArray());
        packfile.AddRange(checksum);

        return packfile.ToArray();
    }

    private static byte[] EncodeObjectHeader(int type, int size)
    {
        var bytes = new List<byte>();
        var byteVal = (type << 4) | (size & 0x0f);
        var sizeRemaining = size >> 4;

        while (sizeRemaining > 0)
        {
            bytes.Add((byte)(byteVal | 0x80));
            byteVal = sizeRemaining & 0x7f;
            sizeRemaining >>= 7;
        }

        bytes.Add((byte)byteVal);

        return bytes.ToArray();
    }
}
