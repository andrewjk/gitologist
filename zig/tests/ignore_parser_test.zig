const std = @import("std");

const IgnoreParser = @import("gitologist").IgnoreParser;
const IgnorePattern = @import("gitologist").IgnorePattern;
const init = @import("gitologist").init;
const add = @import("gitologist").add;
const addAll = @import("gitologist").addAll;
const status = @import("gitologist").status;

fn createTempDir(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const tmp_path = try std.fs.path.join(allocator, &[_][]const u8{ "/tmp", name });
    return tmp_path;
}

fn cleanupTempDir(io: std.Io, path: []const u8) void {
    const cwd = std.Io.Dir.cwd();
    cwd.deleteTree(io, path) catch {};
}

test "should ignore simple patterns" {
    const allocator = std.testing.allocator;

    var parser = IgnoreParser.init(allocator);
    defer parser.deinit();

    // Set up test patterns manually
    var patterns = std.StringArrayHashMap(std.ArrayList(IgnorePattern)).init(allocator);

    var pattern_list = std.ArrayList(IgnorePattern).initCapacity(allocator, 2) catch unreachable;
    try pattern_list.append(allocator, .{
        .pattern = try allocator.dupe(u8, "node_modules"),
        .is_negated = false,
        .is_directory_only = true,
        .path_prefix = try allocator.dupe(u8, "."),
    });
    try pattern_list.append(allocator, .{
        .pattern = try allocator.dupe(u8, "*.log"),
        .is_negated = false,
        .is_directory_only = false,
        .path_prefix = try allocator.dupe(u8, "."),
    });

    const key = try allocator.dupe(u8, ".");
    try patterns.put(key, pattern_list);

    parser.setPatternsForTesting(patterns);

    try std.testing.expect(parser.isIgnored("node_modules", true));
    try std.testing.expect(parser.isIgnored("app.log", false));
    try std.testing.expect(!parser.isIgnored("src/main.ts", false));
}

test "should handle negation patterns" {
    const allocator = std.testing.allocator;

    var parser = IgnoreParser.init(allocator);
    defer parser.deinit();

    var patterns = std.StringArrayHashMap(std.ArrayList(IgnorePattern)).init(allocator);

    var pattern_list = std.ArrayList(IgnorePattern).initCapacity(allocator, 2) catch unreachable;
    try pattern_list.append(allocator, .{
        .pattern = try allocator.dupe(u8, "*.log"),
        .is_negated = false,
        .is_directory_only = false,
        .path_prefix = try allocator.dupe(u8, "."),
    });
    try pattern_list.append(allocator, .{
        .pattern = try allocator.dupe(u8, "important.log"),
        .is_negated = true,
        .is_directory_only = false,
        .path_prefix = try allocator.dupe(u8, "."),
    });

    const key = try allocator.dupe(u8, ".");
    try patterns.put(key, pattern_list);

    parser.setPatternsForTesting(patterns);

    try std.testing.expect(parser.isIgnored("debug.log", false));
    try std.testing.expect(!parser.isIgnored("important.log", false));
}

test "should handle directory-only patterns" {
    const allocator = std.testing.allocator;

    var parser = IgnoreParser.init(allocator);
    defer parser.deinit();

    var patterns = std.StringArrayHashMap(std.ArrayList(IgnorePattern)).init(allocator);

    var pattern_list = std.ArrayList(IgnorePattern).initCapacity(allocator, 1) catch unreachable;
    try pattern_list.append(allocator, .{
        .pattern = try allocator.dupe(u8, "build"),
        .is_negated = false,
        .is_directory_only = true,
        .path_prefix = try allocator.dupe(u8, "."),
    });

    const key = try allocator.dupe(u8, ".");
    try patterns.put(key, pattern_list);

    parser.setPatternsForTesting(patterns);

    try std.testing.expect(parser.isIgnored("build", true));
    try std.testing.expect(!parser.isIgnored("build", false));
    try std.testing.expect(!parser.isIgnored("build/output.txt", false));
}

