const std = @import("std");
const lis_lcs = @import("lis_lcs");
const testing = std.testing;

pub fn DPatchEncoder(comptime T: type) type {
    return struct {
        pub const CopyDetails = struct {
            start: usize,
            len: usize,
        };

        pub const InsertInstruction = union(enum) {
            copy: CopyDetails,
            data: []const T,
        };

        pub const DPatchInstruction = union(enum) {
            copy: CopyDetails,
            insert: InsertInstruction,
        };

        allocator: std.mem.Allocator,
        source: []const T,
        target: []const T,
        lcs: []const T,

        source_index: usize,
        target_index: usize,
        lcs_index: usize,
        insert_buffer: std.ArrayList(T),

        pub fn init(source: []const T, target: []const T, allocator: std.mem.Allocator) !DPatchEncoder(T) {
            const lcs = try lis_lcs.longestCommonSubsequence(T, allocator, source, target);

            return DPatchEncoder(T){
                .allocator = allocator,
                .source = source,
                .target = target,
                .lcs = lcs,
                .source_index = 0,
                .target_index = 0,
                .lcs_index = 0,
                .insert_buffer = std.ArrayList(T).init(allocator),
            };
        }

        pub fn deinit(self: *DPatchEncoder(T)) void {
            self.allocator.free(self.lcs);
            self.insert_buffer.deinit();
        }

        fn createInsertInstruction(self: *DPatchEncoder(T), data: []const T) !DPatchInstruction {
            const instruction: InsertInstruction = if (std.mem.indexOf(T, self.insert_buffer.items, data)) |copy_start|
                .{ .copy = .{ .start = copy_start, .len = data.len } }
            else
                .{ .data = data };

            try self.insert_buffer.appendSlice(data);
            return DPatchInstruction{ .insert = instruction };
        }

        pub fn next(self: *DPatchEncoder(T)) !?DPatchInstruction {
            if (self.target_index >= self.target.len) {
                return null;
            }

            if (self.lcs_index >= self.lcs.len) {
                const insert_data = self.target[self.target_index..];
                self.target_index = self.target.len;
                return try self.createInsertInstruction(insert_data);
            }

            const lcs_char = self.lcs[self.lcs_index];

            const s_match_rel = std.mem.indexOfScalar(T, self.source[self.source_index..], lcs_char) orelse unreachable;
            const s_match_idx = self.source_index + s_match_rel;

            const t_match_rel = std.mem.indexOfScalar(T, self.target[self.target_index..], lcs_char) orelse unreachable;
            const t_match_idx = self.target_index + t_match_rel;

            if (t_match_idx > self.target_index) {
                const insert_data = self.target[self.target_index..t_match_idx];
                self.target_index = t_match_idx;
                return try self.createInsertInstruction(insert_data);
            }

            var common_len: usize = 0;
            while (s_match_idx + common_len < self.source.len and
                t_match_idx + common_len < self.target.len and
                self.source[s_match_idx + common_len] == self.target[t_match_idx + common_len])
            {
                common_len += 1;
            }

            const common_block = self.source[s_match_idx .. s_match_idx + common_len];
            var lcs_consumed: usize = 0;
            var search_offset: usize = 0;
            while (self.lcs_index + lcs_consumed < self.lcs.len and search_offset < common_block.len) {
                const current_lcs_char = self.lcs[self.lcs_index + lcs_consumed];
                if (std.mem.indexOfScalar(T, common_block[search_offset..], current_lcs_char)) |rel_idx| {
                    lcs_consumed += 1;
                    search_offset += rel_idx + 1;
                } else {
                    break;
                }
            }

            const copy_details = CopyDetails{ .start = s_match_idx, .len = common_len };
            self.source_index = s_match_idx + common_len;
            self.target_index = t_match_idx + common_len;
            self.lcs_index += lcs_consumed;

            return DPatchInstruction{ .copy = copy_details };
        }
    };
}

test "DPatchEncoder init" {
    const allocator = testing.allocator;

    const source = "sea";
    const target = "eat";

    var encoder = try DPatchEncoder(u8).init(source, target, allocator);
    defer encoder.deinit();

    try std.testing.expectEqualSlices(u8, source, encoder.source);
    try std.testing.expectEqualSlices(u8, target, encoder.target);
    try std.testing.expectEqualStrings( "ea", encoder.lcs);
}

test "DPatchEncoder next" {
    const source = "aaacccbbb";
    const target = "xxxaaaxxxbbb";

    var encoder = try DPatchEncoder(u8).init(source, target, testing.allocator);
    defer encoder.deinit();

    var instruction = try encoder.next();
    try testing.expect(instruction != null);
    try testing.expectEqualStrings("xxx", instruction.?.insert.data);

    instruction = try encoder.next();
    try testing.expect(instruction != null);
    try testing.expectEqual(instruction.?.copy.start, 0);
    try testing.expectEqual(instruction.?.copy.len, 3);

    instruction = try encoder.next();
    try testing.expect(instruction != null);
    try testing.expectEqual(instruction.?.insert.copy.start, 0);
    try testing.expectEqual(instruction.?.insert.copy.len, 3);

    instruction = try encoder.next();
    try testing.expect(instruction != null);
    try testing.expectEqual(instruction.?.copy.start, 6);
    try testing.expectEqual(instruction.?.copy.len, 3);

    instruction = try encoder.next();
    try testing.expect(instruction == null);
}
