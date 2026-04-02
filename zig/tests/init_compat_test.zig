const std = @import("std");

const init = @import("gitologist").init;

test "should create same directory structure as git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir);

    const their_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir);

    {
        const dir = try cwd.openDir(io, our_git_dir, .{});
        dir.close(io);
    }

    {
        const dir = try cwd.openDir(io, their_git_dir, .{});
        dir.close(io);
    }

    const our_objects = try std.fs.path.join(allocator, &[_][]const u8{ our_git_dir, "objects" });
    defer allocator.free(our_objects);

    {
        const dir = try cwd.openDir(io, our_objects, .{});
        dir.close(io);
    }

    const their_objects = try std.fs.path.join(allocator, &[_][]const u8{ their_git_dir, "objects" });
    defer allocator.free(their_objects);

    {
        const dir = try cwd.openDir(io, their_objects, .{});
        dir.close(io);
    }

    const our_refs_heads = try std.fs.path.join(allocator, &[_][]const u8{ our_git_dir, "refs", "heads" });
    defer allocator.free(our_refs_heads);

    {
        const dir = try cwd.openDir(io, our_refs_heads, .{});
        dir.close(io);
    }

    const their_refs_heads = try std.fs.path.join(allocator, &[_][]const u8{ their_git_dir, "refs", "heads" });
    defer allocator.free(their_refs_heads);

    {
        const dir = try cwd.openDir(io, their_refs_heads, .{});
        dir.close(io);
    }

    const our_refs_tags = try std.fs.path.join(allocator, &[_][]const u8{ our_git_dir, "refs", "tags" });
    defer allocator.free(our_refs_tags);

    {
        const dir = try cwd.openDir(io, our_refs_tags, .{});
        dir.close(io);
    }

    const their_refs_tags = try std.fs.path.join(allocator, &[_][]const u8{ their_git_dir, "refs", "tags" });
    defer allocator.free(their_refs_tags);

    {
        const dir = try cwd.openDir(io, their_refs_tags, .{});
        dir.close(io);
    }
}

test "should create HEAD pointing to same branch as git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-head-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-head-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir_path);
    const our_git_dir = try cwd.openDir(io, our_git_dir_path, .{});
    defer our_git_dir.close(io);

    const our_head = try our_git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited);
    defer allocator.free(our_head);

    const their_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir_path);
    const their_git_dir = try cwd.openDir(io, their_git_dir_path, .{});
    defer their_git_dir.close(io);

    const their_head = try their_git_dir.readFileAlloc(io, "HEAD", allocator, .unlimited);
    defer allocator.free(their_head);

    try std.testing.expect(std.mem.startsWith(u8, our_head, "ref: refs/heads/"));
    try std.testing.expect(std.mem.startsWith(u8, their_head, "ref: refs/heads/"));
}

test "should create valid config file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-config-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-config-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir_path);
    const our_git_dir = try cwd.openDir(io, our_git_dir_path, .{});
    defer our_git_dir.close(io);

    const our_config = try our_git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(our_config);

    const their_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir_path);
    const their_git_dir = try cwd.openDir(io, their_git_dir_path, .{});
    defer their_git_dir.close(io);

    const their_config = try their_git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(their_config);

    try std.testing.expect(std.mem.indexOf(u8, our_config, "[core]") != null);
    try std.testing.expect(std.mem.indexOf(u8, our_config, "repositoryformatversion") != null);
    try std.testing.expect(std.mem.indexOf(u8, their_config, "[core]") != null);
    try std.testing.expect(std.mem.indexOf(u8, their_config, "repositoryformatversion") != null);
}

test "should create empty objects directory like git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-objects-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-objects-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir_path);
    const our_git_dir = try cwd.openDir(io, our_git_dir_path, .{});
    defer our_git_dir.close(io);

    var our_objects = try our_git_dir.openDir(io, "objects", .{});
    defer our_objects.close(io);

    var our_entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 0) catch unreachable;
    defer our_entries.deinit(allocator);
    {
        var it = our_objects.iterate();
        while (try it.next(io)) |entry| {
            try our_entries.append(allocator, entry);
        }
    }

    const their_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir_path);
    const their_git_dir = try cwd.openDir(io, their_git_dir_path, .{});
    defer their_git_dir.close(io);

    var their_objects = try their_git_dir.openDir(io, "objects", .{});
    defer their_objects.close(io);

    var their_entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 0) catch unreachable;
    defer their_entries.deinit(allocator);
    {
        var it = their_objects.iterate();
        while (try it.next(io)) |entry| {
            try their_entries.append(allocator, entry);
        }
    }
}

test "should create empty refs/heads directory like git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-refs-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-refs-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir_path);
    const our_git_dir = try cwd.openDir(io, our_git_dir_path, .{});
    defer our_git_dir.close(io);

    var our_refs = try our_git_dir.openDir(io, "refs", .{});
    defer our_refs.close(io);

    var our_refs_heads = try our_refs.openDir(io, "heads", .{});
    defer our_refs_heads.close(io);

    var our_entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 0) catch unreachable;
    defer our_entries.deinit(allocator);
    {
        var it = our_refs_heads.iterate();
        while (try it.next(io)) |entry| {
            try our_entries.append(allocator, entry);
        }
    }

    const their_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir_path);
    const their_git_dir = try cwd.openDir(io, their_git_dir_path, .{});
    defer their_git_dir.close(io);

    var their_refs = try their_git_dir.openDir(io, "refs", .{});
    defer their_refs.close(io);

    var their_refs_heads = try their_refs.openDir(io, "heads", .{});
    defer their_refs_heads.close(io);

    var their_entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 0) catch unreachable;
    defer their_entries.deinit(allocator);
    {
        var it = their_refs_heads.iterate();
        while (try it.next(io)) |entry| {
            try their_entries.append(allocator, entry);
        }
    }
}

test "should create description file" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const ours_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-desc-ours" });
    defer allocator.free(ours_path);

    const theirs_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-desc-theirs" });
    defer allocator.free(theirs_path);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, ours_path);
    defer cwd.deleteTree(io, ours_path) catch {};

    try cwd.createDirPath(io, theirs_path);
    defer cwd.deleteTree(io, theirs_path) catch {};

    try init(io, allocator, ours_path);

    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = theirs_path },
    });
    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    const our_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ ours_path, ".git" });
    defer allocator.free(our_git_dir_path);
    const our_git_dir = try cwd.openDir(io, our_git_dir_path, .{});
    defer our_git_dir.close(io);

    _ = try our_git_dir.openFile(io, "description", .{});

    const their_git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ theirs_path, ".git" });
    defer allocator.free(their_git_dir_path);
    const their_git_dir = try cwd.openDir(io, their_git_dir_path, .{});
    defer their_git_dir.close(io);

    _ = try their_git_dir.openFile(io, "description", .{});
}
