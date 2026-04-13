const std = @import("std");

const utils = @import("utils.zig");
const packfile = @import("packfile.zig");

pub fn enumerateObjects(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8, sha: []const u8, visited: *std.StringHashMap(void)) !std.ArrayList(packfile.PackObject) {
    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    if (visited.get(sha) != null) {
        return objects;
    }

    try visited.put(sha, {});

    const object_data = try utils.readObject(io, allocator, git_dir_path, sha);
    defer allocator.free(object_data);

    const header_end = std.mem.indexOfScalar(u8, object_data, '\n') orelse return objects;
    const header = object_data[0..header_end];

    const space_idx = std.mem.indexOfScalar(u8, header, ' ') orelse return objects;
    const obj_type = header[0..space_idx];

    const content = object_data[header_end + 1 ..];

    try objects.append(allocator, .{
        .obj_type = try allocator.dupe(u8, obj_type),
        .sha = try allocator.dupe(u8, sha),
        .content = try allocator.dupe(u8, content),
    });

    if (std.mem.eql(u8, obj_type, "commit")) {
        var lines = std.mem.splitScalar(u8, content, '\n');

        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "parent ")) {
                const parent_sha = line["parent ".len..];
                const parent_objects = try enumerateObjects(io, allocator, git_dir_path, parent_sha, visited);
                for (parent_objects.items) |obj| {
                    try objects.append(allocator, .{
                        .obj_type = try allocator.dupe(u8, obj.obj_type),
                        .sha = try allocator.dupe(u8, obj.sha),
                        .content = try allocator.dupe(u8, obj.content),
                    });
                }
            } else if (std.mem.startsWith(u8, line, "tree ")) {
                const tree_sha = line["tree ".len..];
                const tree_objects = try enumerateObjects(io, allocator, git_dir_path, tree_sha, visited);
                for (tree_objects.items) |obj| {
                    try objects.append(allocator, .{
                        .obj_type = try allocator.dupe(u8, obj.obj_type),
                        .sha = try allocator.dupe(u8, obj.sha),
                        .content = try allocator.dupe(u8, obj.content),
                    });
                }
            }
        }
    } else if (std.mem.eql(u8, obj_type, "tree")) {
        var entries = try utils.parseTreeEntries(allocator, object_data);
        defer {
            for (entries.items) |entry| {
                allocator.free(entry.path);
                allocator.free(entry.sha);
                allocator.free(entry.mode);
                allocator.free(entry.entry_type);
            }
            entries.deinit(allocator);
        }

        for (entries.items) |entry| {
            const entry_objects = try enumerateObjects(io, allocator, git_dir_path, entry.sha, visited);
            for (entry_objects.items) |obj| {
                try objects.append(allocator, .{
                    .obj_type = try allocator.dupe(u8, obj.obj_type),
                    .sha = try allocator.dupe(u8, obj.sha),
                    .content = try allocator.dupe(u8, obj.content),
                });
            }
        }
    }

    return objects;
}

pub fn getAllObjects(io: std.Io, allocator: std.mem.Allocator, git_dir_path: []const u8) !std.ArrayList(packfile.PackObject) {
    var objects = std.ArrayList(packfile.PackObject).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const objects_dir_path = try std.fs.path.join(allocator, &[_][]const u8{ git_dir_path, "objects" });
    defer allocator.free(objects_dir_path);

    const cwd = std.Io.Dir.cwd();
    const objects_dir = cwd.openDir(io, objects_dir_path, .{}) catch return objects;
    defer objects_dir.close(io);

    var it = objects_dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (entry.name.len != 2) continue;

        const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ objects_dir_path, entry.name });
        defer allocator.free(dir_path);

        const subdir = cwd.openDir(io, dir_path, .{}) catch continue;
        defer subdir.close(io);

        var sub_it = subdir.iterate();
        while (try sub_it.next(io)) |file| {
            if (file.kind != .file) continue;

            const sha = try std.fmt.allocPrint(allocator, "{s}{s}", .{ entry.name, file.name });

            const object_data = utils.readObject(io, allocator, git_dir_path, sha) catch {
                allocator.free(sha);
                continue;
            };
            defer allocator.free(object_data);

            const header_end = std.mem.indexOfScalar(u8, object_data, '\n') orelse {
                allocator.free(sha);
                continue;
            };
            const header = object_data[0..header_end];

            const space_idx = std.mem.indexOfScalar(u8, header, ' ') orelse {
                allocator.free(sha);
                continue;
            };
            const obj_type = header[0..space_idx];

            const content = object_data[header_end + 1 ..];

            try objects.append(allocator, .{
                .obj_type = try allocator.dupe(u8, obj_type),
                .sha = sha,
                .content = try allocator.dupe(u8, content),
            });
        }
    }

    return objects;
}
