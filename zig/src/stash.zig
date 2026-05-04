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

    const commit_data = try utils.readObject(io, allocator, git_dir_path, commit_sha);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    var target_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = target_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        target_entries.deinit();
    }
    try flattenTree(io, allocator, git_dir_path, tree_sha, "", &target_entries);

    try resetHardDir(io, allocator, path, path, git_dir_path, gitignore, &target_entries);

    // Create any remaining target files
    {
        var remaining = target_entries.iterator();
        while (remaining.next()) |entry| {
            const file_path = entry.key_ptr.*;
            const sha = entry.value_ptr.*;

            const blob_data = try utils.readObject(io, allocator, git_dir_path, sha);
            defer allocator.free(blob_data);

            const content = utils.extractContentFromBlob(blob_data);
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file_path });
            defer allocator.free(full_path);

            const parent = std.fs.path.dirname(full_path) orelse ".";
            const cwd = std.Io.Dir.cwd();
            cwd.createDirPath(io, parent) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };

            try cwd.writeFile(io, .{ .sub_path = full_path, .data = content });
        }
    }

    try updateIndexFromTree(io, allocator, git_dir_path, path, tree_sha);
}

fn resetHardDir(
    io: std.Io,
    allocator: std.mem.Allocator,
    repo_path: []const u8,
    current_dir: []const u8,
    git_dir_path: []const u8,
    gitignore: ignore_parser.IgnoreParser,
    target_entries: *std.StringHashMap([]const u8),
) !void {
    const cwd = std.Io.Dir.cwd();
    const dir = cwd.openDir(io, current_dir, .{}) catch return;
    defer dir.close(io);

    var entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 20) catch unreachable;
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.name);
        }
        entries.deinit(allocator);
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
            try entries.append(allocator, entry_copy);
        }
    }

    const dir_rel = if (std.mem.eql(u8, current_dir, repo_path))
        ""
    else
        current_dir[repo_path.len + 1 ..];

    for (entries.items) |entry| {
        const rel_path = if (dir_rel.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_rel, entry.name });
        defer allocator.free(rel_path);

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ current_dir, entry.name });
        defer allocator.free(full_path);

        const is_dir = entry.kind == .directory;
        if (gitignore.isIgnored(rel_path, is_dir)) continue;

        if (entry.kind == .directory) {
            // Check if any target file is under this directory
            var has_target_files = false;
            var target_iter = target_entries.iterator();
            while (target_iter.next()) |tentry| {
                const target_path = tentry.key_ptr.*;
                if (std.mem.eql(u8, target_path, rel_path) or
                    (std.mem.startsWith(u8, target_path, rel_path) and target_path.len > rel_path.len and target_path[rel_path.len] == '/'))
                {
                    has_target_files = true;
                    break;
                }
            }

            if (!has_target_files) {
                cwd.deleteTree(io, full_path) catch |err| {
                    if (err != error.FileNotFound) {
                        // Ignore errors
                    }
                };
                continue;
            }

            try resetHardDir(io, allocator, repo_path, full_path, git_dir_path, gitignore, target_entries);
        } else {
            const target_sha = target_entries.get(rel_path);
            if (target_sha) |sha| {
                const file_content = cwd.readFileAlloc(io, full_path, allocator, .unlimited) catch |err| {
                    if (err == error.FileNotFound) {
                        _ = target_entries.fetchRemove(rel_path);
                        continue;
                    }
                    return err;
                };
                defer allocator.free(file_content);

                const current_hash = try utils.hashObject(io, allocator, git_dir_path, file_content, "blob");
                defer allocator.free(current_hash);

                if (!std.mem.eql(u8, current_hash, sha)) {
                    const blob_data = try utils.readObject(io, allocator, git_dir_path, sha);
                    defer allocator.free(blob_data);
                    const content = utils.extractContentFromBlob(blob_data);
                    try cwd.writeFile(io, .{ .sub_path = full_path, .data = content });
                }

                const removed = target_entries.fetchRemove(rel_path);
                if (removed) |kv| {
                    allocator.free(kv.key);
                    allocator.free(kv.value);
                }
            } else {
                cwd.deleteFile(io, full_path) catch |err| {
                    if (err != error.FileNotFound) {
                        // Ignore errors
                    }
                };
            }
        }
    }
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

    const stash_commit_sha_raw = cwd.readFileAlloc(io, stash_ref_path, allocator, .unlimited) catch {
        return error.NoStashFound;
    };
    defer allocator.free(stash_commit_sha_raw);

    const stash_commit_sha = std.mem.trim(u8, stash_commit_sha_raw, &std.ascii.whitespace);

    const stash_commit_data = try utils.readObject(io, allocator, git_dir_path, stash_commit_sha);
    defer allocator.free(stash_commit_data);

    const stash_tree_sha = try utils.extractTreeFromCommit(stash_commit_data);

    const merge_base_sha = extractParentFromCommit(stash_commit_data) orelse {
        try restoreTree(io, allocator, path, git_dir_path, stash_tree_sha, "");
        return;
    };

    const current_head_sha_opt = try utils.getCurrentCommit(io, allocator, git_dir_path);
    const current_head_sha = current_head_sha_opt orelse {
        try restoreTree(io, allocator, path, git_dir_path, stash_tree_sha, "");
        return;
    };
    defer allocator.free(current_head_sha);

    if (std.mem.eql(u8, current_head_sha, merge_base_sha)) {
        try restoreTree(io, allocator, path, git_dir_path, stash_tree_sha, "");
        return;
    }

    const merge_base_tree_data = try utils.readObject(io, allocator, git_dir_path, merge_base_sha);
    defer allocator.free(merge_base_tree_data);

    const merge_base_tree_sha = try utils.extractTreeFromCommit(merge_base_tree_data);
    var merge_base_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = merge_base_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        merge_base_entries.deinit();
    }
    try flattenTree(io, allocator, git_dir_path, merge_base_tree_sha, "", &merge_base_entries);

    const current_head_data = try utils.readObject(io, allocator, git_dir_path, current_head_sha);
    defer allocator.free(current_head_data);

    const current_head_tree_sha = try utils.extractTreeFromCommit(current_head_data);
    var current_head_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = current_head_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        current_head_entries.deinit();
    }
    try flattenTree(io, allocator, git_dir_path, current_head_tree_sha, "", &current_head_entries);

    var stash_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = stash_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        stash_entries.deinit();
    }
    try flattenTree(io, allocator, git_dir_path, stash_tree_sha, "", &stash_entries);

    var merged_entries = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = merged_entries.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        merged_entries.deinit();
    }

    {
        var stash_iter = stash_entries.iterator();
        while (stash_iter.next()) |entry| {
            const file_path = entry.key_ptr.*;
            const sha = entry.value_ptr.*;

            const base_sha = merge_base_entries.get(file_path);
            const current_sha = current_head_entries.get(file_path);

            if (current_sha == null or (base_sha != null and std.mem.eql(u8, current_sha.?, base_sha.?))) {
                const key_copy = try allocator.dupe(u8, file_path);
                const val_copy = try allocator.dupe(u8, sha);
                try merged_entries.put(key_copy, val_copy);
                continue;
            }

            if (base_sha != null and std.mem.eql(u8, sha, base_sha.?)) {
                const key_copy = try allocator.dupe(u8, file_path);
                const val_copy = try allocator.dupe(u8, current_sha.?);
                try merged_entries.put(key_copy, val_copy);
                continue;
            }

            const base_content = if (base_sha) |bs| try readBlobContent(io, allocator, git_dir_path, bs) else "";
            defer if (base_sha != null) allocator.free(base_content);
            const stash_content = try readBlobContent(io, allocator, git_dir_path, sha);
            defer allocator.free(stash_content);
            const current_content = try readBlobContent(io, allocator, git_dir_path, current_sha.?);
            defer allocator.free(current_content);

            const merged = try threeWayMerge(allocator, base_content, stash_content, current_content);
            defer allocator.free(merged);
            const merged_sha = try utils.hashObject(io, allocator, git_dir_path, merged, "blob");
            defer allocator.free(merged_sha);

            const key_copy = try allocator.dupe(u8, file_path);
            const val_copy = try allocator.dupe(u8, merged_sha);
            try merged_entries.put(key_copy, val_copy);
        }
    }

    {
        var head_iter = current_head_entries.iterator();
        while (head_iter.next()) |entry| {
            const file_path = entry.key_ptr.*;
            const sha = entry.value_ptr.*;

            if (merged_entries.contains(file_path)) continue;

            const base_sha = merge_base_entries.get(file_path);
            if (base_sha != null and !std.mem.eql(u8, sha, base_sha.?)) {
                const key_copy = try allocator.dupe(u8, file_path);
                const val_copy = try allocator.dupe(u8, sha);
                try merged_entries.put(key_copy, val_copy);
            }
        }
    }

    {
        var merged_iter = merged_entries.iterator();
        while (merged_iter.next()) |entry| {
            const file_path = entry.key_ptr.*;
            const sha = entry.value_ptr.*;

            const content = try readBlobContent(io, allocator, git_dir_path, sha);
            defer allocator.free(content);

            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file_path });
            defer allocator.free(full_path);

            const parent_dir = std.fs.path.dirname(full_path) orelse ".";
            cwd.createDirPath(io, parent_dir) catch |err| {
                if (err != error.PathAlreadyExists) return err;
            };

            try cwd.writeFile(io, .{ .sub_path = full_path, .data = content });
        }
    }
}

