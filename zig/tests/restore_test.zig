const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const restore = @import("gitologist").restore;
const restoreAll = @import("gitologist").restoreAll;
const status = @import("gitologist").status;

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    return tmp_path;
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

test "should restore a modified file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try restore(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("original", content);
}

test "should restore multiple files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "original1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "original2" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file1.txt", "file2.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "modified2" });

    try restore(io, allocator, tmp_path, &[_][]const u8{ "file1.txt", "file2.txt" });

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);
    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings("original1", content1);
    try std.testing.expectEqualStrings("original2", content2);
}

test "should throw error for non-existent file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-nonexistent");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = restore(io, allocator, tmp_path, &[_][]const u8{"nonexistent.txt"});
    try std.testing.expectError(error.FileNotFound, result);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-restore-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = restore(io, allocator, non_git_dir, &[_][]const u8{"test.txt"});
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if file not in commit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-not-in-commit");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    const new_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "newfile.txt" });
    defer allocator.free(new_file_path);
    try cwd.writeFile(io, .{ .sub_path = new_file_path, .data = "new content" });

    const result = restore(io, allocator, tmp_path, &[_][]const u8{"newfile.txt"});
    try std.testing.expectError(error.FileNotInCommit, result);
}

test "should update status after restore" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-status");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    var result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.modified.len > 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);
    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);
    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);
    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);

    try restore(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    result = try status(io, allocator, tmp_path);

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

test "should restore all modified files with restoreAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-all");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "original1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "original2" });

    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file3.txt" });
    defer allocator.free(file3_path);
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "original3" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file1.txt", "file2.txt", "file3.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "modified2" });
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "modified3" });

    try restoreAll(io, allocator, tmp_path);

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);
    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);
    const content3 = try cwd.readFileAlloc(io, file3_path, allocator, .unlimited);
    defer allocator.free(content3);

    try std.testing.expectEqualStrings("original1", content1);
    try std.testing.expectEqualStrings("original2", content2);
    try std.testing.expectEqualStrings("original3", content3);
}

test "should do nothing with restoreAll when no modified files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-no-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try restoreAll(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);

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

test "should throw error with restoreAll if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-restore-all-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = restoreAll(io, allocator, non_git_dir);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should handle files in subdirectories" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-restore-subdir");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src" });
    defer allocator.free(src_path);
    try cwd.createDirPath(io, src_path);

    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ src_path, "index.ts" });
    defer allocator.free(index_path);
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"src/index.ts"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = index_path, .data = "modified" });

    try restore(io, allocator, tmp_path, &[_][]const u8{"src/index.ts"});

    const content = try cwd.readFileAlloc(io, index_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("original", content);
}
