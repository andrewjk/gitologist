const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const status = @import("gitologist").status;

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    return tmp_path;
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

test "should commit staged files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-staged");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    for (commit_sha) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);
    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);
    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);
    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should throw error if nothing to commit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-nothing");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = commit(io, allocator, tmp_path, "Empty commit");
    try std.testing.expectError(error.NothingToCommit, result);
}

test "should throw error if no files staged" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-no-staged");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const result = commit(io, allocator, tmp_path, "Test commit");
    try std.testing.expectError(error.NoFilesStaged, result);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-commit-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = commit(io, allocator, non_git_dir, "Test commit");
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should create commit object in .git/objects" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-objects");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Test commit");
    defer allocator.free(commit_sha);

    const objects_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "objects" });
    defer allocator.free(objects_dir);

    const dir = try cwd.openDir(io, objects_dir, .{});
    defer dir.close(io);

    var dir_iter = dir.iterate();
    var count: usize = 0;
    while (try dir_iter.next(io)) |_| {
        count += 1;
    }

    try std.testing.expect(count > 0);
}

test "should update branch reference" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-branch");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Test commit");
    defer allocator.free(commit_sha);

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "master" });
    defer allocator.free(branch_path);

    const branch_ref = try cwd.readFileAlloc(io, branch_path, allocator, .unlimited);
    defer allocator.free(branch_ref);

    const trimmed = std.mem.trim(u8, branch_ref, &std.ascii.whitespace);
    try std.testing.expectEqualStrings(commit_sha, trimmed);
}

test "should handle multiple commits" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const first_sha = try commit(io, allocator, tmp_path, "First commit");
    defer allocator.free(first_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(second_sha);

    try std.testing.expect(!std.mem.eql(u8, first_sha, second_sha));

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "master" });
    defer allocator.free(branch_path);

    const branch_ref = try cwd.readFileAlloc(io, branch_path, allocator, .unlimited);
    defer allocator.free(branch_ref);

    const trimmed = std.mem.trim(u8, branch_ref, &std.ascii.whitespace);
    try std.testing.expectEqualStrings(second_sha, trimmed);
}

test "should handle commit with message containing newlines" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-multiline");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const message = "Multi-line\ncommit\nmessage";
    const commit_sha = try commit(io, allocator, tmp_path, message);
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    for (commit_sha) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }
}

test "should commit multiple files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-commit-multiple-files");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file3.txt" });
    defer allocator.free(file3_path);
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "content3" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file1.txt", "file2.txt", "file3.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Add multiple files");
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);
    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);
    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);
    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}
