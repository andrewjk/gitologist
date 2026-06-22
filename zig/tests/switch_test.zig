const std = @import("std");

const switchBranch = @import("gitologist").switchBranch;

test "should write branch name to HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-switch-branch" });
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

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ refs_heads_path, "feature-branch" });
    defer allocator.free(branch_path);
    try cwd.writeFile(io, .{ .sub_path = branch_path, .data = "abc123\n" });

    try switchBranch(io, allocator, tmp_path, "feature-branch");

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const head_content = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
    defer allocator.free(head_content);

    try std.testing.expectEqualStrings("ref: refs/heads/feature-branch\n", head_content);
}

test "should throw if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-switch-not-a-repo" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const result = switchBranch(io, allocator, tmp_path, "feature-branch");
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw if branch does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-switch-no-branch" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    try cwd.createDirPath(io, git_dir_path);

    const result = switchBranch(io, allocator, tmp_path, "nonexistent");
    try std.testing.expectError(error.BranchNotFound, result);
}
