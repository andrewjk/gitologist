//! By convention, root.zig is the root source file when making a package.
const std = @import("std");

pub const init = @import("init.zig").init;
pub const status = @import("status.zig").status;
