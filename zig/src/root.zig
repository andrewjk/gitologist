//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const init = @import("init.zig").init;
pub const status = @import("status.zig").status;
pub const add = @import("add.zig").add;
pub const addAll = @import("add.zig").addAll;
pub const commit = @import("commit.zig").commit;
pub const restore = @import("restore.zig").restore;
pub const restoreAll = @import("restore.zig").restoreAll;
pub const stash = @import("stash.zig").stash;
pub const unstash = @import("stash.zig").unstash;
pub const switchBranch = @import("switch.zig").switchBranch;
pub const remoteAdd = @import("remote.zig").remoteAdd;
pub const hasRemote = @import("remote.zig").hasRemote;
pub const getRemoteUrl = @import("remote.zig").getRemoteUrl;
pub const setRemoteUrl = @import("remote.zig").setRemoteUrl;
pub const clone = @import("clone.zig").clone;
pub const push = @import("push.zig").push;
pub const setUpstreamBranch = @import("push.zig").setUpstreamBranch;
pub const pull = @import("pull.zig").pull;
pub const log = @import("log.zig").log;
pub const show = @import("show.zig").show;
pub const merge = @import("merge.zig").merge;
pub const getCurrentBranch = @import("branch.zig").getCurrentBranch;
pub const getCurrentCommit = @import("branch.zig").getCurrentCommit;
pub const _utils = @import("utils.zig");

pub const IgnoreParser = @import("ignore_parser.zig").IgnoreParser;
pub const IgnorePattern = @import("ignore_parser.zig").IgnorePattern;

pub const LogEntry = @import("types/LogEntry.zig").LogEntry;
pub const LogOptions = @import("types/LogOptions.zig").LogOptions;
pub const MergeOptions = @import("merge.zig").MergeOptions;
pub const types = struct {
    pub const StatusInfo = @import("types/StatusInfo.zig").StatusInfo;
};

pub const RemoteOptions = @import("types/RemoteOptions.zig").RemoteOptions;
pub const Credentials = @import("types/RemoteOptions.zig").Credentials;

pub const packfile = @import("packfile.zig");

// Placeholder function for main.zig
pub fn printAnotherMessage(writer: anytype) !void {
    try writer.writeAll("Hello from Gitologist!\n");
}
