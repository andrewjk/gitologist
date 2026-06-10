const std = @import("std");

const init = @import("gitologist").init;
const add = @import("gitologist").add;
const commit = @import("gitologist").commit;
const log = @import("gitologist").log;
const clone = @import("gitologist").clone;
const LogOptions = @import("gitologist").LogOptions;

test "should create an index that git can read" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-add-ours" });
    defer allocator.free(our_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "test content" });

    const test_file2_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, "test 2.txt" });
    defer allocator.free(test_file2_path);

    try cwd.writeFile(io, .{ .sub_path = test_file2_path, .data = "test content 2" });

    try add(io, allocator, our_dir, &[_][]const u8{ "test.txt", "test 2.txt" });

    const git_status_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "status" },
        .cwd = .{ .path = our_dir },
    });
    defer {
        allocator.free(git_status_result.stdout);
        allocator.free(git_status_result.stderr);
    }

    // Check git command succeeded
    switch (git_status_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("git status failed with exit code {d}. stderr: {s}\n", .{ code, git_status_result.stderr });
            }
            try std.testing.expectEqual(@as(u32, 0), code);
        },
        .signal => |sig| {
            std.debug.print("git status killed by signal {d}. stderr: {s}\n", .{ sig, git_status_result.stderr });
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    try std.testing.expect(std.mem.indexOf(u8, git_status_result.stdout, "new file:   test.txt") != null);
    try std.testing.expect(std.mem.indexOf(u8, git_status_result.stdout, "new file:   test 2.txt") != null);
}

test "should create valid commit structure" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-commit-ours" });
    defer allocator.free(our_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, "test.txt" });
    defer allocator.free(test_file_path);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "test content" });
    try add(io, allocator, our_dir, &[_][]const u8{"test.txt"});

    const commit_sha = try commit(io, allocator, our_dir, "Test commit");
    defer allocator.free(commit_sha);

    // Verify commit has valid SHA format (40 hex characters)
    try std.testing.expectEqual(@as(usize, 40), commit_sha.len);
    for (commit_sha) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }

    // Verify commit is stored in .git/objects
    const objects_dir = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, ".git", "objects", commit_sha[0..2] });
    defer allocator.free(objects_dir);

    const obj_dir = try cwd.openDir(io, objects_dir, .{});
    defer obj_dir.close(io);

    // The object file should exist (rest of SHA as filename)
    const obj_file = try obj_dir.openFile(io, commit_sha[2..], .{});
    obj_file.close(io);

    // Verify git can read our commit
    const git_log_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "log", "--oneline" },
        .cwd = .{ .path = our_dir },
    });
    defer {
        allocator.free(git_log_result.stdout);
        allocator.free(git_log_result.stderr);
    }

    // Check git command succeeded
    switch (git_log_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("git log failed with exit code {d}. stderr: {s}\n", .{ code, git_log_result.stderr });
            }
            try std.testing.expectEqual(@as(u32, 0), code);
        },
        .signal => |sig| {
            std.debug.print("git log killed by signal {d}. stderr: {s}\n", .{ sig, git_log_result.stderr });
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    try std.testing.expect(std.mem.indexOf(u8, git_log_result.stdout, "Test commit") != null);

    // Verify our log can read the commit
    const log_result = try log(io, allocator, our_dir, null);
    defer {
        for (log_result) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(log_result);
    }

    try std.testing.expectEqual(@as(usize, 1), log_result.len);
    try std.testing.expectEqualStrings("Test commit", log_result[0].message);

    // Check git status - should be clean
    const git_status_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "status" },
        .cwd = .{ .path = our_dir },
    });
    defer {
        allocator.free(git_status_result.stdout);
        allocator.free(git_status_result.stderr);
    }

    switch (git_status_result.term) {
        .exited => |code| {
            try std.testing.expectEqual(@as(u32, 0), code);
        },
        .signal => return error.ProcessSignaled,
        else => unreachable,
    }

    try std.testing.expect(std.mem.indexOf(u8, git_status_result.stdout, "nothing to commit, working tree clean") != null);
}

