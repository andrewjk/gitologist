const std = @import("std");

const utils = @import("utils.zig");
const pull = @import("pull.zig");
const setUpstreamBranch = @import("push.zig").setUpstreamBranch;

const RemoteBranchInfo = struct {
	remote_name: []const u8,
	commit_sha: []const u8,
};

pub fn switchBranch(io: std.Io, allocator: std.mem.Allocator, path: []const u8, branch_name: []const u8) !void {
	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
	defer allocator.free(git_dir_path);

	const cwd = std.Io.Dir.cwd();

	const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
		return error.NotAGitRepository;
	};
	git_dir.close(io);

	var cache = utils.PackfileCache.init(allocator);
	defer cache.deinit();

	// 1. Local branch exists: check out its tree, then point HEAD at it.
	const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
	defer allocator.free(local_branch_path);

	if (cwd.access(io, local_branch_path, .{})) |_| {
		const commit_sha_with_newline = try cwd.readFileAlloc(io, local_branch_path, allocator, .unlimited);
		defer allocator.free(commit_sha_with_newline);
		const commit_sha = std.mem.trim(u8, commit_sha_with_newline, &std.ascii.whitespace);

		// Check out the tree first (uses the current HEAD as the baseline for
		// change detection); only move HEAD once the checkout succeeds.
		try pull.checkoutTree(io, allocator, git_dir_path, path, commit_sha, &cache);

		try writeHead(io, allocator, git_dir_path, branch_name);
		return;
	} else |_| {}

	// 2. DWIM: no local branch, but exactly one remote tracking branch exists.
	const dwim = try findRemoteBranch(io, allocator, git_dir_path, branch_name);
	if (dwim) |remote_info| {
		defer allocator.free(remote_info.remote_name);
		defer allocator.free(remote_info.commit_sha);

		try utils.updateBranch(io, allocator, git_dir_path, branch_name, remote_info.commit_sha);
		try setUpstreamBranch(io, allocator, path, remote_info.remote_name, branch_name);

		try pull.checkoutTree(io, allocator, git_dir_path, path, remote_info.commit_sha, &cache);

		try writeHead(io, allocator, git_dir_path, branch_name);
		return;
	}

	// 3. No local branch and zero (or multiple) matching remotes.
	return error.BranchNotFound;
}

fn writeHead(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, branch_name: []const u8) !void {
	const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path);

	const head_content = try std.fmt.allocPrint(allocator, "ref: refs/heads/{s}\n", .{branch_name});
	defer allocator.free(head_content);

	const cwd = std.Io.Dir.cwd();
	try cwd.writeFile(io, .{ .sub_path = head_path, .data = head_content });
}

/// Finds a single remote that has `refs/remotes/<remote>/<branch_name>`.
/// Returns the remote name and commit SHA when exactly one match exists, otherwise null.
fn findRemoteBranch(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, branch_name: []const u8) !?RemoteBranchInfo {
	const remotes_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes" });
	defer allocator.free(remotes_dir_path);

	const cwd = std.Io.Dir.cwd();

	const remotes_dir = cwd.openDir(io, remotes_dir_path, .{}) catch {
		return null;
	};
	defer remotes_dir.close(io);

	var match: ?RemoteBranchInfo = null;
	var match_count: usize = 0;

	var dir_iter = remotes_dir.iterate();
	while (try dir_iter.next(io)) |entry| {
		if (entry.kind != .directory) continue;

		const branch_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ remotes_dir_path, entry.name, branch_name });
		defer allocator.free(branch_ref_path);

		if (cwd.access(io, branch_ref_path, .{})) |_| {} else |_| {
			continue;
		}

		const sha_with_newline = try cwd.readFileAlloc(io, branch_ref_path, allocator, .unlimited);
		const sha = std.mem.trim(u8, sha_with_newline, &std.ascii.whitespace);
		const sha_copy = try allocator.dupe(u8, sha);
		allocator.free(sha_with_newline);

		const name_copy = try allocator.dupe(u8, entry.name);

		if (match) |m| {
			allocator.free(m.remote_name);
			allocator.free(m.commit_sha);
		}
		match = .{ .remote_name = name_copy, .commit_sha = sha_copy };
		match_count += 1;
	}

	if (match_count == 1) {
		return match;
	}

	if (match) |m| {
		allocator.free(m.remote_name);
		allocator.free(m.commit_sha);
	}
	return null;
}
