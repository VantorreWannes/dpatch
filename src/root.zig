const std = @import("std");
const encoder = @import("encoder.zig");
const testing = std.testing;

const COPY_TAG: u8 = 0x01;
const INSERT_COPY_TAG: u8 = 0x02;
const INSERT_DATA_TAG: u8 = 0x03;

/// Encodes the difference between a source and a target sequence into a patch.
///
/// This function computes the longest common subsequence (LCS) between the source and target
/// sequences to generate a compact patch. The patch can then be used with the `decode`
/// function to reconstruct the target from the source.
///
/// # Parameters
///
/// - `T`: The type of elements in the sequences.
/// - `source`: The original sequence of data.
/// - `target`: The new sequence of data.
/// - `allocator`: An allocator for managing memory for the patch and intermediate data structures.
///
/// # Returns
///
/// A `[]const u8` slice representing the generated patch. The caller is responsible for freeing
/// this memory using the provided allocator.
///
/// # Errors
///
/// Can return an error if memory allocation fails.
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

/// Decodes a patch to reconstruct the target sequence from a source sequence.
///
/// This function applies the instructions in a patch to the source sequence to generate
/// the target sequence.
///
/// # Parameters
///
/// - `T`: The type of elements in the sequences.
/// - `source`: The original sequence of data.
/// - `patch`: The patch generated by the `encode` function.
/// - `allocator`: An allocator for managing memory for the reconstructed target sequence.
///
/// # Returns
///
/// A `[]const T` slice representing the reconstructed target sequence. The caller is responsible
/// for freeing this memory using the provided allocator.
///
/// # Errors
///
/// - `error.InvalidPatchFormat`: If the patch is malformed or contains invalid instructions.
/// - Can also return an error if memory allocation fails.
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

test encode {
    const allocator = testing.allocator;
    const source = "aaacccbbb";
    const target = "xxxaaaxxxbbb";
    const patch = try encode(u8, source, target, allocator);
    defer allocator.free(patch);
    const expected = &[_]u8{ 3, 3, 120, 120, 120, 1, 0, 3, 2, 0, 3, 1, 6, 3 };
    try testing.expectEqualSlices(u8, expected, patch);
}

test decode {
    const allocator = testing.allocator;
    const source = "aaacccbbb";
    const patch = &[_]u8{ 3, 3, 120, 120, 120, 1, 0, 3, 2, 0, 3, 1, 6, 3 };
    const target = try decode(u8, source, patch, allocator);
    defer allocator.free(target);

    const expected = "xxxaaaxxxbbb";
    try testing.expectEqualSlices(u8, expected, target);
}

test "fuzz encode and decode" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            const source = input[0 .. input.len / 2];
            const target = input[input.len / 2 ..];
            const allocator = testing.allocator;
            const patch = try encode(u8, source, target, allocator);
            defer allocator.free(patch);
            const decoded = try decode(u8, source, patch, allocator);
            defer allocator.free(decoded);
            try std.testing.expectEqualStrings(target, decoded);
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
