const std = @import("std");

pub const StatusInfo = struct {
    branch: []const u8,
    up_to_date: []const u8,
    staged: []const []const u8,
    modified: []const []const u8,
    untracked: []const []const u8,
    deleted: []const []const u8,

    pub fn deinit(self: StatusInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.branch);
        allocator.free(self.up_to_date);

        for (self.staged) |item| allocator.free(item);
        allocator.free(self.staged);

        for (self.modified) |item| allocator.free(item);
        allocator.free(self.modified);

        for (self.untracked) |item| allocator.free(item);
        allocator.free(self.untracked);

        for (self.deleted) |item| allocator.free(item);
        allocator.free(self.deleted);
    }
};