test "should produce same commit structure as git" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-commit-ours2" });
    defer allocator.free(our_dir);

    const their_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-commit-theirs2" });
    defer allocator.free(their_dir);

    const cwd = std.Io.Dir.cwd();

    // Our implementation
    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    const our_file_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, "file.txt" });
    defer allocator.free(our_file_path);

    try cwd.writeFile(io, .{ .sub_path = our_file_path, .data = "content" });
    try add(io, allocator, our_dir, &[_][]const u8{"file.txt"});

    const our_sha = try commit(io, allocator, our_dir, "Same message");
    defer allocator.free(our_sha);

    // Real git
    try cwd.createDirPath(io, their_dir);
    defer cwd.deleteTree(io, their_dir) catch {};

    const init_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(init_result.stdout);
        allocator.free(init_result.stderr);
    }

    switch (init_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git init killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const their_file_path = try std.fs.path.join(allocator, &[_][]const u8{ their_dir, "file.txt" });
    defer allocator.free(their_file_path);

    try cwd.writeFile(io, .{ .sub_path = their_file_path, .data = "content" });

    const add_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "add", "." },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(add_result.stdout);
        allocator.free(add_result.stderr);
    }

    switch (add_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git add killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const commit_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "commit", "-m", "Same message" },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(commit_result.stdout);
        allocator.free(commit_result.stderr);
    }

    switch (commit_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git commit killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    // Both should have valid commit SHAs (40 hex characters)
    try std.testing.expectEqual(@as(usize, 40), our_sha.len);
    for (our_sha) |c| {
        const is_hex = (c >= '0' and c <= '9') or (c >= 'a' and c <= 'f');
        try std.testing.expect(is_hex);
    }

    // Both should have 1 commit in log
    const our_log = try log(io, allocator, our_dir, null);
    defer {
        for (our_log) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(our_log);
    }

    const their_log_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "log", "--oneline" },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(their_log_result.stdout);
        allocator.free(their_log_result.stderr);
    }

    switch (their_log_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git log killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    try std.testing.expectEqual(@as(usize, 1), our_log.len);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, their_log_result.stdout, "\n"));
}

test "should show commits in reverse chronological order" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-log-order" });
    defer allocator.free(our_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    const test_file_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, "file.txt" });
    defer allocator.free(test_file_path);

    // Create multiple commits
    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content1" });
    try add(io, allocator, our_dir, &[_][]const u8{"file.txt"});
    const sha1 = try commit(io, allocator, our_dir, "First commit");
    allocator.free(sha1);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content2" });
    try add(io, allocator, our_dir, &[_][]const u8{"file.txt"});
    const sha2 = try commit(io, allocator, our_dir, "Second commit");
    allocator.free(sha2);

    try cwd.writeFile(io, .{ .sub_path = test_file_path, .data = "content3" });
    try add(io, allocator, our_dir, &[_][]const u8{"file.txt"});
    const sha3 = try commit(io, allocator, our_dir, "Third commit");
    allocator.free(sha3);

    const our_log = try log(io, allocator, our_dir, null);
    defer {
        for (our_log) |entry| {
            allocator.free(entry.sha);
            allocator.free(entry.abbreviated_sha);
            allocator.free(entry.tree);
            if (entry.parent) |p| allocator.free(p);
            allocator.free(entry.author);
            allocator.free(entry.author_email);
            allocator.free(entry.committer);
            allocator.free(entry.message);
        }
        allocator.free(our_log);
    }

    // Should have 3 commits
    try std.testing.expectEqual(@as(usize, 3), our_log.len);

    // Should show commits in reverse chronological order
    try std.testing.expectEqualStrings("Third commit", our_log[0].message);
    try std.testing.expectEqualStrings("Second commit", our_log[1].message);
    try std.testing.expectEqualStrings("First commit", our_log[2].message);

    // Verify parent relationships
    try std.testing.expect(our_log[0].parent != null);
    try std.testing.expect(our_log[1].parent != null);
    try std.testing.expect(our_log[2].parent == null);

    // Verify git log shows same order
    const git_log_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "log", "--oneline" },
        .cwd = .{ .path = our_dir },
    });
    defer {
        allocator.free(git_log_result.stdout);
        allocator.free(git_log_result.stderr);
    }

    switch (git_log_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("git log failed with exit code {d}. stderr: {s}\n", .{ code, git_log_result.stderr });
            }
            try std.testing.expectEqual(@as(u32, 0), code);
        },
        .signal => |sig| {
            std.debug.print("git log killed by signal {d}. stderr: {s}\n", .{ sig, git_log_result.stderr });
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    try std.testing.expect(std.mem.indexOf(u8, git_log_result.stdout, "Third commit") != null);
    try std.testing.expect(std.mem.indexOf(u8, git_log_result.stdout, "Second commit") != null);
    try std.testing.expect(std.mem.indexOf(u8, git_log_result.stdout, "First commit") != null);
}

