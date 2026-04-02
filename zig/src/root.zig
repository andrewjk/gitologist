//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const init = @import("init.zig").init;
pub const status = @import("status.zig").status;
pub const add = @import("add.zig").add;
pub const addAll = @import("add.zig").addAll;
pub const commit = @import("commit.zig").commit;
pub const restore = @import("restore.zig").restore;
pub const restoreAll = @import("restore.zig").restoreAll;
