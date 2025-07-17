const std = @import("std");
const encoder = @import("encoder.zig");
const testing = std.testing;

const COPY_TAG: u8 = 0x01;
const INSERT_COPY_TAG: u8 = 0x02;
const INSERT_DATA_TAG: u8 = 0x03;

pub fn encode(
    comptime T: type,
    source: []const T,
    target: []const T,
    allocator: std.mem.Allocator,
) ![]const T {
    var dpatch_encoder = try encoder.DPatchEncoder(T).init(source, target, allocator);
    defer dpatch_encoder.deinit();
    var patch = std.ArrayList(u8).init(allocator);
    defer patch.deinit();
    var writer = patch.writer();

    while (try dpatch_encoder.next()) |delta| {
        switch (delta) {
            .insert => |instruction| {
                switch (instruction) {
                    .data => |data| {
                        try writer.writeByte(INSERT_DATA_TAG);
                        try std.leb.writeUleb128(writer, data.len);
                        try writer.writeAll(data);
                    },
                    .copy => |details| {
                        try writer.writeByte(INSERT_COPY_TAG);
                        try std.leb.writeUleb128(writer, details.start);
                        try std.leb.writeUleb128(writer, details.len);
                    },
                }
            },
            .copy => |details| {
                try writer.writeByte(COPY_TAG);
                try std.leb.writeUleb128(writer, details.start);
                try std.leb.writeUleb128(writer, details.len);
            },
        }
    }
    return try patch.toOwnedSlice();
}

pub fn decode(
    comptime T: type,
    source: []const T,
    patch: []const u8,
    allocator: std.mem.Allocator,
) ![]const T {
    var target = std.ArrayList(T).init(allocator);
    defer target.deinit();

    var insert_buffer = std.ArrayList(T).init(allocator);
    defer insert_buffer.deinit();

    var stream = std.io.fixedBufferStream(patch);
    const reader = stream.reader();

    while (stream.pos < stream.buffer.len) {
        const tag = try reader.readByte();
        switch (tag) {
            COPY_TAG => {
                const start: usize = try std.leb.readUleb128(usize, reader);
                const len: usize = try std.leb.readUleb128(usize, reader);
                try target.appendSlice(source[start .. start + len]);
            },
            INSERT_COPY_TAG => {
                const start: usize = try std.leb.readUleb128(usize, reader);
                const len: usize = try std.leb.readUleb128(usize, reader);
                const data = insert_buffer.items[start .. start + len];
                try target.appendSlice(data);
                try insert_buffer.appendSlice(data);
            },
            INSERT_DATA_TAG => {
                const len: usize = try std.leb.readUleb128(usize, reader);
                const data = try allocator.alloc(T, len);
                defer allocator.free(data);
                _ = try reader.readAll(data);

                try target.appendSlice(data);
                try insert_buffer.appendSlice(data);
            },
            else => return error.InvalidPatchFormat,
        }
    }

    return target.toOwnedSlice();
}

test "encode and decode" {
    const allocator = testing.allocator;
    const source = "aaacccbbb";
    const target = "xxxaaaxxxbbb";
    const patch = try encode(u8, source, target, allocator);
    defer allocator.free(patch);
    const decoded = try decode(u8, source, patch, allocator);
    defer allocator.free(decoded);
    try std.testing.expectEqualStrings(target, decoded);
}
