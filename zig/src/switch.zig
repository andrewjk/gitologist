const std = @import("std");

pub fn switchBranch(io: std.Io, allocator: std.mem.Allocator, path: []const u8, branch_name: []const u8) !void {
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
    defer allocator.free(git_dir_path);

    const cwd = std.Io.Dir.cwd();

    _ = cwd.openDir(io, git_dir_path, .{}) catch {
        return error.NotAGitRepository;
    };

    const branch_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "refs", "heads", branch_name });
    defer allocator.free(branch_path);

    if (cwd.access(io, branch_path, .{})) |_| {} else |_| {
        return error.BranchNotFound;
    }

    const head_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "HEAD" });
    defer allocator.free(head_path);

    const head_content = try std.fmt.allocPrint(allocator, "ref: refs/heads/{s}\n", .{branch_name});
    defer allocator.free(head_content);

    try cwd.writeFile(io, .{ .sub_path = head_path, .data = head_content });
}
