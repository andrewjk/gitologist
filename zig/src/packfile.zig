const std = @import("std");

pub const PackObject = struct {
    obj_type: []const u8,
    sha: []const u8,
    content: []const u8,
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

    // Exclude checksum (last 20 bytes) from parsing
    const data_without_checksum = data[0 .. data.len - 20];

    var offset: usize = 12;

    for (0..num_objects) |_| {
        if (offset >= data_without_checksum.len) {
            return error.InvalidPackfileSignature;
        }

        const header_result = try parseObjectHeader(data_without_checksum, offset);
        const obj_type_num = header_result.type;
        offset = header_result.new_offset;

        const decompress_result = try decompressStreamData(allocator, data_without_checksum, offset);
        const inflated = decompress_result.decompressed;
        const bytes_consumed = decompress_result.bytes_consumed;

        const object_type = try getObjectType(obj_type_num);
        const object_header = try std.fmt.allocPrint(allocator, "{s} {d}\x00", .{ object_type, inflated.len });
        defer allocator.free(object_header);

        var hasher = std.crypto.hash.Sha1.init(.{});
        hasher.update(object_header);
        hasher.update(inflated);

        var hash: [20]u8 = undefined;
        hasher.final(&hash);

        const sha = try allocator.alloc(u8, 40);
        const hex_digits = "0123456789abcdef";
        for (0..20) |i| {
            sha[2 * i] = hex_digits[hash[i] >> 4];
            sha[2 * i + 1] = hex_digits[hash[i] & 0x0f];
        }

        try objects.append(allocator, .{
            .obj_type = try allocator.dupe(u8, object_type),
            .sha = sha,
            .content = inflated,
        });

        offset += bytes_consumed;
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

    // In a true streaming implementation, we would track bytes consumed
    // For now, return the entire remaining data as consumed
    const bytes_consumed = data.len - offset;

    return DecompressResult{
        .decompressed = inflated,
        .bytes_consumed = bytes_consumed,
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

        // Compress content
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

    // Add checksum
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(packfile.items);
    var checksum: [20]u8 = undefined;
    hasher.final(&checksum);

    try packfile.appendSlice(allocator, &checksum);

    return packfile.toOwnedSlice(allocator);
}

fn encodeObjectHeader(allocator: std.mem.Allocator, type_num: usize, size: usize) ![]const u8 {
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