test "should create repo structure like git clone" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    // Create a bare remote repository using real git
    const base_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-clone-base" });
    defer allocator.free(base_dir);

    const cwd = std.Io.Dir.cwd();

    try cwd.createDirPath(io, base_dir);
    defer cwd.deleteTree(io, base_dir) catch {};

    const remote_dir = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, "remote.git" });
    defer allocator.free(remote_dir);

    // Create the remote directory first, then run git init --bare inside it
    try cwd.createDirPath(io, remote_dir);

    const bare_init_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init", "--bare" },
        .cwd = .{ .path = remote_dir },
    });
    defer {
        allocator.free(bare_init_result.stdout);
        allocator.free(bare_init_result.stderr);
    }

    switch (bare_init_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git init --bare killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    // Create initial content in the remote using a temporary clone
    const temp_clone = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, "temp-clone" });
    defer allocator.free(temp_clone);

    const clone_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "clone", remote_dir, "temp-clone" },
        .cwd = .{ .path = base_dir },
    });
    defer {
        allocator.free(clone_result.stdout);
        allocator.free(clone_result.stderr);
    }

    switch (clone_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git clone killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const readme_path = try std.fs.path.join(allocator, &[_][]const u8{ temp_clone, "README.md" });
    defer allocator.free(readme_path);

    try cwd.writeFile(io, .{ .sub_path = readme_path, .data = "# Initial" });

    const add_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "add", "." },
        .cwd = .{ .path = temp_clone },
    });
    defer {
        allocator.free(add_result.stdout);
        allocator.free(add_result.stderr);
    }

    switch (add_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git add killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const commit_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "commit", "-m", "Initial commit" },
        .cwd = .{ .path = temp_clone },
    });
    defer {
        allocator.free(commit_result.stdout);
        allocator.free(commit_result.stderr);
    }

    switch (commit_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git commit killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const push_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "push", "origin", "main" },
        .cwd = .{ .path = temp_clone },
    });
    defer {
        allocator.free(push_result.stdout);
        allocator.free(push_result.stderr);
    }

    switch (push_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git push killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    // Clean up temp clone
    try cwd.deleteTree(io, temp_clone);

    // Now test our clone implementation
    const our_clone = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, "our-clone" });
    defer allocator.free(our_clone);

    const result_path = try clone(io, allocator, remote_dir, our_clone, null);
    defer allocator.free(result_path);

    // Verify our clone exists with proper structure
    const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ our_clone, ".git" });
    defer allocator.free(git_dir_path);

    const git_dir = try cwd.openDir(io, git_dir_path, .{});
    defer git_dir.close(io);

    const objects_dir = try git_dir.openDir(io, "objects", .{});
    defer objects_dir.close(io);

    const refs_dir = try git_dir.openDir(io, "refs", .{});
    defer refs_dir.close(io);

    const heads_dir = try refs_dir.openDir(io, "heads", .{});
    defer heads_dir.close(io);

    // Verify remote is configured
    const config = try git_dir.readFileAlloc(io, "config", allocator, .unlimited);
    defer allocator.free(config);

    try std.testing.expect(std.mem.indexOf(u8, config, "[remote \"origin\"]") != null);
    try std.testing.expect(std.mem.indexOf(u8, config, remote_dir) != null);

    // Compare with git clone output
    const their_clone = try std.fs.path.join(allocator, &[_][]const u8{ base_dir, "their-clone" });
    defer allocator.free(their_clone);

    const git_clone_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "clone", remote_dir, "their-clone" },
        .cwd = .{ .path = base_dir },
    });
    defer {
        allocator.free(git_clone_result.stdout);
        allocator.free(git_clone_result.stderr);
    }

    switch (git_clone_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git clone killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    // Verify git clone succeeded
    try std.testing.expect(std.mem.indexOf(u8, git_clone_result.stderr, "Cloning into") != null);

    // Clean up git clone
    try cwd.deleteTree(io, their_clone);
}

