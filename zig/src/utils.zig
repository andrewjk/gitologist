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

pub const IndexEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
};
