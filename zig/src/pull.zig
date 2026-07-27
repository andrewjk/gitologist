const std = @import("std");

const utils = @import("utils.zig");
const fetch = @import("fetch.zig");
const getCurrentBranch = @import("branch.zig").getCurrentBranch;
const getCurrentCommit = @import("branch.zig").getCurrentCommit;
const RemoteOptions = @import("types/RemoteOptions.zig").RemoteOptions;

pub fn pull(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote: ?[]const u8, branch: ?[]const u8, options: ?*const RemoteOptions) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const remote_name = if (remote) |r| r else "origin";

    var fetch_result = try fetch.fetchOrigin(io, allocator, path, remote_name, options);
    defer {
        allocator.free(fetch_result.remote);
        for (fetch_result.refs.items) |ref| {
            allocator.free(ref.name);
            allocator.free(ref.sha);
        }
        fetch_result.refs.deinit(allocator);
    }

    var branch_name: []const u8 = undefined;
    var free_branch_name = false;

    if (branch) |b| {
        branch_name = b;
    } else {
        branch_name = try getCurrentBranch(io, allocator, git_dir_path);
        free_branch_name = true;
    }
    defer if (free_branch_name) allocator.free(branch_name);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name, branch_name });
    defer allocator.free(remote_branch_path);

    const remote_branch_file = cwd.openFile(io, remote_branch_path, .{}) catch {
        return error.RemoteBranchDoesNotExist;
    };
    remote_branch_file.close(io);

    const remote_commit_sha_with_newline = try cwd.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_commit_sha_with_newline);

    const remote_commit_sha = std.mem.trim(u8, remote_commit_sha_with_newline, &std.ascii.whitespace);

    const current_commit_sha_opt = try getCurrentCommit(io, allocator, git_dir_path);

    if (current_commit_sha_opt == null) {
        const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
        defer allocator.free(local_branch_path);

        const local_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
        defer allocator.free(local_branch_dir);

        try cwd.createDirPath(io, local_branch_dir);

        const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{remote_commit_sha});
        defer allocator.free(commit_with_newline);

        try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = commit_with_newline });

        const commit_data = try utils.readObject(io, allocator, git_dir_path, remote_commit_sha, &cache);
        defer allocator.free(commit_data);

        const tree_sha = try utils.extractTreeFromCommit(commit_data);

        var current_blobs = std.StringHashMap([]const u8).init(allocator);
        defer current_blobs.deinit();

        try extractTreeToWorkingDirectory(io, allocator, git_dir_path, path, tree_sha, &current_blobs, &cache);

        try updateIndex(io, allocator, git_dir_path, tree_sha, &cache);
        return;
    }

    const current_commit_sha = current_commit_sha_opt.?;
    defer allocator.free(current_commit_sha);

    if (std.mem.eql(u8, current_commit_sha, remote_commit_sha)) {
        return;
    }

    const is_ancestor = try isAncestorOf(io, allocator, git_dir_path, current_commit_sha, remote_commit_sha, &cache);

    const current_tree_sha_opt = try getTree(io, allocator, git_dir_path, current_commit_sha, &cache);
    defer if (current_tree_sha_opt) |sha| allocator.free(sha);

    var current_blobs = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = current_blobs.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        current_blobs.deinit();
    }

    if (current_tree_sha_opt) |tree_sha| {
        try getTreeBlobs(io, allocator, git_dir_path, tree_sha, "", &current_blobs, &cache);
    }

    if (is_ancestor) {
        const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
        defer allocator.free(local_branch_path);

        const local_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
        defer allocator.free(local_branch_dir);

        try cwd.createDirPath(io, local_branch_dir);

        const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{remote_commit_sha});
        defer allocator.free(commit_with_newline);

        try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = commit_with_newline });

        const commit_data = try utils.readObject(io, allocator, git_dir_path, remote_commit_sha, &cache);
        defer allocator.free(commit_data);

        const tree_sha = try utils.extractTreeFromCommit(commit_data);

        try checkForLocalChanges(io, allocator, git_dir_path, path, &current_blobs, tree_sha, &cache);
        try extractTreeToWorkingDirectory(io, allocator, git_dir_path, path, tree_sha, &current_blobs, &cache);

        try updateIndex(io, allocator, git_dir_path, tree_sha, &cache);
        return;
    }

    const merge_base = try findMergeBase(io, allocator, git_dir_path, current_commit_sha, remote_commit_sha, &cache);

    if (merge_base) |base| {
        if (std.mem.eql(u8, base, remote_commit_sha)) {
            allocator.free(base);
            return;
        }
        allocator.free(base);
    }

    const merge_commit_sha = try createMergeCommit(io, allocator, git_dir_path, current_commit_sha, remote_commit_sha, branch_name, remote_name, &cache);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(local_branch_path);

    const local_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
    defer allocator.free(local_branch_dir);

    try cwd.createDirPath(io, local_branch_dir);

    const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{merge_commit_sha});
    defer allocator.free(commit_with_newline);

    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = commit_with_newline });

    const commit_data = try utils.readObject(io, allocator, git_dir_path, merge_commit_sha, &cache);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    try checkForLocalChanges(io, allocator, git_dir_path, path, &current_blobs, tree_sha, &cache);
    try extractTreeToWorkingDirectory(io, allocator, git_dir_path, path, tree_sha, &current_blobs, &cache);

    try updateIndex(io, allocator, git_dir_path, tree_sha, &cache);
}

