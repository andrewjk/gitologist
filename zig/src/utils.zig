const std = @import("std");

pub fn hashFile(io: std.Io, allocator: std.mem.Allocator, file_path: []const u8) ![]const u8 {
    const cwd = std.Io.Dir.cwd();
    const file = try cwd.openFile(io, file_path, .{});
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var hasher = std.crypto.hash.Sha1.init(.{});
    var offset: u64 = 0;

    while (true) {
        const bytes_read = try std.Io.File.readPositionalAll(file, io, &buffer, offset);
        if (bytes_read == 0) break;
        hasher.update(buffer[0..bytes_read]);
        offset += bytes_read;
    }

    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    const hex_hash = try allocator.alloc(u8, 40);
    const hex_digits = "0123456789abcdef";

    for (0..20) |i| {
        hex_hash[2 * i] = hex_digits[hash[i] >> 4];
        hex_hash[2 * i + 1] = hex_digits[hash[i] & 0x0f];
    }

    return hex_hash;
}

pub fn getIndex(io: std.Io, allocator: std.mem.Allocator, index_path: []const u8) !std.StringHashMap(IndexEntry) {
    var index = std.StringHashMap(IndexEntry).init(allocator);

    const cwd = std.Io.Dir.cwd();
    const file = cwd.openFile(io, index_path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            return index;
        }
        return err;
    };
    defer file.close(io);

    var buffer: [4096]u8 = undefined;
    var content = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer content.deinit(allocator);
    var offset: u64 = 0;

    while (true) {
        const bytes_read = try std.Io.File.readPositionalAll(file, io, &buffer, offset);
        if (bytes_read == 0) break;
        try content.appendSlice(allocator, buffer[0..bytes_read]);
        offset += bytes_read;
    }

    if (content.items.len < 12) {
        return index;
    }

    const signature = content.items[0..4];
    if (!std.mem.eql(u8, signature, "DIRC")) {
        return index;
    }

    const num_entries = std.mem.readInt(u32, content.items[8..12], .big);

    var entry_offset: usize = 12;

    for (0..num_entries) |_| {
        if (entry_offset + 62 > content.items.len) {
            break;
        }

        const ctime_seconds = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset],
            content.items[entry_offset + 1],
            content.items[entry_offset + 2],
            content.items[entry_offset + 3],
        }));
        const ctime_nanos = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 4],
            content.items[entry_offset + 5],
            content.items[entry_offset + 6],
            content.items[entry_offset + 7],
        }));
        const mtime_seconds = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 8],
            content.items[entry_offset + 9],
            content.items[entry_offset + 10],
            content.items[entry_offset + 11],
        }));
        const mtime_nanos = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 12],
            content.items[entry_offset + 13],
            content.items[entry_offset + 14],
            content.items[entry_offset + 15],
        }));
        const dev = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 16],
            content.items[entry_offset + 17],
            content.items[entry_offset + 18],
            content.items[entry_offset + 19],
        }));
        const ino = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 20],
            content.items[entry_offset + 21],
            content.items[entry_offset + 22],
            content.items[entry_offset + 23],
        }));
        const mode_value = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 24],
            content.items[entry_offset + 25],
            content.items[entry_offset + 26],
            content.items[entry_offset + 27],
        }));
        const uid = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 28],
            content.items[entry_offset + 29],
            content.items[entry_offset + 30],
            content.items[entry_offset + 31],
        }));
        const gid = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 32],
            content.items[entry_offset + 33],
            content.items[entry_offset + 34],
            content.items[entry_offset + 35],
        }));
        const size = std.mem.bigToNative(u32, @bitCast([4]u8{
            content.items[entry_offset + 36],
            content.items[entry_offset + 37],
            content.items[entry_offset + 38],
            content.items[entry_offset + 39],
        }));

        const sha_bytes = content.items[entry_offset + 40 .. entry_offset + 60];
        var sha: [40]u8 = undefined;
        for (0..20) |i| {
            const byte = sha_bytes[i];
            sha[2 * i] = "0123456789abcdef"[byte >> 4];
            sha[2 * i + 1] = "0123456789abcdef"[byte & 0x0f];
        }
        const sha_str = try allocator.dupe(u8, &sha);

        const flags = std.mem.bigToNative(u16, @bitCast([2]u8{
            content.items[entry_offset + 60],
            content.items[entry_offset + 61],
        }));
        const path_len = flags & 0x0FFF;

        if (entry_offset + 62 + path_len > content.items.len) {
            allocator.free(sha_str);
            break;
        }

        const path_bytes = content.items[entry_offset + 62 .. entry_offset + 62 + path_len];
        const path = try allocator.dupe(u8, path_bytes);

        const mode = try std.fmt.allocPrint(allocator, "{o}", .{mode_value});

        const entry_length = 62 + path_len + 1;
        const padding_length = (8 - (entry_length % 8)) % 8;
        entry_offset += entry_length + padding_length;

        try index.put(path, .{
            .path = path,
            .sha = sha_str,
            .mode = mode,
            .size = size,
            .ctime_seconds = ctime_seconds,
            .ctime_nanos = ctime_nanos,
            .mtime_seconds = mtime_seconds,
            .mtime_nanos = mtime_nanos,
            .dev = dev,
            .ino = ino,
            .uid = uid,
            .gid = gid,
        });
    }

    return index;
}

