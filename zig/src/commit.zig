const std = @import("std");

const utils = @import("utils.zig");
const getCurrentBranch = @import("branch.zig").getCurrentBranch;
const getCurrentCommit = @import("branch.zig").getCurrentCommit;

const status_module = @import("status.zig");

pub fn commit(io: std.Io, allocator: std.mem.Allocator, path: []const u8, message: []const u8) ![]const u8 {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const current_status = try status_module.status(io, allocator, path);
    defer current_status.deinit(allocator);

    if (current_status.staged.len == 0 and
        current_status.modified.len == 0 and
        current_status.untracked.len == 0 and
        current_status.deleted.len == 0)
    {
        return error.NothingToCommit;
    }

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

    if (index.count() == 0) {
        return error.NoFilesStaged;
    }

    const tree_sha = try createTree(io, allocator, git_dir_path, &index);
    defer allocator.free(tree_sha);

    const parent_sha_opt = try getCurrentCommit(io, allocator, git_dir_path);

    const commit_sha = try createCommit(io, allocator, git_dir_path, tree_sha, message, parent_sha_opt);

    if (parent_sha_opt) |parent_sha| {
        allocator.free(parent_sha);
    }

    const branch_name = try getCurrentBranch(io, allocator, git_dir_path);
    defer allocator.free(branch_name);

    try utils.updateBranch(io, allocator, git_dir_path, branch_name, commit_sha);

    return commit_sha;
}

pub fn createTree(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, index: *const std.StringHashMap(utils.IndexEntry)) ![]const u8 {
    return createTreeRecursive(io, allocator, git_dir_path, index, "");
}

fn createTreeRecursive(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    index: *const std.StringHashMap(utils.IndexEntry),
    prefix: []const u8,
) ![]const u8 {
    var paths = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit(allocator);
    }

    var iter = index.iterator();
    while (iter.next()) |entry| {
        const path = entry.key_ptr.*;
        if (shouldIncludeInTree(path, prefix)) {
            try paths.append(allocator, try allocator.dupe(u8, path));
        }
    }

    std.sort.insertion([]const u8, paths.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var tree_entries = std.ArrayList(utils.TreeEntry).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (tree_entries.items) |entry| {
            allocator.free(entry.path);
            allocator.free(entry.sha);
            allocator.free(entry.mode);
            allocator.free(entry.entry_type);
        }
        tree_entries.deinit(allocator);
    }

    for (paths.items) |path| {
        const entry = index.get(path).?;
        // Use the SHA from the index entry directly - it was computed during add

        const entry_path = if (prefix.len == 0) path else path[prefix.len + 1 ..];

        try tree_entries.append(allocator, .{
            .path = try allocator.dupe(u8, entry_path),
            .sha = try allocator.dupe(u8, entry.sha),
            .mode = try allocator.dupe(u8, entry.mode),
            .entry_type = try allocator.dupe(u8, "blob"),
        });
    }

    var subdirs = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var subdir_iter = subdirs.iterator();
        while (subdir_iter.next()) |subdir_entry| {
            for (subdir_entry.value_ptr.*.items) |p| allocator.free(p);
            subdir_entry.value_ptr.*.deinit(allocator);
            allocator.free(subdir_entry.key_ptr.*);
        }
        subdirs.deinit();
    }

    iter = index.iterator();
    while (iter.next()) |entry| {
        const path = entry.key_ptr.*;
        if (std.mem.indexOf(u8, path, "/") != null) {
            const dir = getSubdirectory(path, prefix);
            if (dir) |dir_name| {
                const dir_entry = try subdirs.getOrPut(dir_name);
                if (!dir_entry.found_existing) {
                    dir_entry.value_ptr.* = std.ArrayList([]const u8).initCapacity(allocator, 5) catch unreachable;
                    dir_entry.key_ptr.* = try allocator.dupe(u8, dir_name);
                }
                try dir_entry.value_ptr.*.append(allocator, try allocator.dupe(u8, path));
            }
        }
    }

    var subdir_iter = subdirs.iterator();
    while (subdir_iter.next()) |subdir_entry| {
        const dir_name = subdir_entry.key_ptr.*;
        var dir_prefix: []const u8 = dir_name;
        var need_free = false;

        if (prefix.len != 0) {
            dir_prefix = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, dir_name });
            need_free = true;
        }

        const dir_sha = try createTreeRecursive(io, allocator, git_dir_path, index, dir_prefix);

        if (need_free) {
            allocator.free(dir_prefix);
        }

        try tree_entries.append(allocator, .{
            .path = try allocator.dupe(u8, dir_name),
            .sha = dir_sha,
            .mode = try allocator.dupe(u8, "040000"),
            .entry_type = try allocator.dupe(u8, "tree"),
        });
    }

    // Sort entries by path (Git requires this)
    std.sort.insertion(utils.TreeEntry, tree_entries.items, {}, struct {
        fn lessThan(_: void, a: utils.TreeEntry, b: utils.TreeEntry) bool {
            return std.mem.lessThan(u8, a.path, b.path);
        }
    }.lessThan);

    // Build tree content as binary data
    // Format: <mode> <name>\0<20-byte SHA> for each entry
    var tree_content = std.ArrayList(u8).initCapacity(allocator, 100) catch unreachable;
    defer tree_content.deinit(allocator);

    for (tree_entries.items) |entry| {
        try tree_content.appendSlice(allocator, entry.mode);
        try tree_content.appendSlice(allocator, " ");
        try tree_content.appendSlice(allocator, entry.path);
        try tree_content.append(allocator, 0);

        // Convert hex SHA back to bytes
        var sha_bytes: [20]u8 = undefined;
        for (0..20) |i| {
            const byte_high = std.fmt.charToDigit(entry.sha[2 * i], 16) catch 0;
            const byte_low = std.fmt.charToDigit(entry.sha[2 * i + 1], 16) catch 0;
            sha_bytes[i] = byte_high * 16 + byte_low;
        }
        try tree_content.appendSlice(allocator, &sha_bytes);
    }

    return utils.hashObjectBinary(io, allocator, git_dir_path, tree_content.items, "tree");
}

