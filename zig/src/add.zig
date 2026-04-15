const std = @import("std");

const utils = @import("utils.zig");

const status_module = @import("status.zig");
const IgnoreParser = @import("ignore_parser.zig").IgnoreParser;

pub fn add(io: std.Io, allocator: std.mem.Allocator, path: []const u8, files: []const []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    // Load gitignore patterns
    var gitignore = IgnoreParser.init(allocator);
    defer gitignore.deinit();
    try gitignore.loadGitignore(io, path);

    const git_index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(git_index_path);

    var index = try utils.getIndex(io, allocator, git_index_path);
    defer {
        var iter = index.iterator();
        while (iter.next()) |entry| {
            const value = entry.value_ptr.*;
            allocator.free(value.path);
            allocator.free(value.sha);
            allocator.free(value.mode);
        }
        index.deinit();
    }

    for (files) |file| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file });
        defer allocator.free(full_path);

        if (cwd.access(io, full_path, .{})) |_| {} else |_| {
            return error.FileNotFound;
        }

        if (gitignore.isIgnored(file, false)) {
            continue;
        }

        const file_content = try cwd.readFileAlloc(io, full_path, allocator, .unlimited);
        defer allocator.free(file_content);

        // Write blob object to .git/objects and get hash
        const hash = try utils.hashObject(io, allocator, git_dir_path, file_content, "blob");
        defer allocator.free(hash);

        const hash_copy = try allocator.dupe(u8, hash);
        const mode_copy = try allocator.dupe(u8, "100644");

        const old_entry = index.fetchRemove(file);
        if (old_entry) |entry| {
            allocator.free(entry.value.path);
            allocator.free(entry.value.sha);
            allocator.free(entry.value.mode);
        }

        const file_copy = try allocator.dupe(u8, file);
        try index.put(file_copy, .{
            .path = file_copy,
            .sha = hash_copy,
            .mode = mode_copy,
            .size = 0,
            .ctime_seconds = 0,
            .ctime_nanos = 0,
            .mtime_seconds = 0,
            .mtime_nanos = 0,
            .dev = 0,
            .ino = 0,
            .uid = 0,
            .gid = 0,
        });
    }

    try utils.writeIndex(io, allocator, git_index_path, index);
}

pub fn addAll(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const current_status = try status_module.status(io, allocator, path);
    defer {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |item| allocator.free(item);
        allocator.free(current_status.staged);
        for (current_status.deleted) |item| allocator.free(item);
        allocator.free(current_status.deleted);
    }

    const total_files = current_status.untracked.len + current_status.modified.len;
    if (total_files > 0) {
        var files_to_add = std.ArrayList([]const u8).initCapacity(allocator, total_files) catch unreachable;

        for (current_status.untracked) |file| {
            try files_to_add.append(allocator, file);
        }
        for (current_status.modified) |file| {
            try files_to_add.append(allocator, file);
        }

        defer {
            for (files_to_add.items) |file| {
                allocator.free(file);
            }
            files_to_add.deinit(allocator);
        }

        try add(io, allocator, path, files_to_add.items);
    }

    if (current_status.deleted.len > 0) {
        const git_index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
        defer allocator.free(git_index_path);

        var index = try utils.getIndex(io, allocator, git_index_path);
        defer {
            var iter = index.iterator();
            while (iter.next()) |entry| {
                const value = entry.value_ptr.*;
                allocator.free(value.path);
                allocator.free(value.sha);
                allocator.free(value.mode);
            }
            index.deinit();
        }

        for (current_status.deleted) |file| {
            const old_entry = index.fetchRemove(file);
            if (old_entry) |entry| {
                allocator.free(entry.value.path);
                allocator.free(entry.value.sha);
                allocator.free(entry.value.mode);
            }
        }

        try utils.writeIndex(io, allocator, git_index_path, index);
    }

    // Don't free untracked and modified items - they're moved to files_to_add and freed there
    // Only free the slices themselves, not the items they contain
    allocator.free(current_status.untracked);
    allocator.free(current_status.modified);
}
