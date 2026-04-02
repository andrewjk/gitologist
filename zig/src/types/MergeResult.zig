const std = @import("std");

pub const MergeResult = struct {
    success: bool,
    fast_forward: bool,
    commit_sha: ?[]const u8 = null,
    message: ?[]const u8 = null,
};
