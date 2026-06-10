const std = @import("std");

const LogEntry = @import("types/LogEntry.zig").LogEntry;
const LogOptions = @import("types/LogOptions.zig").LogOptions;

const utils = @import("utils.zig");

pub fn log(io: std.Io, allocator: std.mem.Allocator, path: []const u8, options: ?LogOptions) ![]LogEntry {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();
    const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };
    git_dir.close(io);

    const opts = options orelse LogOptions{};

    var branch_name: []const u8 = undefined;
    var free_branch_name = false;

    if (opts.branch) |b| {
        branch_name = b;
    } else {
        branch_name = try utils.getCurrentBranch(io, allocator, git_dir_path);
        free_branch_name = true;
    }
    defer if (free_branch_name) allocator.free(branch_name);

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(branch_path);

    const commit_sha_with_newline = cwd.readFileAlloc(io, branch_path, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            if (opts.branch) |_| {
                return error.BranchNotFound;
            }
            return try allocator.alloc(LogEntry, 0);
        }
        return err;
    };
    defer allocator.free(commit_sha_with_newline);

    const commit_sha = std.mem.trim(u8, commit_sha_with_newline, &std.ascii.whitespace);

    var entries = std.ArrayList(LogEntry).initCapacity(allocator, 10) catch unreachable;
    var current_sha: ?[]const u8 = null;
    errdefer {
        if (current_sha) |s| allocator.free(s);
        for (entries.items) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        entries.deinit(allocator);
    }

    const limit = opts.limit orelse std.math.maxInt(usize);

    if (opts.file) |file_path| {
        var cache = std.AutoHashMap([40]u8, ?[]const u8).init(allocator);
        defer {
            var cache_iter = cache.iterator();
            while (cache_iter.next()) |cache_entry| {
                if (cache_entry.value_ptr.*) |sha| {
                    allocator.free(sha);
                }
            }
            cache.deinit();
        }

        while (true) {
            const sha_to_parse = if (current_sha) |s| s else commit_sha;
            const entry = try parseCommitEntry(io, allocator, git_dir_path, sha_to_parse);

            if (current_sha) |s| {
                allocator.free(s);
            }

        const current_blob_sha = try getFileBlobSha(io, allocator, git_dir_path, entry.tree, file_path, &cache);

        var should_include = false;

        if (entry.parent) |p| {
            const parent_entry = try parseCommitEntry(io, allocator, git_dir_path, p);
            defer freeLogEntry(allocator, parent_entry);
            const parent_blob_sha = try getFileBlobSha(io, allocator, git_dir_path, parent_entry.tree, file_path, &cache);
            should_include = !blobShaEqual(current_blob_sha, parent_blob_sha);
                current_sha = try allocator.dupe(u8, p);
            } else {
                should_include = current_blob_sha != null;
                current_sha = null;
            }

            if (should_include) {
                try entries.append(allocator, entry);
                if (entries.items.len >= limit) break;
            } else {
                freeLogEntry(allocator, entry);
            }

            if (current_sha == null) break;
        }

        if (current_sha) |s| {
            allocator.free(s);
        }

        return entries.toOwnedSlice(allocator);
    }

    while (entries.items.len < limit) {
        const sha_to_parse = if (current_sha) |s| s else commit_sha;

        const entry = try parseCommitEntry(io, allocator, git_dir_path, sha_to_parse);

        if (current_sha) |s| {
            allocator.free(s);
        }

        if (entry.parent) |p| {
            current_sha = try allocator.dupe(u8, p);
        } else {
            current_sha = null;
        }

        try entries.append(allocator, entry);

        if (current_sha == null) {
            break;
        }
    }

    if (current_sha) |s| {
        allocator.free(s);
    }

    return entries.toOwnedSlice(allocator);
}

fn parseCommitEntry(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, commit_sha: []const u8) !LogEntry {
    const commit_data = try utils.readObject(io, allocator, git_dir_path, commit_sha);
    defer allocator.free(commit_data);

    const content = utils.extractContentFromBlob(commit_data);

    const tree = try extractField(allocator, content, "tree") orelse try allocator.dupe(u8, "");
    const parent_opt = try extractField(allocator, content, "parent");
    const author_str = try extractField(allocator, content, "author") orelse try allocator.dupe(u8, "");
    defer allocator.free(author_str);

    var committer_str: []const u8 = undefined;
    var committer_from_author = false;
    if (try extractField(allocator, content, "committer")) |cs| {
        committer_str = cs;
    } else {
        committer_str = author_str;
        committer_from_author = true;
    }

    defer if (!committer_from_author) allocator.free(committer_str);

    const message = try extractMessage(allocator, content);

    const timestamp = extractTimestamp(if (author_str.len > 0) author_str else committer_str);

    const sha_copy = try allocator.dupe(u8, commit_sha);
    const abbreviated_sha = try allocator.dupe(u8, commit_sha[0..7]);

    const author = try formatAuthor(allocator, if (author_str.len > 0) author_str else committer_str);
    const committer = try formatAuthor(allocator, if (committer_str.len > 0) committer_str else author_str);

    return LogEntry{
        .sha = sha_copy,
        .abbreviated_sha = abbreviated_sha,
        .tree = tree,
        .parent = parent_opt,
        .author = author,
        .committer = committer,
        .date = timestamp,
        .message = message,
    };
}

