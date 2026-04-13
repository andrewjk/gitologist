const std = @import("std");

const StatusInfo = @import("types/StatusInfo.zig").StatusInfo;

const utils = @import("utils.zig");
const IgnoreParser = @import("ignore_parser.zig").IgnoreParser;

pub fn status(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !StatusInfo {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const branch = try getBranch(io, allocator, git_dir);

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

    var staged = std.ArrayList([]const u8).initCapacity(allocator, index.count()) catch unreachable;
    var modified = std.ArrayList([]const u8).initCapacity(allocator, index.count()) catch unreachable;
    var untracked = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    var deleted = std.ArrayList([]const u8).initCapacity(allocator, index.count()) catch unreachable;

    var iter = index.iterator();
    while (iter.next()) |entry| {
        const index_path = entry.key_ptr.*;
        const path_copy = try allocator.dupe(u8, index_path);
        try staged.append(allocator, path_copy);
    }

    // Load gitignore patterns
    var gitignore = IgnoreParser.init(allocator);
    defer gitignore.deinit();
    try gitignore.loadGitignore(io, path);

    var working_files = try getWorkingFiles(io, allocator, path, gitignore);
    defer {
        for (working_files.items) |file| {
            allocator.free(file);
        }
        working_files.deinit(allocator);
    }

    for (working_files.items) |file| {
        if (!index.contains(file)) {
            const file_copy = try allocator.dupe(u8, file);
            try untracked.append(allocator, file_copy);
        }
    }

    iter = index.iterator();
    while (iter.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const index_entry = entry.value_ptr.*;

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file_path });
        defer allocator.free(full_path);

        if (cwd.access(io, full_path, .{})) |_| {
            const file = cwd.openFile(io, full_path, .{}) catch continue;
            defer file.close(io);

            const current_hash = try utils.hashFileAsBlob(io, allocator, full_path);
            defer allocator.free(current_hash);

            if (!std.mem.eql(u8, index_entry.sha, current_hash)) {
                const path_copy = try allocator.dupe(u8, file_path);
                try modified.append(allocator, path_copy);
            }
        } else |_| {
            const path_copy = try allocator.dupe(u8, file_path);
            try deleted.append(allocator, path_copy);
        }
    }

    const up_to_date = try std.fmt.allocPrint(allocator, "Your branch is up to date with 'origin/{s}'.", .{branch});

    return .{
        .branch = branch,
        .up_to_date = up_to_date,
        .staged = try staged.toOwnedSlice(allocator),
        .modified = try modified.toOwnedSlice(allocator),
        .untracked = try untracked.toOwnedSlice(allocator),
        .deleted = try deleted.toOwnedSlice(allocator),
    };
}

fn getBranch(io: std.Io, allocator: std.mem.Allocator, git_dir: std.Io.Dir) ![]const u8 {
    const head_content = git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            return allocator.dupe(u8, "(detached HEAD)");
        }
        return err;
    };
    defer allocator.free(head_content);

    const trimmed = std.mem.trim(u8, head_content, &std.ascii.whitespace);

    const prefix = "ref: refs/heads/";
    if (std.mem.startsWith(u8, trimmed, prefix)) {
        const branch = trimmed[prefix.len..];
        return allocator.dupe(u8, branch);
    }

    return allocator.dupe(u8, "(detached HEAD)");
}

fn getWorkingFiles(io: std.Io, allocator: std.mem.Allocator, path: []const u8, gitignore: IgnoreParser) !std.ArrayList([]const u8) {
    var files = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;

    const cwd = std.Io.Dir.cwd();
    const dir = try cwd.openDir(io, path, .{});
    defer dir.close(io);

    try scan(io, allocator, dir, path, path, &files, gitignore);

    return files;
}

fn scan(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir: std.Io.Dir,
    base_path: []const u8,
    current_path: []const u8,
    files: *std.ArrayList([]const u8),
    gitignore: IgnoreParser,
) !void {
    var dir_entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 20) catch unreachable;
    defer {
        for (dir_entries.items) |entry| {
            allocator.free(entry.name);
        }
        dir_entries.deinit(allocator);
    }

    {
        var iter = dir.iterate();
        while (try iter.next(io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".git")) continue;
            const name_copy = try allocator.dupe(u8, entry.name);
            const entry_copy = std.Io.Dir.Entry{
                .name = name_copy,
                .kind = entry.kind,
                .inode = entry.inode,
            };
            try dir_entries.append(allocator, entry_copy);
        }
    }

    for (dir_entries.items) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ current_path, entry.name });
        defer allocator.free(full_path);

        const is_directory = entry.kind == .directory;
        const rel_path = try std.fs.path.relative(allocator, ".", null, base_path, full_path);
        defer allocator.free(rel_path);

        // Check if this path is ignored
        if (gitignore.isIgnored(rel_path, is_directory)) {
            continue;
        }

        switch (entry.kind) {
            .directory => {
                const sub_dir = try dir.openDir(io, entry.name, .{});
                defer sub_dir.close(io);
                try scan(io, allocator, sub_dir, base_path, full_path, files, gitignore);
            },
            .file => {
                const rel_path_copy = try allocator.dupe(u8, rel_path);
                try files.append(allocator, rel_path_copy);
            },
            else => {},
        }
    }
}
