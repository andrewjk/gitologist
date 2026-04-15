const std = @import("std");

const packfile = @import("packfile.zig");
const utils = @import("utils.zig");
const remote = @import("remote.zig");

pub const FetchResult = struct {
    remote: []const u8,
    refs: std.ArrayList(RefInfo),
};

pub const RefInfo = struct {
    name: []const u8,
    sha: []const u8,
};

const DiscoveredRef = struct {
    sha: []const u8,
    ref: []const u8,
};

pub fn fetchFromRemote(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote_name_param: ?[]const u8) !FetchResult {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const remote_name = if (remote_name_param) |r| r else "origin";
    const remote_url_opt = try remote.getRemoteUrl(io, allocator, git_dir_path, remote_name);

    if (remote_url_opt == null) {
        return FetchResult{
            .remote = try allocator.dupe(u8, remote_name),
            .refs = std.ArrayList(RefInfo).initCapacity(allocator, 0) catch unreachable,
        };
    }

    const remote_url = remote_url_opt.?;
    defer allocator.free(remote_url);

    var refs = try discoverRefs(io, allocator, remote_url);
    defer {
        for (refs.items) |ref| {
            allocator.free(ref.sha);
            allocator.free(ref.ref);
        }
        refs.deinit(allocator);
    }

    var result = FetchResult{
        .remote = try allocator.dupe(u8, remote_name),
        .refs = std.ArrayList(RefInfo).initCapacity(allocator, 0) catch unreachable,
    };
    errdefer {
        allocator.free(result.remote);
        for (result.refs.items) |ref_info| {
            allocator.free(ref_info.name);
            allocator.free(ref_info.sha);
        }
        result.refs.deinit(allocator);
    }

    var wants = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (wants.items) |want| allocator.free(want);
        wants.deinit(allocator);
    }

    var haves = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (haves.items) |have| allocator.free(have);
        haves.deinit(allocator);
    }

    for (refs.items) |ref| {
        if (std.mem.startsWith(u8, ref.ref, "refs/heads/")) {
            const branch_name = ref.ref["refs/heads/".len..];
            const local_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
            defer allocator.free(local_ref_path);

            if (cwd.access(io, local_ref_path, .{})) |_| {
                const local_sha_with_newline = try cwd.readFileAlloc(io, local_ref_path, allocator, .unlimited);
                defer allocator.free(local_sha_with_newline);

                const local_sha = std.mem.trim(u8, local_sha_with_newline, &std.ascii.whitespace);
                try haves.append(allocator, try allocator.dupe(u8, local_sha));
            } else |err| {
                if (err != error.FileNotFound) {
                    return err;
                }
            }

            try wants.append(allocator, try allocator.dupe(u8, ref.sha));
            try result.refs.append(allocator, .{
                .name = try allocator.dupe(u8, branch_name),
                .sha = try allocator.dupe(u8, ref.sha),
            });
        }
    }

    if (wants.items.len > 0) {
        var objects = try fetchPackfile(io, allocator, remote_url, wants, haves);
        defer {
            for (objects.items) |obj| {
                allocator.free(obj.obj_type);
                allocator.free(obj.sha);
                allocator.free(obj.content);
            }
            objects.deinit(allocator);
        }

        try storeObjects(io, allocator, git_dir_path, objects);
    }

    for (result.refs.items) |ref_info| {
        const remote_ref_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name, ref_info.name });
        defer allocator.free(remote_ref_path);

        const remote_ref_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name });
        defer allocator.free(remote_ref_dir);

        try cwd.createDirPath(io, remote_ref_dir);

        const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{ref_info.sha});
        defer allocator.free(commit_with_newline);

        try cwd.writeFile(io, .{ .sub_path = remote_ref_path, .data = commit_with_newline });
    }

    return result;
}

