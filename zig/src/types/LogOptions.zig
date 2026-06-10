const std = @import("std");

pub const LogOptions = struct {
    limit: ?usize = null,
    oneline: bool = false,
    branch: ?[]const u8 = null,
    file: ?[]const u8 = null,
};
