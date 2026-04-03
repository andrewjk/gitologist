const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const merge = @import("gitologist").merge;
const MergeOptions = @import("gitologist").MergeOptions;

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const non_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-not-repo" });
    defer allocator.free(non_git_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, non_git_dir);
    defer cwd.deleteTree(io, non_git_dir) catch {};

    const result = merge(io, allocator, non_git_dir, "feature", null);
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error when merging a branch into itself" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-1" });
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

    const result = merge(io, allocator, tmp_path, "main", null);
    try std.testing.expectError(error.CannotMergeIntoSelf, result);
}

test "should throw error if branch not found" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-2" });
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

    const result = merge(io, allocator, tmp_path, "nonexistent", null);
    try std.testing.expectError(error.BranchNotFound, result);
}

test "should throw error when merging into empty branch" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-3" });
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

    try createBranch(io, allocator, tmp_path, "feature");
    try checkoutBranch(io, allocator, tmp_path, "feature");

    const feature_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "feature.txt" });
    defer allocator.free(feature_file_path);

    try cwd.writeFile(io, .{ .sub_path = feature_file_path, .data = "feature content" });

    const feature_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(feature_paths);
    feature_paths[0] = try allocator.dupe(u8, "feature.txt");
    defer allocator.free(feature_paths[0]);

    try add(io, allocator, tmp_path, feature_paths);
    const feature_sha = try commit(io, allocator, tmp_path, "Feature commit");
    allocator.free(feature_sha);

    try checkoutBranch(io, allocator, tmp_path, "main");
    try deleteBranchCommit(io, allocator, tmp_path);

    const result = merge(io, allocator, tmp_path, "feature", null);
    try std.testing.expectError(error.CannotMergeIntoEmptyBranch, result);
}

test "should perform fast-forward merge when possible" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-4" });
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

    try createBranch(io, allocator, tmp_path, "feature");
    try checkoutBranch(io, allocator, tmp_path, "feature");

    const feature_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "feature.txt" });
    defer allocator.free(feature_file_path);

    try cwd.writeFile(io, .{ .sub_path = feature_file_path, .data = "feature content" });

    const feature_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(feature_paths);
    feature_paths[0] = try allocator.dupe(u8, "feature.txt");
    defer allocator.free(feature_paths[0]);

    try add(io, allocator, tmp_path, feature_paths);
    const feature_sha = try commit(io, allocator, tmp_path, "Feature commit");

    try checkoutBranch(io, allocator, tmp_path, "main");

    const result = try merge(io, allocator, tmp_path, "feature", null);
    defer {
        if (result.commit_sha) |s| allocator.free(s);
        if (result.message) |msg| allocator.free(msg);
    }

    try std.testing.expect(result.success);
    try std.testing.expect(result.fast_forward);
    if (result.commit_sha) |s| {
        try std.testing.expectEqualStrings(feature_sha, s);
    }
    allocator.free(feature_sha);
}

test "should create merge commit when not fast-forward" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-5" });
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

    try createBranch(io, allocator, tmp_path, "feature");
    try checkoutBranch(io, allocator, tmp_path, "feature");

    const feature_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "feature.txt" });
    defer allocator.free(feature_file_path);

    try cwd.writeFile(io, .{ .sub_path = feature_file_path, .data = "feature content" });

    const feature_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(feature_paths);
    feature_paths[0] = try allocator.dupe(u8, "feature.txt");
    defer allocator.free(feature_paths[0]);

    try add(io, allocator, tmp_path, feature_paths);
    const feature_sha = try commit(io, allocator, tmp_path, "Feature commit");
    allocator.free(feature_sha);

    try checkoutBranch(io, allocator, tmp_path, "main");

    const main_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "main.txt" });
    defer allocator.free(main_file_path);

    try cwd.writeFile(io, .{ .sub_path = main_file_path, .data = "main content" });

    const main_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(main_paths);
    main_paths[0] = try allocator.dupe(u8, "main.txt");
    defer allocator.free(main_paths[0]);

    try add(io, allocator, tmp_path, main_paths);
    const main_sha = try commit(io, allocator, tmp_path, "Master commit");
    allocator.free(main_sha);

    const result = try merge(io, allocator, tmp_path, "feature", null);
    defer {
        if (result.commit_sha) |s| allocator.free(s);
        if (result.message) |msg| allocator.free(msg);
    }

    try std.testing.expect(result.success);
    try std.testing.expect(!result.fast_forward);
    if (result.commit_sha) |s| {
        try std.testing.expect(s.len == 40);
    }
}

