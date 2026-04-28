const std = @import("std");

const utils = @import("utils.zig");
const status_module = @import("status.zig");
const commit_module = @import("commit.zig");
const add_module = @import("add.zig");
const ignore_parser = @import("ignore_parser.zig");

pub fn stash(io: std.Io, allocator: std.mem.Allocator, path: []const u8, message: []const u8) ![]const u8 {
    const default_message = "WIP";
    const stash_message = if (message.len == 0) default_message else message;

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const current_status = try status_module.status(io, allocator, path);

    const head_commit_sha_opt = try utils.getCurrentCommit(io, allocator, git_dir_path);
    const head_commit_sha = head_commit_sha_opt orelse {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |item| allocator.free(item);
        allocator.free(current_status.staged);
        for (current_status.modified) |item| allocator.free(item);
        allocator.free(current_status.modified);
        for (current_status.untracked) |item| allocator.free(item);
        allocator.free(current_status.untracked);
        for (current_status.deleted) |item| allocator.free(item);
        allocator.free(current_status.deleted);
        return error.HeadNotFound;
    };
    defer allocator.free(head_commit_sha);

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

    const head_commit_data = try utils.readObject(io, allocator, git_dir_path, head_commit_sha);
    defer allocator.free(head_commit_data);

    const tree_sha_slice = try utils.extractTreeFromCommit(head_commit_data);
    const head_tree_sha = try allocator.dupe(u8, tree_sha_slice);
    defer allocator.free(head_tree_sha);

    var head_tree_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = head_tree_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        head_tree_entries.deinit();
    }

    const head_tree_data = try utils.readObject(io, allocator, git_dir_path, head_tree_sha);
    defer allocator.free(head_tree_data);

    var head_entries = try utils.parseTreeEntries(allocator, head_tree_data);
    defer {
        for (head_entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        head_entries.deinit(allocator);
    }

    for (head_entries.items) |entry| {
        const path_copy = try allocator.dupe(u8, entry.path);
        const sha_copy = try allocator.dupe(u8, entry.sha);
        try head_tree_entries.put(path_copy, sha_copy);
    }

    var has_staged_changes = false;

    var index_iter = index.iterator();
    while (index_iter.next()) |entry| {
        const file_path = entry.key_ptr.*;
        const index_entry = entry.value_ptr.*;

        const head_sha = head_tree_entries.get(file_path);
        if (head_sha) |sha| {
            if (!std.mem.eql(u8, sha, index_entry.sha)) {
                has_staged_changes = true;
                break;
            }
        } else {
            has_staged_changes = true;
            break;
        }
    }

    if (!has_staged_changes and
        current_status.modified.len == 0 and
        current_status.untracked.len == 0 and
        current_status.deleted.len == 0)
    {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |item| allocator.free(item);
        allocator.free(current_status.staged);
        for (current_status.modified) |item| allocator.free(item);
        allocator.free(current_status.modified);
        for (current_status.untracked) |item| allocator.free(item);
        allocator.free(current_status.untracked);
        for (current_status.deleted) |item| allocator.free(item);
        allocator.free(current_status.deleted);
        return error.NothingToStash;
    }

    // Stage modified and untracked files
    for (current_status.modified) |file| {
        try stageFile(io, allocator, path, git_dir_path, file, &index);
    }

    for (current_status.untracked) |file| {
        try stageFile(io, allocator, path, git_dir_path, file, &index);
    }

    // Remove deleted files from the index
    for (current_status.deleted) |file| {
        const old_entry = index.fetchRemove(file);
        if (old_entry) |entry| {
            allocator.free(entry.value.path);
            allocator.free(entry.value.sha);
            allocator.free(entry.value.mode);
        }
    }

    const tree_sha = try commit_module.createTree(io, allocator, git_dir_path, &index);
    defer allocator.free(tree_sha);

    const stash_commit_sha = try commit_module.createCommit(io, allocator, git_dir_path, tree_sha, stash_message, head_commit_sha);

    const stash_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "stash" });
    defer allocator.free(stash_ref_path);

    const stash_ref_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{stash_commit_sha});
    defer allocator.free(stash_ref_with_newline);

    cwd.createDirPath(io, std.fs.path.dirname(stash_ref_path) orelse ".") catch |err| {
        if (err != error.PathAlreadyExists) {
            return err;
        }
    };

    try cwd.writeFile(io, .{ .sub_path = stash_ref_path, .data = stash_ref_with_newline });

    try resetHard(io, allocator, path, git_dir_path, head_commit_sha);

    allocator.free(current_status.branch);
    allocator.free(current_status.up_to_date);
    for (current_status.staged) |item| allocator.free(item);
    allocator.free(current_status.staged);
    for (current_status.modified) |item| allocator.free(item);
    allocator.free(current_status.modified);
    for (current_status.untracked) |item| allocator.free(item);
    allocator.free(current_status.untracked);
    for (current_status.deleted) |item| allocator.free(item);
    allocator.free(current_status.deleted);

    return stash_commit_sha;
}