test "should create same directory structure as git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-init-ours" });
    defer allocator.free(our_dir);

    const their_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-init-theirs" });
    defer allocator.free(their_dir);

    const cwd = std.Io.Dir.cwd();

    // Our implementation
    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    // Real git
    try cwd.createDirPath(io, their_dir);
    defer cwd.deleteTree(io, their_dir) catch {};

    const init_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(init_result.stdout);
        allocator.free(init_result.stderr);
    }

    switch (init_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git init killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const our_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, ".git" });
    defer allocator.free(our_git_dir);

    const their_git_dir = try std.fs.path.join(allocator, &[_][]const u8{ their_dir, ".git" });
    defer allocator.free(their_git_dir);

    // Both should have .git directory
    const our_git = try cwd.openDir(io, our_git_dir, .{});
    defer our_git.close(io);

    const their_git = try cwd.openDir(io, their_git_dir, .{});
    defer their_git.close(io);

    // Both should have objects directory
    const our_objects = try our_git.openDir(io, "objects", .{});
    defer our_objects.close(io);

    const their_objects = try their_git.openDir(io, "objects", .{});
    defer their_objects.close(io);

    // Both should have refs/heads directory
    var our_refs = try our_git.openDir(io, "refs", .{});
    defer our_refs.close(io);

    var their_refs = try their_git.openDir(io, "refs", .{});
    defer their_refs.close(io);

    _ = try our_refs.openDir(io, "heads", .{});
    _ = try their_refs.openDir(io, "heads", .{});

    // Both should have refs/tags directory
    _ = try our_refs.openDir(io, "tags", .{});
    _ = try their_refs.openDir(io, "tags", .{});
}

test "should create HEAD pointing to same ref format as git init" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const our_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-head-ours" });
    defer allocator.free(our_dir);

    const their_dir = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", "gitologist-compat-head-theirs" });
    defer allocator.free(their_dir);

    const cwd = std.Io.Dir.cwd();

    // Our implementation
    try cwd.createDirPath(io, our_dir);
    defer cwd.deleteTree(io, our_dir) catch {};

    try init(io, allocator, our_dir);

    // Real git
    try cwd.createDirPath(io, their_dir);
    defer cwd.deleteTree(io, their_dir) catch {};

    const init_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "git", "init" },
        .cwd = .{ .path = their_dir },
    });
    defer {
        allocator.free(init_result.stdout);
        allocator.free(init_result.stderr);
    }

    switch (init_result.term) {
        .exited => |code| try std.testing.expectEqual(@as(u32, 0), code),
        .signal => |sig| {
            std.debug.print("git init killed by signal {d}\n", .{sig});
            return error.ProcessSignaled;
        },
        else => unreachable,
    }

    const our_head_path = try std.fs.path.join(allocator, &[_][]const u8{ our_dir, ".git", "HEAD" });
    defer allocator.free(our_head_path);

    const their_head_path = try std.fs.path.join(allocator, &[_][]const u8{ their_dir, ".git", "HEAD" });
    defer allocator.free(their_head_path);

    const our_head = try cwd.readFileAlloc(io, our_head_path, allocator, .unlimited);
    defer allocator.free(our_head);

    const their_head = try cwd.readFileAlloc(io, their_head_path, allocator, .unlimited);
    defer allocator.free(their_head);

    // Both should point to a branch (usually main or master)
    try std.testing.expect(std.mem.startsWith(u8, our_head, "ref: refs/heads/"));
    try std.testing.expect(std.mem.startsWith(u8, their_head, "ref: refs/heads/"));
}
