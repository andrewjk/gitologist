const std = @import("std");

pub const StatusInfo = struct {
    branch: []const u8,
    up_to_date: []const u8,
    staged: []const []const u8,
    modified: []const []const u8,
    untracked: []const []const u8,
    deleted: []const []const u8,
};