fn extractParentFromCommit(commit_data: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, commit_data, "\n");
    while (lines.next()) |line| {
        if (line.len == 0) break;
        if (std.mem.startsWith(u8, line, "parent ")) {
            return line[7..];
        }
    }
    return null;
}

fn flattenTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    prefix: []const u8,
    entries: *std.StringHashMap([]const u8),
) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha);
    defer allocator.free(tree_data);

    var tree_entries = try utils.parseTreeEntries(allocator, tree_data);
    defer {
        for (tree_entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        tree_entries.deinit(allocator);
    }

    for (tree_entries.items) |entry| {
        var entry_path_buf: [512]u8 = undefined;
        const entry_path = if (prefix.len == 0)
            try std.fmt.bufPrint(&entry_path_buf, "{s}", .{entry.path})
        else
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}", .{ prefix, entry.path });

        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const key_copy = try allocator.dupe(u8, entry_path);
            const val_copy = try allocator.dupe(u8, entry.sha);
            try entries.put(key_copy, val_copy);
        } else if (std.mem.eql(u8, entry.entry_type, "tree")) {
            try flattenTree(io, allocator, git_dir_path, entry.sha, entry_path, entries);
        }
    }
}

fn readBlobContent(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8) ![]const u8 {
    const blob_data = try utils.readObject(io, allocator, git_dir_path, sha);
    defer allocator.free(blob_data);
    const content = utils.extractContentFromBlob(blob_data);
    return try allocator.dupe(u8, content);
}

