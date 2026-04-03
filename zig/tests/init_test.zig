const std = @import("std");

const init = @import("gitologist").init;

fn createTempDir(allocator: std.mem.Allocator) ![]const u8 {
    const tmp_dir = std.testing.tmpDir(.{});
    const path = try allocator.dupe(u8, tmp_dir.dir.path);
    return path;
}

fn cleanupTempDir(path: []const u8) void {
    _ = path;
}

test "should create .git directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-dir" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    git_dir.close(io);
}

test "should not create .git if it already exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-exists" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    try cwd.createDirPath(io, git_dir_path);

    var git_dir = try cwd.openDir(io, git_dir_path, .{});
    try git_dir.writeFile(io, .{ .sub_path = "custom-file", .data = "test" });
    git_dir.close(io);

    try init(io, allocator, tmp_path);

    git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const custom_file = try git_dir.readFileAlloc(io, "custom-file", allocator, .unlimited);
    defer allocator.free(custom_file);

    try std.testing.expectEqualStrings("test", custom_file);
}

test "should create HEAD file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-head" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const head = try git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited);
    defer allocator.free(head);

    try std.testing.expectEqualStrings("ref: refs/heads/main\n", head);
}

test "should create config file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-config" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[core]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "repositoryformatversion = 0") != null);
}

test "should create objects directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-objects" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    _ = try git_dir.openDir(io, "objects", .{});
}

test "should create refs/heads directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-refs-heads" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    var refs_dir = try git_dir.openDir(io, "refs", .{});
    defer refs_dir.close(io);

    _ = try refs_dir.openDir(io, "heads", .{});
}

test "should create refs/tags directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-refs-tags" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    var refs_dir = try git_dir.openDir(io, "refs", .{});
    defer refs_dir.close(io);

    _ = try refs_dir.openDir(io, "tags", .{});
}

test "should create info directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test-info" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    _ = try git_dir.openDir(io, "info", .{});
}
