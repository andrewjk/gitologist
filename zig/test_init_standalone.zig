const std = @import("std");

const init_impl = @import("src/init.zig");

const testing = std.testing;

test "init creates git repository" {
    const io = testing.io;
    const allocator = testing.allocator;

    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-test" });
    defer allocator.free(tmp_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, tmp_path);
    defer cwd.deleteTree(io, tmp_path) catch {};

    try init_impl.init(io, allocator, tmp_path);

    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const head = try git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited);
    defer allocator.free(head);

    try testing.expectEqualStrings("ref: refs/heads/master\n", head);
}