fn threeWayMerge(
    allocator: std.mem.Allocator,
    base: []const u8,
    theirs: []const u8,
    ours: []const u8,
) ![]const u8 {
    if (std.mem.eql(u8, base, ours)) return try allocator.dupe(u8, theirs);
    if (std.mem.eql(u8, base, theirs)) return try allocator.dupe(u8, ours);

    var base_lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer base_lines.deinit(allocator);
    var theirs_lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer theirs_lines.deinit(allocator);
    var ours_lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer ours_lines.deinit(allocator);

    splitLines(allocator, base, &base_lines);
    splitLines(allocator, theirs, &theirs_lines);
    splitLines(allocator, ours, &ours_lines);

    var base_to_theirs = std.StringHashMap(DiffChange).init(allocator);
    defer {
        var iter = base_to_theirs.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        base_to_theirs.deinit();
    }
    try diffLines(allocator, base_lines.items, theirs_lines.items, &base_to_theirs);

    var base_to_ours = std.StringHashMap(DiffChange).init(allocator);
    defer {
        var iter = base_to_ours.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        base_to_ours.deinit();
    }
    try diffLines(allocator, base_lines.items, ours_lines.items, &base_to_ours);

    var result = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer result.deinit(allocator);

    var bi: usize = 0;
    var ti: usize = 0;
    var oi: usize = 0;

    while (bi < base_lines.items.len) {
        var bi_buf: [20]u8 = undefined;
        const bi_key = try std.fmt.bufPrint(&bi_buf, "{}", .{bi});
        const theirs_change = base_to_theirs.get(bi_key);
        const ours_change = base_to_ours.get(bi_key);

        if (theirs_change != null and ours_change != null) {
            const tc = theirs_change.?;
            const oc = ours_change.?;

            if (std.mem.eql(u8, tc.change_type, "replace") and std.mem.eql(u8, oc.change_type, "replace")) {
                if (stringsEqual(tc.lines, oc.lines)) {
                    for (tc.lines) |line| try result.append(allocator, line);
                } else {
                    try result.append(allocator, "<<<<<<< Updated upstream");
                    for (oc.lines) |line| try result.append(allocator, line);
                    try result.append(allocator, "=======");
                    for (tc.lines) |line| try result.append(allocator, line);
                    try result.append(allocator, ">>>>>>> Stashed changes");
                }
            } else if (std.mem.eql(u8, tc.change_type, "delete") and std.mem.eql(u8, oc.change_type, "delete")) {
                // Both deleted
            } else if (std.mem.eql(u8, tc.change_type, "insert") and std.mem.eql(u8, oc.change_type, "insert")) {
                if (stringsEqual(tc.lines, oc.lines)) {
                    for (tc.lines) |line| try result.append(allocator, line);
                } else {
                    for (oc.lines) |line| try result.append(allocator, line);
                    for (tc.lines) |line| try result.append(allocator, line);
                }
            } else {
                try result.append(allocator, "<<<<<<< Updated upstream");
                for (oc.lines) |line| try result.append(allocator, line);
                try result.append(allocator, "=======");
                for (tc.lines) |line| try result.append(allocator, line);
                try result.append(allocator, ">>>>>>> Stashed changes");
            }
        } else if (theirs_change != null) {
            for (theirs_change.?.lines) |line| try result.append(allocator, line);
        } else if (ours_change != null) {
            for (ours_change.?.lines) |line| try result.append(allocator, line);
        } else {
            try result.append(allocator, base_lines.items[bi]);
        }

        bi += 1;
        ti += (if (theirs_change != null) theirs_change.?.skip + 1 else @as(usize, 1));
        oi += (if (ours_change != null) ours_change.?.skip + 1 else @as(usize, 1));
    }

    while (ti < theirs_lines.items.len) {
        try result.append(allocator, theirs_lines.items[ti]);
        ti += 1;
    }
    while (oi < ours_lines.items.len) {
        try result.append(allocator, ours_lines.items[oi]);
        oi += 1;
    }

    return try std.mem.join(allocator, "\n", result.items);
}

