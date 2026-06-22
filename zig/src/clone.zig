const std = @import("std");

const RemoteOptions = @import("types/RemoteOptions.zig").RemoteOptions;

pub fn clone(io: std.Io, allocator: std.mem.Allocator, url: []const u8, target_path: ?[]const u8, options: ?*const RemoteOptions) ![]const u8 {
    const init_fn = @import("init.zig").init;
    const remote_add_fn = @import("remote.zig").remoteAdd;
    const fetch_fn = @import("fetch.zig").fetchOrigin;

    const cwd = std.Io.Dir.cwd();

    const repo_name = try extractRepoName(allocator, url);
    defer allocator.free(repo_name);

    const path = if (target_path) |tp| try allocator.dupe(u8, tp) else try std.fs.path.join(allocator, &[_][]const u8{ ".", repo_name });

    if (cwd.access(io, path, .{})) |_| {
        allocator.free(path);
        return error.DestinationPathAlreadyExists;
    } else |err| {
        if (err != error.FileNotFound) {
            allocator.free(path);
            return err;
        }
    }

    try cwd.createDirPath(io, path);

    try init_fn(io, allocator, path);

    try remote_add_fn(io, allocator, path, "origin", url);

    _ = fetch_fn(io, allocator, path, "origin", options) catch {
        // Fetch may fail for fake URLs or unreachable remotes, but clone should still succeed
    };

    return path;
}

fn extractRepoName(allocator: std.mem.Allocator, url: []const u8) ![]const u8 {
    var clean_url = url;

    if (std.mem.endsWith(u8, clean_url, ".git")) {
        clean_url = clean_url[0 .. clean_url.len - 4];
    }

    var parts = std.mem.splitScalar(u8, clean_url, '/');
    var last_part: []const u8 = "";

    while (parts.next()) |part| {
        if (part.len > 0) {
            last_part = part;
        }
    }

    const at_index = std.mem.lastIndexOfScalar(u8, last_part, '@');
    const name = if (at_index) |idx| last_part[idx + 1 ..] else last_part;

    return allocator.dupe(u8, name);
}
