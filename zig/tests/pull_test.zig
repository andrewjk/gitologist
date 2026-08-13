const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const addAll = @import("gitologist").addAll;
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

test "should fast-forward when remote is ahead" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-10" });
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
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    try push(io, allocator, tmp_path, null, null, null);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths3 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths3);
    paths3[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths3[0]);
    try add(io, allocator, tmp_path, paths3);

    try pull(io, allocator, tmp_path, null, null, null);

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("modified", content);

    const local_branch_content = try cwd.readFileAlloc(io, local_branch_path, allocator, .unlimited);
    defer allocator.free(local_branch_content);

    const trimmed = std.mem.trim(u8, local_branch_content, &std.ascii.whitespace);
    try std.testing.expectEqualStrings(second_sha, trimmed);

    allocator.free(first_sha);
    allocator.free(second_sha);
}

test "should throw error when local changes would be overwritten" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-11" });
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
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths2[0]);

    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const paths3 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths3);
    paths3[0] = try allocator.dupe(u8, "test.txt");
    defer allocator.free(paths3[0]);
    try add(io, allocator, tmp_path, paths3);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "local changes" });

    const result = pull(io, allocator, tmp_path, null, null, null);
    try std.testing.expectError(error.LocalChangesWouldBeOverwritten, result);

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("local changes", content);

    allocator.free(first_sha);
}

test "should delete files removed on remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-13" });
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
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    // Remove file2 on the remote
    try cwd.deleteFile(io, file2_path);
    try addAll(io, allocator, tmp_path);
    const second_sha = try commit(io, allocator, tmp_path, "Remove file2");
    allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    // Reset local branch back to first commit to simulate another clone
    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "content3" });

    const paths2 = try allocator.alloc([]const u8, 3);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "file1.txt");
    paths2[1] = try allocator.dupe(u8, "file2.txt");
    paths2[2] = try allocator.dupe(u8, "file3.txt");
    defer allocator.free(paths2[0]);
    defer allocator.free(paths2[1]);
    defer allocator.free(paths2[2]);
    try add(io, allocator, tmp_path, paths2);

    try pull(io, allocator, tmp_path, null, null, null);

    // file2 should be deleted from the working tree
    const file2_exists = if (cwd.access(io, file2_path, .{})) |_| true else |_| false;
    try std.testing.expect(!file2_exists);

    // surviving files should be untouched
    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    const content3 = try cwd.readFileAlloc(io, file3_path, allocator, .unlimited);
    defer allocator.free(content1);
    defer allocator.free(content3);

    try std.testing.expectEqualStrings("content1", content1);
    try std.testing.expectEqualStrings("content3", content3);

    allocator.free(first_sha);
}

test "should preserve locally modified file deleted on remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-14" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file1_path);
    defer allocator.free(file2_path);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const paths = try allocator.alloc([]const u8, 2);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "file1.txt");
    paths[1] = try allocator.dupe(u8, "file2.txt");
    defer allocator.free(paths[0]);
    defer allocator.free(paths[1]);

    try add(io, allocator, tmp_path, paths);
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    // Remove file2 on the remote
    try cwd.deleteFile(io, file2_path);
    try addAll(io, allocator, tmp_path);
    const second_sha = try commit(io, allocator, tmp_path, "Remove file2");
    allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    // Reset local branch back to first commit to simulate another clone
    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const paths2 = try allocator.alloc([]const u8, 2);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "file1.txt");
    paths2[1] = try allocator.dupe(u8, "file2.txt");
    defer allocator.free(paths2[0]);
    defer allocator.free(paths2[1]);
    try add(io, allocator, tmp_path, paths2);

    // Make uncommitted local edits to file2, which was deleted on the remote
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "local changes" });

    try pull(io, allocator, tmp_path, null, null, null);

    // file2 should be preserved because it has uncommitted local edits
    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings("local changes", content2);

    // file1 should be untouched
    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);

    try std.testing.expectEqualStrings("content1", content1);

    allocator.free(first_sha);
}