const DiffChange = struct {
    change_type: []const u8,
    lines: []const []const u8,
    skip: usize,
};

fn splitLines(allocator: std.mem.Allocator, content: []const u8, list: *std.ArrayList([]const u8)) void {
    if (content.len == 0) return;
    var start: usize = 0;
    for (content, 0..) |ch, i| {
        if (ch == '\n') {
            list.append(allocator, content[start..i]) catch unreachable;
            start = i + 1;
        }
    }
    if (start < content.len) {
        list.append(allocator, content[start..]) catch unreachable;
    }
}

fn diffLines(
    allocator: std.mem.Allocator,
    base: []const []const u8,
    modified: []const []const u8,
    changes: *std.StringHashMap(DiffChange),
) !void {
    var lcs = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer lcs.deinit(allocator);
    try longestCommonSubsequence(allocator, base, modified, &lcs);

    var bi: usize = 0;
    var mi: usize = 0;
    var lcs_idx: usize = 0;

    while (bi < base.len or mi < modified.len) {
        if (lcs_idx < lcs.items.len and bi < base.len and mi < modified.len) {
            if (std.mem.eql(u8, base[bi], lcs.items[lcs_idx]) and std.mem.eql(u8, modified[mi], lcs.items[lcs_idx])) {
                bi += 1;
                mi += 1;
                lcs_idx += 1;
                continue;
            }
        }

        const start_bi = bi;
        while (bi < base.len and (lcs_idx >= lcs.items.len or !std.mem.eql(u8, base[bi], lcs.items[lcs_idx]))) {
            bi += 1;
        }
        const base_count = bi - start_bi;

        const start_mi = mi;
        while (mi < modified.len and (lcs_idx >= lcs.items.len or !std.mem.eql(u8, modified[mi], lcs.items[lcs_idx]))) {
            mi += 1;
        }
        const mod_count = mi - start_mi;

        if (base_count > 0 or mod_count > 0) {
            var bi_buf: [20]u8 = undefined;
            const key = try std.fmt.bufPrint(&bi_buf, "{}", .{start_bi});
            const key_copy = try allocator.dupe(u8, key);

            if (base_count == 0 and mod_count > 0) {
                try changes.put(key_copy, .{
                    .change_type = "insert",
                    .lines = modified[start_mi..mi],
                    .skip = 0,
                });
            } else if (base_count > 0 and mod_count == 0) {
                try changes.put(key_copy, .{
                    .change_type = "delete",
                    .lines = &[_][]const u8{},
                    .skip = base_count - 1,
                });
            } else {
                try changes.put(key_copy, .{
                    .change_type = "replace",
                    .lines = modified[start_mi..mi],
                    .skip = base_count - 1,
                });
            }
        }

        if (lcs_idx < lcs.items.len and bi < base.len and std.mem.eql(u8, base[bi], lcs.items[lcs_idx])) {
            bi += 1;
            mi += 1;
            lcs_idx += 1;
        }
    }
}

