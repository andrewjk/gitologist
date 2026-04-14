const std = @import("std");

const packfile = @import("gitologist").packfile;

test "should create packfile with blob object" {
    const allocator = std.testing.allocator;

    const blob_content = "hello world";
    const blob_sha = "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0";

    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const obj_type = try allocator.dupe(u8, "blob");
    const sha = try allocator.dupe(u8, blob_sha);
    const content = try allocator.dupe(u8, blob_content);

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const result = try packfile.createPackfile(allocator, objects);
    defer allocator.free(result);

    try std.testing.expect(result.len > 12);
    try std.testing.expect(std.mem.eql(u8, result[0..4], "PACK"));

    const version = std.mem.readInt(u32, result[4..8], .big);
    try std.testing.expect(version == 2);

    const num_objects = std.mem.readInt(u32, result[8..12], .big);
    try std.testing.expect(num_objects == 1);
}

test "should create packfile with multiple objects" {
    const allocator = std.testing.allocator;

    var tree_content = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer tree_content.deinit(allocator);

    try tree_content.appendSlice(allocator, "100644 file.txt");
    try tree_content.append(allocator, 0);
    try tree_content.appendSlice(allocator, "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0");

    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const obj_type1 = try allocator.dupe(u8, "blob");
    const sha1 = try allocator.dupe(u8, "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0");
    const content1 = try allocator.dupe(u8, "hello world");

    try objects.append(allocator, .{
        .obj_type = obj_type1,
        .sha = sha1,
        .content = content1,
    });

    const obj_type2 = try allocator.dupe(u8, "blob");
    const sha2 = try allocator.dupe(u8, "8d0e41234f23b8da1c8cc8e5a6d5da1b5c5e1234");
    const content2 = try allocator.dupe(u8, "another file");

    try objects.append(allocator, .{
        .obj_type = obj_type2,
        .sha = sha2,
        .content = content2,
    });

    const obj_type3 = try allocator.dupe(u8, "tree");
    const sha3 = try allocator.dupe(u8, "4b825dc642cb6eb9a060e54bf8d69288fbee4904");
    const content3 = try allocator.dupe(u8, tree_content.items);

    try objects.append(allocator, .{
        .obj_type = obj_type3,
        .sha = sha3,
        .content = content3,
    });

    const result = try packfile.createPackfile(allocator, objects);
    defer allocator.free(result);

    const num_objects = std.mem.readInt(u32, result[8..12], .big);
    try std.testing.expect(num_objects == 3);
}

test "should create packfile with commit object" {
    const allocator = std.testing.allocator;

    const commit_content = "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\n" ++
        "author Test <test@example.com> 1234567890 +0000\n" ++
        "committer Test <test@example.com> 1234567890 +0000\n" ++
        "\n" ++
        "Initial commit\n";

    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const obj_type = try allocator.dupe(u8, "commit");
    const sha = try allocator.dupe(u8, "c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0");
    const content = try allocator.dupe(u8, commit_content);

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const result = try packfile.createPackfile(allocator, objects);
    defer allocator.free(result);

    try std.testing.expect(std.mem.eql(u8, result[0..4], "PACK"));

    const version = std.mem.readInt(u32, result[4..8], .big);
    try std.testing.expect(version == 2);

    const num_objects = std.mem.readInt(u32, result[8..12], .big);
    try std.testing.expect(num_objects == 1);
}

test "should create packfile with tag object" {
    const allocator = std.testing.allocator;

    const tag_content = "object c9bde8b8a0a0e0c0b0a0e0c0b0a0e0c0b0a0e0c0\n" ++
        "type commit\n" ++
        "tag v1.0.0\n" ++
        "tagger Test <test@example.com> 1234567890 +0000\n" ++
        "\n" ++
        "Version 1.0.0\n";

    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const obj_type = try allocator.dupe(u8, "tag");
    const sha = try allocator.dupe(u8, "a1b2c3d4e5f6789012345678901234567890abcd");
    const content = try allocator.dupe(u8, tag_content);

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const result = try packfile.createPackfile(allocator, objects);
    defer allocator.free(result);

    try std.testing.expect(std.mem.eql(u8, result[0..4], "PACK"));

    const version = std.mem.readInt(u32, result[4..8], .big);
    try std.testing.expect(version == 2);

    const num_objects = std.mem.readInt(u32, result[8..12], .big);
    try std.testing.expect(num_objects == 1);
}

