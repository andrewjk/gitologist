const std = @import("std");

const utils = @import("utils.zig");
const fetch = @import("fetch.zig");

pub fn pull(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote: ?[]const u8, branch: ?[]const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const remote_name = if (remote) |r| r else "origin";

    var fetch_result = try fetch.fetchFromRemote(io, allocator, path, remote_name);
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
        branch_name = try utils.getCurrentBranch(io, allocator, git_dir_path);
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

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(local_branch_path);

    const local_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
    defer allocator.free(local_branch_dir);

    try cwd.createDirPath(io, local_branch_dir);

    const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{remote_commit_sha});
    defer allocator.free(commit_with_newline);

    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = commit_with_newline });

    const commit_data = try utils.readObject(io, allocator, git_dir_path, remote_commit_sha);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    try extractTreeToWorkingDirectory(io, allocator, git_dir_path, path, tree_sha);

    try updateIndex(io, allocator, git_dir_path, tree_sha);
}

fn extractTreeToWorkingDirectory(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
    tree_sha: []const u8,
) !void {
    try extractTreeRecursive(io, allocator, git_dir_path, working_path, tree_sha, "");
}

fn extractTreeRecursive(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    working_path: []const u8,
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
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}", .{ working_path, entry.path })
        else
            try std.fmt.bufPrint(&entry_path_buf, "{s}/{s}/{s}", .{ working_path, prefix, entry.path });

        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const blob_data = try utils.readObject(io, allocator, git_dir_path, entry.sha);
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

            try extractTreeRecursive(io, allocator, git_dir_path, working_path, entry.sha, new_prefix);
        }
    }
}

fn updateIndex(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
) !void {
    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    var index_content = std.ArrayList(u8).initCapacity(allocator, 100) catch unreachable;
    defer index_content.deinit(allocator);

    try updateIndexRecursive(io, allocator, git_dir_path, tree_sha, "", &index_content);

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

    for (entries.items) |entry| {
        if (std.mem.eql(u8, entry.entry_type, "blob")) {
            const blob_data = try utils.readObject(io, allocator, git_dir_path, entry.sha);
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

            try updateIndexRecursive(io, allocator, git_dir_path, entry.sha, new_prefix, index_content);
        }
    }
}
