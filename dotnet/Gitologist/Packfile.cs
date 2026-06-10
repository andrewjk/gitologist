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
    private enum PackEntryKind
    {
        Object,
        OfsDelta,
        RefDelta
    }

    private class PackEntryType
    {
        public PackEntryKind Kind { get; set; }
        public string? ObjectType { get; set; }
        public int OfsDeltaOffset { get; set; }
        public string? RefDeltaBaseSha { get; set; }
    }

    private class RawPackEntry
    {
        public PackEntryType EntryType { get; set; } = null!;
        public byte[] Content { get; set; } = null!;
        public int PackOffset { get; set; }
    }

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

        var dataWithoutChecksum = data.Take(data.Length - 20).ToArray();

        var rawEntries = new List<RawPackEntry>();
        var offsetToIndex = new Dictionary<int, int>();
        var offset = 12;

        for (var i = 0; i < numObjects; i++)
        {
            if (offset >= dataWithoutChecksum.Length)
            {
                throw new InvalidOperationException("Invalid packfile: offset out of bounds");
            }

            var (typeNum, _, headerEndOffset) = ParseObjectHeader(dataWithoutChecksum, offset);

            var entryTypeResult = ParsePackEntryType(typeNum, dataWithoutChecksum, headerEndOffset)
                ?? throw new InvalidOperationException($"Unknown object type: {typeNum}");

            var (inflated, bytesConsumed) = DecompressStreamData(dataWithoutChecksum, entryTypeResult.DataOffset);

            rawEntries.Add(new RawPackEntry
            {
                EntryType = entryTypeResult.EntryType,
                Content = inflated,
                PackOffset = offset
            });
            offsetToIndex[offset] = rawEntries.Count - 1;
            offset = entryTypeResult.DataOffset + bytesConsumed;
        }

        var resolved = new Dictionary<int, (byte[] Content, string Type)>();

        (byte[] Content, string Type) ResolveEntry(int index)
        {
            if (resolved.TryGetValue(index, out var cached)) return cached;
            var entry = rawEntries[index];
            byte[] content;
            string objType;

            switch (entry.EntryType.Kind)
            {
                case PackEntryKind.Object:
                    content = entry.Content;
                    objType = entry.EntryType.ObjectType!;
                    break;
                case PackEntryKind.OfsDelta:
                    {
                        var basePackOffset = entry.PackOffset - entry.EntryType.OfsDeltaOffset;
                        var baseIndex = offsetToIndex[basePackOffset];
                        var base_ = ResolveEntry(baseIndex);
                        content = ApplyDelta(base_.Content, entry.Content);
                        objType = base_.Type;
                        break;
                    }
                case PackEntryKind.RefDelta:
                    {
                        int? baseIndex = null;
                        for (var j = 0; j < rawEntries.Count; j++)
                        {
                            var raw = rawEntries[j];
                            if (raw.EntryType.Kind != PackEntryKind.Object) continue;
                            var header = $"{raw.EntryType.ObjectType} {raw.Content.Length}\0";
                            var headerBytes = Encoding.UTF8.GetBytes(header);
                            var fullData = headerBytes.Concat(raw.Content).ToArray();
                            using var sha1 = SHA1.Create();
                            var hashBytes = sha1.ComputeHash(fullData);
                            var sha = Convert.ToHexString(hashBytes).ToLowerInvariant();
                            if (sha == entry.EntryType.RefDeltaBaseSha)
                            {
                                baseIndex = j;
                                break;
                            }
                        }
                        var base_ = ResolveEntry(baseIndex!.Value);
                        content = ApplyDelta(base_.Content, entry.Content);
                        objType = base_.Type;
                        break;
                    }
                default:
                    throw new InvalidOperationException("Unknown entry kind");
            }

            var result = (content, objType);
            resolved[index] = result;
            return result;
        }

        var objects = new List<PackObject>();

        for (var i = 0; i < rawEntries.Count; i++)
        {
            var entry = rawEntries[i];
            byte[] content;
            string objectType;

            if (entry.EntryType.Kind == PackEntryKind.Object)
            {
                objectType = entry.EntryType.ObjectType!;
                content = entry.Content;
            }
            else
            {
                var resolvedResult = ResolveEntry(i);
                content = resolvedResult.Content;
                objectType = resolvedResult.Type;
            }

            var objectHeader = $"{objectType} {content.Length}\0";
            var headerBytes = Encoding.UTF8.GetBytes(objectHeader);
            var fullData = headerBytes.Concat(content).ToArray();

            using var sha1_ = SHA1.Create();
            var hashBytes = sha1_.ComputeHash(fullData);
            var sha = Convert.ToHexString(hashBytes).ToLowerInvariant();

            objects.Add(new PackObject
            {
                Type = objectType,
                Sha = sha,
                Content = content
            });
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
        var remainingData = new byte[data.Length - offset];
        Array.Copy(data, offset, remainingData, 0, remainingData.Length);

        var inflated = Utils.Decompress(remainingData);

        var lo = 1;
        var hi = remainingData.Length;
        while (lo < hi)
        {
            var mid = (lo + hi) / 2;
            try
            {
                var slice = new byte[mid];
                Array.Copy(remainingData, 0, slice, 0, mid);
                var test = Utils.Decompress(slice);
                if (test.Length == inflated.Length && test.SequenceEqual(inflated))
                {
                    hi = mid;
                }
                else
                {
                    lo = mid + 1;
                }
            }
            catch
            {
                lo = mid + 1;
            }
        }

        var adler32 = ComputeAdler32(inflated);
        var adlerBytes = BitConverter.GetBytes(adler32).Reverse().ToArray();
        for (var i = lo; i <= remainingData.Length - 4; i++)
        {
            if (remainingData[i] == adlerBytes[0] &&
                remainingData[i + 1] == adlerBytes[1] &&
                remainingData[i + 2] == adlerBytes[2] &&
                remainingData[i + 3] == adlerBytes[3])
            {
                return (inflated, i + 4);
            }
        }

        return (inflated, lo);
    }

    private static uint ComputeAdler32(byte[] data)
    {
        const uint MOD = 65521;
        uint a = 1, b = 0;
        foreach (var b_ in data)
        {
            a = (a + b_) % MOD;
            b = (b + a) % MOD;
        }
        return (b << 16) | a;
    }

    private static (PackEntryType EntryType, int DataOffset)? ParsePackEntryType(int typeNum, byte[] data, int offset)
    {
        switch (typeNum)
        {
            case 1: return (new PackEntryType { Kind = PackEntryKind.Object, ObjectType = "commit" }, offset);
            case 2: return (new PackEntryType { Kind = PackEntryKind.Object, ObjectType = "tree" }, offset);
            case 3: return (new PackEntryType { Kind = PackEntryKind.Object, ObjectType = "blob" }, offset);
            case 4: return (new PackEntryType { Kind = PackEntryKind.Object, ObjectType = "tag" }, offset);
            case 6:
                {
                    var off = offset;
                    var byteVal = data[off];
                    off++;
                    var negOffset = byteVal & 0x7f;
                    while ((byteVal & 0x80) != 0)
                    {
                        byteVal = data[off];
                        off++;
                        negOffset = ((negOffset + 1) << 7) | (byteVal & 0x7f);
                    }
                    return (new PackEntryType { Kind = PackEntryKind.OfsDelta, OfsDeltaOffset = negOffset }, off);
                }
            case 7:
                {
                    if (offset + 20 > data.Length) return null;
                    var shaBytes = data.Skip(offset).Take(20).ToArray();
                    var sha = Convert.ToHexString(shaBytes).ToLowerInvariant();
                    return (new PackEntryType { Kind = PackEntryKind.RefDelta, RefDeltaBaseSha = sha }, offset + 20);
                }
            default:
                return null;
        }
    }

    private static byte[] ApplyDelta(byte[] baseData, byte[] delta)
    {
        var deltaOffset = 0;

        int ReadSize()
        {
            var size = 0;
            var shift = 0;
            while (deltaOffset < delta.Length)
            {
                var byteVal = delta[deltaOffset];
                deltaOffset++;
                size |= (byteVal & 0x7f) << shift;
                shift += 7;
                if ((byteVal & 0x80) == 0) break;
            }
            return size;
        }

        ReadSize();
        ReadSize();

        var parts = new List<byte[]>();

        while (deltaOffset < delta.Length)
        {
            var cmd = delta[deltaOffset];
            deltaOffset++;

            if ((cmd & 0x80) != 0)
            {
                var copyOffset = 0;
                var copySize = 0;

                if ((cmd & 0x01) != 0) { copyOffset = delta[deltaOffset]; deltaOffset++; }
                if ((cmd & 0x02) != 0) { copyOffset |= delta[deltaOffset] << 8; deltaOffset++; }
                if ((cmd & 0x04) != 0) { copyOffset |= delta[deltaOffset] << 16; deltaOffset++; }
                if ((cmd & 0x08) != 0) { copyOffset |= delta[deltaOffset] << 24; deltaOffset++; }

                if ((cmd & 0x10) != 0) { copySize = delta[deltaOffset]; deltaOffset++; }
                if ((cmd & 0x20) != 0) { copySize |= delta[deltaOffset] << 8; deltaOffset++; }
                if ((cmd & 0x40) != 0) { copySize |= delta[deltaOffset] << 16; deltaOffset++; }

                if (copySize == 0) copySize = 0x10000;

                var copySlice = new byte[copySize];
                Array.Copy(baseData, copyOffset, copySlice, 0, copySize);
                parts.Add(copySlice);
            }
            else if (cmd > 0)
            {
                var insertData = new byte[cmd];
                Array.Copy(delta, deltaOffset, insertData, 0, cmd);
                deltaOffset += cmd;
                parts.Add(insertData);
            }
        }

        var result = new byte[parts.Sum(p => p.Length)];
        var pos = 0;
        foreach (var part in parts)
        {
            Array.Copy(part, 0, result, pos, part.Length);
            pos += part.Length;
        }
        return result;
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

    internal static byte[] EncodeObjectHeader(int type, int size)
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
