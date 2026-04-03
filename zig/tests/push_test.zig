const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const push = @import("gitologist").push;

test "should push to default remote and branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-1" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, null, null);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "origin", "master" });
    defer allocator.free(remote_branch_path);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);

    const trimmed = std.mem.trim(u8, remote_branch_content, &std.ascii.whitespace);
    try std.testing.expect(trimmed.len == 40);
    for (trimmed) |c| {
        try std.testing.expect((c >= 'a' and c <= 'f') or (c >= '0' and c <= '9'));
    }
}

test "should push to specified remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-2" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, "upstream", null);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "upstream", "master" });
    defer allocator.free(remote_branch_path);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);
}

test "should push to specified branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-3" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "HEAD" });
    defer allocator.free(head_path);
    try cwd.writeFile(io, .{ .sub_path = head_path, .data = "ref: refs/heads/main\n" });

    const refs_heads_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads" });
    defer allocator.free(refs_heads_path);
    try cwd.createDirPath(io, refs_heads_path);

    const main_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(main_path);
    try cwd.writeFile(io, .{ .sub_path = main_path, .data = "abc123\n" });

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, "origin", "main");

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "origin", "main" });
    defer allocator.free(remote_branch_path);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-not-repo" });
    defer allocator.free(non_git_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, non_git_dir);
    defer cwd.deleteTree(io, non_git_dir) catch {};

    const result = push(io, allocator, non_git_dir, null, null);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if there are uncommitted changes" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-4" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const result = push(io, allocator, tmp_path, null, null);
    try std.testing.expectError(error.UncommittedChanges, result);
}

test "should throw error if there are untracked files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-5" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    const test2_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test2.txt" });
    defer allocator.free(test2_file_path);
    try cwd.writeFile(io, .{ .sub_path = test2_file_path, .data = "untracked" });

    const result = push(io, allocator, tmp_path, null, null);
    try std.testing.expectError(error.UncommittedChanges, result);
}

test "should throw error if local branch does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-6" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "HEAD" });
    defer allocator.free(head_path);
    try cwd.writeFile(io, .{ .sub_path = head_path, .data = "ref: refs/heads/nonexistent\n" });

    const result = push(io, allocator, tmp_path, null, null);
    try std.testing.expectError(error.LocalBranchDoesNotExist, result);
}

test "should update existing remote branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-7" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "First commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");

    try push(io, allocator, tmp_path, null, null);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "origin", "master" });
    defer allocator.free(remote_branch_path);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);

    const trimmed_remote = std.mem.trim(u8, remote_branch_content, &std.ascii.whitespace);

    try std.testing.expectEqualStrings(second_sha, trimmed_remote);

    allocator.free(second_sha);
}

test "should create remote directory if it does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-8" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, "myremote", null);

    const remote_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "myremote" });
    defer allocator.free(remote_dir);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    _ = try git_dir.openDir(io, remote_dir, .{});

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ remote_dir, "master" });
    defer allocator.free(remote_branch_path);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);
}

test "should handle multiple pushes to same branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-push-test-9" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "First commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, null, null);

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "remotes", "origin", "master" });
    defer allocator.free(remote_branch_path);

    const git_dir = try cwd.openDir(io, tmp_path, .{});
    defer git_dir.close(io);

    const remote_branch_content = try git_dir.readFileAlloc(io, remote_branch_path, allocator, .unlimited);
    defer allocator.free(remote_branch_content);

    const remote_sha = std.mem.trim(u8, remote_branch_content, &std.ascii.whitespace);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "master" });
    defer allocator.free(local_branch_path);

    const local_branch_content = try git_dir.readFileAlloc(io, local_branch_path, allocator, .unlimited);
    defer allocator.free(local_branch_content);

    const local_sha = std.mem.trim(u8, local_branch_content, &std.ascii.whitespace);

    try std.testing.expectEqualStrings(remote_sha, local_sha);
}