test "should load gitignore from repository" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitignore-load-test");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, tmp_path);

    // Create a .gitignore file
    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "node_modules/\n*.log\n.env\n" });

    var parser = IgnoreParser.init(allocator);
    defer parser.deinit();
    try parser.loadGitignore(io, tmp_path);

    try std.testing.expect(parser.isIgnored("node_modules", true));
    try std.testing.expect(parser.isIgnored("app.log", false));
    try std.testing.expect(parser.isIgnored(".env", false));
    try std.testing.expect(!parser.isIgnored("src/main.ts", false));
}

test "should respect gitignore in status command" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitignore-status-test");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    // Create files
    const main_ts_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "main.ts" });
    defer allocator.free(main_ts_path);
    try cwd.writeFile(io, .{ .sub_path = main_ts_path, .data = "console.log('hello');" });

    const debug_log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "debug.log" });
    defer allocator.free(debug_log_path);
    try cwd.writeFile(io, .{ .sub_path = debug_log_path, .data = "debug info" });

    const node_modules_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "node_modules" });
    defer allocator.free(node_modules_path);
    try cwd.createDirPath(io, node_modules_path);

    const package_json_path = try std.fs.path.join(allocator, &[_][]const u8{ node_modules_path, "package.json" });
    defer allocator.free(package_json_path);
    try cwd.writeFile(io, .{ .sub_path = package_json_path, .data = "{}" });

    // Create .gitignore
    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "node_modules/\n*.log\n" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    // Should only see main.ts, not debug.log or node_modules/
    var found_main = false;
    var found_debug = false;
    var found_node_modules = false;

    for (result.untracked) |file| {
        if (std.mem.eql(u8, file, "main.ts")) found_main = true;
        if (std.mem.eql(u8, file, "debug.log")) found_debug = true;
        if (std.mem.eql(u8, file, "node_modules/package.json")) found_node_modules = true;
    }

    try std.testing.expect(found_main);
    try std.testing.expect(!found_debug);
    try std.testing.expect(!found_node_modules);
}

test "should respect gitignore in addAll command" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitignore-addall-test");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    // Create files
    const main_ts_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "main.ts" });
    defer allocator.free(main_ts_path);
    try cwd.writeFile(io, .{ .sub_path = main_ts_path, .data = "console.log('hello');" });

    const debug_log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "debug.log" });
    defer allocator.free(debug_log_path);
    try cwd.writeFile(io, .{ .sub_path = debug_log_path, .data = "debug info" });

    // Create .gitignore
    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "*.log\n" });

    try addAll(io, allocator, tmp_path);

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    // Should have staged main.ts but not debug.log
    var found_main = false;
    var found_debug = false;

    for (result.staged) |file| {
        if (std.mem.eql(u8, file, "main.ts")) found_main = true;
        if (std.mem.eql(u8, file, "debug.log")) found_debug = true;
    }

    try std.testing.expect(found_main);
    try std.testing.expect(!found_debug);
}

test "should respect gitignore in add command for specific files" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const tmp_path = try createTempDir(allocator, "gitignore-add-specific-test");
    defer allocator.free(tmp_path);
    defer cleanupTempDir(io, tmp_path);

    try init(io, allocator, tmp_path);

    const cwd = std.Io.Dir.cwd();

    // Create files
    const main_ts_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "main.ts" });
    defer allocator.free(main_ts_path);
    try cwd.writeFile(io, .{ .sub_path = main_ts_path, .data = "console.log('hello');" });

    const debug_log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "debug.log" });
    defer allocator.free(debug_log_path);
    try cwd.writeFile(io, .{ .sub_path = debug_log_path, .data = "debug info" });

    // Create .gitignore
    const gitignore_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, ".gitignore" });
    defer allocator.free(gitignore_path);
    try cwd.writeFile(io, .{ .sub_path = gitignore_path, .data = "*.log\n" });

    // Try to add both files
    try add(io, allocator, tmp_path, &[_][]const u8{ "main.ts", "debug.log" });

    const result = try status(io, allocator, tmp_path);
    defer result.deinit(allocator);

    // Should have staged main.ts but not debug.log
    var found_main = false;
    var found_debug = false;

    for (result.staged) |file| {
        if (std.mem.eql(u8, file, "main.ts")) found_main = true;
        if (std.mem.eql(u8, file, "debug.log")) found_debug = true;
    }

    try std.testing.expect(found_main);
    try std.testing.expect(!found_debug);
}
