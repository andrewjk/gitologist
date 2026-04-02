const std = @import("std");

const utils = @import("utils.zig");

const status_module = @import("status.zig");

pub fn restore(io: std.Io, allocator: std.mem.Allocator, path: []const u8, files: []const []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    for (files) |file| {
        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file });
        defer allocator.free(file_path);

        if (cwd.access(io, file_path, .{})) |_| {} else |_| {
            return error.FileNotFound;
        }
    }

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", "master" });
    defer allocator.free(branch_path);

    const commit_sha_bytes = try cwd.readFileAlloc(io, branch_path, allocator, .unlimited);
    defer allocator.free(commit_sha_bytes);

    const commit_sha = std.mem.trim(u8, commit_sha_bytes, &std.ascii.whitespace);

    const commit_data = try utils.readObject(io, allocator, git_dir_path, commit_sha);
    defer allocator.free(commit_data);

    const tree_sha = try utils.extractTreeFromCommit(commit_data);

    for (files) |file| {
        const blob_sha = try findBlobInTree(io, allocator, git_dir_path, tree_sha, file);
        defer {
            if (blob_sha) |sha| allocator.free(sha);
        }
        if (blob_sha == null) {
            return error.FileNotInCommit;
        }

        const blob_data = try utils.readObject(io, allocator, git_dir_path, blob_sha.?);
        defer allocator.free(blob_data);

        const content = utils.extractContentFromBlob(blob_data);

        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ path, file });
        defer allocator.free(file_path);

        try cwd.writeFile(io, .{ .sub_path = file_path, .data = content });
    }
}

pub fn restoreAll(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    defer git_dir.close(io);

    const current_status = try status_module.status(io, allocator, path);

    const files_to_restore = current_status.modified;

    if (files_to_restore.len == 0) {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |item| allocator.free(item);
        allocator.free(current_status.staged);
        for (current_status.modified) |item| allocator.free(item);
        allocator.free(current_status.modified);
        for (current_status.untracked) |item| allocator.free(item);
        allocator.free(current_status.untracked);
        return;
    }

    const files_slice = try allocator.dupe([]const u8, files_to_restore);
    defer allocator.free(files_slice);

    allocator.free(current_status.branch);
    allocator.free(current_status.up_to_date);
    for (current_status.staged) |item| allocator.free(item);
    allocator.free(current_status.staged);
    for (current_status.untracked) |item| allocator.free(item);
    allocator.free(current_status.untracked);

    try restore(io, allocator, path, files_slice);

    allocator.free(current_status.modified);

    for (files_slice) |file| {
        allocator.free(file);
    }
}

fn findBlobInTree(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, tree_sha: []const u8, file_path: []const u8) !?[]const u8 {
    var parts = std.mem.splitScalar(u8, file_path, '/');
    const name = parts.first();
    const rest = parts.rest();

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
        if (std.mem.eql(u8, entry.path, name)) {
            if (std.mem.eql(u8, entry.entry_type, "blob")) {
                if (rest.len == 0) {
                    return try allocator.dupe(u8, entry.sha);
                }
                return null;
            }
            if (std.mem.eql(u8, entry.entry_type, "tree")) {
                if (rest.len > 0) {
                    const sub_result = try findBlobInTree(io, allocator, git_dir_path, entry.sha, rest);
                    if (sub_result) |sha| {
                        const sha_copy = try allocator.dupe(u8, sha);
                        allocator.free(sha);
                        return sha_copy;
                    }
                    return null;
                }
                return null;
            }
        }
    }

    return null;
}
