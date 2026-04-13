const std = @import("std");

pub const IndexEntry = struct {
    path: []const u8,
    sha: []const u8,
    mode: []const u8,
    size: u32,
    ctime_seconds: u32,
    ctime_nanos: u32,
    mtime_seconds: u32,
    mtime_nanos: u32,
    dev: u32,
    ino: u32,
    uid: u32,
    gid: u32,
};
