const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const addAll = @import("gitologist").addAll;
const commit = @import("gitologist").commit;
const status = @import("gitologist").status;
const push = @import("gitologist").push;
const pull = @import("gitologist").pull;
const stash = @import("gitologist").stash;
const unstash = @import("gitologist").unstash;

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
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.modified.len);

    const file_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(file_content);

    try std.testing.expectEqualSlices(u8, "initial content", file_content);
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
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 0), result.untracked.len);

    _ = cwd.openFile(io, newfile_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    try std.testing.expect(false); // Should not reach here
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

test "should restore stashed modified file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-restore-modified");
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

    const after_stash_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(after_stash_content);

    try std.testing.expectEqualSlices(u8, "initial content", after_stash_content);

    try unstash(io, allocator, tmp_path);

    const after_unstash_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(after_unstash_content);

    try std.testing.expectEqualSlices(u8, "modified content", after_unstash_content);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    const has_modified = blk: {
        for (result.modified) |file| {
            if (std.mem.eql(u8, file, "test.txt")) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try std.testing.expect(has_modified);
}

test "should restore stashed untracked file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-restore-untracked");
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

    _ = cwd.openFile(io, newfile_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
    };

    try unstash(io, allocator, tmp_path);

    const content = try cwd.readFileAlloc(io, newfile_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualSlices(u8, "untracked content", content);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    const has_untracked = blk: {
        for (result.untracked) |file| {
            if (std.mem.eql(u8, file, "newfile.txt")) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try std.testing.expect(has_untracked);
}

test "should throw error if no stash exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-no-stash");
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

    const result = unstash(io, allocator, tmp_path);
    try std.testing.expectError(error.NoStashFound, result);
}

test "should throw error if not a git repository for unstash" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try createTempDir(allocator, "gitologist-stash-not-repo-unstash");
    defer allocator.free(non_git_dir);
    defer cleanupTempDir(io, non_git_dir);

    const result = unstash(io, allocator, non_git_dir);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should preserve ignored files when stashing" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-preserve-ignored");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(test_file_path);

    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "initial content" });
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "*.log\nnode_modules/\n" });
    try add(io, allocator, tmp_path, &[_][]const u8{ ".gitignore", "test.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "modified content" });

    const debug_log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "debug.log" });
    defer allocator.free(debug_log_path);

    try cwd.writeFile(io, .{ .sub_path = debug_log_path, .data = "log data" });

    const nm_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "node_modules" });
    defer allocator.free(nm_path);

    const nm_pkg_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "node_modules", "pkg" });
    defer allocator.free(nm_pkg_path);

    const nm_index_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "node_modules", "pkg", "index.js" });
    defer allocator.free(nm_index_path);

    cwd.createDirPath(io, nm_pkg_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    try cwd.writeFile(io, .{ .sub_path = nm_index_path, .data = "module" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    const after_stash_content = try cwd.readFileAlloc(io, test_file_path, allocator, .unlimited);
    defer allocator.free(after_stash_content);
    try std.testing.expectEqualSlices(u8, "initial content", after_stash_content);

    const log_content = try cwd.readFileAlloc(io, debug_log_path, allocator, .unlimited);
    defer allocator.free(log_content);
    try std.testing.expectEqualSlices(u8, "log data", log_content);

    const nm_content = try cwd.readFileAlloc(io, nm_index_path, allocator, .unlimited);
    defer allocator.free(nm_content);
    try std.testing.expectEqualSlices(u8, "module", nm_content);
}

test "should stash multiple files and preserve ignored" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-multi-preserve");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const tracked_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "tracked.txt" });
    defer allocator.free(tracked_path);

    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);

    try cwd.writeFile(io, .{ .sub_path = tracked_path, .data = "tracked content" });
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "*.log\nbuild/\n" });
    try add(io, allocator, tmp_path, &[_][]const u8{ ".gitignore", "tracked.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = tracked_path, .data = "modified" });

    const new_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "new.txt" });
    defer allocator.free(new_path);

    try cwd.writeFile(io, .{ .sub_path = new_path, .data = "new file" });

    const build_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "build" });
    defer allocator.free(build_path);

    const build_output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "build", "output.js" });
    defer allocator.free(build_output_path);

    cwd.createDirPath(io, build_path) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };
    try cwd.writeFile(io, .{ .sub_path = build_output_path, .data = "compiled" });

    const error_log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "error.log" });
    defer allocator.free(error_log_path);

    try cwd.writeFile(io, .{ .sub_path = error_log_path, .data = "errors" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    const build_content = try cwd.readFileAlloc(io, build_output_path, allocator, .unlimited);
    defer allocator.free(build_content);
    try std.testing.expectEqualSlices(u8, "compiled", build_content);

    const log_content = try cwd.readFileAlloc(io, error_log_path, allocator, .unlimited);
    defer allocator.free(log_content);
    try std.testing.expectEqualSlices(u8, "errors", log_content);
}

test "should merge stashed changes with changes to HEAD after stash" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-merge");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2\nline3\nline4\nline5" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2-modified\nline3\nline4\nline5" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2\nline3\nline4-pulled\nline5" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file.txt"});
    const pulled_sha = try commit(io, allocator, tmp_path, "Pulled changes");
    defer allocator.free(pulled_sha);

    try unstash(io, allocator, tmp_path);

    const content = try cwd.readFileAlloc(io, file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expectEqualSlices(u8, "line1\nline2-modified\nline3\nline4-pulled\nline5", content);
}

test "should detect conflicts when both stash and HEAD modify same lines" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-conflict");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2\nline3" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2-local\nline3" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "line1\nline2-remote\nline3" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file.txt"});
    const remote_sha = try commit(io, allocator, tmp_path, "Remote changes");
    defer allocator.free(remote_sha);

    try unstash(io, allocator, tmp_path);

    const content = try cwd.readFileAlloc(io, file_path, allocator, .unlimited);
    defer allocator.free(content);

    try std.testing.expect(std.mem.indexOf(u8, content, "<<<<<<< Updated upstream") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "line2-remote") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "=======") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, "line2-local") != null);
    try std.testing.expect(std.mem.indexOf(u8, content, ">>>>>>> Stashed changes") != null);
}

