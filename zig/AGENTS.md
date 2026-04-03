# Zig Implementation - Agent Guidelines

## Testing

Run tests with:

```bash
zig build test
```

**Note:** If the command produces no output, all tests passed successfully. Zig's test runner only outputs information when tests fail or when there are memory leaks.

## Important API Changes in Current Zig Version

### ArrayList

The `std.ArrayList(T)` API has changed:

- **Initialization**: Use `std.ArrayList(T).initCapacity(allocator, 0)` instead of `.init(allocator)`
- **Deinitialization**: Use `list.deinit(allocator)` - the allocator is now passed as a parameter
- **Appending**: Use `list.append(allocator, item)` - the allocator is now passed as a parameter

Example:

```zig
var entries = std.ArrayList(std.Io.Dir.Entry).initCapacity(allocator, 0) catch unreachable;
defer entries.deinit(allocator);
try entries.append(allocator, entry);
```

### Directory Iteration

The `std.Io.Dir` API uses `.iterate()` to get an iterator:

```zig
var it = dir.iterate();
while (try it.next(io)) |entry| {
    // process entry
}
```

Note: There is no `readdirAlloc` method. Use the iterator pattern with `ArrayList` to collect entries.

### Process Running

The `std.process.run` function uses a union for the `cwd` parameter:

```zig
const result = try std.process.run(allocator, io, .{
    .argv = &[_][]const u8{ "git", "init" },
    .cwd = .{ .path = "/some/path" },  // Note: .{ .path = ... } wrapper
});
defer {
    allocator.free(result.stdout);
    allocator.free(result.stderr);
}
```

### Path Joining and Memory Management

Always free paths created with `std.fs.path.join`:

```zig
const path = try std.fs.path.join(allocator, &[_][]const u8{ base, ".git" });
defer allocator.free(path);
const dir = try cwd.openDir(io, path, .{});
```

**Common leak pattern to avoid:**

```zig
// DON'T DO THIS - leaks memory
const dir = try cwd.openDir(io, try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" }), .{});

// DO THIS INSTEAD
const git_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ path, ".git" });
defer allocator.free(git_dir_path);
const dir = try cwd.openDir(io, git_dir_path, .{});
```

## Project Structure

- `build.zig` - Build configuration
- `src/` - Source code
  - `main.zig` - CLI entry point
  - `root.zig` - Library root module
  - `init.zig` - Git init implementation
  - `types/` - Type definitions
- `tests/` - Test files
  - `all_tests.zig` - Test suite aggregator
  - `init_test.zig` - Unit tests for init
  - `init_compat_test.zig` - Compatibility tests with official git

## Build Commands

```bash
zig build              # Build the project
zig build run          # Run the executable
zig build test         # Run all tests
```
