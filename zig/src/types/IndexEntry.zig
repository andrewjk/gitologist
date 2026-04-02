const std = @import("std");

pub const IndexEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
};
