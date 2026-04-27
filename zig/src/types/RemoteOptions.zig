const std = @import("std");

pub const Credentials = struct {
    username: []const u8,
    token: []const u8,
};

pub const RemoteOptions = struct {
    credentials: ?*const Credentials = null,
};
