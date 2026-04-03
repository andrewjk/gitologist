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

fn cleanupStatus(allocator: std.mem.Allocator, result: StatusInfo) void {
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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);
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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
    defer cleanupStatus(allocator, result);

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
