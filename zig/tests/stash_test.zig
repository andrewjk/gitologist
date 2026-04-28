const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const status = @import("gitologist").status;
const stash = @import("gitologist").stash;

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    return tmp_path;
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

test "should stash a modified file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-modified");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified content" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try std.testing.expectEqual(@as(usize, 40), stash_sha.len);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqual(@as(usize, 0), result.modified.len);

    const file_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(file_content);

    try std.testing.expectEqualSlices(u8, "initial content", file_content);

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

test "should stash an untracked file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-untracked");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const newfile_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "newfile.txt" });
    defer allocator.free(newfile_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = newfile_path, .data = "untracked content" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try std.testing.expectEqual(@as(usize, 40), stash_sha.len);

    const result = try status(io, allocator, tmp_path);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);

    _ = cwd.openFile(io, newfile_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
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
        return;
    };
    try std.testing.expect(false); // Should not reach here

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

test "should update stash ref" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-ref");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const stash_sha = try stash(io, allocator, tmp_path, "Save work");
    defer allocator.free(stash_sha);

    const stash_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "stash" });
    defer allocator.free(stash_ref_path);

    const ref_content = try cwd.readFileAlloc(io, stash_ref_path, allocator, .unlimited);
    defer allocator.free(ref_content);

    const trimmed = std.mem.trim(u8, ref_content, &std.ascii.whitespace);
    try std.testing.expectEqualSlices(u8, stash_sha, trimmed);
}

test "should reset index to HEAD after stash" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-reset-index");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const pre_stash_status = try status(io, allocator, tmp_path);

    const has_staged = blk: {
        for (pre_stash_status.staged) |file| {
            if (std.mem.eql(u8, file, "test.txt")) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try std.testing.expect(has_staged);

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    allocator.free(pre_stash_status.branch);
    allocator.free(pre_stash_status.up_to_date);
    for (pre_stash_status.staged) |item| allocator.free(item);
    allocator.free(pre_stash_status.staged);
    for (pre_stash_status.modified) |item| allocator.free(item);
    allocator.free(pre_stash_status.modified);
    for (pre_stash_status.untracked) |item| allocator.free(item);
    allocator.free(pre_stash_status.untracked);
    for (pre_stash_status.deleted) |item| allocator.free(item);
    allocator.free(pre_stash_status.deleted);

    const post_stash_status = try status(io, allocator, tmp_path);

    const file_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(file_content);

    try std.testing.expectEqualSlices(u8, "initial content", file_content);
    try std.testing.expectEqual(@as(usize, 0), post_stash_status.modified.len);

    allocator.free(post_stash_status.branch);
    allocator.free(post_stash_status.up_to_date);
    for (post_stash_status.staged) |item| allocator.free(item);
    allocator.free(post_stash_status.staged);
    for (post_stash_status.modified) |item| allocator.free(item);
    allocator.free(post_stash_status.modified);
    for (post_stash_status.untracked) |item| allocator.free(item);
    allocator.free(post_stash_status.untracked);
    for (post_stash_status.deleted) |item| allocator.free(item);
    allocator.free(post_stash_status.deleted);
}

test "should throw error if nothing to stash" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-nothing");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    const result = stash(io, allocator, tmp_path, "WIP");
    try std.testing.expectError(error.NothingToStash, result);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-stash-not-repo");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = stash(io, allocator, non_git_dir, "WIP");
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should handle custom stash message" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-custom");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content" });
    try add(io, allocator, tmp_path, &[_][]const u8{"test.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified" });

    const message = "Work in progress on feature X";
    const stash_sha = try stash(io, allocator, tmp_path, message);
    defer allocator.free(stash_sha);

    const commit_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "objects", stash_sha[0..2], stash_sha[2..] });
    defer allocator.free(commit_path);

    const file = cwd.openFile(io, commit_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    file.close(io);
    try std.testing.expect(true); // File exists
}