/// Checks out the tree of `commit_sha` into the working directory and index,
/// guarding against overwriting uncommitted changes. Shared by `pull` and `switchBranch`.
pub fn checkoutTree(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, working_path: []const u8, commit_sha: []const u8, pack_cache: *utils.PackfileCache) !void {
    const commit_data = try utils.readObject(io, allocator, git_dir_path, commit_sha, pack_cache);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    var current_blobs = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = current_blobs.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        current_blobs.deinit();
    }

    const current_commit_sha_opt = try getCurrentCommit(io, allocator, git_dir_path);
    if (current_commit_sha_opt) |current_commit_sha| {
        defer allocator.free(current_commit_sha);

        const current_tree_sha_opt = try getTree(io, allocator, git_dir_path, current_commit_sha, pack_cache);
        if (current_tree_sha_opt) |current_tree_sha| {
            defer allocator.free(current_tree_sha);
            try getTreeBlobs(io, allocator, git_dir_path, current_tree_sha, "", &current_blobs, pack_cache);
        }
    }

    try checkForLocalChanges(io, allocator, git_dir_path, working_path, &current_blobs, tree_sha, pack_cache);
    try extractTreeToWorkingDirectory(io, allocator, git_dir_path, working_path, tree_sha, &current_blobs, pack_cache);
    try updateIndex(io, allocator, git_dir_path, tree_sha, pack_cache);
}

fn getTreeBlobs(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, tree_sha: []const u8, prefix: []const u8, blobs: *std.StringHashMap([]const u8), pack_cache: *utils.PackfileCache) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha, pack_cache);
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

    for (entries.items) |entry| {
        const path = if (prefix.len == 0) entry.path else blk: {
            var buf: [512]u8 = undefined;
            break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
        };

        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const path_copy = try allocator.dupe(u8, path);
            const sha_copy = try allocator.dupe(u8, entry.sha);
            errdefer allocator.free(path_copy);
            errdefer allocator.free(sha_copy);
            try blobs.put(path_copy, sha_copy);
        } else if (std.mem.eql(u8, entry.entry_type, "tree")) {
            try getTreeBlobs(io, allocator, git_dir_path, entry.sha, path, blobs, pack_cache);
        }
    }
}

fn checkForLocalChanges(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, working_path: []const u8, current_blobs: *const std.StringHashMap([]const u8), new_tree_sha: []const u8, pack_cache: *utils.PackfileCache) !void {
    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    var index = try utils.getIndex(io, allocator, index_path);
    defer {
        var iter = index.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.value_ptr.path);
            allocator.free(entry.value_ptr.sha);
            allocator.free(entry.value_ptr.mode);
        }
        index.deinit();
    }

    var new_blobs = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = new_blobs.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        new_blobs.deinit();
    }

    try getTreeBlobs(io, allocator, git_dir_path, new_tree_sha, "", &new_blobs, pack_cache);

    var new_iter = new_blobs.iterator();
    while (new_iter.next()) |new_entry| {
        const path = new_entry.key_ptr.*;
        const new_sha = new_entry.value_ptr.*;

        const current_sha = current_blobs.get(path);
        if (current_sha != null and std.mem.eql(u8, current_sha.?, new_sha)) {
            continue;
        }

        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ working_path, path });
        defer allocator.free(full_path);

        const cwd = std.Io.Dir.cwd();
        const file = cwd.openFile(io, full_path, .{}) catch |err| {
            if (err == error.FileNotFound) continue else return err;
        };
        file.close(io);

        const index_entry = index.get(path) orelse continue;

        const current_hash = try utils.hashFileAsBlob(io, allocator, full_path);
        defer allocator.free(current_hash);

        if (!std.mem.eql(u8, current_hash, index_entry.sha)) {
            return error.LocalChangesWouldBeOverwritten;
        }
    }
}

fn extractTreeToWorkingDirectory(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
    tree_sha: []const u8,
    current_blobs: *const std.StringHashMap([]const u8),
    pack_cache: *utils.PackfileCache,
) !void {
    try extractTreeRecursive(io, allocator, git_dir_path, working_path, tree_sha, "", current_blobs, pack_cache);
}