test "should allow non-fast-forward merge with option" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-6" });
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

    try createBranch(io, allocator, tmp_path, "feature");
    try checkoutBranch(io, allocator, tmp_path, "feature");

    const feature_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "feature.txt" });
    defer allocator.free(feature_file_path);

    try cwd.writeFile(io, .{ .sub_path = feature_file_path, .data = "feature content" });

    const feature_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(feature_paths);
    feature_paths[0] = try allocator.dupe(u8, "feature.txt");
    defer allocator.free(feature_paths[0]);

    try add(io, allocator, tmp_path, feature_paths);
    const feature_sha = try commit(io, allocator, tmp_path, "Feature commit");
    allocator.free(feature_sha);

    try checkoutBranch(io, allocator, tmp_path, "main");

    const opts = MergeOptions{ .no_fast_forward = true };
    const result = try merge(io, allocator, tmp_path, "feature", opts);
    defer {
        if (result.commit_sha) |s| allocator.free(s);
        if (result.message) |msg| allocator.free(msg);
    }

    try std.testing.expect(result.success);
    try std.testing.expect(!result.fast_forward);
    if (result.commit_sha) |s| {
        try std.testing.expect(s.len == 40);
    }
}

test "should report already up to date when branches are same" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-7" });
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

    try createBranch(io, allocator, tmp_path, "feature");

    const result = try merge(io, allocator, tmp_path, "feature", null);
    defer {
        if (result.commit_sha) |s| allocator.free(s);
        if (result.message) |msg| allocator.free(msg);
    }

    try std.testing.expect(result.success);
    if (result.message) |msg| {
        try std.testing.expectEqualStrings("Already up to date.", msg);
    }
}

test "should use custom merge message" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-merge-test-8" });
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

    try createBranch(io, allocator, tmp_path, "feature");
    try checkoutBranch(io, allocator, tmp_path, "feature");

    const feature_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "feature.txt" });
    defer allocator.free(feature_file_path);

    try cwd.writeFile(io, .{ .sub_path = feature_file_path, .data = "feature content" });

    const feature_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(feature_paths);
    feature_paths[0] = try allocator.dupe(u8, "feature.txt");
    defer allocator.free(feature_paths[0]);

    try add(io, allocator, tmp_path, feature_paths);
    const feature_sha = try commit(io, allocator, tmp_path, "Feature commit");
    allocator.free(feature_sha);

    try checkoutBranch(io, allocator, tmp_path, "main");

    const main_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "main.txt" });
    defer allocator.free(main_file_path);

    try cwd.writeFile(io, .{ .sub_path = main_file_path, .data = "main content" });

    const main_paths = try allocator.alloc([]const u8, 1);
    defer allocator.free(main_paths);
    main_paths[0] = try allocator.dupe(u8, "main.txt");
    defer allocator.free(main_paths[0]);

    try add(io, allocator, tmp_path, main_paths);
    const main_sha = try commit(io, allocator, tmp_path, "Master commit");
    allocator.free(main_sha);

    const custom_message = try allocator.dupe(u8, "Custom merge message");
    defer allocator.free(custom_message);

    const opts = MergeOptions{ .message = custom_message };
    const result = try merge(io, allocator, tmp_path, "feature", opts);
    defer {
        if (result.commit_sha) |s| allocator.free(s);
        if (result.message) |msg| allocator.free(msg);
    }

    try std.testing.expect(result.success);
    if (result.message) |msg| {
        try std.testing.expectEqualStrings("Custom merge message", msg);
    }
}

fn createBranch(io: std.Io, allocator: std.mem.Allocator, path: []const u8, branch_name: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const cwd = std.Io.Dir.cwd();
    const current_head = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
    defer allocator.free(current_head);

    const trimmed = std.mem.trim(u8, current_head, &std.ascii.whitespace);

    const prefix = "ref: refs/heads/";
    if (!std.mem.startsWith(u8, trimmed, prefix)) {
        return error.NotOnABranch;
    }

    const current_branch = trimmed[prefix.len..];
    const current_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", current_branch });
    defer allocator.free(current_branch_path);

    const current_commit = cwd.readFileAlloc(io, current_branch_path, allocator, .unlimited) catch {
        return error.CurrentBranchHasNoCommits;
    };
    defer allocator.free(current_commit);

    const new_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(new_branch_path);

    const dir_path = std.fs.path.dirname(new_branch_path) orelse return error.InvalidPath;
    try cwd.createDirPath(io, dir_path);

    try cwd.writeFile(io, .{ .sub_path = new_branch_path, .data = current_commit });
}

fn checkoutBranch(io: std.Io, allocator: std.mem.Allocator, path: []const u8, branch_name: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const head_content = try std.fmt.allocPrint(allocator, "ref: refs/heads/{s}\n", .{branch_name});
    defer allocator.free(head_content);

    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(io, .{ .sub_path = head_path, .data = head_content });
}

fn deleteBranchCommit(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const cwd = std.Io.Dir.cwd();
    const current_head = try cwd.readFileAlloc(io, head_path, allocator, .unlimited);
    defer allocator.free(current_head);

    const trimmed = std.mem.trim(u8, current_head, &std.ascii.whitespace);

    const prefix = "ref: refs/heads/";
    if (!std.mem.startsWith(u8, trimmed, prefix)) {
        return error.NotOnABranch;
    }

    const current_branch = trimmed[prefix.len..];
    const current_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", current_branch });
    defer allocator.free(current_branch_path);

    cwd.deleteFile(io, current_branch_path) catch {};
}