fn storeObjects(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, objects: std.ArrayList(packfile.PackObject)) !void {
    for (objects.items) |obj| {
        _ = try utils.hashObjectBinary(io, allocator, git_dir_path, obj.content, obj.obj_type);
    }
}

fn discoverRefs(io: std.Io, allocator: std.mem.Allocator, remote_url: []const u8) !std.ArrayList(DiscoveredRef) {
    var url_parts = std.mem.splitScalar(u8, remote_url, '/');
    var host: []const u8 = undefined;
    var path: []const u8 = undefined;

    var i: usize = 0;
    while (url_parts.next()) |part| {
        if (i == 0) {
            if (std.mem.startsWith(u8, part, "http://")) {
                host = part["http://".len..];
            } else if (std.mem.startsWith(u8, part, "https://")) {
                host = part["https://".len..];
            } else {
                host = part;
            }
        } else {
            path = part;
        }
        i += 1;
    }

    const full_url = try std.fmt.allocPrint(allocator, "http://{s}/info/refs?service=git-upload-pack", .{host});
    defer allocator.free(full_url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(full_url);
    var request = try client.request(.GET, uri, .{});
    defer request.deinit();

    try request.sendBodiless();

    var redirect_buffer: [4096]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    if (response.head.status != .ok) {
        return error.FailedToDiscoverRefs;
    }

    var body = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer body.deinit(allocator);

    var transfer_buffer: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buffer);

    try reader.appendRemainingUnlimited(allocator, &body);

    var lines = try packfile.decodePktLines(allocator, body.items);
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    var refs = std.ArrayList(DiscoveredRef).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (refs.items) |ref| {
            allocator.free(ref.sha);
            allocator.free(ref.ref);
        }
        refs.deinit(allocator);
    }

    var started = false;

    for (lines.items) |line| {
        if (std.mem.indexOf(u8, line, "# service=git-upload-pack")) |_| {
            started = true;
            continue;
        }

        if (!started) continue;
        if (line.len == 0) continue;

        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;

        var parts = std.mem.splitScalar(u8, trimmed, ' ');
        const sha_str = parts.next() orelse continue;
        const ref_str = parts.next() orelse continue;

        if (sha_str.len != 40) continue;

        const is_valid_sha = blk: {
            for (sha_str) |c| {
                if (!(std.ascii.isDigit(c) or (std.ascii.isHex(c)))) break :blk false;
            }
            break :blk true;
        };

        if (!is_valid_sha) continue;

        const null_idx = std.mem.indexOfScalar(u8, ref_str, 0) orelse ref_str.len;
        const ref_name = std.mem.trim(u8, ref_str[0..null_idx], &std.ascii.whitespace);

        try refs.append(allocator, .{
            .sha = try allocator.dupe(u8, sha_str),
            .ref = try allocator.dupe(u8, ref_name),
        });
    }

    return refs;
}

