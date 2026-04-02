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

    var iter = std.mem.splitScalar(u8, content.items, '\n');
    while (iter.next()) |line| {
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ' ');
        const path = parts.first();
        const sha = parts.next() orelse continue;
        const mode = parts.next() orelse "100644";

        const path_copy = try allocator.dupe(u8, path);
        const sha_copy = try allocator.dupe(u8, sha);
        const mode_copy = try allocator.dupe(u8, mode);

        try index.put(path_copy, .{
            .path = try allocator.dupe(u8, path),
            .sha = sha_copy,
            .mode = mode_copy,
        });
    }

    return index;
}

pub fn writeIndex(io: std.Io, allocator: std.mem.Allocator, index_path: []const u8, index: std.StringHashMap(IndexEntry)) !void {
    var content = std.ArrayList(u8).initCapacity(allocator, 100) catch unreachable;
    defer content.deinit(allocator);

    var iter = index.iterator();
    while (iter.next()) |entry| {
        const value = entry.value_ptr.*;
        const line = try std.fmt.allocPrint(allocator, "{s} {s} {s}\n", .{ value.path, value.sha, value.mode });
        defer allocator.free(line);
        try content.appendSlice(allocator, line);
    }

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

    var compressed = std.ArrayList(u8).initCapacity(allocator, content.len + 100) catch unreachable;
    defer compressed.deinit(allocator);

    try compressed.appendSlice(allocator, header);
    try compressed.appendSlice(allocator, content);

    try cwd.writeFile(io, .{ .sub_path = obj_path, .data = compressed.items });

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
    allocator.free(commit_sha);

    return try allocator.dupe(u8, trimmed);
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
};

pub const TreeEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
    entry_type: []const u8,
};
