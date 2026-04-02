const std = @import("std");

pub const TreeType = enum {
    blob,
    tree,
};

pub const TreeEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
    type: TreeType,
};