pub fn writeIndex(io: std.Io, allocator: std.mem.Allocator, index_path: []const u8, index: std.StringHashMap(IndexEntry)) !void {
    var entries = std.ArrayList(IndexEntry).initCapacity(allocator, index.count()) catch unreachable;
    defer entries.deinit(allocator);

    var iter = index.iterator();
    while (iter.next()) |entry| {
        try entries.append(allocator, entry.value_ptr.*);
    }

    std.sort.block(IndexEntry, entries.items, {}, struct {
        fn compare(_: void, a: IndexEntry, b: IndexEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.compare);

    var content = std.ArrayList(u8).initCapacity(allocator, 100) catch unreachable;
    defer content.deinit(allocator);

    try content.appendSlice(allocator, "DIRC");
    try content.appendSlice(allocator, &[_]u8{ 0, 0, 0, 2 });
    const num_entries: u32 = @intCast(entries.items.len);
    const num_entries_bytes = std.mem.nativeToBig(u32, num_entries);
    try content.appendSlice(allocator, &@as([4]u8, @bitCast(num_entries_bytes)));

    for (entries.items) |entry| {
        const entry_start = content.items.len;

        try content.appendNTimes(allocator, 0, 62);

        const ctime_bytes = std.mem.nativeToBig(u32, entry.ctime_seconds);
        @memcpy(content.items[entry_start .. entry_start + 4], &@as([4]u8, @bitCast(ctime_bytes)));
        const ctime_nanos_bytes = std.mem.nativeToBig(u32, entry.ctime_nanos);
        @memcpy(content.items[entry_start + 4 .. entry_start + 8], &@as([4]u8, @bitCast(ctime_nanos_bytes)));
        const mtime_seconds_bytes = std.mem.nativeToBig(u32, entry.mtime_seconds);
        @memcpy(content.items[entry_start + 8 .. entry_start + 12], &@as([4]u8, @bitCast(mtime_seconds_bytes)));
        const mtime_nanos_bytes = std.mem.nativeToBig(u32, entry.mtime_nanos);
        @memcpy(content.items[entry_start + 12 .. entry_start + 16], &@as([4]u8, @bitCast(mtime_nanos_bytes)));
        const dev_bytes = std.mem.nativeToBig(u32, entry.dev);
        @memcpy(content.items[entry_start + 16 .. entry_start + 20], &@as([4]u8, @bitCast(dev_bytes)));
        const ino_bytes = std.mem.nativeToBig(u32, entry.ino);
        @memcpy(content.items[entry_start + 20 .. entry_start + 24], &@as([4]u8, @bitCast(ino_bytes)));

        const mode_value = std.fmt.parseUnsigned(u32, entry.mode, 8) catch 0o100644;
        const mode_bytes = std.mem.nativeToBig(u32, mode_value);
        @memcpy(content.items[entry_start + 24 .. entry_start + 28], &@as([4]u8, @bitCast(mode_bytes)));

        const uid_bytes = std.mem.nativeToBig(u32, entry.uid);
        @memcpy(content.items[entry_start + 28 .. entry_start + 32], &@as([4]u8, @bitCast(uid_bytes)));
        const gid_bytes = std.mem.nativeToBig(u32, entry.gid);
        @memcpy(content.items[entry_start + 32 .. entry_start + 36], &@as([4]u8, @bitCast(gid_bytes)));
        const size_bytes = std.mem.nativeToBig(u32, entry.size);
        @memcpy(content.items[entry_start + 36 .. entry_start + 40], &@as([4]u8, @bitCast(size_bytes)));

        var sha_bytes: [20]u8 = undefined;
        for (0..20) |i| {
            const byte_high = std.fmt.charToDigit(entry.sha[2 * i], 16) catch 0;
            const byte_low = std.fmt.charToDigit(entry.sha[2 * i + 1], 16) catch 0;
            sha_bytes[i] = byte_high * 16 + byte_low;
        }
        @memcpy(content.items[entry_start + 40 .. entry_start + 60], &sha_bytes);

        const flags: u16 = @intCast(@min(entry.path.len, 0xFFF));
        const flags_bytes = std.mem.nativeToBig(u16, flags);
        @memcpy(content.items[entry_start + 60 .. entry_start + 62], &@as([2]u8, @bitCast(flags_bytes)));

        try content.appendSlice(allocator, entry.path);
        try content.append(allocator, 0);

        const entry_length = 62 + entry.path.len + 1;
        const padding_length = (8 - (entry_length % 8)) % 8;
        try content.appendNTimes(allocator, 0, padding_length);
    }

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(content.items);
    var checksum: [20]u8 = undefined;
    hasher.final(&checksum);

    try content.appendSlice(allocator, &checksum);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = content.items });
}

