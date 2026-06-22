const std = @import("std");

const utils = @import("utils.zig");
const getCurrentBranch = @import("branch.zig").getCurrentBranch;
const packfile = @import("packfile.zig");
const remote = @import("remote.zig");
const objects = @import("objects.zig");
const gitologist = @import("root.zig");
const RemoteOptions = gitologist.RemoteOptions;

pub fn push(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote_name_param: ?[]const u8, branch: ?[]const u8, options: ?*const RemoteOptions) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const remote_name = if (remote_name_param) |r| r else "origin";

    var branch_name: []const u8 = undefined;
    var free_branch_name = false;

    if (branch) |b| {
        branch_name = b;
    } else {
        branch_name = try getCurrentBranch(io, allocator, git_dir_path);
        free_branch_name = true;
    }
    defer if (free_branch_name) allocator.free(branch_name);

    const local_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(local_branch_path);

    const local_branch_file = cwd.openFile(io, local_branch_path, .{}) catch {
        const err_msg = try std.fmt.allocPrint(allocator, "Local branch '{s}' does not exist", .{branch_name});
        defer allocator.free(err_msg);
        return error.LocalBranchDoesNotExist;
    };
    local_branch_file.close(io);

    const status_fn = @import("status.zig").status;
    const current_status = try status_fn(io, allocator, path);
    defer {
        allocator.free(current_status.branch);
        allocator.free(current_status.up_to_date);
        for (current_status.staged) |file| allocator.free(file);
        for (current_status.modified) |file| allocator.free(file);
        for (current_status.untracked) |file| allocator.free(file);
        for (current_status.deleted) |file| allocator.free(file);
        allocator.free(current_status.staged);
        allocator.free(current_status.modified);
        allocator.free(current_status.untracked);
        allocator.free(current_status.deleted);
    }

    if (current_status.modified.len > 0 or current_status.untracked.len > 0 or current_status.deleted.len > 0) {
        return error.UncommittedChanges;
    }

    const commit_sha_with_newline = try cwd.readFileAlloc(io, local_branch_path, allocator, .unlimited);
    defer allocator.free(commit_sha_with_newline);

    const commit_sha = std.mem.trim(u8, commit_sha_with_newline, &std.ascii.whitespace);

    const remote_url_opt = try remote.getRemoteUrl(io, allocator, git_dir_path, remote_name);

    if (remote_url_opt) |remote_url| {
        defer allocator.free(remote_url);
        if (std.mem.startsWith(u8, remote_url, "http://") or std.mem.startsWith(u8, remote_url, "https://")) {
            try pushToRemote(io, allocator, remote_url, commit_sha, branch_name, git_dir_path, options);
        }
    }

    const remote_branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name, branch_name });
    defer allocator.free(remote_branch_path);

    const remote_branch_dir = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "remotes", remote_name });
    defer allocator.free(remote_branch_dir);

    try cwd.createDirPath(io, remote_branch_dir);

    const commit_with_newline = try std.fmt.allocPrint(allocator, "{s}\n", .{commit_sha});
    defer allocator.free(commit_with_newline);

    try cwd.writeFile(io, .{ .sub_path = remote_branch_path, .data = commit_with_newline });
}