fn longestCommonSubsequence(
    allocator: std.mem.Allocator,
    a: []const []const u8,
    b: []const []const u8,
    result: *std.ArrayList([]const u8),
) !void {
    const m = a.len;
    const n = b.len;

    var dp = std.ArrayList(std.ArrayList(u32)).initCapacity(allocator, 0) catch unreachable;
    defer {
        var i: usize = 0;
        while (i < dp.items.len) : (i += 1) {
            dp.items[i].deinit(allocator);
        }
        dp.deinit(allocator);
    }

    for (0..m + 1) |_| {
        var row = std.ArrayList(u32).initCapacity(allocator, 0) catch unreachable;
        for (0..n + 1) |_| {
            row.append(allocator, 0) catch unreachable;
        }
        try dp.append(allocator, row);
    }

    for (1..m + 1) |i| {
        for (1..n + 1) |j| {
            if (std.mem.eql(u8, a[i - 1], b[j - 1])) {
                dp.items[i].items[j] = dp.items[i - 1].items[j - 1] + 1;
            } else {
                dp.items[i].items[j] = @max(dp.items[i - 1].items[j], dp.items[i].items[j - 1]);
            }
        }
    }

    var temp = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer temp.deinit(allocator);

    var ii: usize = m;
    var jj: usize = n;
    while (ii > 0 and jj > 0) {
        if (std.mem.eql(u8, a[ii - 1], b[jj - 1])) {
            try temp.append(allocator, a[ii - 1]);
            ii -= 1;
            jj -= 1;
        } else if (dp.items[ii - 1].items[jj] > dp.items[ii].items[jj - 1]) {
            ii -= 1;
        } else {
            jj -= 1;
        }
    }

    for (0..temp.items.len) |i| {
        try result.append(allocator, temp.items[temp.items.len - 1 - i]);
    }
}

fn stringsEqual(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |aa, bb| {
        if (!std.mem.eql(u8, aa, bb)) return false;
    }
    return true;
}
