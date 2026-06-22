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

fn computeSha(obj_type: []const u8, content: []const u8) [40]u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    var header_buf: [64]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "{s} {d}\x00", .{ obj_type, content.len }) catch unreachable;
    hasher.update(header);
    hasher.update(content);

    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    var hex: [40]u8 = undefined;
    const hex_digits = "0123456789abcdef";
    for (0..20) |i| {
        hex[2 * i] = hex_digits[hash[i] >> 4];
        hex[2 * i + 1] = hex_digits[hash[i] & 0x0f];
    }
    return hex;
}

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(std.testing.io, path) catch {};
    return path;
}

test "should read loose object" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-test-loose");
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const init = @import("gitologist").init;
    try init(io, allocator, tmp_path);

    const content = "hello world";
    const sha = try @import("gitologist").utils.hashObject(io, allocator, git_dir_path, content, "blob");
    defer allocator.free(sha);

    var cache = @import("gitologist").utils.PackfileCache.init(allocator);
    defer cache.deinit();
    const data = try @import("gitologist").utils.readObjectData(io, allocator, git_dir_path, sha, &cache);
    defer allocator.free(data);

    const null_idx = std.mem.indexOfScalar(u8, data, 0) orelse return error.TestExpectedEqual;
    const header = data[0..null_idx];
    const body = data[null_idx + 1 ..];

    try std.testing.expectEqualStrings("blob 11", header);
    try std.testing.expectEqualStrings(content, body);
}

test "should read object from packfile" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-test-packfile-read");
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const init = @import("gitologist").init;
    try init(io, allocator, tmp_path);

    const blob_content = "packfile content";
    const sha_hex = computeSha("blob", blob_content);

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
    const sha = try allocator.dupe(u8, &sha_hex);
    const content = try allocator.dupe(u8, blob_content);

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const pack_data = try packfile.createPackfile(allocator, objects);
    defer allocator.free(pack_data);

    const pack_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "objects", "pack" });
    defer allocator.free(pack_dir_path);

    cwd.createDirPath(io, pack_dir_path) catch {};
    var pack_dir = try cwd.openDir(io, pack_dir_path, .{});
    defer pack_dir.close(io);

    try pack_dir.writeFile(io, .{ .sub_path = "test.pack", .data = pack_data });

    const utils = @import("gitologist").utils;
    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();
    const data = try utils.readObjectData(io, allocator, git_dir_path, sha, &cache);
    defer allocator.free(data);

    const null_idx = std.mem.indexOfScalar(u8, data, 0) orelse return error.TestExpectedEqual;
    const header = data[0..null_idx];
    const body = data[null_idx + 1 ..];

    try std.testing.expectEqualStrings("blob 16", header);
    try std.testing.expectEqualStrings(content, body);
}

test "should throw error when object not found" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-test-not-found");
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const init = @import("gitologist").init;
    try init(io, allocator, tmp_path);

    const utils = @import("gitologist").utils;
    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();
    const result = utils.readObjectData(io, allocator, git_dir_path, "0000000000000000000000000000000000000000", &cache);
    try std.testing.expectError(error.ObjectNotFound, result);
}

test "should read object via packfile" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-test-read-object-via-packfile");
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const init = @import("gitologist").init;
    try init(io, allocator, tmp_path);

    const commit_content = "tree 4b825dc642cb6eb9a060e54bf8d69288fbee4904\nauthor Test <test@example.com> 1234567890 +0000\ncommitter Test <test@example.com> 1234567890 +0000\n\nInitial commit\n";
    const sha_hex = computeSha("commit", commit_content);

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
    const sha = try allocator.dupe(u8, &sha_hex);
    const content = try allocator.dupe(u8, commit_content);

    try objects.append(allocator, .{
        .obj_type = obj_type,
        .sha = sha,
        .content = content,
    });

    const pack_data = try packfile.createPackfile(allocator, objects);
    defer allocator.free(pack_data);

    const pack_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "objects", "pack" });
    defer allocator.free(pack_dir_path);

    cwd.createDirPath(io, pack_dir_path) catch {};
    var pack_dir = try cwd.openDir(io, pack_dir_path, .{});
    defer pack_dir.close(io);

    try pack_dir.writeFile(io, .{ .sub_path = "commits.pack", .data = pack_data });

    const utils = @import("gitologist").utils;
    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();
    const data = try utils.readObject(io, allocator, git_dir_path, sha, &cache);
    defer allocator.free(data);

    try std.testing.expect(std.mem.indexOf(u8, data, "commit") != null);
    try std.testing.expect(std.mem.indexOf(u8, data, "Initial commit") != null);
}

fn encodeOfsDeltaOffset(allocator: std.mem.Allocator, n: usize) ![]const u8 {
    var buf: [16]u8 = undefined;
    var len: usize = 0;

    buf[len] = @as(u8, @intCast(n & 0x7f));
    len += 1;
    var remaining = n >> 7;
    while (remaining > 0) {
        remaining -= 1;
        var i: usize = len;
        while (i > 0) : (i -= 1) {
            buf[i] = buf[i - 1];
        }
        buf[0] = @as(u8, @intCast((remaining & 0x7f) | 0x80));
        len += 1;
        remaining >>= 7;
    }

    return try allocator.dupe(u8, buf[0..len]);
}