fn pushToRemote(
    io: std.Io,
    allocator: std.mem.Allocator,
    remote_url: []const u8,
    commit_sha: []const u8,
    branch_name: []const u8,
    git_dir_path: []const u8,
    options: ?*const RemoteOptions,
) !void {
    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();

    var old_sha: []const u8 = undefined;
    var free_old_sha = false;

    var refs = discoverRefsForPush(io, allocator, remote_url, options) catch {
        // If we can't discover refs, assume it's a new branch
        const zeros = try allocator.alloc(u8, 40);
        @memset(zeros, '0');
        var visited = std.StringHashMap(void).init(allocator);
        defer visited.deinit();
        var pack_objects = try objects.enumerateObjects(io, allocator, git_dir_path, commit_sha, &visited, &cache);
        defer {
            for (pack_objects.items) |obj| {
                allocator.free(obj.obj_type);
                allocator.free(obj.sha);
                allocator.free(obj.content);
            }
            pack_objects.deinit(allocator);
        }
        const pack_data = try packfile.createPackfile(allocator, pack_objects);
        defer allocator.free(pack_data);
        return try sendPush(io, allocator, remote_url, zeros, commit_sha, branch_name, pack_data, options);
    };
    defer {
        for (refs.items) |ref| {
            allocator.free(ref.sha);
            allocator.free(ref.ref);
        }
        refs.deinit(allocator);
    }

    const remote_ref = blk: {
        for (refs.items) |ref| {
            const expected_ref = try std.fmt.allocPrint(allocator, "refs/heads/{s}", .{branch_name});
            defer allocator.free(expected_ref);

            if (std.mem.eql(u8, ref.ref, expected_ref)) {
                break :blk ref;
            }
        }
        break :blk null;
    };

    if (remote_ref) |r| {
        old_sha = r.sha;
    } else {
        const zeros = try allocator.alloc(u8, 40);
        @memset(zeros, '0');
        old_sha = zeros;
        free_old_sha = true;
    }
    defer if (free_old_sha) allocator.free(old_sha);

    var visited = std.StringHashMap(void).init(allocator);
    defer visited.deinit();

    var pack_objects = try objects.enumerateObjects(io, allocator, git_dir_path, commit_sha, &visited, &cache);
    defer {
        for (pack_objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        pack_objects.deinit(allocator);
    }

    const pack_data = try packfile.createPackfile(allocator, pack_objects);
    defer allocator.free(pack_data);

    try sendPush(io, allocator, remote_url, old_sha, commit_sha, branch_name, pack_data, options);
}

fn buildPushRequest(allocator: std.mem.Allocator, old_sha: []const u8, new_sha: []const u8, branch_name: []const u8, pack_data: []const u8) ![]const u8 {
    var lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    const update_cmd = try std.fmt.allocPrint(allocator, "{s} {s} refs/heads/{s}\x00report-status agent=gitologist/1.0", .{ old_sha, new_sha, branch_name });
    defer allocator.free(update_cmd);

    const update_pkt = try packfile.encodePktLine(allocator, update_cmd);
    try lines.append(allocator, update_pkt);

    const flush_pkt = try packfile.encodePktLine(allocator, null);
    try lines.append(allocator, flush_pkt);

    try lines.append(allocator, try allocator.dupe(u8, pack_data));

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    for (lines.items) |line| {
        try result.appendSlice(allocator, line);
    }

    return result.toOwnedSlice(allocator);
}

fn sendPush(
    io: std.Io,
    allocator: std.mem.Allocator,
    remote_url: []const u8,
    old_sha: []const u8,
    new_sha: []const u8,
    branch_name: []const u8,
    pack_data: []const u8,
    options: ?*const RemoteOptions,
) !void {
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

    const full_url = try std.fmt.allocPrint(allocator, "http://{s}/git-receive-pack", .{host});
    defer allocator.free(full_url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(full_url);

    var headers_buf: [4]std.http.Header = undefined;
    var headers_len: usize = 0;
    headers_buf[headers_len] = .{ .name = "Content-Type", .value = "application/x-git-receive-pack-request" };
    headers_len += 1;
    headers_buf[headers_len] = .{ .name = "Accept", .value = "application/x-git-receive-pack-result" };
    headers_len += 1;
    headers_buf[headers_len] = .{ .name = "Git-Protocol", .value = "version=2" };
    headers_len += 1;

    var req_options: std.http.Client.RequestOptions = .{
        .extra_headers = headers_buf[0..headers_len],
    };

    if (options) |opts| {
        if (opts.credentials) |creds| {
            const auth_string = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ creds.username, creds.token });
            defer allocator.free(auth_string);

            const encoder = std.base64.standard.Encoder;
            const auth_bytes_len = encoder.calcSize(auth_string.len);
            const auth_bytes = try allocator.alloc(u8, auth_bytes_len);
            defer allocator.free(auth_bytes);
            _ = encoder.encode(auth_bytes, auth_string);

            const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{auth_bytes});
            defer allocator.free(auth_header);

            headers_buf[headers_len] = .{ .name = "Authorization", .value = auth_header };
            headers_len += 1;
            req_options.extra_headers = headers_buf[0..headers_len];
        }
    }

    var request = try client.request(.POST, uri, req_options);
    defer request.deinit();

    const request_body = try buildPushRequest(allocator, old_sha, new_sha, branch_name, pack_data);
    defer allocator.free(request_body);

    try request.sendBodyComplete(@constCast(request_body));

    var redirect_buffer: [4096]u8 = undefined;
    var response = try request.receiveHead(&redirect_buffer);

    if (response.head.status != .ok) {
        var body = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
        defer body.deinit(allocator);
        var transfer_buffer: [8192]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        try reader.appendRemainingUnlimited(allocator, &body);
        return error.PushFailed;
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

    for (lines.items) |line| {
        if (std.mem.startsWith(u8, line, "ng ")) {
            const reason = line["ng ".len..];
            _ = reason;
            return error.PushRejected;
        }
    }
}

const DiscoveredRef = struct {
    sha: []const u8,
    ref: []const u8,
};

