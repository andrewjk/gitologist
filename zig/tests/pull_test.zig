const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const push = @import("gitologist").push;
const pull = @import("gitologist").pull;

test "should pull from default remote and branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-1" });
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

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, null, null, null);

    try pull(io, allocator, tmp_path, null, null, null);

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("modified", content);
}

test "should pull from specified remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-2" });
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

    try push(io, allocator, tmp_path, "upstream", null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, "upstream", null, null);

    try pull(io, allocator, tmp_path, "upstream", null, null);

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("modified", content);
}

test "should pull from specified branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-3" });
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

    try push(io, allocator, tmp_path, "origin", "main", null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, "origin", "main", null);

    try pull(io, allocator, tmp_path, "origin", "main", null);

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("modified", content);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-not-repo" });
    defer allocator.free(non_git_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, non_git_dir);
    defer cwd.deleteTree(io, non_git_dir) catch {};

    const result = pull(io, allocator, non_git_dir, null, null, null);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if remote branch does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-6" });
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

    const result = pull(io, allocator, tmp_path, null, null, null);
    try std.testing.expectError(error.RemoteBranchDoesNotExist, result);
}

test "should update local branch reference" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-7" });
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

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");

    try push(io, allocator, tmp_path, null, null, null);

    try pull(io, allocator, tmp_path, null, null, null);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);

    const local_branch_content = try cwd.readFileAlloc(io, local_branch_path, allocator, .unlimited);
    defer allocator.free(local_branch_content);

    const trimmed = std.mem.trim(u8, local_branch_content, &std.ascii.whitespace);

    try std.testing.expectEqualStrings(second_sha, trimmed);

    allocator.free(second_sha);
}

test "should handle directories" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-8" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const src_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src" });
    defer allocator.free(src_dir_path);
    try cwd.createDirPath(io, src_dir_path);

    const index_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "src", "index.ts" });
    defer allocator.free(index_file_path);
    try cwd.writeFile(io, .{ .sub_path = index_file_path, .data = "console.log('hello')" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "src/index.ts");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = index_file_path, .data = "console.log('world')" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "src/index.ts");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, null, null, null);

    try pull(io, allocator, tmp_path, null, null, null);

    const content = try cwd.readFileAlloc(io, index_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("console.log('world')", content);
}

test "should handle multiple files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-9" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file3.txt" });
    defer allocator.free(file1_path);
    defer allocator.free(file2_path);
    defer allocator.free(file3_path);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "content3" });

    const paths = try allocator.alloc([]const u8, 3);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "file1.txt");
    paths[1] = try allocator.dupe(u8, "file2.txt");
    paths[2] = try allocator.dupe(u8, "file3.txt");
    defer allocator.free(paths[0]);
    defer allocator.free(paths[1]);
    defer allocator.free(paths[2]);

    try add(io, allocator, tmp_path, paths);
    const sha = try commit(io, allocator, tmp_path, "Initial commit");
    allocator.free(sha);

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "modified2" });
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "modified3" });

    const paths2 = try allocator.alloc([]const u8, 3);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "file1.txt");
    paths2[1] = try allocator.dupe(u8, "file2.txt");
    paths2[2] = try allocator.dupe(u8, "file3.txt");
    defer allocator.free(paths2[0]);
    defer allocator.free(paths2[1]);
    defer allocator.free(paths2[2]);

    try add(io, allocator, tmp_path, paths2);
    const sha2 = try commit(io, allocator, tmp_path, "Second commit");
    allocator.free(sha2);

    try push(io, allocator, tmp_path, null, null, null);

    try pull(io, allocator, tmp_path, null, null, null);

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    const content3 = try cwd.readFileAlloc(io, file3_path, allocator, .unlimited);
    defer allocator.free(content1);
    defer allocator.free(content2);
    defer allocator.free(content3);

    try std.testing.expectEqualStrings("modified1", content1);
    try std.testing.expectEqualStrings("modified2", content2);
    try std.testing.expectEqualStrings("modified3", content3);
}
