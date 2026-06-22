const std = @import("std");

pub fn getCurrentBranch(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8) ![]const u8 {
	const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path);

	const cwd = std.Io.Dir.cwd();
	const head_content = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
	defer allocator.free(head_content);

	const trimmed = std.mem.trim(u8, head_content, &std.ascii.whitespace);

	const prefix = "ref: refs/heads/";
	if (std.mem.startsWith(u8, trimmed, prefix)) {
		const branch = trimmed[prefix.len..];
		return allocator.dupe(u8, branch);
	}

	return allocator.dupe(u8, "(detached HEAD)");
}

pub fn getCurrentCommit(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8) !?[]const u8 {
	const branch = try getCurrentBranch(io, allocator, git_dir_path);
	defer allocator.free(branch);

	if (std.mem.eql(u8, branch, "(detached HEAD)")) {
		return null;
	}

	const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch });
	defer allocator.free(branch_path);

	const cwd = std.Io.Dir.cwd();
	const commit_sha = cwd.readFileAlloc(io, branch_path, allocator, .unlimited) catch |err| {
		if (err == error.FileNotFound) {
			return null;
		}
		return err;
	};

	const trimmed = std.mem.trim(u8, commit_sha, &std.ascii.whitespace);
	const result = try allocator.dupe(u8, trimmed);
	allocator.free(commit_sha);

	return result;
}
