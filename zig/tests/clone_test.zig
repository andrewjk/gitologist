const std = @import("std");

const clone = @import("gitologist").clone;

test "should clone a repository to default directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-1" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ result_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        try std.testing.expect(false);
        return;
    };
    git_dir.close(io);
}

test "should clone to specified directory" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-2" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my-custom-dir" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);

    _ = cwd.openDir(io, target_path, .{}) catch {
        try std.testing.expect(false);
        return;
    };
}

test "should extract repo name from URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-3" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/my-repo.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);
}

test "should initialize git repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-4" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo.git", target_path);
    defer allocator.free(result_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ result_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const head = try git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited);
    defer allocator.free(head);

    try std.testing.expect(std.mem.indexOf(u8, head, "ref: refs/heads/master") != null);
}

test "should add remote" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-5" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo.git", target_path);
    defer allocator.free(result_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ result_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"origin\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/user/repo.git") != null);
}

test "should handle URLs with .git extension" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-6" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ result_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/user/repo.git") != null);
}

test "should handle URLs without .git extension" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-7" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/repo", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ result_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "url = https://github.com/user/repo") != null);
}

test "should extract repo name from complex URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-8" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/org/team/project.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);
}

test "should handle subdirectory in URL" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-9" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test-repo" });
    defer allocator.free(target_path);

    const result_path = try clone(io, allocator, "https://github.com/user/nested/project.git", target_path);
    defer allocator.free(result_path);

    try std.testing.expectEqualStrings(target_path, result_path);
}

test "should throw error if directory already exists" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-clone-test-10" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    const existing_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "repo" });
    defer allocator.free(existing_path);

    try cwd.createDirPath(io, existing_path);

    const result = clone(io, allocator, "https://github.com/user/repo.git", existing_path);
    try std.testing.expectError(error.DestinationPathAlreadyExists, result);
}
