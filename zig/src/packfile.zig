const std = @import("std");

pub const PackObject = struct {
    obj_type: []const u8,
    sha: []const u8,
    content: []const u8,
};

const PackEntryKind = enum {
    object,
    ofs_delta,
    ref_delta,
};

const PackEntryType = union(PackEntryKind) {
    object: []const u8,
    ofs_delta: usize,
    ref_delta: [40]u8,
};

const RawPackEntry = struct {
    entry_type: PackEntryType,
    content: []const u8,
    pack_offset: usize,
};

const PackEntryTypeResult = struct {
    entry_type: PackEntryType,
    data_offset: usize,
};

pub fn encodePktLine(allocator: std.mem.Allocator, line: ?[]const u8) ![]const u8 {
    if (line == null) {
        return try allocator.dupe(u8, "0000");
    }

    const length = line.?.len + 4;
    const hex_length = try std.fmt.allocPrint(allocator, "{x:0>4}", .{length});
    defer allocator.free(hex_length);

    if (length == 4) {
        return try allocator.dupe(u8, hex_length);
    }

    const result = try allocator.alloc(u8, hex_length.len + line.?.len);
    @memcpy(result[0..hex_length.len], hex_length);
    @memcpy(result[hex_length.len..], line.?);

    return result;
}

pub fn decodePktLines(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList([]const u8) {
    var lines = std.ArrayList([]const u8).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (lines.items) |line| allocator.free(line);
        lines.deinit(allocator);
    }

    var offset: usize = 0;

    while (offset < data.len) {
        if (offset + 4 > data.len) {
            break;
        }

        const hex_length = data[offset .. offset + 4];
        if (std.mem.eql(u8, hex_length, "0000")) {
            const empty_line = try allocator.dupe(u8, "");
            try lines.append(allocator, empty_line);
            offset += 4;
            continue;
        }

        const length = std.fmt.parseUnsigned(usize, hex_length, 16) catch break;
        if (length == 0 or length > data.len - offset) {
            break;
        }

        const line_data = data[offset + 4 .. offset + length];
        const line = try allocator.dupe(u8, line_data);
        try lines.append(allocator, line);

        offset += length;
    }

    return lines;
}