pub fn hashObject(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, content: []const u8, obj_type: []const u8) ![]const u8 {
    const header = try std.fmt.allocPrint(allocator, "{s} {d}\x00", .{ obj_type, content.len });
    defer allocator.free(header);

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(header);
    hasher.update(content);

    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    const hex_hash = try allocator.alloc(u8, 40);
    const hex_digits = "0123456789abcdef";

    for (0..20) |i| {
        hex_hash[2 * i] = hex_digits[hash[i] >> 4];
        hex_hash[2 * i + 1] = hex_digits[hash[i] & 0x0f];
    }

    const obj_dir = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ git_dir_path, hex_hash[0..2] });
    defer allocator.free(obj_dir);

    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(io, obj_dir) catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    const obj_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ obj_dir, hex_hash[2..] });
    defer allocator.free(obj_path);

    // Compress the object data with zlib (required by git)
    const flate = std.compress.flate;

    var file = try cwd.createFile(io, obj_path, .{});
    defer file.close(io);

    var write_buffer: [flate.max_window_len]u8 = undefined;
    var file_writer = std.Io.File.Writer.init(file, io, &write_buffer);
    var flate_buffer: [flate.max_window_len]u8 = undefined;
    var compress = try flate.Compress.init(&file_writer.interface, &flate_buffer, .zlib, .default);
    try compress.writer.writeAll(header);
    try compress.writer.writeAll(content);
    try compress.writer.flush();
    try compress.finish();
    try file_writer.interface.flush();

    return hex_hash;
}

pub fn getCurrentBranch(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8) ![]const u8 {
    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const cwd = std.Io.Dir.cwd();
    const head_content = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
    defer allocator.free(head_content);

    const trimmed = std.mem.trim(u8, head_content, &std.ascii.whitespace);

    const prefix = "ref: refs/heads/";
    if (std.mem.startsWith(u8, trimmed, prefix)) {
        const branch = trimmed[prefix.len..];
        return allocator.dupe(u8, branch);
    }

    return allocator.dupe(u8, "(detached HEAD)");
}

