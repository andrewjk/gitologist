const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const addAll = @import("gitologist").addAll;
const commit = @import("gitologist").commit;
const status = @import("gitologist").status;
const restore = @import("gitologist").restore;
const restoreAll = @import("gitologist").restoreAll;
const log = @import("gitologist").log;
const remoteAdd = @import("gitologist").remoteAdd;

const StatusInfo = @import("gitologist").types.StatusInfo;

var test_counter: u64 = 0;

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    _ = @atomicRmw(u64, &test_counter, .Add, 1, .seq_cst);
    const unique_name = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ name, test_counter });
    defer allocator.free(unique_name);
    return try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", unique_name });
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

// MARK: - Add Tests

test "should add file with single space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-single");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add file with multiple spaces in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test  multiple  spaces.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test  multiple  spaces.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add file with leading space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-leading");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, " leading.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{" leading.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add file with trailing space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-trailing");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "trailing .txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"trailing .txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add files in folder with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-folder");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "file.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"my folder/file.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add files in folder with multiple spaces in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-folder-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my  test  folder" });
    defer allocator.free(my_folder);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "file.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"my  test  folder/file.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add file with space in name in folder with space" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-folder-file");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"my folder/test file.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should add multiple files with spaces in names" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-multiple-files");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file three.txt" });
    defer allocator.free(file3_path);
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "content3" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file one.txt", "file two.txt", "file three.txt" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

test "should update modified file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.modified.len);
}

test "should add all files with spaces using addAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-addall");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.ts" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "console.log('hello')" });

    try addAll(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
}

// MARK: - Commit Tests

test "should commit file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-commit");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Add file with space");
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);
}

test "should commit multiple files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-commit-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file one.txt", "file two.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Add multiple files with spaces");
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);
}

test "should commit files in folder with space" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-commit-folder");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"my folder/test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Add file in folder with space");
    defer allocator.free(commit_sha);

    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);
}

test "should handle multiple commits with files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-commits-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const first_sha = try commit(io, allocator, tmp_path, "First commit");
    defer allocator.free(first_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const second_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(second_sha);

    try std.testing.expect(!std.mem.eql(u8, first_sha, second_sha));

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.modified.len);
}

// MARK: - Status Tests

test "should detect untracked file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-status-untracked");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    var found = false;
    for (result.untracked) |file| {
        if (std.mem.eql(u8, file, "test file.txt")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "should detect multiple untracked files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-status-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.ts" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "console.log('hello')" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    var found_file_one = false;
    var found_file_two = false;
    var found_folder_file = false;
    for (result.untracked) |file| {
        if (std.mem.eql(u8, file, "file one.txt")) found_file_one = true;
        if (std.mem.eql(u8, file, "file two.txt")) found_file_two = true;
        if (std.mem.eql(u8, file, "my folder/test file.ts")) found_folder_file = true;
    }
    try std.testing.expect(found_file_one);
    try std.testing.expect(found_file_two);
    try std.testing.expect(found_folder_file);
}

test "should detect modified file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-status-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    var found = false;
    for (result.modified) |file| {
        if (std.mem.eql(u8, file, "test file.txt")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "should detect deleted file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-status-deleted");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Add file");
    defer allocator.free(commit_sha);

    try cwd.deleteFile(io, test_file_path);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    var found = false;
    for (result.deleted) |file| {
        if (std.mem.eql(u8, file, "test file.txt")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

// MARK: - Restore Tests

test "should restore modified file with space in name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-restore");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try restore(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("original", content);
}

test "should restore multiple files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-restore-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "original1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "original2" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file one.txt", "file two.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "modified2" });

    try restore(io, allocator, tmp_path, &[_][]const u8{ "file one.txt", "file two.txt" });

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);

    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings("original1", content1);
    try std.testing.expectEqualStrings("original2", content2);
}

