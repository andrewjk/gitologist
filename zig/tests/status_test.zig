const std = @import("std");

const init = @import("gitologist").init;
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

test "should return current branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-branch");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqualStrings("main", result.branch);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should return up to date message" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-update");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(std.mem.indexOf(u8, result.up_to_date, "Your branch is up to date with") != null);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should return empty arrays for changes when no files exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-empty");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.staged.len == 0);
    try std.testing.expect(result.modified.len == 0);
    try std.testing.expect(result.untracked.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);
    allocator.free(result.staged);
    allocator.free(result.modified);
    allocator.free(result.untracked);
}

test "should detect untracked files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-untracked");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.untracked.len == 1);
    try std.testing.expectEqualStrings("test.txt", result.untracked[0]);
    try std.testing.expect(result.modified.len == 0);
    try std.testing.expect(result.staged.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should detect multiple untracked files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const readme_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "README.md" });
    defer allocator.free(readme_path);

    try cwd.writeFile(io, .{ .sub_path = readme_path, .data = "# Test" });

    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src" });
    defer allocator.free(src_path);

    try cwd.createDirPath(io, src_path);

    const index_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src", "index.ts" });
    defer allocator.free(index_file_path);

    try cwd.writeFile(io, .{ .sub_path = index_file_path, .data = "console.log('hello')" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.untracked.len == 3);

    var found_test = false;
    var found_readme = false;
    var found_index = false;

    for (result.untracked) |file| {
        if (std.mem.eql(u8, file, "test.txt")) found_test = true;
        if (std.mem.eql(u8, file, "README.md")) found_readme = true;
        if (std.mem.eql(u8, file, "src/index.ts")) found_index = true;
    }

    try std.testing.expect(found_test);
    try std.testing.expect(found_readme);
    try std.testing.expect(found_index);

    try std.testing.expect(result.modified.len == 0);
    try std.testing.expect(result.staged.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should detect modified files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const original_hash = try hashString(allocator, "original");
    defer allocator.free(original_hash);

    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    const index_data = try std.fmt.allocPrint(allocator, "test.txt\t{s}\t100644\n", .{original_hash});
    defer allocator.free(index_data);
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = index_data });

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified content" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.modified.len == 1);
    try std.testing.expectEqualStrings("test.txt", result.modified[0]);
    try std.testing.expect(result.untracked.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should detect deleted files as deleted" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-deleted");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const hash = try hashString(allocator, "content");
    defer allocator.free(hash);

    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    const index_data = try std.fmt.allocPrint(allocator, "test.txt\t{s}\t100644\n", .{hash});
    defer allocator.free(index_data);
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = index_data });

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try cwd.deleteFile(io, test_file_path);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.deleted.len == 1);
    try std.testing.expectEqualStrings("test.txt", result.deleted[0]);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);

    for (result.deleted) |item| allocator.free(item);
    allocator.free(result.deleted);
}

test "should handle detached HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-detached");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    try git_dir.writeFile(io, .{ .sub_path = "HEAD", .data = "deadbeef\n" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqualStrings("(detached HEAD)", result.branch);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-status-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    try std.testing.expectError(error.NotAGitRepository, status(io, allocator, non_git_dir));
}

test "should handle custom branch name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-branch-name");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    try git_dir.writeFile(io, .{ .sub_path = "HEAD", .data = "ref: refs/heads/main\n" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqualStrings("main", result.branch);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should not detect .git directory as untracked" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-git-dir");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const other_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "other" });
    defer allocator.free(other_path);

    try cwd.createDirPath(io, other_path);

    const other_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "other", "file.txt" });
    defer allocator.free(other_file_path);

    try cwd.writeFile(io, .{ .sub_path = other_file_path, .data = "content" });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.untracked.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}

test "should correctly identify files matching index" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-status-match");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const hash = try hashString(allocator, "content");
    defer allocator.free(hash);

    const index_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "index" });
    defer allocator.free(index_path);

    const index_data = try std.fmt.allocPrint(allocator, "test.txt\t{s}\t100644\n", .{hash});
    defer allocator.free(index_data);
    try cwd.writeFile(io, .{ .sub_path = index_path, .data = index_data });

    const result = try status(io, allocator, tmp_path);

    try std.testing.expect(result.modified.len == 0);
    try std.testing.expect(result.untracked.len == 0);

    allocator.free(result.branch);
    allocator.free(result.up_to_date);

    for (result.staged) |item| allocator.free(item);
    allocator.free(result.staged);

    for (result.modified) |item| allocator.free(item);
    allocator.free(result.modified);

    for (result.untracked) |item| allocator.free(item);
    allocator.free(result.untracked);
}