test "should not overwrite unchanged files with local modifications" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-12" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file1_path);
    defer allocator.free(file2_path);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const paths = try allocator.alloc([]const u8, 2);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "file1.txt");
    paths[1] = try allocator.dupe(u8, "file2.txt");
    defer allocator.free(paths[0]);
    defer allocator.free(paths[1]);

    try add(io, allocator, tmp_path, paths);
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "file1.txt");
    defer allocator.free(paths2[0]);
    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const paths3 = try allocator.alloc([]const u8, 2);
    defer allocator.free(paths3);
    paths3[0] = try allocator.dupe(u8, "file1.txt");
    paths3[1] = try allocator.dupe(u8, "file2.txt");
    defer allocator.free(paths3[0]);
    defer allocator.free(paths3[1]);
    try add(io, allocator, tmp_path, paths3);

    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "local changes to file2" });

    try pull(io, allocator, tmp_path, null, null, null);

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);

    try std.testing.expectEqualStrings("modified1", content1);

    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings("local changes to file2", content2);

    allocator.free(first_sha);
}

test "should preserve untracked local file when pull would overwrite it" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-13" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const file_a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fileA.txt" });
    const file_b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fileB.txt" });
    defer allocator.free(file_a_path);
    defer allocator.free(file_b_path);

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "contentA" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "fileA.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    // Remote adds fileB
    try cwd.writeFile(io, .{ .sub_path = file_b_path, .data = "remoteB" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "fileB.txt");
    defer allocator.free(paths2[0]);
    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Add fileB");
    defer allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    // Reset local branch back to first commit and rebuild the index
    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "contentA" });
    try cwd.deleteFile(io, file_b_path);
    try addAll(io, allocator, tmp_path);

    // Create an untracked local fileB with local content
    try cwd.writeFile(io, .{ .sub_path = file_b_path, .data = "localB" });

    try pull(io, allocator, tmp_path, null, null, null);

    // fileB must be preserved (not overwritten by the remote's "remoteB")
    const file_b_content = try cwd.readFileAlloc(io, file_b_path, allocator, .unlimited);
    defer allocator.free(file_b_content);
    try std.testing.expectEqualStrings("localB", file_b_content);

    // fileA should be untouched
    const file_a_content = try cwd.readFileAlloc(io, file_a_path, allocator, .unlimited);
    defer allocator.free(file_a_content);
    try std.testing.expectEqualStrings("contentA", file_a_content);

    allocator.free(first_sha);
}

test "should preserve modified tracked file when pull would overwrite it" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-pull-test-14" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const file_a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fileA.txt" });
    defer allocator.free(file_a_path);

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "contentA" });

    const paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths);
    paths[0] = try allocator.dupe(u8, "fileA.txt");
    defer allocator.free(paths[0]);

    try add(io, allocator, tmp_path, paths);
    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");

    try push(io, allocator, tmp_path, null, null, null);

    // Remote modifies fileA
    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "remoteUpdated" });

    const paths2 = try allocator.alloc([]const u8, 1);
    defer allocator.free(paths2);
    paths2[0] = try allocator.dupe(u8, "fileA.txt");
    defer allocator.free(paths2[0]);
    try add(io, allocator, tmp_path, paths2);
    const second_sha = try commit(io, allocator, tmp_path, "Modify fileA");
    defer allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    // Reset local branch back to first commit and rebuild the index
    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "contentA" });
    try addAll(io, allocator, tmp_path);

    // Make a local modification to the tracked fileA. Unlike an unstaged
    // edit (which throws "would be overwritten by merge"), a staged change
    // passes the pre-flight check and is preserved by the checkout logic.
    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "localModified" });
    try add(io, allocator, tmp_path, paths);

    try pull(io, allocator, tmp_path, null, null, null);

    // fileA must be preserved (not overwritten by the remote's "remoteUpdated")
    const file_a_modified = try cwd.readFileAlloc(io, file_a_path, allocator, .unlimited);
    defer allocator.free(file_a_modified);
    try std.testing.expectEqualStrings("localModified", file_a_modified);

    allocator.free(first_sha);
}
