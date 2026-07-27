const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const switchBranch = @import("gitologist").switchBranch;

test "should switch to existing local branch and update HEAD and tree" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-switch-local-branch" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();
	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	try init(io, allocator, tmp_path);

	const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
	defer allocator.free(file_path);
	try cwd.writeFile(io, .{ .sub_path = file_path, .data = "A" });

	{
		const paths = try allocator.alloc([]const u8, 1);
		defer allocator.free(paths);
		paths[0] = try allocator.dupe(u8, "file.txt");
		defer allocator.free(paths[0]);
		try add(io, allocator, tmp_path, paths);
	}
	const first_sha = try commit(io, allocator, tmp_path, "First commit");

	// Create a "feature" branch pointing at the first commit.
	const feature_ref = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "feature" });
	defer allocator.free(feature_ref);
	try cwd.writeFile(io, .{ .sub_path = feature_ref, .data = first_sha });
	allocator.free(first_sha);

	// Second commit on main changes the working tree (file.txt = "B").
	try cwd.writeFile(io, .{ .sub_path = file_path, .data = "B" });
	{
		const paths = try allocator.alloc([]const u8, 1);
		defer allocator.free(paths);
		paths[0] = try allocator.dupe(u8, "file.txt");
		defer allocator.free(paths[0]);
		try add(io, allocator, tmp_path, paths);
	}
	const second_sha = try commit(io, allocator, tmp_path, "Second commit");
	allocator.free(second_sha);

	try switchBranch(io, allocator, tmp_path, "feature");

	const head_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "HEAD" });
	defer allocator.free(head_path);
	const head_content = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
	defer allocator.free(head_content);
	try std.testing.expectEqualStrings("ref: refs/heads/feature\n", head_content);

	const content = try cwd.readFileAlloc(io, file_path, allocator, .unlimited);
	defer allocator.free(content);
	try std.testing.expectEqualStrings("A", content);
}

test "should create local branch from single remote tracking branch" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-switch-dwim" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();
	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	try init(io, allocator, tmp_path);

	const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
	defer allocator.free(file_path);
	try cwd.writeFile(io, .{ .sub_path = file_path, .data = "content" });

	{
		const paths = try allocator.alloc([]const u8, 1);
		defer allocator.free(paths);
		paths[0] = try allocator.dupe(u8, "file.txt");
		defer allocator.free(paths[0]);
		try add(io, allocator, tmp_path, paths);
	}
	const sha = try commit(io, allocator, tmp_path, "Initial commit");

	// Simulate a fetched remote-tracking branch with no local branch yet.
	const remote_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "origin" });
	defer allocator.free(remote_branch_dir);
	try cwd.createDirPath(io, remote_branch_dir);

	const remote_branch_ref = try std.fs.path.join(allocator, &[_][]const u8{ remote_branch_dir, "feature" });
	defer allocator.free(remote_branch_ref);
	try cwd.writeFile(io, .{ .sub_path = remote_branch_ref, .data = sha });

	try switchBranch(io, allocator, tmp_path, "feature");

	// Local branch created at the same SHA.
	const local_ref = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "feature" });
	defer allocator.free(local_ref);
	const local_sha_raw = try cwd.readFileAlloc(io, local_ref, allocator, .unlimited);
	defer allocator.free(local_sha_raw);
	const local_sha = std.mem.trim(u8, local_sha_raw, &std.ascii.whitespace);
	try std.testing.expectEqualStrings(sha, local_sha);
	allocator.free(sha);

	// HEAD points at the new local branch.
	const head_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "HEAD" });
	defer allocator.free(head_path);
	const head_content = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
	defer allocator.free(head_content);
	try std.testing.expectEqualStrings("ref: refs/heads/feature\n", head_content);

	// Tracking config written.
	const config_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "config" });
	defer allocator.free(config_path);
	const config = try cwd.readFileAlloc(io, config_path, allocator, .unlimited);
	defer allocator.free(config);
	try std.testing.expect(std.mem.indexOf(u8, config, "[branch \"feature\"]") != null);
	try std.testing.expect(std.mem.indexOf(u8, config, "remote = origin") != null);
	try std.testing.expect(std.mem.indexOf(u8, config, "merge = refs/heads/feature") != null);

	// Tree checked out.
	const content = try cwd.readFileAlloc(io, file_path, allocator, .unlimited);
	defer allocator.free(content);
	try std.testing.expectEqualStrings("content", content);
}

test "should throw if branch does not exist" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-switch-not-found" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();
	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	try init(io, allocator, tmp_path);

	try std.testing.expectError(error.BranchNotFound, switchBranch(io, allocator, tmp_path, "nonexistent"));
}

test "should throw if not a git repository" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-switch-not-a-repo" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();
	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	try std.testing.expectError(error.NotAGitRepository, switchBranch(io, allocator, tmp_path, "feature-branch"));
}
