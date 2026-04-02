const std = @import("std");

const HEAD_FILE = "ref: refs/heads/master\n";
const CONFIG_FILE = "[core]\n\trepositoryformatversion = 0\n\tfilemode = true\n\tbare = false\n\tlogallrefupdates = true\n";

pub fn init(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const git_dir = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir);

    const cwd = std.Io.Dir.cwd();

    if (cwd.openDir(io, git_dir, .{})) |_| {
        return;
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }

    {
        const objects_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "objects" });
        defer allocator.free(objects_path);
        try cwd.createDirPath(io, objects_path);
    }

    {
        const refs_heads_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "refs", "heads" });
        defer allocator.free(refs_heads_path);
        try cwd.createDirPath(io, refs_heads_path);
    }

    {
        const refs_tags_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "refs", "tags" });
        defer allocator.free(refs_tags_path);
        try cwd.createDirPath(io, refs_tags_path);
    }

    {
        const info_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "info" });
        defer allocator.free(info_path);
        try cwd.createDirPath(io, info_path);
    }

    {
        const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "HEAD" });
        defer allocator.free(head_path);
        try cwd.writeFile(io, .{ .sub_path = head_path, .data = HEAD_FILE });
    }

    {
        const config_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "config" });
        defer allocator.free(config_path);
        try cwd.writeFile(io, .{ .sub_path = config_path, .data = CONFIG_FILE });
    }

    {
        const description_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir, "description" });
        defer allocator.free(description_path);
        try cwd.writeFile(io, .{
            .sub_path = description_path,
            .data = "Unnamed repository; edit this file 'description' to name the repository.\n",
        });
    }
}