fn stageFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    git_dir_path: []const u8,
    file_path: []const u8,
    index: *std.StringHashMap(utils.IndexEntry),
) !void {
    const full_path = try std.fs.path.join(allocator, &[_][]const u8{ repo_path, file_path });
    defer allocator.free(full_path);

    const cwd = std.Io.Dir.cwd();
    const content = try cwd.readFileAlloc(io, full_path, allocator, .unlimited);
    defer allocator.free(content);

    const hash = try utils.hashObject(io, allocator, git_dir_path, content, "blob");
    defer allocator.free(hash);

    const file_stat = cwd.statFile(io, full_path, .{}) catch |err| {
        if (err == error.FileNotFound) return err;
        return err;
    };

    const old_entry = index.fetchRemove(file_path);
    if (old_entry) |entry| {
        allocator.free(entry.value.path);
        allocator.free(entry.value.sha);
        allocator.free(entry.value.mode);
    }

    const path_copy = try allocator.dupe(u8, file_path);
    const hash_copy = try allocator.dupe(u8, hash);
    const mode_copy = try allocator.dupe(u8, "100644");

    try index.put(path_copy, .{
        .path = path_copy,
        .sha = hash_copy,
        .mode = mode_copy,
        .size = @intCast(file_stat.size),
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

fn resetHard(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    git_dir_path: []const u8,
    commit_sha: []const u8,
) !void {
    var gitignore = ignore_parser.IgnoreParser.init(allocator);
    defer gitignore.deinit();
    gitignore.loadGitignore(io, path) catch {};

    const cwd = std.Io.Dir.cwd();
    const repo_dir = cwd.openDir(io, path, .{}) catch return error.NotADirectory;
    defer repo_dir.close(io);

    var entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 20) catch unreachable;
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.name);
        }
        entries.deinit(allocator);
    }

    {
        var iter = repo_dir.iterate();
        while (try iter.next(io)) |entry| {
            if (std.mem.eql(u8, entry.name, ".git")) continue;

            const is_dir = entry.kind == .directory;
            if (gitignore.isIgnored(entry.name, is_dir)) continue;

            const name_copy = try allocator.dupe(u8, entry.name);
            const entry_copy = std.Io.Dir.Entry{
                .name = name_copy,
                .kind = entry.kind,
                .inode = entry.inode,
            };
            try entries.append(allocator, entry_copy);
        }
    }

    for (entries.items) |entry| {
        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry.name });
        defer allocator.free(full_path);

        cwd.deleteTree(io, full_path) catch |err| {
            if (err != error.FileNotFound) {
                // Ignore errors
            }
        };
    }

    const commit_data = try utils.readObject(io, allocator, git_dir_path, commit_sha);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    try restoreTree(io, allocator, path, git_dir_path, tree_sha, "");

    try updateIndexFromTree(io, allocator, git_dir_path, path, tree_sha);
}