pub fn getCurrentCommit(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8) !?[]const u8 {
    const branch = try getCurrentBranch(io, allocator, git_dir_path);
    defer allocator.free(branch);

    if (std.mem.eql(u8, branch, "(detached HEAD)")) {
        return null;
    }

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch });
    defer allocator.free(branch_path);

    const cwd = std.Io.Dir.cwd();
    const commit_sha = cwd.readFileAlloc(io, branch_path, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };

    const trimmed = std.mem.trim(u8, commit_sha, &std.ascii.whitespace);
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(commit_sha);

    return result;
}

pub fn updateBranch(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, branch_name: []const u8, commit_sha: []const u8) !void {
    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(branch_path);

    const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{commit_sha});
    defer allocator.free(commit_with_newline);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = branch_path, .data = commit_with_newline });
}

pub const IndexEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
    size: u32,
    ctime_seconds: u32,
    ctime_nanos: u32,
    mtime_seconds: u32,
    mtime_nanos: u32,
    dev: u32,
    ino: u32,
    uid: u32,
    gid: u32,
};

pub const TreeEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
    entry_type: []const u8,
};

pub fn readObject(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8) ![]const u8 {
    const obj_dir = sha[0..2];
    const obj_name = sha[2..];

    const obj_path = try std.fmt.allocPrint(allocator, "{s}/objects/{s}/{s}", .{ git_dir_path, obj_dir, obj_name });
    defer allocator.free(obj_path);

    const cwd = std.Io.Dir.cwd();
    var file = try cwd.openFile(io, obj_path, .{});
    defer file.close(io);

    const flate = std.compress.flate;

    var read_buffer: [flate.max_window_len]u8 = undefined;
    var file_reader = std.Io.File.Reader.init(file, io, &read_buffer);
    var flate_buffer: [flate.max_window_len]u8 = undefined;
    var decompress = flate.Decompress.init(&file_reader.interface, .zlib, &flate_buffer);
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    _ = try decompress.reader.streamRemaining(&writer.writer);

    return writer.toOwnedSlice();
}

pub fn extractContentFromBlob(blob_data: []const u8) []const u8 {
    const null_idx = std.mem.indexOfScalar(u8, blob_data, 0) orelse return blob_data;
    return blob_data[null_idx + 1 ..];
}

pub fn extractTreeFromCommit(commit_data: []const u8) ![]const u8 {
    const content = extractContentFromBlob(commit_data);

    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        if (line.len == 0) continue;
        if (std.mem.startsWith(u8, line, "tree ")) {
            const tree_sha = line["tree ".len..];
            return tree_sha;
        }
    }

    return error.TreeNotFound;
}

pub fn parseTreeEntries(allocator: std.mem.Allocator, tree_data: []const u8) !std.ArrayList(TreeEntry) {
    const content = extractContentFromBlob(tree_data);

    var entries = std.ArrayList(TreeEntry).initCapacity(allocator, 10) catch unreachable;
    errdefer {
        for (entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        entries.deinit(allocator);
    }

    var i: usize = 0;
    while (i < content.len) {
        const first_space = std.mem.indexOfScalar(u8, content[i..], ' ') orelse break;
        const mode = content[i .. i + first_space];

        const second_space = std.mem.indexOfScalar(u8, content[i + first_space + 1 ..], ' ') orelse break;
        const type_start = i + first_space + 1;
        const entry_type_str = content[type_start .. type_start + second_space];

        const sha_start = type_start + second_space + 1;
        if (sha_start + 40 > content.len) break;
        const sha = content[sha_start .. sha_start + 40];

        const null_after_sha = sha_start + 40;
        if (null_after_sha >= content.len) break;
        if (content[null_after_sha] != 0) break;

        const path_start = null_after_sha + 1;
        const null_after_path = std.mem.indexOfScalar(u8, content[path_start..], 0) orelse break;
        const path = content[path_start .. path_start + null_after_path];

        try entries.append(allocator, .{
            .path = try allocator.dupe(u8, path),
            .sha = try allocator.dupe(u8, sha),
            .mode = try allocator.dupe(u8, mode),
            .entry_type = try allocator.dupe(u8, entry_type_str),
        });

        i = path_start + null_after_path + 1;
    }

    return entries;
}