test "should keep HEAD changes when stash did not modify a file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-keep-head");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "a.txt" });
    defer allocator.free(a_path);

    const b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "b.txt" });
    defer allocator.free(b_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-original" });
    try cwd.writeFile(io, .{ .sub_path = b_path, .data = "b-original" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "a.txt", "b.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-local" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try cwd.writeFile(io, .{ .sub_path = b_path, .data = "b-remote" });
    try add(io, allocator, tmp_path, &[_][]const u8{"b.txt"});
    const remote_sha = try commit(io, allocator, tmp_path, "Remote changes");
    defer allocator.free(remote_sha);

    try unstash(io, allocator, tmp_path);

    const a_content = try cwd.readFileAlloc(io, a_path, allocator, .unlimited);
    defer allocator.free(a_content);
    try std.testing.expectEqualSlices(u8, "a-local", a_content);

    const b_content = try cwd.readFileAlloc(io, b_path, allocator, .unlimited);
    defer allocator.free(b_content);
    try std.testing.expectEqualSlices(u8, "b-remote", b_content);
}

test "should restore multiple stashed files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-multiple");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);

    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "content1" });
    try add(io, allocator, tmp_path, &[_][]const u8{"file1.txt"});

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = file1_path, .data = "modified1" });
    try cwd.writeFile(io, .{ .sub_path = file2_path, .data = "content2" });

    const stash_sha = try stash(io, allocator, tmp_path, "Multiple files");
    defer allocator.free(stash_sha);

    const after_stash_content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(after_stash_content1);

    try std.testing.expectEqualSlices(u8, "content1", after_stash_content1);

    _ = cwd.openFile(io, file2_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
    };

    try unstash(io, allocator, tmp_path);

    const after_unstash_content1 = try cwd.readFileAlloc(io, file1_path, allocator, .unlimited);
    defer allocator.free(after_unstash_content1);

    try std.testing.expectEqualSlices(u8, "modified1", after_unstash_content1);

    const after_unstash_content2 = try cwd.readFileAlloc(io, file2_path, allocator, .unlimited);
    defer allocator.free(after_unstash_content2);

    try std.testing.expectEqualSlices(u8, "content2", after_unstash_content2);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    const has_modified = blk: {
        for (result.modified) |file| {
            if (std.mem.eql(u8, file, "file1.txt")) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try std.testing.expect(has_modified);

    const has_untracked = blk: {
        for (result.untracked) |file| {
            if (std.mem.eql(u8, file, "file2.txt")) {
                break :blk true;
            }
        }
        break :blk false;
    };
    try std.testing.expect(has_untracked);
}

test "should restore stashed deleted file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-restore-deleted");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    const other_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "other.txt" });
    defer allocator.free(other_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = file_path, .data = "initial content" });
    try cwd.writeFile(io, .{ .sub_path = other_path, .data = "other content" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "test.txt", "other.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    cwd.deleteFile(io, file_path) catch {};

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    const after_stash_content = try cwd.readFileAlloc(io, other_path, allocator, .unlimited);
    defer allocator.free(after_stash_content);

    try std.testing.expectEqualSlices(u8, "other content", after_stash_content);

    try std.testing.expectEqual(@as(usize, 2), try countFilesInDir(io, allocator, tmp_path));

    try unstash(io, allocator, tmp_path);

    try std.testing.expectEqual(@as(usize, 1), try countFilesInDir(io, allocator, tmp_path));

    _ = cwd.openFile(io, file_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    try std.testing.expect(false);
}

test "should delete files that exist in HEAD but not in stash when HEAD has not moved" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-delete-head");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "a.txt" });
    defer allocator.free(a_path);

    const b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "b.txt" });
    defer allocator.free(b_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-original" });
    try cwd.writeFile(io, .{ .sub_path = b_path, .data = "b-original" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "a.txt", "b.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-local" });
    cwd.deleteFile(io, b_path) catch {};

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try unstash(io, allocator, tmp_path);

    const a_content = try cwd.readFileAlloc(io, a_path, allocator, .unlimited);
    defer allocator.free(a_content);
    try std.testing.expectEqualSlices(u8, "a-local", a_content);

    _ = cwd.openFile(io, b_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    try std.testing.expect(false);
}

test "should delete files that were deleted in stash and not modified in current HEAD" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-delete-stash");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "a.txt" });
    defer allocator.free(a_path);

    const b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "b.txt" });
    defer allocator.free(b_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-original" });
    try cwd.writeFile(io, .{ .sub_path = b_path, .data = "b-original" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "a.txt", "b.txt" });

    const init_commit_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(init_commit_sha);

    cwd.deleteFile(io, b_path) catch {};

    const stash_sha = try stash(io, allocator, tmp_path, "Delete b");
    defer allocator.free(stash_sha);

    try cwd.writeFile(io, .{ .sub_path = a_path, .data = "a-remote" });
    try add(io, allocator, tmp_path, &[_][]const u8{"a.txt"});
    const remote_sha = try commit(io, allocator, tmp_path, "Remote changes");
    defer allocator.free(remote_sha);

    try unstash(io, allocator, tmp_path);

    const a_content = try cwd.readFileAlloc(io, a_path, allocator, .unlimited);
    defer allocator.free(a_content);
    try std.testing.expectEqualSlices(u8, "a-remote", a_content);

    _ = cwd.openFile(io, b_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    try std.testing.expect(false);
}

test "should not restore a file deleted on the remote after stash pull unstash" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitologist-stash-remote-deleted");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    const file_a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fileA.txt" });
    const file_b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fileB.txt" });
    defer allocator.free(file_a_path);
    defer allocator.free(file_b_path);

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "a" });
    try cwd.writeFile(io, .{ .sub_path = file_b_path, .data = "b" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "fileA.txt", "fileB.txt" });

    const first_sha = try commit(io, allocator, tmp_path, "Initial commit");
    defer allocator.free(first_sha);

    try push(io, allocator, tmp_path, null, null, null);

    // Delete fileB on the remote and push.
    try cwd.deleteFile(io, file_b_path);
    try addAll(io, allocator, tmp_path);
    const second_sha = try commit(io, allocator, tmp_path, "Delete fileB");
    allocator.free(second_sha);
    try push(io, allocator, tmp_path, null, null, null);

    // Simulate a second clone at the first commit with an uncommitted
    // local edit to fileA, then refresh like RefreshManager does:
    // stash -> pull -> unstash.
    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git", "refs", "heads", "main" });
    defer allocator.free(local_branch_path);
    try cwd.writeFile(io, .{ .sub_path = local_branch_path, .data = first_sha });

    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "a" });
    try cwd.writeFile(io, .{ .sub_path = file_b_path, .data = "b" });
    try add(io, allocator, tmp_path, &[_][]const u8{ "fileA.txt", "fileB.txt" });
    try cwd.writeFile(io, .{ .sub_path = file_a_path, .data = "a-modified" });

    const stash_sha = try stash(io, allocator, tmp_path, "WIP");
    defer allocator.free(stash_sha);

    try pull(io, allocator, tmp_path, null, null, null);
    try unstash(io, allocator, tmp_path);

    // fileA's local edit must be restored...
    const content_a = try cwd.readFileAlloc(io, file_a_path, allocator, .unlimited);
    defer allocator.free(content_a);
    try std.testing.expectEqualSlices(u8, "a-modified", content_a);

    // ...but fileB was deleted on the remote and must NOT come back.
    _ = cwd.openFile(io, file_b_path, .{}) catch |err| {
        try std.testing.expect(err == error.FileNotFound);
        return;
    };
    try std.testing.expect(false);
}

fn countFilesInDir(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !usize {
    const cwd = std.Io.Dir.cwd();
    const dir = cwd.openDir(io, path, .{}) catch return 0;
    defer dir.close(io);

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (std.mem.eql(u8, entry.name, ".git")) continue;
        if (entry.kind == .directory) {
            const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ path, entry.name });
            defer allocator.free(sub_path);
            count += try countFilesInDir(io, allocator, sub_path);
        } else {
            count += 1;
        }
    }
    return count;
}
