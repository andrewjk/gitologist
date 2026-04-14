const std = @import("std");

fn trimRight(comptime T: type, slice: []const T) []const T {
    var end = slice.len;
    while (end > 0 and std.ascii.isWhitespace(slice[end - 1])) {
        end -= 1;
    }
    return slice[0..end];
}

pub fn remoteAdd(io: std.Io, allocator: std.mem.Allocator, path: []const u8, name: []const u8, url: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "config" });
    defer allocator.free(config_path);

    var config_content: []u8 = "";
    var free_config_content = false;

    if (cwd.access(io, config_path, .{})) |_| {
        config_content = try cwd.readFileAlloc(io, config_path, allocator, .unlimited);
        free_config_content = true;
    } else |err| {
        if (err != error.FileNotFound) {
            return err;
        }
    }
    defer if (free_config_content) allocator.free(config_content);

    const remote_pattern = try std.fmt.allocPrint(allocator, "[remote \"{s}\"]", .{name});
    defer allocator.free(remote_pattern);

    if (std.mem.indexOf(u8, config_content, remote_pattern)) |_| {
        return error.RemoteAlreadyExists;
    }

    const fetch_refspec = try std.fmt.allocPrint(allocator, "+refs/heads/*:refs/remotes/{s}/*", .{name});
    defer allocator.free(fetch_refspec);

    const remote_config = try std.fmt.allocPrint(allocator, "[remote \"{s}\"]\n\turl = {s}\n\tfetch = {s}\n", .{ name, url, fetch_refspec });
    defer allocator.free(remote_config);

    var result = std.ArrayList(u8).initCapacity(allocator, config_content.len + remote_config.len + 10) catch unreachable;
    defer result.deinit(allocator);

    const trimmed_config = trimRight(u8, config_content);
    try result.appendSlice(allocator, trimmed_config);
    try result.appendSlice(allocator, "\n\n");
    try result.appendSlice(allocator, remote_config);
    try result.appendSlice(allocator, "\n");

    try cwd.writeFile(io, .{ .sub_path = config_path, .data = result.items });
}

pub fn hasRemote(io: std.Io, allocator: std.mem.Allocator, path: []const u8, name: []const u8) bool {
    const git_dir_path = std.fs.path.join(allocator, &[_][]const u8{ path, ".git" }) catch return false;
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    if (cwd.access(io, git_dir_path, .{})) |_| {} else |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return false;
    }

    const config_path = std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "config" }) catch return false;
    defer allocator.free(config_path);

    if (cwd.access(io, config_path, .{})) |_| {} else |err| {
        if (err == error.FileNotFound) {
            return false;
        }
        return false;
    }

    const config_content = cwd.readFileAlloc(io, config_path, allocator, .unlimited) catch return false;
    defer allocator.free(config_content);

    const remote_pattern = std.fmt.allocPrint(allocator, "[remote \"{s}\"]", .{name}) catch return false;
    defer allocator.free(remote_pattern);

    if (std.mem.indexOf(u8, config_content, remote_pattern)) |_| {
        return true;
    }

    return false;
}

pub fn getRemoteUrl(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, remote_name: []const u8) !?[]const u8 {
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "config" });
    defer allocator.free(config_path);

    const cwd = std.Io.Dir.cwd();
    const config_content = cwd.readFileAlloc(io, config_path, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer allocator.free(config_content);

    var lines = std.mem.splitScalar(u8, config_content, '\n');

    var in_remote_section = false;
    var current_remote: []const u8 = "";

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        var remote_pattern_buf: [256]u8 = undefined;
        const remote_pattern = try std.fmt.bufPrint(&remote_pattern_buf, "[remote \"{s}\"]", .{remote_name});

        if (std.mem.indexOf(u8, trimmed, remote_pattern)) |_| {
            in_remote_section = true;
            current_remote = remote_name;
            continue;
        }

        if (in_remote_section and std.mem.eql(u8, current_remote, remote_name)) {
            if (std.mem.indexOf(u8, trimmed, "url")) |_| {
                var parts = std.mem.splitScalar(u8, trimmed, '=');
                _ = parts.next(); // Skip "url"
                const url = parts.next() orelse continue;
                const trimmed_url = std.mem.trim(u8, url, &std.ascii.whitespace);
                return try allocator.dupe(u8, trimmed_url);
            }
        }

        if (std.mem.startsWith(u8, trimmed, "[") and !std.mem.startsWith(u8, trimmed, "[remote")) {
            in_remote_section = false;
        }
    }

    return null;
}
