const std = @import("std");

const getCurrentBranch = @import("gitologist").getCurrentBranch;
const getCurrentCommit = @import("gitologist").getCurrentCommit;

test "should return branch name from HEAD" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-branch-name" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();

	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
	defer allocator.free(git_dir_path);
	try cwd.createDirPath(io, git_dir_path);

	const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path);
	try cwd.writeFile(io, .{ .sub_path = head_path, .data = "ref: refs/heads/main\n" });

	const branch = try getCurrentBranch(io, allocator, git_dir_path);
	defer allocator.free(branch);
	try std.testing.expectEqualStrings("main", branch);
}

test "should return current commit SHA" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-branch-commit" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();

	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
	defer allocator.free(git_dir_path);
	try cwd.createDirPath(io, git_dir_path);

	const refs_heads_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
	defer allocator.free(refs_heads_path);
	try cwd.createDirPath(io, refs_heads_path);

	const head_path2 = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path2);
	try cwd.writeFile(io, .{ .sub_path = head_path2, .data = "ref: refs/heads/main\n" });
	const main_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ refs_heads_path, "main" });
	defer allocator.free(main_branch_path);
	try cwd.writeFile(io, .{ .sub_path = main_branch_path, .data = "abc123def456abc123def456abc123def4567890\n" });

	const commit_sha_opt = try getCurrentCommit(io, allocator, git_dir_path);
	try std.testing.expect(commit_sha_opt != null);
	defer allocator.free(commit_sha_opt.?);
	try std.testing.expectEqualStrings("abc123def456abc123def456abc123def4567890", commit_sha_opt.?);
}

test "should return null if no commit exists" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-branch-no-commit" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();

	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
	defer allocator.free(git_dir_path);
	try cwd.createDirPath(io, git_dir_path);

	const refs_heads_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads" });
	defer allocator.free(refs_heads_path);
	try cwd.createDirPath(io, refs_heads_path);

	const head_path3 = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path3);
	try cwd.writeFile(io, .{ .sub_path = head_path3, .data = "ref: refs/heads/main\n" });

	const commit_sha_opt = try getCurrentCommit(io, allocator, git_dir_path);
	try std.testing.expect(commit_sha_opt == null);
}

test "should return detached HEAD" {
	const io = std.testing.io;
	const allocator = std.testing.allocator;

	const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-branch-detached" });
	defer allocator.free(tmp_path);

	const cwd = std.Io.Dir.cwd();

	try cwd.createDirPath(io, tmp_path);
	defer cwd.deleteTree(io, tmp_path) catch {};

	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
	defer allocator.free(git_dir_path);
	try cwd.createDirPath(io, git_dir_path);

	const head_path4 = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
	defer allocator.free(head_path4);
	try cwd.writeFile(io, .{ .sub_path = head_path4, .data = "abc123def456abc123def456abc123def4567890\n" });

	const branch = try getCurrentBranch(io, allocator, git_dir_path);
	defer allocator.free(branch);
	try std.testing.expectEqualStrings("(detached HEAD)", branch);
}
