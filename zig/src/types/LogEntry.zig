const std = @import("std");

pub const LogEntry = struct {
    sha: []const u8,
    abbreviated_sha: []const u8,
    tree: []const u8,
    parent: ?[]const u8,
    author: []const u8,
    committer: []const u8,
    date: i64,
    message: []const u8,
};
