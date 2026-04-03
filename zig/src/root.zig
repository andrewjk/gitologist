//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const init = @import("init.zig").init;
pub const status = @import("status.zig").status;
pub const add = @import("add.zig").add;
pub const addAll = @import("add.zig").addAll;
pub const commit = @import("commit.zig").commit;
pub const restore = @import("restore.zig").restore;
pub const restoreAll = @import("restore.zig").restoreAll;
pub const remoteAdd = @import("remote.zig").remoteAdd;
pub const clone = @import("clone.zig").clone;
pub const push = @import("push.zig").push;
pub const pull = @import("pull.zig").pull;
pub const log = @import("log.zig").log;
pub const merge = @import("merge.zig").merge;

pub const IgnoreParser = @import("ignore_parser.zig").IgnoreParser;
pub const IgnorePattern = @import("ignore_parser.zig").IgnorePattern;

pub const LogEntry = @import("types/LogEntry.zig").LogEntry;
pub const LogOptions = @import("types/LogOptions.zig").LogOptions;
pub const MergeOptions = @import("merge.zig").MergeOptions;

// Placeholder function for main.zig
pub fn printAnotherMessage(writer: anytype) !void {
    try writer.writeAll("Hello from Gitologist!\n");
}
