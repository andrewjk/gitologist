const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const show = @import("gitologist").show;

test "should read file content at HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-1" });
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

    const content = try show(io, allocator, tmp_path, "test.txt", null);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("content", content);
}

test "should read nested file content at HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-2" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const sub_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sub" });
    defer allocator.free(sub_dir);
    try cwd.createDirPath(io, sub_dir);

    const inner_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sub", "inner.txt" });
    defer allocator.free(inner_path);

    try cwd.writeFile(io, .{ .sub_path = inner_path, .data = "inner content" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "sub/inner.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Add nested file");
    allocator.free(sha);

    const content = try show(io, allocator, tmp_path, "sub/inner.txt", null);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("inner content", content);
}

test "should reflect latest committed content after updates" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-3" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "v1" });

    const paths1 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths1);
    paths1[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths1[0]);

    try add(io, allocator, tmp_path, paths1);
    const sha1 = try commit(io, allocator, tmp_path, "First");
    allocator.free(sha1);

    {
        const content = try show(io, allocator, tmp_path, "test.txt", null);
        defer allocator.free(content);
        try std.testing.expectEqualStrings("v1", content);
    }

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "v2" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second");
    allocator.free(sha2);

    {
        const content = try show(io, allocator, tmp_path, "test.txt", null);
        defer allocator.free(content);
        try std.testing.expectEqualStrings("v2", content);
    }
}

test "should not reflect uncommitted working changes" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-4" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "committed" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha1 = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha1);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "uncommitted" });

    const content = try show(io, allocator, tmp_path, "test.txt", null);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("committed", content);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-not-repo" });
    defer allocator.free(non_git_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, non_git_dir);
    defer cwd.deleteTree(io, non_git_dir) catch {};

    const result = show(io, allocator, non_git_dir, "test.txt", null);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if file does not exist in HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-5" });
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

    const result = show(io, allocator, tmp_path, "nonexistent.txt", null);
    try std.testing.expectError(error.PathNotFound, result);
}

test "should throw error if path points to a directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-6" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const sub_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sub" });
    defer allocator.free(sub_dir);
    try cwd.createDirPath(io, sub_dir);

    const inner_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sub", "inner.txt" });
    defer allocator.free(inner_path);

    try cwd.writeFile(io, .{ .sub_path = inner_path, .data = "inner" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "sub/inner.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Add nested file");
    allocator.free(sha);

    const result = show(io, allocator, tmp_path, "sub", null);
    try std.testing.expectError(error.PathNotFound, result);
}

test "should read file content at a specific commit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-7" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "v1" });
    try add(io, allocator, tmp_path, paths);
    const first_sha = try commit(io, allocator, tmp_path, "First");
    defer allocator.free(first_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "v2" });
    try add(io, allocator, tmp_path, paths);
    const second_sha = try commit(io, allocator, tmp_path, "Second");
    defer allocator.free(second_sha);

    {
        const content = try show(io, allocator, tmp_path, "test.txt", first_sha);
        defer allocator.free(content);
        try std.testing.expectEqualStrings("v1", content);
    }

    {
        const content = try show(io, allocator, tmp_path, "test.txt", second_sha);
        defer allocator.free(content);
        try std.testing.expectEqualStrings("v2", content);
    }

    {
        const content = try show(io, allocator, tmp_path, "test.txt", null);
        defer allocator.free(content);
        try std.testing.expectEqualStrings("v2", content);
    }
}

test "should throw path not found at older commit for file added later" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-8" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const first_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "first.txt" });
    defer allocator.free(first_file_path);
    try cwd.writeFile(io, .{ .sub_path = first_file_path, .data = "first" });

    const paths1 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths1);
    paths1[0] = try allocator.dupe(u8, "first.txt");
    defer allocator.free(paths1[0]);

    try add(io, allocator, tmp_path, paths1);
    const first_sha = try commit(io, allocator, tmp_path, "First");
    defer allocator.free(first_sha);

    const later_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "later.txt" });
    defer allocator.free(later_file_path);
    try cwd.writeFile(io, .{ .sub_path = later_file_path, .data = "later" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "later.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Add later file");
    allocator.free(second_sha);

    const result = show(io, allocator, tmp_path, "later.txt", first_sha);
    try std.testing.expectError(error.PathNotFound, result);
}

test "should throw error if commit does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-show-test-9" });
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

    const result = show(io, allocator, tmp_path, "test.txt", "0000000000000000000000000000000000000000");
    try std.testing.expectError(error.CommitNotFound, result);
}
