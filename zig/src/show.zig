const std = @import("std");

const utils = @import("utils.zig");
const getCurrentCommit = @import("branch.zig").getCurrentCommit;

pub fn show(
	io: std.Io,
	allocator: std.mem.Allocator,
	path: []const u8,
	file_path: []const u8,
	commit: ?[]const u8,
) ![]const u8 {
	const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
	defer allocator.free(git_dir_path);

	const cwd = std.Io.Dir.cwd();
	const git_dir = cwd.openDir(io, git_dir_path, .{}) catch {
		return error.NotAGitRepository;
	};
	git_dir.close(io);

	var pack_cache = utils.PackfileCache.init(allocator);
	defer pack_cache.deinit();

	var head_sha: ?[]const u8 = null;
	defer if (head_sha) |h| allocator.free(h);

	if (commit == null) {
		head_sha = try getCurrentCommit(io, allocator, git_dir_path) orelse {
			return error.PathNotFound;
		};
	}

	const commit_sha = commit orelse head_sha.?;

	const commit_data = if (commit != null) blk: {
		const data = utils.readObject(io, allocator, git_dir_path, commit_sha, &pack_cache) catch {
			return error.CommitNotFound;
		};
		if (!std.mem.startsWith(u8, data, "commit ")) {
			allocator.free(data);
			return error.CommitNotFound;
		}
		break :blk data;
	} else try utils.readObject(io, allocator, git_dir_path, commit_sha, &pack_cache);
	defer allocator.free(commit_data);

	const tree_sha = try utils.extractTreeFromCommit(commit_data);

	const blob_sha = try resolveBlobSha(io, allocator, git_dir_path, tree_sha, file_path, &pack_cache) orelse {
		return error.PathNotFound;
	};
	defer allocator.free(blob_sha);

	const blob_data = try utils.readObject(io, allocator, git_dir_path, blob_sha, &pack_cache);
	defer allocator.free(blob_data);

	const content = utils.extractContentFromBlob(blob_data);
	return try allocator.dupe(u8, content);
}

fn resolveBlobSha(
	io: std.Io,
	allocator: std.mem.Allocator,
	git_dir_path: []const u8,
	tree_sha: []const u8,
	file_path: []const u8,
	pack_cache: *utils.PackfileCache,
) !?[]const u8 {
	var parts = std.mem.splitScalar(u8, file_path, '/');

	var current_sha = try allocator.dupe(u8, tree_sha);
	var current_is_tree = true;
	defer allocator.free(current_sha);

	while (parts.next()) |part| {
		if (!current_is_tree) {
			return null;
		}

		const tree_data = try utils.readObject(io, allocator, git_dir_path, current_sha, pack_cache);
		defer allocator.free(tree_data);

		var entries = try utils.parseTreeEntries(allocator, tree_data);
		defer {
			for (entries.items) |e| {
				allocator.free(e.path);
				allocator.free(e.sha);
				allocator.free(e.mode);
				allocator.free(e.entry_type);
			}
			entries.deinit(allocator);
		}

		var found = false;
		for (entries.items) |e| {
			if (std.mem.eql(u8, e.path, part)) {
				const new_sha = try allocator.dupe(u8, e.sha);
				const new_is_tree = std.mem.eql(u8, e.entry_type, "tree");
				allocator.free(current_sha);
				current_sha = new_sha;
				current_is_tree = new_is_tree;
				found = true;
				break;
			}
		}

		if (!found) {
			return null;
		}
	}

	if (current_is_tree) {
		return null;
	}

	return try allocator.dupe(u8, current_sha);
}