fn extractTreeRecursive(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
    tree_sha: []const u8,
    prefix: []const u8,
    current_blobs: *const std.StringHashMap([]const u8),
    pack_cache: *utils.PackfileCache,
) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha, pack_cache);
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
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}", .{ working_path, entry.path })
        else
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}/{s}", .{ working_path, prefix, entry.path });

        const path = if (prefix.len == 0) entry.path else blk: {
            var buf: [512]u8 = undefined;
            break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
        };

        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const current_sha = current_blobs.get(path);
            if (current_sha != null and std.mem.eql(u8, current_sha.?, entry.sha)) {
                continue;
            }

            const blob_data = try utils.readObject(io, allocator, git_dir_path, entry.sha, pack_cache);
            defer allocator.free(blob_data);

            const content = utils.extractContentFromBlob(blob_data);

            try cwd.writeFile(io, .{ .sub_path = entry_path, .data = content });
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

            try extractTreeRecursive(io, allocator, git_dir_path, working_path, entry.sha, new_prefix, current_blobs, pack_cache);
        }
    }
}

fn updateIndex(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    pack_cache: *utils.PackfileCache,
) !void {
    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    var index_content = std.ArrayList(u8).initCapacity(allocator, 100) catch unreachable;
    defer index_content.deinit(allocator);

    try updateIndexRecursive(io, allocator, git_dir_path, tree_sha, "", &index_content, pack_cache);

    try index_content.appendSlice(allocator, "\n");

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = index_content.items });
}

fn updateIndexRecursive(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    prefix: []const u8,
    index_content: *std.ArrayList(u8),
    pack_cache: *utils.PackfileCache,
) !void {
    const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha, pack_cache);
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

    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const blob_data = try utils.readObject(io, allocator, git_dir_path, entry.sha, pack_cache);
            defer allocator.free(blob_data);

            const file_content = utils.extractContentFromBlob(blob_data);

            // Use git blob hash format (with "blob <size>\0" header)
            const blob_header = try std.fmt.allocPrint(allocator, "blob {d}\x00{s}", .{ file_content.len, file_content });
            defer allocator.free(blob_header);

            var hasher = std.crypto.hash.Sha1.init(.{});
            hasher.update(blob_header);

            var hash: [20]u8 = undefined;
            hasher.final(&hash);

            const hex_hash = try allocator.alloc(u8, 40);
            const hex_digits = "0123456789abcdef";

            for (0..20) |i| {
                hex_hash[2 * i] = hex_digits[hash[i] >> 4];
                hex_hash[2 * i + 1] = hex_digits[hash[i] & 0x0f];
            }
            defer allocator.free(hex_hash);

            const entry_path = if (prefix.len == 0) entry.path else blk: {
                var buf: [512]u8 = undefined;
                break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
            };

            try index_content.appendSlice(allocator, entry_path);
            try index_content.appendSlice(allocator, " ");
            try index_content.appendSlice(allocator, hex_hash);
            try index_content.appendSlice(allocator, "\n");
        } else if (std.mem.eql(u8, entry.entry_type, "tree")) {
            const new_prefix = if (prefix.len == 0) entry.path else blk: {
                var buf: [512]u8 = undefined;
                break :blk try std.fmt.bufPrint(&buf, "{s}/{s}", .{ prefix, entry.path });
            };

            try updateIndexRecursive(io, allocator, git_dir_path, entry.sha, new_prefix, index_content, pack_cache);
        }
    }
}

fn isAncestorOf(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, ancestor_sha: []const u8, descendant_sha: []const u8, pack_cache: *utils.PackfileCache) !bool {
    var visited = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (visited.items) |sha| allocator.free(sha);
        visited.deinit(allocator);
    }

    var queue = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (queue.items) |sha| allocator.free(sha);
        queue.deinit(allocator);
    }

    try queue.append(allocator, try allocator.dupe(u8, descendant_sha));

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);

        if (std.mem.eql(u8, current, ancestor_sha)) {
            allocator.free(current);
            return true;
        }

        var already_visited = false;
        for (visited.items) |sha| {
            if (std.mem.eql(u8, sha, current)) {
                already_visited = true;
                break;
            }
        }

        if (already_visited) {
            allocator.free(current);
            continue;
        }

        try visited.append(allocator, current);

        var parents = try getParents(io, allocator, git_dir_path, current, pack_cache);
        defer {
            for (parents.items) |sha| allocator.free(sha);
            parents.deinit(allocator);
        }
        for (parents.items) |parent| {
            try queue.append(allocator, try allocator.dupe(u8, parent));
        }
    }

    return false;
}