fn extractField(allocator: std.mem.Allocator, commit_data: []const u8, field_name: []const u8) !?[]const u8 {
    var lines = std.mem.splitScalar(u8, commit_data, '\n');

    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, field_name)) {
            if (line.len > field_name.len + 1 and line[field_name.len] == ' ') {
                const value = line[field_name.len + 1 ..];
                return try allocator.dupe(u8, value);
            }
        }
    }

    return null;
}

fn trimRight(comptime T: type, slice: []const T) []const T {
    var end = slice.len;
    while (end > 0 and std.ascii.isWhitespace(slice[end - 1])) {
        end -= 1;
    }
    return slice[0..end];
}

fn extractMessage(allocator: std.mem.Allocator, commit_data: []const u8) ![]const u8 {
    const empty_line_index = std.mem.indexOf(u8, commit_data, "\n\n");

    if (empty_line_index) |idx| {
        if (idx + 2 >= commit_data.len) {
            return try allocator.dupe(u8, "");
        }
        const message = commit_data[idx + 2 ..];
        const trimmed = trimRight(u8, message);
        return try allocator.dupe(u8, trimmed);
    }

    return try allocator.dupe(u8, "");
}

fn extractTimestamp(author: []const u8) i64 {
    const last_space_idx = std.mem.lastIndexOfScalar(u8, author, ' ') orelse return 0;

    const timestamp_str = author[last_space_idx + 1 ..];

    const timestamp = std.fmt.parseInt(i64, timestamp_str, 10) catch 0;

    return timestamp;
}

fn formatAuthor(allocator: std.mem.Allocator, author: []const u8) ![]const u8 {
    const angle_open_idx = std.mem.indexOfScalar(u8, author, '<') orelse {
        return try allocator.dupe(u8, std.mem.trim(u8, author, &std.ascii.whitespace));
    };

    const space_before_angle = std.mem.lastIndexOfScalar(u8, author[0..angle_open_idx], ' ') orelse 0;

    if (space_before_angle == 0) {
        return try allocator.dupe(u8, std.mem.trim(u8, author[0..angle_open_idx], &std.ascii.whitespace));
    }

    const name = author[0..space_before_angle];
    return try allocator.dupe(u8, std.mem.trim(u8, name, &std.ascii.whitespace));
}

fn freeLogEntry(allocator: std.mem.Allocator, entry: LogEntry) void {
    allocator.free(entry.sha);
    allocator.free(entry.abbreviated_sha);
    allocator.free(entry.tree);
    if (entry.parent) |p| allocator.free(p);
    allocator.free(entry.author);
    allocator.free(entry.committer);
    allocator.free(entry.message);
}

fn blobShaEqual(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null and b == null) return true;
    if (a == null or b == null) return false;
    return std.mem.eql(u8, a.?, b.?);
}

fn getFileBlobSha(
    io: std.Io,
    allocator: std.mem.Allocator,
    git_dir_path: []const u8,
    tree_sha: []const u8,
    file_path: []const u8,
    cache: *std.AutoHashMap([40]u8, ?[]const u8),
) !?[]const u8 {
    var key: [40]u8 = undefined;
    @memcpy(&key, tree_sha[0..40]);

    if (cache.get(key)) |cached| {
        return cached;
    }

    var parts = std.mem.splitScalar(u8, file_path, '/');
    const first_part = parts.next() orelse {
        try cache.put(key, null);
        return null;
    };

    var current_sha: ?[]const u8 = null;
    var current_is_tree = false;

    {
        const tree_data = try utils.readObject(io, allocator, git_dir_path, tree_sha);
        defer allocator.free(tree_data);

        var tree_entries = try utils.parseTreeEntries(allocator, tree_data);
        defer {
            for (tree_entries.items) |e| {
                allocator.free(e.path);
                allocator.free(e.sha);
                allocator.free(e.mode);
                allocator.free(e.entry_type);
            }
            tree_entries.deinit(allocator);
        }

        for (tree_entries.items) |e| {
            if (std.mem.eql(u8, e.path, first_part)) {
                current_sha = try allocator.dupe(u8, e.sha);
                current_is_tree = std.mem.eql(u8, e.entry_type, "tree");
                break;
            }
        }
    }

    if (current_sha == null) {
        try cache.put(key, null);
        return null;
    }

    while (parts.next()) |part| {
        if (!current_is_tree) {
            allocator.free(current_sha.?);
            try cache.put(key, null);
            return null;
        }
        const sub_tree_data = try utils.readObject(io, allocator, git_dir_path, current_sha.?);
        defer allocator.free(sub_tree_data);
        var sub_entries = try utils.parseTreeEntries(allocator, sub_tree_data);
        defer {
            for (sub_entries.items) |e| {
                allocator.free(e.path);
                allocator.free(e.sha);
                allocator.free(e.mode);
                allocator.free(e.entry_type);
            }
            sub_entries.deinit(allocator);
        }

        var found = false;
        for (sub_entries.items) |e| {
            if (std.mem.eql(u8, e.path, part)) {
                const new_sha = try allocator.dupe(u8, e.sha);
                allocator.free(current_sha.?);
                current_sha = new_sha;
                current_is_tree = std.mem.eql(u8, e.entry_type, "tree");
                found = true;
                break;
            }
        }

        if (!found) {
            allocator.free(current_sha.?);
            try cache.put(key, null);
            return null;
        }
    }

    try cache.put(key, current_sha.?);
    return current_sha.?;
}