fn restoreTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    path: []const u8,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    prefix: []const u8,
) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha);
    defer allocator.free(tree_data);

    var entries = try utils.parseTreeEntries(allocator, tree_data);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        entries.deinit(allocator);
    }

    const cwd = std.Io.Dir.cwd();

    for (entries.items) |entry| {
        var entry_path_buf: [512]u8 = undefined;
        const entry_path = if (prefix.len == 0)
            try std.fmt.bufPrint(&entry_path_buf, "{s}", .{entry.path})
        else
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}", .{ prefix, entry.path });

        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const blob_data = try utils.readObject(io, allocator, git_dir_path, entry.sha);
            defer allocator.free(blob_data);

            const content = utils.extractContentFromBlob(blob_data);

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry_path });
            defer allocator.free(full_path);

            const parent_dir = std.fs.path.dirname(full_path) orelse ".";
            cwd.createDirPath(io, parent_dir) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };

            try cwd.writeFile(io, .{ .sub_path = full_path, .data = content });
        } else if (std.mem.eql(u8, entry.entry_type, "tree")) {
            cwd.createDirPath(io, entry_path) catch |err| {
                if (err != error.PathAlreadyExists) {
                    return err;
                }
            };

            const new_prefix = if (prefix.len == 0) entry.path else blk: {
                var buf: [512]u8 = undefined;
                break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
            };

            try restoreTree(io, allocator, path, git_dir_path, entry.sha, new_prefix);
        }
    }
}

fn updateIndexFromTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
    tree_sha: []const u8,
) !void {
    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    var index = std.StringHashMap(utils.IndexEntry).init(allocator);
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

    try updateIndexRecursive(io, allocator, git_dir_path, working_path, tree_sha, "", &index);

    try utils.writeIndex(io, allocator, index_path, index);
}

fn updateIndexRecursive(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
    tree_sha: []const u8,
    prefix: []const u8,
    index: *std.StringHashMap(utils.IndexEntry),
) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha);
    defer allocator.free(tree_data);

    var entries = try utils.parseTreeEntries(allocator, tree_data);
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        entries.deinit(allocator);
    }

    const cwd = std.Io.Dir.cwd();

    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const entry_path = if (prefix.len == 0) entry.path else blk: {
                var buf: [512]u8 = undefined;
                break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
            };

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ working_path, entry_path });
            defer allocator.free(full_path);

            const file_stat = cwd.statFile(io, full_path, .{}) catch |err| {
                if (err == error.FileNotFound) {
                    return;
                }
                return err;
            };

            const path_copy = try allocator.dupe(u8, entry_path);
            const sha_copy = try allocator.dupe(u8, entry.sha);
            const mode_copy = try allocator.dupe(u8, entry.mode);

            if (index.get(path_copy)) |old_entry| {
                allocator.free(old_entry.path);
                allocator.free(old_entry.sha);
                allocator.free(old_entry.mode);
            }

            try index.put(path_copy, .{
                .path = path_copy,
                .sha = sha_copy,
                .mode = mode_copy,
                .size = @intCast(file_stat.size),
                .ctime_seconds = 0,
                .ctime_nanos = 0,
                .mtime_seconds = 0,
                .mtime_nanos = 0,
                .dev = 0,
                .ino = 0,
                .uid = 0,
                .gid = 0,
            });
        } else if (std.mem.eql(u8, entry.entry_type, "tree")) {
            const new_prefix = if (prefix.len == 0) entry.path else blk: {
                var buf: [512]u8 = undefined;
                break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
            };

            try updateIndexRecursive(io, allocator, git_dir_path, working_path, entry.sha, new_prefix, index);
        }
    }
}

pub fn unstash(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const stash_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "stash" });
    defer allocator.free(stash_ref_path);

    const stash_commit_sha = cwd.readFileAlloc(io, stash_ref_path, allocator, .unlimited) catch {
        return error.NoStashFound;
    };
    defer allocator.free(stash_commit_sha);

    const trimmed_sha = std.mem.trim(u8, stash_commit_sha, &std.ascii.whitespace);

    const stash_commit_data = try utils.readObject(io, allocator, git_dir_path, trimmed_sha);
    defer allocator.free(stash_commit_data);

    const tree_sha = try utils.extractTreeFromCommit(stash_commit_data);

    try restoreTree(io, allocator, path, git_dir_path, tree_sha, "");
}