fn discoverRefsForPush(io: std.Io, allocator: std.mem.Allocator, remote_url: []const u8, options: ?*const RemoteOptions) !std.ArrayList(DiscoveredRef) {
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

    const full_url = try std.fmt.allocPrint(allocator, "http://{s}/info/refs?service=git-receive-pack", .{host});
    defer allocator.free(full_url);

    var client: std.http.Client = .{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(full_url);

    var headers_buf: [4]std.http.Header = undefined;
    var headers_len: usize = 0;
    headers_buf[headers_len] = .{ .name = "Accept", .value = "application/x-git-receive-pack-advertisement" };
    headers_len += 1;
    headers_buf[headers_len] = .{ .name = "Git-Protocol", .value = "version=2" };
    headers_len += 1;

    var req_options: std.http.Client.RequestOptions = .{
        .extra_headers = headers_buf[0..headers_len],
    };

    if (options) |opts| {
        if (opts.credentials) |creds| {
            const auth_string = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ creds.username, creds.token });
            defer allocator.free(auth_string);

            const encoder = std.base64.standard.Encoder;
            const auth_bytes_len = encoder.calcSize(auth_string.len);
            const auth_bytes = try allocator.alloc(u8, auth_bytes_len);
            defer allocator.free(auth_bytes);
            _ = encoder.encode(auth_bytes, auth_string);

            const auth_header = try std.fmt.allocPrint(allocator, "Basic {s}", .{auth_bytes});
            defer allocator.free(auth_header);

            headers_buf[headers_len] = .{ .name = "Authorization", .value = auth_header };
            headers_len += 1;
            req_options.extra_headers = headers_buf[0..headers_len];
        }
    }

    var request = try client.request(.GET, uri, req_options);
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

    var started = false;

    var refs = std.ArrayList(DiscoveredRef).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (refs.items) |ref| {
            allocator.free(ref.sha);
            allocator.free(ref.ref);
        }
        refs.deinit(allocator);
    }

    for (lines.items) |line| {
        if (std.mem.indexOf(u8, line, "# service=git-receive-pack")) |_| {
            started = true;
            continue;
        }

        if (!started) continue;
        if (line.len == 0) continue;

        var parts = std.mem.splitScalar(u8, line, ' ');
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
        const ref_name = ref_str[0..null_idx];

        try refs.append(allocator, .{
            .sha = try allocator.dupe(u8, sha_str),
            .ref = try allocator.dupe(u8, ref_name),
        });
    }

    return refs;
}

pub fn setUpstreamBranch(io: std.Io, allocator: std.mem.Allocator, path: []const u8, remote_name: []const u8, branch_name: []const u8) !void {
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git", "config" });
    defer allocator.free(config_path);

    const cwd = std.Io.Dir.cwd();

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

    var lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    var line_iter = std.mem.splitScalar(u8, config_content, '\n');
    while (line_iter.next()) |line| {
        try lines.append(allocator, try allocator.dupe(u8, line));
    }

    var in_branch_section = false;
    var found_branch_section = false;
    var insert_index: ?usize = null;

    const branch_section_pattern = try std.fmt.allocPrint(allocator, "[branch \"{s}\"]", .{branch_name});
    defer allocator.free(branch_section_pattern);

    for (lines.items, 0..) |line, i| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);

        if (std.mem.eql(u8, trimmed, branch_section_pattern)) {
            in_branch_section = true;
            found_branch_section = true;
            continue;
        }

        if (in_branch_section) {
            if (std.mem.startsWith(u8, trimmed, "remote =") or std.mem.startsWith(u8, trimmed, "merge =")) {
                continue;
            }
            if (insert_index == null) {
                insert_index = i;
            }
        } else {
            if (std.mem.startsWith(u8, trimmed, "[") and insert_index == null) {
                insert_index = i;
            }
        }
    }

    const remote_line = try std.fmt.allocPrint(allocator, "\tremote = {s}", .{remote_name});
    defer allocator.free(remote_line);

    const merge_line = try std.fmt.allocPrint(allocator, "\tmerge = refs/heads/{s}", .{branch_name});
    defer allocator.free(merge_line);

    if (!found_branch_section) {
        try lines.append(allocator, try allocator.dupe(u8, ""));
        try lines.append(allocator, try allocator.dupe(u8, branch_section_pattern));
        try lines.append(allocator, try allocator.dupe(u8, remote_line));
        try lines.append(allocator, try allocator.dupe(u8, merge_line));
    } else {
        const idx = insert_index orelse lines.items.len;
        try lines.insert(allocator, idx, try allocator.dupe(u8, merge_line));
        try lines.insert(allocator, idx, try allocator.dupe(u8, remote_line));
    }

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    defer result.deinit(allocator);

    for (lines.items, 0..) |line, i| {
        try result.appendSlice(allocator, line);
        if (i < lines.items.len - 1) {
            try result.append(allocator, '\n');
        }
    }

    try cwd.writeFile(io, .{ .sub_path = config_path, .data = result.items });
}