fn shouldIncludeInTree(path: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0) {
        return std.mem.indexOf(u8, path, "/") == null;
    }

    if (!std.mem.startsWith(u8, path, prefix)) {
        return false;
    }

    if (path.len <= prefix.len + 1) {
        return false;
    }

    const remaining = path[prefix.len + 1 ..];
    return std.mem.indexOf(u8, remaining, "/") == null;
}

fn getSubdirectory(path: []const u8, prefix: []const u8) ?[]const u8 {
    if (prefix.len == 0) {
        const slash_idx = std.mem.indexOf(u8, path, "/") orelse return null;
        return path[0..slash_idx];
    }

    if (!std.mem.startsWith(u8, path, prefix)) {
        return null;
    }

    if (path.len <= prefix.len + 1) {
        return null;
    }

    const remaining = path[prefix.len + 1 ..];
    const slash_idx = std.mem.indexOf(u8, remaining, "/") orelse return null;
    return remaining[0..slash_idx];
}

pub fn createCommit(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    message: []const u8,
    parent_sha_opt: ?[]const u8,
) ![]const u8 {
    const timestamp: i64 = 0;

    const offset_seconds = 0;
    const sign_char: u8 = if (offset_seconds >= 0) '+' else '-';
    const abs_offset = @abs(offset_seconds);
    const hours = abs_offset / 3600;
    const minutes = (abs_offset % 3600) / 60;

    const author = try std.fmt.allocPrint(allocator, "User <user@example.com> {d} {c}{d:0>2}{d:0>2}", .{ timestamp, sign_char, hours, minutes });
    defer allocator.free(author);

    var commit_content = std.ArrayList(u8).initCapacity(allocator, 200) catch unreachable;
    defer commit_content.deinit(allocator);

    try commit_content.appendSlice(allocator, "tree ");
    try commit_content.appendSlice(allocator, tree_sha);
    try commit_content.appendSlice(allocator, "\n");

    if (parent_sha_opt) |parent_sha| {
        try commit_content.appendSlice(allocator, "parent ");
        try commit_content.appendSlice(allocator, parent_sha);
        try commit_content.appendSlice(allocator, "\n");
    }

    try commit_content.appendSlice(allocator, "author ");
    try commit_content.appendSlice(allocator, author);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "committer ");
    try commit_content.appendSlice(allocator, author);
    try commit_content.appendSlice(allocator, "\n");
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, message);
    try commit_content.appendSlice(allocator, "\n");

    return utils.hashObject(io, allocator, git_dir_path, commit_content.items, "commit");
}
