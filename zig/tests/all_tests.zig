comptime {
    _ = @import("init_test.zig");
    _ = @import("init_compat_test.zig");
    _ = @import("status_test.zig");
    _ = @import("add_test.zig");
    _ = @import("commit_test.zig");
    _ = @import("restore_test.zig");
    _ = @import("stash_test.zig");
    _ = @import("remote_test.zig");
    _ = @import("clone_test.zig");
    _ = @import("push_test.zig");
    _ = @import("pull_test.zig");
    _ = @import("log_test.zig");
    _ = @import("show_test.zig");
    _ = @import("merge_test.zig");
    _ = @import("git_compat_test.zig");
    _ = @import("ignore_parser_test.zig");
    _ = @import("spaces_in_names_test.zig");
    _ = @import("packfile_test.zig");
    _ = @import("switch_test.zig");
    _ = @import("branch_test.zig");
}
