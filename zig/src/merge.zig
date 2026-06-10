const std = @import("std");

const MergeResult = @import("types/MergeResult.zig").MergeResult;

const utils = @import("utils.zig");

pub const MergeOptions = struct {
    message: ?[]const u8 = null,
    no_fast_forward: bool = false,
};

pub fn merge(io: std.Io, allocator: std.mem.Allocator, path: []const u8, branch_name: []const u8, options: ?MergeOptions) !MergeResult {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    var cache = utils.PackfileCache.init(allocator);
    defer cache.deinit();

    const cwd = std.Io.Dir.cwd();
    _ = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };

    const current_branch = try utils.getCurrentBranch(io, allocator, git_dir_path);
    defer allocator.free(current_branch);

    if (std.mem.eql(u8, current_branch, branch_name)) {
        return error.CannotMergeIntoSelf;
    }

    const current_sha_opt = try utils.getCurrentCommit(io, allocator, git_dir_path);
    const branch_sha_opt = try getBranchCommit(io, allocator, git_dir_path, branch_name);

    if (branch_sha_opt == null) {
        if (current_sha_opt) |s| allocator.free(s);
        return error.BranchNotFound;
    }

    if (current_sha_opt == null) {
        allocator.free(branch_sha_opt.?);
        return error.CannotMergeIntoEmptyBranch;
    }

    const current_sha = current_sha_opt.?;
    const branch_sha = branch_sha_opt.?;

    if (std.mem.eql(u8, current_sha, branch_sha)) {
        allocator.free(current_sha);
        allocator.free(branch_sha);
        return MergeResult{
            .success = true,
            .fast_forward = false,
            .message = try allocator.dupe(u8, "Already up to date."),
        };
    }

    const is_ancestor = try isAncestorOf(io, allocator, git_dir_path, current_sha, branch_sha, &cache);

    const opts = options orelse MergeOptions{};

    if (is_ancestor and !opts.no_fast_forward) {
        try utils.updateBranch(io, allocator, git_dir_path, current_branch, branch_sha);
        const result = MergeResult{
            .success = true,
            .fast_forward = true,
            .commit_sha = try allocator.dupe(u8, branch_sha),
            .message = try std.fmt.allocPrint(allocator, "Fast-forward merge of '{s}' into '{s}'", .{ branch_name, current_branch }),
        };
        allocator.free(current_sha);
        allocator.free(branch_sha);
        return result;
    }

    const merge_base = try findMergeBase(io, allocator, git_dir_path, current_sha, branch_sha, &cache);

    if (merge_base) |base| {
        if (std.mem.eql(u8, base, current_sha)) {
            // Current is already up to date with branch (current is ancestor of branch)
            allocator.free(base);
            allocator.free(current_sha);
            allocator.free(branch_sha);
            return MergeResult{
                .success = true,
                .fast_forward = false,
                .message = try allocator.dupe(u8, "Already up to date."),
            };
        }
        allocator.free(base);
    }

    const merge_message = if (opts.message) |msg| try allocator.dupe(u8, msg) else try std.fmt.allocPrint(allocator, "Merge branch '{s}' into '{s}'", .{ branch_name, current_branch });

    const merge_commit_sha = try createMergeCommit(io, allocator, git_dir_path, current_sha, branch_sha, merge_message, &cache);

    try utils.updateBranch(io, allocator, git_dir_path, current_branch, merge_commit_sha);

    allocator.free(current_sha);
    allocator.free(branch_sha);

    return MergeResult{
        .success = true,
        .fast_forward = false,
        .commit_sha = merge_commit_sha,
        .message = merge_message,
    };
}

fn getBranchCommit(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, branch_name: []const u8) !?[]const u8 {
    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(branch_path);

    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, branch_path, allocator, .unlimited) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };

    const trimmed = std.mem.trim(u8, content, &std.ascii.whitespace);
    const result = try allocator.dupe(u8, trimmed);
    allocator.free(content);

    return result;
}

fn isAncestorOf(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, ancestor_sha: []const u8, descendant_sha: []const u8, pack_cache: *utils.PackfileCache) !bool {
    var visited = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (visited.items) |sha| allocator.free(sha);
        visited.deinit(allocator);
    }

    var queue = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (queue.items) |sha| allocator.free(sha);
        queue.deinit(allocator);
    }

    try queue.append(allocator, try allocator.dupe(u8, descendant_sha));

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);

        if (std.mem.eql(u8, current, ancestor_sha)) {
            allocator.free(current);
            return true;
        }

        var already_visited = false;
        for (visited.items) |sha| {
            if (std.mem.eql(u8, sha, current)) {
                already_visited = true;
                break;
            }
        }

        if (already_visited) {
            allocator.free(current);
            continue;
        }

        try visited.append(allocator, current);

        var parents = try getParents(io, allocator, git_dir_path, current, pack_cache);
        defer {
            for (parents.items) |sha| allocator.free(sha);
            parents.deinit(allocator);
        }
        for (parents.items) |parent| {
            try queue.append(allocator, try allocator.dupe(u8, parent));
        }
    }

    return false;
}