test "should restore file in folder with space" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-restore-folder");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, my_folder);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.txt" });
    defer allocator.free(test_file_path);
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });

    try add(io, allocator, tmp_path, &[_][]const u8{"my folder/test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    try restore(io, allocator, tmp_path, &[_][]const u8{"my folder/test file.txt"});

    const content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualStrings("original", content);
}

test "should restore all modified files with spaces using restoreAll" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-restoreall");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "original1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "original2" });

    try add(io, allocator, tmp_path, &[_][]const u8{ "file one.txt", "file two.txt" });

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "modified2" });

    try restoreAll(io, allocator, tmp_path);

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);

    const content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(content2);

    try std.testing.expectEqualStrings("original1", content1);
    try std.testing.expectEqualStrings("original2", content2);
}

test "should update status after restoring file with space" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-restore-status");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "original" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const result1 = try status(io, allocator, tmp_path);
    defer result1.deinit(allocator);

    var found = false;
    for (result1.modified) |file| {
        if (std.mem.eql(u8, file, "test file.txt")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);

    try restore(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const result2 = try status(io, allocator, tmp_path);
    defer result2.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result2.modified.len);
}

// MARK: - Log Tests

test "should log commits for files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-log");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit_sha = try commit(io, allocator, tmp_path, "Add file with space");
    defer allocator.free(commit_sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 1), result.len);

    try std.testing.expectEqualStrings("Add file with space", result[0].message);
}

test "should log multiple commits with files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-log-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content1" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit1_sha = try commit(io, allocator, tmp_path, "First commit");
    defer allocator.free(commit1_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content2" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit2_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(commit2_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content3" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit3_sha = try commit(io, allocator, tmp_path, "Third commit");
    defer allocator.free(commit3_sha);

    const result = try log(io, allocator, tmp_path, null);
    defer {
        for (result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 3), result.len);
    try std.testing.expectEqualStrings("Third commit", result[0].message);
    try std.testing.expectEqualStrings("Second commit", result[1].message);
    try std.testing.expectEqualStrings("First commit", result[2].message);
}

test "should limit commits for files with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-log-limit");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test file.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content1" });

    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit1_sha = try commit(io, allocator, tmp_path, "First commit");
    defer allocator.free(commit1_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content2" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit2_sha = try commit(io, allocator, tmp_path, "Second commit");
    defer allocator.free(commit2_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content3" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test file.txt"});

    const commit3_sha = try commit(io, allocator, tmp_path, "Third commit");
    defer allocator.free(commit3_sha);

    const LogOptions = @import("gitologist").LogOptions;
    const options = LogOptions{ .limit = 2 };

    const result = try log(io, allocator, tmp_path, options);
    defer {
        for (result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(result);
    }

    try std.testing.expectEqual(@as(usize, 2), result.len);
    try std.testing.expectEqualStrings("Third commit", result[0].message);
    try std.testing.expectEqualStrings("Second commit", result[1].message);
}

// MARK: - Remote Tests

test "should add remote with space in URL path" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-remote");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://example.com/path with spaces/repo.git");

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "config" });
    defer allocator.free(config_path);

    const cwd = std.Io.Dir.cwd();
    const config_content = try cwd.readFileAlloc(io, config_path, allocator, .unlimited);
    defer allocator.free(config_content);

    try std.testing.expect(std.mem.indexOf(u8, config_content, "https://example.com/path with spaces/repo.git") != null);
}

// MARK: - Complex Scenario Tests

