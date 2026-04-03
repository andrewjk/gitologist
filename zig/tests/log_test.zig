const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const log = @import("gitologist").log;
const LogOptions = @import("gitologist").LogOptions;

test "should return empty log for empty repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-1" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const result = try log(io, allocator, tmp_path, null);

    try std.testing.expect(result.len == 0);
}

test "should log single commit" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-2" });
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

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expectEqualStrings("Initial commit", result[0].message);
}

test "should log multiple commits in reverse order" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-3" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content1" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha1 = try commit(io, allocator, tmp_path, "First commit");
    allocator.free(sha1);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content2" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content3" });

    const paths3 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths3);
    paths3[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths3[0]);

    try add(io, allocator, tmp_path, paths3);
    const sha3 = try commit(io, allocator, tmp_path, "Third commit");
    allocator.free(sha3);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 3);
    try std.testing.expectEqualStrings("Third commit", result[0].message);
    try std.testing.expectEqualStrings("Second commit", result[1].message);
    try std.testing.expectEqualStrings("First commit", result[2].message);
}

test "should limit number of commits" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-4" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content1" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha1 = try commit(io, allocator, tmp_path, "First commit");
    allocator.free(sha1);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content2" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content3" });

    const paths3 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths3);
    paths3[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths3[0]);

    try add(io, allocator, tmp_path, paths3);
    const sha3 = try commit(io, allocator, tmp_path, "Third commit");
    allocator.free(sha3);

    const opts = LogOptions{ .limit = 2 };
    const result = try log(io, allocator, tmp_path, opts);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 2);
    try std.testing.expectEqualStrings("Third commit", result[0].message);
    try std.testing.expectEqualStrings("Second commit", result[1].message);
}

test "should include commit SHA" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-5" });
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
    const sha = try commit(io, allocator, tmp_path, "Test commit");
    allocator.free(sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].sha.len == 40);
    for (result[0].sha) |c| {
        try std.testing.expect((c >= 'a' and c <= 'f') or (c >= '0' and c <= '9'));
    }
}

test "should include abbreviated SHA" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-6" });
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
    const sha = try commit(io, allocator, tmp_path, "Test commit");
    allocator.free(sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].abbreviated_sha.len == 7);
    for (result[0].abbreviated_sha) |c| {
        try std.testing.expect((c >= 'a' and c <= 'f') or (c >= '0' and c <= '9'));
    }
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-not-repo" });
    defer allocator.free(non_git_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, non_git_dir);
    defer cwd.deleteTree(io, non_git_dir) catch {};

    const result = log(io, allocator, non_git_dir, null);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if branch not found" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-7" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const opts = LogOptions{ .branch = "nonexistent" };
    const result = log(io, allocator, tmp_path, opts);
    try std.testing.expectError(error.BranchNotFound, result);
}

test "should include author" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-8" });
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
    const sha = try commit(io, allocator, tmp_path, "Test commit");
    allocator.free(sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].author.len > 0);
}

test "should include commit date" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-9" });
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
    const sha = try commit(io, allocator, tmp_path, "Test commit");
    allocator.free(sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expect(result[0].date >= 0);
}

test "should handle multi-line commit messages" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-10" });
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
    const sha = try commit(io, allocator, tmp_path, "Multi-line\ncommit\nmessage");
    allocator.free(sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 1);
    try std.testing.expectEqualStrings("Multi-line\ncommit\nmessage", result[0].message);
}

test "should include parent commit reference" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-log-test-11" });
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
    const first_sha = try commit(io, allocator, tmp_path, "First commit");
    errdefer allocator.free(first_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(second_sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(result);
    }

    try std.testing.expect(result.len == 2);
    try std.testing.expect(result[0].parent != null);
    if (result[0].parent) |p| {
        try std.testing.expectEqualStrings(first_sha, p);
    }
    try std.testing.expect(result[1].parent == null);

    allocator.free(first_sha);
}