fn findMergeBase(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha1: []const u8, sha2: []const u8, pack_cache: *utils.PackfileCache) !?[]const u8 {
    if (std.mem.eql(u8, sha1, sha2)) {
        return try allocator.dupe(u8, sha1);
    }

    var ancestors1 = try getAllAncestors(io, allocator, git_dir_path, sha1, pack_cache);
    defer {
        for (ancestors1.items) |sha| allocator.free(sha);
        ancestors1.deinit(allocator);
    }

    var ancestors2 = try getAllAncestors(io, allocator, git_dir_path, sha2, pack_cache);
    defer {
        for (ancestors2.items) |sha| allocator.free(sha);
        ancestors2.deinit(allocator);
    }

    const sha1_copy = try allocator.dupe(u8, sha1);
    errdefer allocator.free(sha1_copy);
    const sha2_copy = try allocator.dupe(u8, sha2);
    errdefer {
        allocator.free(sha2_copy);
        allocator.free(sha1_copy);
    }

    try ancestors1.append(allocator, sha1_copy);
    try ancestors2.append(allocator, sha2_copy);

    for (ancestors1.items) |ancestor| {
        for (ancestors2.items) |other| {
            if (std.mem.eql(u8, ancestor, other)) {
                return try allocator.dupe(u8, ancestor);
            }
        }
    }

    return null;
}

fn getAllAncestors(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !std.ArrayList([]const u8) {
    var ancestors = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    errdefer {
        for (ancestors.items) |s| allocator.free(s);
        ancestors.deinit(allocator);
    }

    var queue = std.ArrayList([]const u8).initCapacity(allocator, 10) catch unreachable;
    defer {
        for (queue.items) |s| allocator.free(s);
        queue.deinit(allocator);
    }

    try queue.append(allocator, try allocator.dupe(u8, sha));

    while (queue.items.len > 0) {
        const current = queue.orderedRemove(0);

        var already_has = false;
        for (ancestors.items) |ancestor| {
            if (std.mem.eql(u8, ancestor, current)) {
                already_has = true;
                break;
            }
        }

        if (already_has) {
            allocator.free(current);
            continue;
        }

        var parents = try getParents(io, allocator, git_dir_path, current, pack_cache);
        defer {
            for (parents.items) |p| allocator.free(p);
            parents.deinit(allocator);
        }
        for (parents.items) |parent| {
            try ancestors.append(allocator, try allocator.dupe(u8, parent));
            try queue.append(allocator, try allocator.dupe(u8, parent));
        }
        allocator.free(current);
    }

    return ancestors;
}

fn getParents(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !std.ArrayList([]const u8) {
    var parents = std.ArrayList([]const u8).initCapacity(allocator, 2) catch unreachable;
    errdefer {
        for (parents.items) |p| allocator.free(p);
        parents.deinit(allocator);
    }

    const commit_data = utils.readObject(io, allocator, git_dir_path, sha, pack_cache) catch |err| {
        if (err == error.FileNotFound) {
            return parents;
        }
        return err;
    };
    defer allocator.free(commit_data);

    const content = utils.extractContentFromBlob(commit_data);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "parent ")) {
            const parent_sha = line["parent ".len..];
            try parents.append(allocator, try allocator.dupe(u8, parent_sha));
        }
    }

    return parents;
}

fn getTree(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, pack_cache: *utils.PackfileCache) !?[]const u8 {
    const commit_data = utils.readObject(io, allocator, git_dir_path, sha, pack_cache) catch |err| {
        if (err == error.FileNotFound) {
            return null;
        }
        return err;
    };
    defer allocator.free(commit_data);

    const content = utils.extractContentFromBlob(commit_data);

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "tree ")) {
            const tree_sha = line["tree ".len..];
            return try allocator.dupe(u8, tree_sha);
        }
    }

    return null;
}

fn createMergeCommit(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, parent1: []const u8, parent2: []const u8, message: []const u8, pack_cache: *utils.PackfileCache) ![]const u8 {
    const tree_sha_opt = try getTree(io, allocator, git_dir_path, parent1, pack_cache);

    if (tree_sha_opt == null) {
        return error.CouldNotGetTreeForMergeCommit;
    }
    defer allocator.free(tree_sha_opt.?);
    const tree_sha = tree_sha_opt.?;

    const timestamp: i64 = 0;
    const offset_seconds = 0;
    const sign_char: u8 = if (offset_seconds >= 0) '+' else '-';
    const abs_offset = @abs(offset_seconds);
    const hours = abs_offset / 3600;
    const minutes = (abs_offset % 3600) / 60;

    const author = try std.fmt.allocPrint(allocator, "User <user@example.com> {d} {c}{d:0>2}{d:0>2}", .{ timestamp, sign_char, hours, minutes });
    defer allocator.free(author);

    var commit_content = std.ArrayList(u8).initCapacity(allocator, 200) catch unreachable;
    defer commit_content.deinit(allocator);

    try commit_content.appendSlice(allocator, "tree ");
    try commit_content.appendSlice(allocator, tree_sha);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "parent ");
    try commit_content.appendSlice(allocator, parent1);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "parent ");
    try commit_content.appendSlice(allocator, parent2);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "author ");
    try commit_content.appendSlice(allocator, author);
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, "committer ");
    try commit_content.appendSlice(allocator, author);
    try commit_content.appendSlice(allocator, "\n");
    try commit_content.appendSlice(allocator, "\n");

    try commit_content.appendSlice(allocator, message);
    try commit_content.appendSlice(allocator, "\n");

    return utils.hashObject(io, allocator, git_dir_path, commit_content.items, "commit");
}