test "should handle complete workflow with files and folders with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-workflow");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file one.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file two.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const my_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my folder" });
    defer allocator.free(my_folder);
    try cwd.createDirPath(io, my_folder);

    const another_folder = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "another  folder" });
    defer allocator.free(another_folder);
    try cwd.createDirPath(io, another_folder);

    const folder_file_path = try std.fs.path.join(allocator, &[_][]const u8{ my_folder, "test file.ts" });
    defer allocator.free(folder_file_path);
    try cwd.writeFile(io, .{ .sub_path = folder_file_path, .data = "console.log('hello')" });

    const another_file_path = try std.fs.path.join(allocator, &[_][]const u8{ another_folder, "data  file.json" });
    defer allocator.free(another_file_path);
    try cwd.writeFile(io, .{ .sub_path = another_file_path, .data = "{\"key\": \"value\"}" });

    try addAll(io, allocator, tmp_path);

    const result1 = try status(io, allocator, tmp_path);
    defer result1.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result1.untracked.len);

    const commit_sha = try commit(io, allocator, tmp_path, "Initial commit with spaced files");
    defer allocator.free(commit_sha);

    const result2 = try status(io, allocator, tmp_path);
    defer result2.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result2.modified.len);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = folder_file_path, .data = "console.log('modified')" });

    const result3 = try status(io, allocator, tmp_path);
    defer result3.deinit(allocator);

    var found_file_one = false;
    var found_folder_file = false;
    for (result3.modified) |file| {
        if (std.mem.eql(u8, file, "file one.txt")) found_file_one = true;
        if (std.mem.eql(u8, file, "my folder/test file.ts")) found_folder_file = true;
    }
    try std.testing.expect(found_file_one);
    try std.testing.expect(found_folder_file);

    try restore(io, allocator, tmp_path, &[_][]const u8{"file one.txt"});

    const content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(content1);
    try std.testing.expectEqualStrings("content1", content1);

    const log_result = try log(io, allocator, tmp_path, null);
    defer {
        for (log_result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(log_result);
    }

    try std.testing.expectEqual(@as(usize, 1), log_result.len);
    try std.testing.expectEqualStrings("Initial commit with spaced files", log_result[0].message);
}

test "should handle files with various space patterns" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-patterns");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const files = [_][]const u8{
        "single space.txt",
        "double  space.txt",
        "triple   space.txt",
        " leading.txt",
        "trailing .txt",
    };

    for (files) |file| {
        const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, file });
        defer allocator.free(file_path);
        try cwd.writeFile(io, .{ .sub_path = file_path, .data = "content" });
    }

    try addAll(io, allocator, tmp_path);

    const commit_sha = try commit(io, allocator, tmp_path, "Add files with various space patterns");
    defer allocator.free(commit_sha);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
    try std.testing.expectEqual(@as(usize, 0), result.modified.len);

    const log_result = try log(io, allocator, tmp_path, null);
    defer {
        for (log_result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(log_result);
    }

    try std.testing.expectEqual(@as(usize, 1), log_result.len);
}

test "should handle nested folders with spaces" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "spaces-nested");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const folder1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "folder one" });
    defer allocator.free(folder1);
    try cwd.createDirPath(io, folder1);

    const folder2 = try std.fs.path.join(allocator, &[_][]const u8{ folder1, "folder two" });
    defer allocator.free(folder2);
    try cwd.createDirPath(io, folder2);

    const folder3 = try std.fs.path.join(allocator, &[_][]const u8{ folder2, "folder three" });
    defer allocator.free(folder3);
    try cwd.createDirPath(io, folder3);

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ folder1, "file1.txt" });
    defer allocator.free(file1_path);
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ folder2, "file2.txt" });
    defer allocator.free(file2_path);
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ folder3, "file3.txt" });
    defer allocator.free(file3_path);
    try cwd.writeFile(io, .{ .sub_path = file3_path, .data = "content3" });

    try addAll(io, allocator, tmp_path);

    const commit_sha = try commit(io, allocator, tmp_path, "Add nested folders with spaces");
    defer allocator.free(commit_sha);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);

    const log_result = try log(io, allocator, tmp_path, null);
    defer {
        for (log_result) |entry| {
            allocator.free(entry.message);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.committer);
        }
        allocator.free(log_result);
    }

    try std.testing.expectEqual(@as(usize, 1), log_result.len);
}
