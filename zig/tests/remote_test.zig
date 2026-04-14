const std = @import("std");

const init = @import("gitologist").init;
const remoteAdd = @import("gitologist").remoteAdd;
const hasRemote = @import("gitologist").hasRemote;

fn trimRight(comptime T: type, slice: []const T) []const T {
    var end = slice.len;
    while (end > 0 and std.ascii.isWhitespace(slice[end - 1])) {
        end -= 1;
    }
    return slice[0..end];
}

test "should add a remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-1" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"origin\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/user/repo.git") != null);
}

test "should add fetch refspec" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-2" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "fetch = +refs/heads/*:refs/remotes/origin/*") != null);
}

test "should add remote with custom name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-3" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "upstream", "https://github.com/original/repo.git");

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"upstream\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/original/repo.git") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "fetch = +refs/heads/*:refs/remotes/upstream/*") != null);
}

test "should throw error if not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-not-repo" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const result = remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");
    try std.testing.expectError(error.NotAGitRepository, result);
}

test "should throw error if remote already exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-exists" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    const result = remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/other/repo.git");
    try std.testing.expectError(error.RemoteAlreadyExists, result);
}

test "should preserve existing config" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-preserve" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");
    try remoteAdd(io, allocator, tmp_path, "upstream", "https://github.com/original/repo.git");

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"origin\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"upstream\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/user/repo.git") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/original/repo.git") != null);
}

test "should append to existing config file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-append" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);
    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const original_config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    const original_config_trimmed = trimRight(u8, original_config);
    defer allocator.free(original_config);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    const new_config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(new_config);

    try std.testing.expect(std.mem.indexOf(u8, new_config, original_config_trimmed) != null);
    try std.testing.expect(std.mem.indexOf(u8, new_config, "[remote \"origin\"]") != null);
}

test "should return false when not a git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-not-repo-2" });
    defer allocator.free(tmp_path);

    try std.testing.expect(!hasRemote(io, allocator, tmp_path, "origin"));
}

test "should return false when remote does not exist" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-no-remote" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try std.testing.expect(!hasRemote(io, allocator, tmp_path, "nonexistent"));
}

test "should return true when origin remote exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-origin" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    try std.testing.expect(hasRemote(io, allocator, tmp_path, "origin"));
}

test "should return true when custom named remote exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-custom" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "upstream", "https://github.com/original/repo.git");

    try std.testing.expect(hasRemote(io, allocator, tmp_path, "upstream"));
}

test "should return false for different remote name" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-remote-test-different" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init(io, allocator, tmp_path);

    try remoteAdd(io, allocator, tmp_path, "origin", "https://github.com/user/repo.git");

    try std.testing.expect(!hasRemote(io, allocator, tmp_path, "upstream"));
}