pub fn parsePackfile(allocator: std.mem.Allocator, data: []const u8) !std.ArrayList(PackObject) {
    var objects = std.ArrayList(PackObject).initCapacity(allocator, 0) catch unreachable;
    errdefer {
        for (objects.items) |obj| {
            allocator.free(obj.obj_type);
            allocator.free(obj.sha);
            allocator.free(obj.content);
        }
        objects.deinit(allocator);
    }

    const signature = data[0..4];
    if (!std.mem.eql(u8, signature, "PACK")) {
        return error.InvalidPackfileSignature;
    }

    const version = std.mem.readInt(u32, data[4..8], .big);
    if (version != 2) {
        return error.UnsupportedPackfileVersion;
    }

    const num_objects = std.mem.readInt(u32, data[8..12], .big);

    const data_without_checksum = data[0 .. data.len - 20];

    var raw_entries = std.ArrayList(RawPackEntry).initCapacity(allocator, 0) catch unreachable;
    defer {
        for (raw_entries.items) |entry| {
            allocator.free(entry.content);
        }
        raw_entries.deinit(allocator);
    }

    var offset_to_index = std.AutoHashMap(usize, usize).init(allocator);
    defer offset_to_index.deinit();

    var offset: usize = 12;

    for (0..num_objects) |_| {
        if (offset >= data_without_checksum.len) {
            return error.InvalidPackfileSignature;
        }

        const header_result = try parseObjectHeader(data_without_checksum, offset);
        const entry_result = parsePackEntryType(header_result.type, data_without_checksum, header_result.new_offset) orelse
            return error.UnknownObjectType;

        const decompress_result = try decompressStreamData(allocator, data_without_checksum, entry_result.data_offset);

        try raw_entries.append(allocator, .{
            .entry_type = entry_result.entry_type,
            .content = decompress_result.decompressed,
            .pack_offset = offset,
        });
        try offset_to_index.put(offset, raw_entries.items.len - 1);
        offset = entry_result.data_offset + decompress_result.bytes_consumed;
    }

    const Resolved = struct { content: []const u8, obj_type: []const u8 };
    var resolved = std.AutoHashMap(usize, Resolved).init(allocator);
    defer {
        var it = resolved.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.content);
            allocator.free(entry.value_ptr.obj_type);
        }
        resolved.deinit();
    }

    const Resolver = struct {
        fn resolve(
            idx: usize,
            entries: []const RawPackEntry,
            off_map: *const std.AutoHashMap(usize, usize),
            res_map: *std.AutoHashMap(usize, Resolved),
            alloc: std.mem.Allocator,
        ) anyerror!Resolved {
            if (res_map.get(idx)) |cached| {
                return .{
                    .content = try alloc.dupe(u8, cached.content),
                    .obj_type = try alloc.dupe(u8, cached.obj_type),
                };
            }
            const entry = entries[idx];
            switch (entry.entry_type) {
                .object => |t| {
                    return .{
                        .content = try alloc.dupe(u8, entry.content),
                        .obj_type = try alloc.dupe(u8, t),
                    };
                },
                .ofs_delta => |neg_offset| {
                    const base_pack_offset = entry.pack_offset - neg_offset;
                    const base_index = off_map.get(base_pack_offset) orelse return error.InvalidPackfileSignature;
                    const base = try resolve(base_index, entries, off_map, res_map, alloc);
                    defer {
                        alloc.free(base.content);
                        alloc.free(base.obj_type);
                    }
                    const delta_content = try applyDelta(alloc, base.content, entry.content);
                    const obj_t = try alloc.dupe(u8, base.obj_type);
                    try res_map.put(idx, .{
                        .content = try alloc.dupe(u8, delta_content),
                        .obj_type = try alloc.dupe(u8, obj_t),
                    });
                    return .{ .content = delta_content, .obj_type = obj_t };
                },
                .ref_delta => |base_sha| {
                    var base_index: ?usize = null;
                    for (entries, 0..) |raw, j| {
                        if (raw.entry_type != .object) continue;
                        const obj_t = raw.entry_type.object;
                        var header_buf: [64]u8 = undefined;
                        const header = std.fmt.bufPrint(&header_buf, "{s} {d}\x00", .{ obj_t, raw.content.len }) catch unreachable;
                        var hasher = std.crypto.hash.Sha1.init(.{});
                        hasher.update(header);
                        hasher.update(raw.content);
                        var hash: [20]u8 = undefined;
                        hasher.final(&hash);
                        var hex: [40]u8 = undefined;
                        const hex_digits = "0123456789abcdef";
                        for (0..20) |i| {
                            hex[2 * i] = hex_digits[hash[i] >> 4];
                            hex[2 * i + 1] = hex_digits[hash[i] & 0x0f];
                        }
                        if (std.mem.eql(u8, &hex, &base_sha)) {
                            base_index = j;
                            break;
                        }
                    }
                    const bi = base_index orelse return error.InvalidPackfileSignature;
                    const base = try resolve(bi, entries, off_map, res_map, alloc);
                    defer {
                        alloc.free(base.content);
                        alloc.free(base.obj_type);
                    }
                    const delta_content = try applyDelta(alloc, base.content, entry.content);
                    const obj_t = try alloc.dupe(u8, base.obj_type);
                    try res_map.put(idx, .{
                        .content = try alloc.dupe(u8, delta_content),
                        .obj_type = try alloc.dupe(u8, obj_t),
                    });
                    return .{ .content = delta_content, .obj_type = obj_t };
                },
            }
        }
    };

    for (raw_entries.items, 0..) |entry, i| {
        var content: []const u8 = undefined;
        var object_type: []const u8 = undefined;
        var needs_free = false;

        switch (entry.entry_type) {
            .object => |t| {
                object_type = t;
                content = entry.content;
            },
            .ofs_delta, .ref_delta => {
                const res = try Resolver.resolve(i, raw_entries.items, &offset_to_index, &resolved, allocator);
                object_type = res.obj_type;
                content = res.content;
                needs_free = true;
            },
        }

        const object_header = try std.fmt.allocPrint(allocator, "{s} {d}\x00", .{ object_type, content.len });
        defer allocator.free(object_header);

        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(object_header);
        hasher.update(content);
        var hash: [20]u8 = undefined;
        hasher.final(&hash);

        const sha = try allocator.alloc(u8, 40);
        const hex_digits = "0123456789abcdef";
        for (0..20) |j| {
            sha[2 * j] = hex_digits[hash[j] >> 4];
            sha[2 * j + 1] = hex_digits[hash[j] & 0x0f];
        }

        try objects.append(allocator, .{
            .obj_type = try allocator.dupe(u8, object_type),
            .sha = sha,
            .content = try allocator.dupe(u8, content),
        });

        if (needs_free) {
            allocator.free(content);
            allocator.free(object_type);
        }
    }

    return objects;
}

const ObjectHeader = struct {
    type: usize,
    size: usize,
    new_offset: usize,
};

