using Microsoft.VisualStudio.TestTools.UnitTesting;
using System.Security.Cryptography;
using System.Text;

namespace Gitologist.Tests;

[TestClass]
public class PackfileTests
{
    [TestMethod]
    public void ShouldCreatePackfileWithBlobObject()
    {
        var blobContent = Encoding.UTF8.GetBytes("hello world");
        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "blob",
                Sha = "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
                Content = blobContent
            }
        };

        var packfile = Packfile.CreatePackfile(objects);

        var signature = Encoding.ASCII.GetString(packfile, 0, 4);
        Assert.AreEqual("PACK", signature);

        var version = BitConverter.ToInt32(packfile.Skip(4).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(2, version);

        var numObjects = BitConverter.ToInt32(packfile.Skip(8).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(1, numObjects);

        Assert.IsTrue(packfile.Length > 12);
    }

    [TestMethod]
    public void ShouldCreatePackfileWithMultipleObjects()
    {
        var treeContent = new List<byte>();
        treeContent.AddRange(Encoding.UTF8.GetBytes("100644 file.txt"));
        treeContent.Add(0x00);
        treeContent.AddRange(Encoding.UTF8.GetBytes("b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0"));

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "blob",
                Sha = "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
                Content = Encoding.UTF8.GetBytes("hello world")
            },
            new PackObject
            {
                Type = "blob",
                Sha = "8d0e41234f23b8da1c8cc8e5a6d5da1b5c5e1234",
                Content = Encoding.UTF8.GetBytes("another file")
            },
            new PackObject
            {
                Type = "tree",
                Sha = "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
                Content = treeContent.ToArray()
            }
        };

        var packfile = Packfile.CreatePackfile(objects);

        var numObjects = BitConverter.ToInt32(packfile.Skip(8).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(3, numObjects);
    }

    [TestMethod]
    public void ShouldCreatePackfileWithCommitObject()
    {
        var commitContent = Encoding.UTF8.GetBytes(
            "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n" +
            "author Test <test@example.com> 1234567890 +0000\n" +
            "committer Test <test@example.com> 1234567890 +0000\n" +
            "\n" +
            "Initial commit\n"
        );

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "commit",
                Sha = "c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0",
                Content = commitContent
            }
        };

        var packfile = Packfile.CreatePackfile(objects);

        var signature = Encoding.ASCII.GetString(packfile, 0, 4);
        Assert.AreEqual("PACK", signature);

        var version = BitConverter.ToInt32(packfile.Skip(4).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(2, version);

        var numObjects = BitConverter.ToInt32(packfile.Skip(8).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(1, numObjects);
    }

    [TestMethod]
    public void ShouldCreatePackfileWithTagObject()
    {
        var tagContent = Encoding.UTF8.GetBytes(
            "object c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0\n" +
            "type commit\n" +
            "tag v1.0.0\n" +
            "tagger Test <test@example.com> 1234567890 +0000\n" +
            "\n" +
            "Version 1.0.0\n"
        );

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "tag",
                Sha = "a1b2c3d4e5f6789012345678901234567890abcd",
                Content = tagContent
            }
        };

        var packfile = Packfile.CreatePackfile(objects);

        var signature = Encoding.ASCII.GetString(packfile, 0, 4);
        Assert.AreEqual("PACK", signature);

        var version = BitConverter.ToInt32(packfile.Skip(4).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(2, version);

        var numObjects = BitConverter.ToInt32(packfile.Skip(8).Take(4).Reverse().ToArray(), 0);
        Assert.AreEqual(1, numObjects);
    }

    [TestMethod]
    public void ShouldIncludeValidChecksumAtEnd()
    {
        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "blob",
                Sha = "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
                Content = Encoding.UTF8.GetBytes("hello world")
            }
        };

        var packfile = Packfile.CreatePackfile(objects);

        Assert.IsTrue(packfile.Length > 12);

        var dataWithoutChecksum = packfile.Take(packfile.Length - 20).ToArray();
        var checksum = packfile.Skip(packfile.Length - 20).Take(20).ToArray();

        using var sha1 = SHA1.Create();
        var expectedChecksum = sha1.ComputeHash(dataWithoutChecksum);

        CollectionAssert.AreEqual(expectedChecksum, checksum);
    }

    [TestMethod]
    public void ShouldThrowErrorForInvalidPackfileSignature()
    {
        var invalidPackfile = Encoding.ASCII.GetBytes("INVALID");

        Assert.ThrowsException<InvalidOperationException>(() => Packfile.ParsePackfile(invalidPackfile));
    }

    [TestMethod]
    public void ShouldThrowErrorForUnsupportedPackfileVersion()
    {
        var buffer = new byte[12];
        Array.Copy(Encoding.ASCII.GetBytes("PACK"), 0, buffer, 0, 4);
        var versionBytes = BitConverter.GetBytes(99).Reverse().ToArray();
        Array.Copy(versionBytes, 0, buffer, 4, 4);

        Assert.ThrowsException<InvalidOperationException>(() => Packfile.ParsePackfile(buffer));
    }

    [TestMethod]
    public void ShouldEncodeAndDecodePktLine()
    {
        var line = "hello world";
        var encoded = Packfile.EncodePktLine(line);
        var decoded = Packfile.DecodePktLines(encoded);

        CollectionAssert.AreEqual(new[] { line }, decoded);
    }

    [TestMethod]
    public void ShouldEncodeAndDecodeNullPktLine()
    {
        var encoded = Packfile.EncodePktLine(null);
        var decoded = Packfile.DecodePktLines(encoded);

        // Null pkt-line is a flush packet, which may or may not be included in decoded output
        Assert.IsTrue(decoded.Count == 0 || decoded.SequenceEqual(new[] { "" }));
    }

    [TestMethod]
    public void ShouldEncodeAndDecodeMultiplePktLines()
    {
        var lines = new[] { "first line", "second line", "third line" };
        var encoded = lines.SelectMany(line => Packfile.EncodePktLine(line)).ToArray();
        var decoded = Packfile.DecodePktLines(encoded);

        CollectionAssert.AreEqual(lines, decoded);
    }

    [TestMethod]
    public void ShouldHandleEmptyStringPktLine()
    {
        var line = "";
        var encoded = Packfile.EncodePktLine(line);
        var decoded = Packfile.DecodePktLines(encoded);

        CollectionAssert.AreEqual(new[] { line }, decoded);
    }

    [TestMethod]
    public void ShouldReturnCorrectTypeForCommit()
    {
        // This is tested indirectly through packfile creation and parsing
        // The GetObjectType method is private, but the integration tests verify it works
        var commitContent = Encoding.UTF8.GetBytes(
            "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n" +
            "author Test <test@example.com> 1234567890 +0000\n" +
            "committer Test <test@example.com> 1234567890 +0000\n" +
            "\n" +
            "Test commit\n"
        );

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "commit",
                Sha = "c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0",
                Content = commitContent
            }
        };

        var packfile = Packfile.CreatePackfile(objects);
        var parsedObjects = Packfile.ParsePackfile(packfile);

        Assert.AreEqual(1, parsedObjects.Count);
        Assert.AreEqual("commit", parsedObjects[0].Type);
    }

    [TestMethod]
    public void ShouldReturnCorrectTypeForTree()
    {
        var treeContent = new List<byte>();
        treeContent.AddRange(Encoding.UTF8.GetBytes("100644 file.txt"));
        treeContent.Add(0x00);
        treeContent.AddRange(Encoding.UTF8.GetBytes("b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0"));

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "tree",
                Sha = "4b825dc642cb6eb9a060e54bf8d69288fbee4904",
                Content = treeContent.ToArray()
            }
        };

        var packfile = Packfile.CreatePackfile(objects);
        var parsedObjects = Packfile.ParsePackfile(packfile);

        Assert.AreEqual(1, parsedObjects.Count);
        Assert.AreEqual("tree", parsedObjects[0].Type);
    }

    [TestMethod]
    public void ShouldReturnCorrectTypeForBlob()
    {
        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "blob",
                Sha = "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0",
                Content = Encoding.UTF8.GetBytes("hello world")
            }
        };

        var packfile = Packfile.CreatePackfile(objects);
        var parsedObjects = Packfile.ParsePackfile(packfile);

        Assert.AreEqual(1, parsedObjects.Count);
        Assert.AreEqual("blob", parsedObjects[0].Type);
    }

    [TestMethod]
    public void ShouldReturnCorrectTypeForTag()
    {
        var tagContent = Encoding.UTF8.GetBytes(
            "object c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0\n" +
            "type commit\n" +
            "tag v1.0.0\n" +
            "tagger Test <test@example.com> 1234567890 +0000\n" +
            "\n" +
            "Version 1.0.0\n"
        );

        var objects = new List<PackObject>
        {
            new PackObject
            {
                Type = "tag",
                Sha = "a1b2c3d4e5f6789012345678901234567890abcd",
                Content = tagContent
            }
        };

        var packfile = Packfile.CreatePackfile(objects);
        var parsedObjects = Packfile.ParsePackfile(packfile);

        Assert.AreEqual(1, parsedObjects.Count);
        Assert.AreEqual("tag", parsedObjects[0].Type);
    }

    [TestMethod]
    public void ShouldThrowErrorForUnknownType()
    {
        // Create a minimal packfile with an invalid type
        var packfile = new List<byte>();
        packfile.AddRange(Encoding.ASCII.GetBytes("PACK"));

        var version = BitConverter.GetBytes((uint)2).Reverse().ToArray();
        packfile.AddRange(version);

        var numObjects = BitConverter.GetBytes((uint)1).Reverse().ToArray();
        packfile.AddRange(numObjects);

        // Object header with invalid type (5)
        packfile.Add(unchecked((byte)((5 << 4) | 0))); // type=5, size=0

        // Empty compressed content
        var emptyCompressed = Utils.CompressBytes(Array.Empty<byte>());
        packfile.AddRange(emptyCompressed);

        // Checksum (20 bytes of zeros)
        packfile.AddRange(new byte[20]);

        Assert.ThrowsException<InvalidOperationException>(() => Packfile.ParsePackfile(packfile.ToArray()));
    }
}