test "should include valid checksum at end" {
    const allocator = std.testing.allocator;

    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const obj_type = try allocator.dupe(u8, "blob");
    const sha = try allocator.dupe(u8, "b6fc4c620b67d95f953a5c1c1230aaab5db5a1b0");
    const content = try allocator.dupe(u8, "hello world");

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const result = try packfile.createPackfile(allocator, objects);
    defer allocator.free(result);

    try std.testing.expect(result.len > 12);

    const data_without_checksum = result[0 .. result.len - 20];
    const checksum = result[result.len - 20 ..];

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(data_without_checksum);
    var expected_checksum: [20]u8 = undefined;
    hasher.final(&expected_checksum);

    try std.testing.expect(std.mem.eql(u8, checksum, &expected_checksum));
}

test "should throw error for invalid packfile signature" {
    const allocator = std.testing.allocator;

    const invalid_packfile = "INVALID";

    const result = packfile.parsePackfile(allocator, invalid_packfile);
    try std.testing.expectError(error.InvalidPackfileSignature, result);
}

test "should throw error for unsupported packfile version" {
    const allocator = std.testing.allocator;

    var buffer: [12]u8 = undefined;
    @memcpy(buffer[0..4], "PACK");

    const version = std.mem.nativeToBig(u32, 99);
    @memcpy(buffer[4..8], &@as([4]u8, @bitCast(version)));

    const result = packfile.parsePackfile(allocator, &buffer);
    try std.testing.expectError(error.UnsupportedPackfileVersion, result);
}

test "should encode and decode pkt line" {
    const allocator = std.testing.allocator;

    const line = "hello world";
    const encoded = try packfile.encodePktLine(allocator, line);
    defer allocator.free(encoded);

    var decoded = try packfile.decodePktLines(allocator, encoded);
    defer {
        for (decoded.items) |item| allocator.free(item);
        decoded.deinit(allocator);
    }

    try std.testing.expect(decoded.items.len == 1);
    try std.testing.expectEqualStrings(line, decoded.items[0]);
}

test "should encode and decode null pkt line" {
    const allocator = std.testing.allocator;

    const encoded = try packfile.encodePktLine(allocator, null);
    defer allocator.free(encoded);

    var decoded = try packfile.decodePktLines(allocator, encoded);
    defer {
        for (decoded.items) |item| allocator.free(item);
        decoded.deinit(allocator);
    }

    // Null pkt-line is a flush packet, which may or may not be included in decoded output
    try std.testing.expect(decoded.items.len == 0 or (decoded.items.len == 1 and decoded.items[0].len == 0));
}

test "should encode and decode multiple pkt lines" {
    const allocator = std.testing.allocator;

    const lines = &[_][]const u8{ "first line", "second line", "third line" };

    var encoded = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer encoded.deinit(allocator);

    for (lines) |line| {
        const line_encoded = try packfile.encodePktLine(allocator, line);
        defer allocator.free(line_encoded);
        try encoded.appendSlice(allocator, line_encoded);
    }

    var decoded = try packfile.decodePktLines(allocator, encoded.items);
    defer {
        for (decoded.items) |item| allocator.free(item);
        decoded.deinit(allocator);
    }

    try std.testing.expect(decoded.items.len == lines.len);

    for (lines, 0..) |expected, i| {
        try std.testing.expectEqualStrings(expected, decoded.items[i]);
    }
}

test "should handle empty string pkt line" {
    const allocator = std.testing.allocator;

    const line = "";
    const encoded = try packfile.encodePktLine(allocator, line);
    defer allocator.free(encoded);

    var decoded = try packfile.decodePktLines(allocator, encoded);
    defer {
        for (decoded.items) |item| allocator.free(item);
        decoded.deinit(allocator);
    }

    try std.testing.expect(decoded.items.len == 1);
    try std.testing.expectEqualStrings(line, decoded.items[0]);
}

test "getObjectType should return correct type for commit" {
    const result = try packfile.getObjectType(1);
    try std.testing.expectEqualStrings("commit", result);
}

test "getObjectType should return correct type for tree" {
    const result = try packfile.getObjectType(2);
    try std.testing.expectEqualStrings("tree", result);
}

test "getObjectType should return correct type for blob" {
    const result = try packfile.getObjectType(3);
    try std.testing.expectEqualStrings("blob", result);
}

test "getObjectType should return correct type for tag" {
    const result = try packfile.getObjectType(4);
    try std.testing.expectEqualStrings("tag", result);
}

test "getObjectType should throw error for unknown type" {
    const result = packfile.getObjectType(99);
    try std.testing.expectError(error.UnknownObjectType, result);
}