fn hexToBuffer(allocator: std.mem.Allocator, hex: *const [40]u8) ![]const u8 {
    var buf = try allocator.alloc(u8, 20);
    for (0..20) |i| {
        const hi_nibble = std.fmt.charToDigit(hex[2 * i], 16) catch unreachable;
        const lo_nibble = std.fmt.charToDigit(hex[2 * i + 1], 16) catch unreachable;
        buf[i] = (hi_nibble << 4) | lo_nibble;
    }
    return buf;
}

const TestPackSpec = struct {
    type_num: usize,
    payload: []const u8,
    extra_data: []const u8,
};

fn buildTestPackfile(allocator: std.mem.Allocator, specs: []const TestPackSpec) ![]const u8 {
    var pack = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    errdefer pack.deinit(allocator);

    try pack.appendSlice(allocator, "PACK");

    const version_bytes = std.mem.nativeToBig(u32, 2);
    try pack.appendSlice(allocator, &@as([4]u8, @bitCast(version_bytes)));

    const num_bytes = std.mem.nativeToBig(u32, @intCast(specs.len));
    try pack.appendSlice(allocator, &@as([4]u8, @bitCast(num_bytes)));

    for (specs) |spec| {
        const header = try packfile.encodeObjectHeader(allocator, spec.type_num, spec.payload.len);
        defer allocator.free(header);
        try pack.appendSlice(allocator, header);
        try pack.appendSlice(allocator, spec.extra_data);

        const flate = std.compress.flate;
        var compressed = std.ArrayList(u8).initCapacity(allocator, 128) catch unreachable;
        var compressed_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &compressed);
        defer compressed_writer.deinit();
        var flate_buffer: [flate.max_window_len]u8 = undefined;
        var compress = try flate.Compress.init(&compressed_writer.writer, &flate_buffer, .zlib, .default);
        try compress.writer.writeAll(spec.payload);
        try compress.writer.flush();
        try compress.finish();
        try compressed_writer.writer.flush();
        var final_compressed = compressed_writer.toArrayList();
        defer final_compressed.deinit(allocator);
        try pack.appendSlice(allocator, final_compressed.items);
    }

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(pack.items);
    var checksum: [20]u8 = undefined;
    hasher.final(&checksum);
    try pack.appendSlice(allocator, &checksum);

    return pack.toOwnedSlice(allocator);
}

test "should resolve OFS_DELTA copying entire base" {
    const allocator = std.testing.allocator;

    const base_content = "hello world";

    var delta = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer delta.deinit(allocator);
    try delta.appendSlice(allocator, &[_]u8{ 0x0b, 0x0b, 0x91, 0x00, 0x0b });

    const base_header = try packfile.encodeObjectHeader(allocator, 3, base_content.len);
    defer allocator.free(base_header);
    const base_compressed_list = try compressTestBytes(allocator, base_content);
    defer allocator.free(base_compressed_list);
    const base_obj_size = base_header.len + base_compressed_list.len;
    const ofs_bytes = try encodeOfsDeltaOffset(allocator, base_obj_size);
    defer allocator.free(ofs_bytes);

    const specs = [_]TestPackSpec{
        .{ .type_num = 3, .payload = base_content, .extra_data = "" },
        .{ .type_num = 6, .payload = delta.items, .extra_data = ofs_bytes },
    };

    const pack_data = try buildTestPackfile(allocator, &specs);
    defer allocator.free(pack_data);

    var objects = try packfile.parsePackfile(allocator, pack_data);
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    try std.testing.expect(objects.items.len == 2);
    try std.testing.expectEqualStrings("blob", objects.items[0].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[0].content);
    try std.testing.expectEqualStrings("blob", objects.items[1].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[1].content);

    const expected_sha = computeSha("blob", base_content);
    try std.testing.expectEqualStrings(&expected_sha, objects.items[0].sha);
    try std.testing.expectEqualStrings(&expected_sha, objects.items[1].sha);
}

test "should resolve OFS_DELTA with modified content" {
    const allocator = std.testing.allocator;

    const base_content = "hello world";
    const expected_content = "hello gitologist";

    var delta = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer delta.deinit(allocator);
    try delta.appendSlice(allocator, &[_]u8{ 0x0b, 0x10, 0x91, 0x00, 0x06, 0x0a });
    try delta.appendSlice(allocator, "gitologist");

    const base_header = try packfile.encodeObjectHeader(allocator, 3, base_content.len);
    defer allocator.free(base_header);
    const base_compressed_list = try compressTestBytes(allocator, base_content);
    defer allocator.free(base_compressed_list);
    const base_obj_size = base_header.len + base_compressed_list.len;
    const ofs_bytes = try encodeOfsDeltaOffset(allocator, base_obj_size);
    defer allocator.free(ofs_bytes);

    const specs = [_]TestPackSpec{
        .{ .type_num = 3, .payload = base_content, .extra_data = "" },
        .{ .type_num = 6, .payload = delta.items, .extra_data = ofs_bytes },
    };

    const pack_data = try buildTestPackfile(allocator, &specs);
    defer allocator.free(pack_data);

    var objects = try packfile.parsePackfile(allocator, pack_data);
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    try std.testing.expect(objects.items.len == 2);
    try std.testing.expectEqualStrings("blob", objects.items[0].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[0].content);
    try std.testing.expectEqualStrings("blob", objects.items[1].obj_type);
    try std.testing.expectEqualStrings(expected_content, objects.items[1].content);
}