fn parseObjectHeader(data: []const u8, offset: usize) !ObjectHeader {
    const byte = data[offset];
    const type_num = (byte >> 4) & 0x07;
    var size: usize = byte & 0x0f;
    var shift: usize = 4;
    var current_offset: usize = offset + 1;

    while ((byte & 0x80) != 0) {
        const next_byte = data[current_offset];
        size |= @as(usize, next_byte & 0x7f) << @intCast(shift);
        shift += 7;
        current_offset += 1;

        if ((next_byte & 0x80) == 0) {
            break;
        }
    }

    return ObjectHeader{
        .type = type_num,
        .size = size,
        .new_offset = current_offset,
    };
}

fn parsePackEntryType(type_num: usize, data: []const u8, offset: usize) ?PackEntryTypeResult {
    return switch (type_num) {
        1 => PackEntryTypeResult{ .entry_type = .{ .object = "commit" }, .data_offset = offset },
        2 => PackEntryTypeResult{ .entry_type = .{ .object = "tree" }, .data_offset = offset },
        3 => PackEntryTypeResult{ .entry_type = .{ .object = "blob" }, .data_offset = offset },
        4 => PackEntryTypeResult{ .entry_type = .{ .object = "tag" }, .data_offset = offset },
        6 => blk: {
            var off = offset;
            var byte = data[off];
            off += 1;
            var neg_offset: usize = byte & 0x7f;
            while ((byte & 0x80) != 0) {
                byte = data[off];
                off += 1;
                neg_offset = ((neg_offset + 1) << 7) | (byte & 0x7f);
            }
            break :blk PackEntryTypeResult{ .entry_type = .{ .ofs_delta = neg_offset }, .data_offset = off };
        },
        7 => blk: {
            if (offset + 20 > data.len) break :blk null;
            const sha_bytes = data[offset..][0..20];
            var hex: [40]u8 = undefined;
            const hex_digits = "0123456789abcdef";
            for (0..20) |i| {
                hex[2 * i] = hex_digits[sha_bytes[i] >> 4];
                hex[2 * i + 1] = hex_digits[sha_bytes[i] & 0x0f];
            }
            break :blk PackEntryTypeResult{ .entry_type = .{ .ref_delta = hex }, .data_offset = offset + 20 };
        },
        else => null,
    };
}

const DecompressResult = struct {
    decompressed: []const u8,
    bytes_consumed: usize,
};

fn decompressStreamData(allocator: std.mem.Allocator, data: []const u8, offset: usize) !DecompressResult {
    const flate = std.compress.flate;

    var reader = std.Io.Reader.fixed(data[offset..]);
    var flate_buffer: [flate.max_window_len]u8 = undefined;
    var decompress = flate.Decompress.init(&reader, .zlib, &flate_buffer);
    var writer: std.Io.Writer.Allocating = .init(allocator);
    defer writer.deinit();
    _ = try decompress.reader.streamRemaining(&writer.writer);

    const inflated = try writer.toOwnedSlice();

    const remaining = data[offset..];
    var lo: usize = 1;
    var hi: usize = remaining.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        var test_reader = std.Io.Reader.fixed(remaining[0..mid]);
        var test_flate_buffer: [flate.max_window_len]u8 = undefined;
        var test_decompress = flate.Decompress.init(&test_reader, .zlib, &test_flate_buffer);
        var test_writer: std.Io.Writer.Allocating = .init(allocator);
        defer test_writer.deinit();

        if (test_decompress.reader.streamRemaining(&test_writer.writer)) |_| {
            const test_inflated = try test_writer.toOwnedSlice();
            defer allocator.free(test_inflated);
            if (test_inflated.len == inflated.len and std.mem.eql(u8, test_inflated, inflated)) {
                hi = mid;
            } else {
                lo = mid + 1;
            }
        } else |_| {
            lo = mid + 1;
        }
    }

    return DecompressResult{
        .decompressed = inflated,
        .bytes_consumed = lo,
    };
}

pub fn getObjectType(type_num: usize) ![]const u8 {
    return switch (type_num) {
        1 => "commit",
        2 => "tree",
        3 => "blob",
        4 => "tag",
        else => error.UnknownObjectType,
    };
}

fn getTypeNumber(obj_type: []const u8) !usize {
    if (std.mem.eql(u8, obj_type, "commit")) return 1;
    if (std.mem.eql(u8, obj_type, "tree")) return 2;
    if (std.mem.eql(u8, obj_type, "blob")) return 3;
    if (std.mem.eql(u8, obj_type, "tag")) return 4;
    return error.UnknownObjectType;
}

