const std = @import("std");

const utils = @import("utils.zig");

pub fn push(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote: ?[]const u8, branch: ?[]const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const remote_name = if (remote) |r| r else "origin";

    var branch_name: []const u8 = undefined;
    var free_branch_name = false;

    if (branch) |b| {
        branch_name = b;
    } else {
        branch_name = try utils.getCurrentBranch(io, allocator, git_dir_path);
        free_branch_name = true;
    }
    defer if (free_branch_name) allocator.free(branch_name);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(local_branch_path);

    const local_branch_file = cwd.openFile(io, local_branch_path, .{}) catch {
        const err_msg = try std.fmt.allocPrint(allocator, "Local branch '{s}' does not exist", .{branch_name});
        defer allocator.free(err_msg);
        return error.LocalBranchDoesNotExist;
    };
    local_branch_file.close(io);

    const status_fn = @import("status.zig").status;
    const current_status = try status_fn(io, allocator, path);
    defer {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |file| allocator.free(file);
        for (current_status.modified) |file| allocator.free(file);
        for (current_status.untracked) |file| allocator.free(file);
        allocator.free(current_status.staged);
        allocator.free(current_status.modified);
        allocator.free(current_status.untracked);
    }

    if (current_status.modified.len > 0 or current_status.untracked.len > 0) {
        return error.UncommittedChanges;
    }

    const commit_sha_with_newline = try cwd.readFileAlloc(io, local_branch_path, allocator, .unlimited);
    defer allocator.free(commit_sha_with_newline);

    const commit_sha = std.mem.trim(u8, commit_sha_with_newline, &std.ascii.whitespace);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name, branch_name });
    defer allocator.free(remote_branch_path);

    const remote_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name });
    defer allocator.free(remote_branch_dir);

    try cwd.createDirPath(io, remote_branch_dir);

    const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{commit_sha});
    defer allocator.free(commit_with_newline);

    try cwd.writeFile(io, .{ .sub_path = remote_branch_path, .data = commit_with_newline });
}