test "should resolve REF_DELTA copying entire base" {
    const allocator = std.testing.allocator;

    const base_content = "hello world";
    const base_sha = computeSha("blob", base_content);

    var delta = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer delta.deinit(allocator);
    try delta.appendSlice(allocator, &[_]u8{ 0x0b, 0x0b, 0x91, 0x00, 0x0b });

    const sha_data = try hexToBuffer(allocator, &base_sha);
    defer allocator.free(sha_data);

    const specs = [_]TestPackSpec{
        .{ .type_num = 3, .payload = base_content, .extra_data = "" },
        .{ .type_num = 7, .payload = delta.items, .extra_data = sha_data },
    };

    const pack_data = try buildTestPackfile(allocator, &specs);
    defer allocator.free(pack_data);

    var objects = try packfile.parsePackfile(allocator, pack_data);
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    try std.testing.expect(objects.items.len == 2);
    try std.testing.expectEqualStrings("blob", objects.items[0].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[0].content);
    try std.testing.expectEqualStrings("blob", objects.items[1].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[1].content);
    try std.testing.expectEqualStrings(&base_sha, objects.items[1].sha);
}

test "should resolve chained OFS_DELTA" {
    const allocator = std.testing.allocator;

    const base_content = "hello world";
    const intermediate_content = "hello gitologist";
    const final_content = "hello beautiful gitologist";

    var delta1 = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer delta1.deinit(allocator);
    try delta1.appendSlice(allocator, &[_]u8{ 0x0b, 0x10, 0x91, 0x00, 0x06, 0x0a });
    try delta1.appendSlice(allocator, "gitologist");

    var delta2 = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer delta2.deinit(allocator);
    try delta2.appendSlice(allocator, &[_]u8{ 0x10, 0x1a, 0x91, 0x00, 0x06, 0x0a });
    try delta2.appendSlice(allocator, "beautiful ");
    try delta2.appendSlice(allocator, &[_]u8{ 0x91, 0x06, 0x0a });

    const base_header = try packfile.encodeObjectHeader(allocator, 3, base_content.len);
    defer allocator.free(base_header);
    const base_compressed_list = try compressTestBytes(allocator, base_content);
    defer allocator.free(base_compressed_list);
    const obj1_size = base_header.len + base_compressed_list.len;

    const ofs_bytes1 = try encodeOfsDeltaOffset(allocator, obj1_size);
    defer allocator.free(ofs_bytes1);

    const delta1_header = try packfile.encodeObjectHeader(allocator, 6, delta1.items.len);
    defer allocator.free(delta1_header);
    const delta1_compressed = try compressTestBytes(allocator, delta1.items);
    defer allocator.free(delta1_compressed);
    const obj2_size = delta1_header.len + ofs_bytes1.len + delta1_compressed.len;

    const ofs_bytes2 = try encodeOfsDeltaOffset(allocator, obj2_size);
    defer allocator.free(ofs_bytes2);

    const specs = [_]TestPackSpec{
        .{ .type_num = 3, .payload = base_content, .extra_data = "" },
        .{ .type_num = 6, .payload = delta1.items, .extra_data = ofs_bytes1 },
        .{ .type_num = 6, .payload = delta2.items, .extra_data = ofs_bytes2 },
    };

    const pack_data = try buildTestPackfile(allocator, &specs);
    defer allocator.free(pack_data);

    var objects = try packfile.parsePackfile(allocator, pack_data);
    defer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    try std.testing.expect(objects.items.len == 3);
    try std.testing.expectEqualStrings("blob", objects.items[0].obj_type);
    try std.testing.expectEqualStrings(base_content, objects.items[0].content);
    try std.testing.expectEqualStrings("blob", objects.items[1].obj_type);
    try std.testing.expectEqualStrings(intermediate_content, objects.items[1].content);
    try std.testing.expectEqualStrings("blob", objects.items[2].obj_type);
    try std.testing.expectEqualStrings(final_content, objects.items[2].content);
}

fn compressTestBytes(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    const flate = std.compress.flate;
    var compressed = std.ArrayList(u8).initCapacity(allocator, 128) catch unreachable;
    var compressed_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &compressed);
    defer compressed_writer.deinit();
    var flate_buffer: [flate.max_window_len]u8 = undefined;
    var compress = try flate.Compress.init(&compressed_writer.writer, &flate_buffer, .zlib, .default);
    try compress.writer.writeAll(data);
    try compress.writer.flush();
    try compress.finish();
    try compressed_writer.writer.flush();
    var final_compressed = compressed_writer.toArrayList();
    defer final_compressed.deinit(allocator);
    return try allocator.dupe(u8, final_compressed.items);
}