fn applyDelta(allocator: std.mem.Allocator, base: []const u8, delta: []const u8) ![]const u8 {
    var delta_offset: usize = 0;

    const readSize = struct {
        fn read(d: []const u8, off: *usize) usize {
            var size: usize = 0;
            var shift: usize = 0;
            while (off.* < d.len) {
                const byte = d[off.*];
                off.* += 1;
                size |= @as(usize, byte & 0x7f) << @intCast(shift);
                shift += 7;
                if ((byte & 0x80) == 0) break;
            }
            return size;
        }
    }.read;

    _ = readSize(delta, &delta_offset);
    _ = readSize(delta, &delta_offset);

    var result = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    errdefer result.deinit(allocator);

    while (delta_offset < delta.len) {
        const cmd = delta[delta_offset];
        delta_offset += 1;

        if ((cmd & 0x80) != 0) {
            var copy_offset: usize = 0;
            var copy_size: usize = 0;

            if ((cmd & 0x01) != 0) {
                copy_offset = delta[delta_offset];
                delta_offset += 1;
            }
            if ((cmd & 0x02) != 0) {
                copy_offset |= @as(usize, delta[delta_offset]) << 8;
                delta_offset += 1;
            }
            if ((cmd & 0x04) != 0) {
                copy_offset |= @as(usize, delta[delta_offset]) << 16;
                delta_offset += 1;
            }
            if ((cmd & 0x08) != 0) {
                copy_offset |= @as(usize, delta[delta_offset]) << 24;
                delta_offset += 1;
            }

            if ((cmd & 0x10) != 0) {
                copy_size = delta[delta_offset];
                delta_offset += 1;
            }
            if ((cmd & 0x20) != 0) {
                copy_size |= @as(usize, delta[delta_offset]) << 8;
                delta_offset += 1;
            }
            if ((cmd & 0x40) != 0) {
                copy_size |= @as(usize, delta[delta_offset]) << 16;
                delta_offset += 1;
            }

            if (copy_size == 0) copy_size = 0x10000;

            try result.appendSlice(allocator, base[copy_offset..][0..copy_size]);
        } else if (cmd > 0) {
            try result.appendSlice(allocator, delta[delta_offset..][0..cmd]);
            delta_offset += cmd;
        }
    }

    return result.toOwnedSlice(allocator);
}

pub fn createPackfile(allocator: std.mem.Allocator, objects: std.ArrayList(PackObject)) ![]const u8 {
    var packfile = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    errdefer packfile.deinit(allocator);

    try packfile.appendSlice(allocator, "PACK");

    const version_bytes = std.mem.nativeToBig(u32, 2);
    try packfile.appendSlice(allocator, &@as([4]u8, @bitCast(version_bytes)));

    const num_objects_bytes = std.mem.nativeToBig(u32, @intCast(objects.items.len));
    try packfile.appendSlice(allocator, &@as([4]u8, @bitCast(num_objects_bytes)));

    for (objects.items) |obj| {
        const type_num = try getTypeNumber(obj.obj_type);
        const header = try encodeObjectHeader(allocator, type_num, obj.content.len);
        defer allocator.free(header);

        const flate = std.compress.flate;
        var compressed = std.ArrayList(u8).initCapacity(allocator, 128) catch unreachable;

        var compressed_writer = std.Io.Writer.Allocating.fromArrayList(allocator, &compressed);
        defer compressed_writer.deinit();

        var flate_buffer: [flate.max_window_len]u8 = undefined;
        var compress = try flate.Compress.init(&compressed_writer.writer, &flate_buffer, .zlib, .default);
        try compress.writer.writeAll(obj.content);
        try compress.writer.flush();
        try compress.finish();
        try compressed_writer.writer.flush();

        var final_compressed = compressed_writer.toArrayList();
        defer final_compressed.deinit(allocator);

        try packfile.appendSlice(allocator, header);
        try packfile.appendSlice(allocator, final_compressed.items);
    }

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(packfile.items);
    var checksum: [20]u8 = undefined;
    hasher.final(&checksum);

    try packfile.appendSlice(allocator, &checksum);

    return packfile.toOwnedSlice(allocator);
}

pub fn encodeObjectHeader(allocator: std.mem.Allocator, type_num: usize, size: usize) ![]const u8 {
    var bytes = std.ArrayList(u8).initCapacity(allocator, 0) catch unreachable;
    errdefer bytes.deinit(allocator);

    var byte: u8 = @intCast((type_num << 4) | (size & 0x0f));
    var size_remaining = size >> 4;

    while (size_remaining > 0) {
        try bytes.append(allocator, byte | 0x80);
        byte = @intCast(size_remaining & 0x7f);
        size_remaining >>= 7;
    }

    try bytes.append(allocator, byte);

    return bytes.toOwnedSlice(allocator);
}