fn buildLsRefsRequest(allocator: std.mem.Allocator) ![]const u8 {
    var lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    const command_pkt = try packfile.encodePktLine(allocator, "command=ls-refs\n");
    try lines.append(allocator, command_pkt);

    const delimiter_pkt = try allocator.dupe(u8, "0001");
    try lines.append(allocator, delimiter_pkt);

    const symrefs_pkt = try packfile.encodePktLine(allocator, "symrefs\n");
    try lines.append(allocator, symrefs_pkt);

    const peel_pkt = try packfile.encodePktLine(allocator, "peel\n");
    try lines.append(allocator, peel_pkt);

    const ref_prefix_pkt = try packfile.encodePktLine(allocator, "ref-prefix refs/heads/\n");
    try lines.append(allocator, ref_prefix_pkt);

    const flush_pkt = try packfile.encodePktLine(allocator, null);
    try lines.append(allocator, flush_pkt);

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    for (lines.items) |line| {
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}

fn extractPackfileFromSideband(allocator: std.mem.Allocator, data: []const u8) ![]const u8 {
    var packfile_data = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    errdefer packfile_data.deinit(allocator);

    var offset: usize = 0;

    while (offset < data.len) {
        if (offset + 4 > data.len) {
            break;
        }

        const hex_length = data[offset .. offset + 4];
        if (std.mem.eql(u8, hex_length, "0000")) {
            offset += 4;
            continue;
        }

        if (std.mem.eql(u8, hex_length, "0001")) {
            offset += 4;
            continue;
        }

        const length = std.fmt.parseUnsigned(usize, hex_length, 16) catch break;
        if (length == 0 or offset + length > data.len) {
            break;
        }

        const payload = data[offset + 4 .. offset + length];

        if (payload.len > 0) {
            const channel = payload[0];
            if (channel == 1) {
                try packfile_data.appendSlice(allocator, payload[1..]);
            } else if (channel == 3) {
                const error_msg = payload[1..];
                std.debug.print("Git error: {s}\n", .{error_msg});
            }
        }

        offset += length;
    }

    return packfile_data.toOwnedSlice(allocator);
}

fn fetchPackfile(io: std.Io, allocator: std.mem.Allocator, remote_url: []const u8, wants: std.ArrayList([]const u8), haves: std.ArrayList([]const u8)) !std.ArrayList(packfile.PackObject) {
    var url_parts = std.mem.splitScalar(u8, remote_url, '/');
    var host: []const u8 = undefined;

    var i: usize = 0;
    while (url_parts.next()) |part| {
        if (i == 0) {
            if (std.mem.startsWith(u8, part, "http://")) {
                host = part["http://".len..];
            } else if (std.mem.startsWith(u8, part, "https://")) {
                host = part["https://".len..];
            } else {
                host = part;
            }
        }
        i += 1;
    }

    const full_url = try std.fmt.allocPrint(allocator, "http://{s}/git-upload-pack", .{host});
    defer allocator.free(full_url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(full_url);
    var request = try client.request(.POST, uri, .{});
    defer request.deinit();

    const request_body = try buildFetchRequest(allocator, wants, haves);
    defer allocator.free(request_body);

    try request.sendBodyComplete(@constCast(request_body));

    var redirect_buffer: [4096]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    if (response.head.status != .ok) {
        return error.FailedToFetchPackfile;
    }

    var body = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer body.deinit(allocator);

    var transfer_buffer: [8192]u8 = undefined;
    const reader = response.reader(&transfer_buffer);

    try reader.appendRemainingUnlimited(allocator, &body);

    const packfile_data = try extractPackfileFromSideband(allocator, body.items);
    defer allocator.free(packfile_data);

    if (packfile_data.len == 0) {
        return std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    }

    return try packfile.parsePackfile(allocator, packfile_data);
}

fn buildFetchRequest(allocator: std.mem.Allocator, wants: std.ArrayList([]const u8), haves: std.ArrayList([]const u8)) ![]const u8 {
    var lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    const command_pkt = try packfile.encodePktLine(allocator, "command=fetch\n");
    try lines.append(allocator, command_pkt);

    const delimiter_pkt = try allocator.dupe(u8, "0001");
    try lines.append(allocator, delimiter_pkt);

    for (wants.items) |w| {
        const pkt_line = try packfile.encodePktLine(allocator, try std.fmt.allocPrint(allocator, "want {s}\n", .{w}));
        try lines.append(allocator, pkt_line);
    }

    for (haves.items) |h| {
        const pkt_line = try packfile.encodePktLine(allocator, try std.fmt.allocPrint(allocator, "have {s}\n", .{h}));
        try lines.append(allocator, pkt_line);
    }

    const done_pkt = try packfile.encodePktLine(allocator, "done\n");
    try lines.append(allocator, done_pkt);

    const flush_pkt = try packfile.encodePktLine(allocator, null);
    try lines.append(allocator, flush_pkt);

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    for (lines.items) |line| {
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}
