const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const addAll = @import("gitologist").addAll;
const status = @import("gitologist").status;

fn hashString(allocator: std.mem.Allocator, content: []const u8) ![]const u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(content);
    var hash: [20]u8 = undefined;
    hasher.final(&hash);

    const hex_hash = try allocator.alloc(u8, 40);
    const hex_digits = "0123456789abcdef";

    for (0..20) |i| {
        hex_hash[2 * i] = hex_digits[hash[i] >> 4];
        hex_hash[2 * i + 1] = hex_digits[hash[i] & 0x0f];
    }

    return hex_hash;
}

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    return tmp_path;
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

test "should add a single file to the index" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-single");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

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

test "should add multiple files to the index" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-multiple");
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

test "should update a modified file in the index" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-update");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

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

test "should throw error for non-existent file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-nonexistent");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = add(io, allocator, tmp_path, &[_][]const u8{"nonexistent.txt"});
    try std.testing.expectError(error.FileNotFound, result);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-not-a-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = add(io, allocator, non_git_dir, &[_][]const u8{"test.txt"});
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should add all untracked files with addAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-addall-untracked");
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

    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src" });
    defer allocator.free(src_path);
    try cwd.createDirPath(io, src_path);

    const index_file_path = try std.fs.path.join(allocator, &[_][]const u8{ src_path, "index.ts" });
    defer allocator.free(index_file_path);
    try cwd.writeFile(io, .{ .sub_path = index_file_path, .data = "console.log('hello')" });

    try addAll(io, allocator, tmp_path);

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

test "should add all modified files with addAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-addall-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try addAll(io, allocator, tmp_path);

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

test "should add both untracked and modified files with addAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-addall-both");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const tracked_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "tracked.txt" });
    defer allocator.free(tracked_path);
    try cwd.writeFile(io, .{ .sub_path = tracked_path, .data = "original" });
    try add(io, allocator, tmp_path, &[_][]const u8{"tracked.txt"});
    try cwd.writeFile(io, .{ .sub_path = tracked_path, .data = "modified" });

    const new_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "new.txt" });
    defer allocator.free(new_path);
    try cwd.writeFile(io, .{ .sub_path = new_path, .data = "new content" });

    try addAll(io, allocator, tmp_path);

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

test "should handle empty repository with addAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-addall-empty");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    try addAll(io, allocator, tmp_path);

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

test "should throw error with addAll if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-addall-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = addAll(io, allocator, non_git_dir);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should verify file hash in index" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-verify-hash");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "index" });
    defer allocator.free(index_path);

    const index_content = cwd.readFileAlloc(io, index_path, allocator, .unlimited) catch unreachable;
    defer allocator.free(index_content);

    const expected_hash = try hashString(allocator, "content");
    defer allocator.free(expected_hash);

    const expected_line = try std.fmt.allocPrint(allocator, "test.txt {s} 100644", .{expected_hash});
    defer allocator.free(expected_line);

    try std.testing.expect(std.mem.indexOf(u8, index_content, expected_line) != null);
}

test "should preserve existing index entries when adding new files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-add-preserve");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file1.txt"});

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    try add(io, allocator, tmp_path, &[_][]const u8{"file2.txt"});

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