fn findMergeBase(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha1: []const u8, sha2: []const u8, pack_cache: *utils.PackfileCache) !?[]const u8 {
    if (std.mem.eql(u8, sha1, sha2)) {
        return try allocator.dupe(u8, sha1);
    }

    var ancestors1 = try getAllAncestors(io, allocator, git_dir_path, sha1, pack_cache);
    defer {
        for (ancestors1.items) |sha| allocator.free(sha);
        ancestors1.deinit(allocator);
    }

    var ancestors2 = try getAllAncestors(io, allocator, git_dir_path, sha2, pack_cache);
    defer {
        for (ancestors2.items) |sha| allocator.free(sha);
        ancestors2.deinit(allocator);
    }

    const sha1_copy = try allocator.dupe(u8, sha1);
    errdefer allocator.free(sha1_copy);
    const sha2_copy = try allocator.dupe(u8, sha2);
    errdefer {
        allocator.free(sha2_copy);
        allocator.free(sha1_copy);
    }

    try ancestors1.append(allocator, sha1_copy);
    try ancestors2.append(allocator, sha2_copy);

    for (ancestors1.items) |ancestor| {
        for (ancestors2.items) |other| {
            if (std.mem.eql(u8, ancestor, other)) {
                return try allocator.dupe(u8, ancestor);
            }
        }
    }

    return null;
}

fn getAllAncestors(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !std.ArrayList([]const u8) {
    var ancestors = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    errdefer {
        for (ancestors.items) |s| allocator.free(s);
        ancestors.deinit(allocator);
    }

    var queue = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (queue.items) |s| allocator.free(s);
        queue.deinit(allocator);
    }

    try queue.append(allocator, try allocator.dupe(u8, sha));

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);

        var already_has = false;
        for (ancestors.items) |ancestor| {
            if (std.mem.eql(u8, ancestor, current)) {
                already_has = true;
                break;
            }
        }

        if (already_has) {
            allocator.free(current);
            continue;
        }

        var parents = try getParents(io, allocator, git_dir_path, current, pack_cache);
        defer {
            for (parents.items) |p| allocator.free(p);
            parents.deinit(allocator);
        }
        for (parents.items) |parent| {
            try ancestors.append(allocator, try allocator.dupe(u8, parent));
            try queue.append(allocator, try allocator.dupe(u8, parent));
        }
        allocator.free(current);
    }

    return ancestors;
}

fn getParents(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !std.ArrayList([]const u8) {
    var parents = std.ArrayList([]const u8).initCapacity(allocator, 2) catch unreachable;
    errdefer {
        for (parents.items) |p| allocator.free(p);
        parents.deinit(allocator);
    }

    const commit_data = utils.readObject(io, allocator, git_dir_path, sha, pack_cache) catch |err| {
        if (err == error.FileNotFound) {
            return parents;
        }
        return err;
    };
    defer allocator.free(commit_data);

    const content = utils.extractContentFromBlob(commit_data);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "parent ")) {
            const parent_sha = line["parent ".len..];
            try parents.append(allocator, try allocator.dupe(u8, parent_sha));
        }
    }

    return parents;
}

fn getTree(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !?[]const u8 {
    const commit_data = utils.readObject(io, allocator, git_dir_path, sha, pack_cache) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer allocator.free(commit_data);

    const content = utils.extractContentFromBlob(commit_data);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "tree ")) {
            const tree_sha = line["tree ".len..];
            return try allocator.dupe(u8, tree_sha);
        }
    }

    return null;
}

fn createMergeCommit(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, parent1: []const u8, parent2: []const u8, branch_name: []const u8, remote_name: []const u8, pack_cache: *utils.PackfileCache) ![]const u8 {
    const tree_sha_opt = try getTree(io, allocator, git_dir_path, parent1, pack_cache);

    if (tree_sha_opt == null) {
        return error.CouldNotGetTreeForMergeCommit;
    }
    defer allocator.free(tree_sha_opt.?);
    const tree_sha = tree_sha_opt.?;

    const timestamp: i64 = 0;
    const offset_seconds = 0;
    const sign_char: u8 = if (offset_seconds >= 0) '+' else '-';
    const abs_offset = @abs(offset_seconds);
    const hours = abs_offset / 3600;
    const minutes = (abs_offset % 3600) / 60;

    const author = try std.fmt.allocPrint(allocator, "User <user@example.com> {d} {c}{d:0>2}{d:0>2}", .{ timestamp, sign_char, hours, minutes });
    defer allocator.free(author);

    const message = try std.fmt.allocPrint(allocator, "Merge branch '{s}' of {s}", .{ branch_name, remote_name });
    defer allocator.free(message);

    var commit_content = std.ArrayList(u8).initCapacity(allocator, 200) catch unreachable;
    defer commit_content.deinit(allocator);

    try commit_content.appendSlice(allocator, "tree ");
    try commit_content.appendSlice(allocator, tree_sha);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "parent ");
    try commit_content.appendSlice(allocator, parent1);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "parent ");
    try commit_content.appendSlice(allocator, parent2);
    try commit_content.appendSlice(allocator, "\n");

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
