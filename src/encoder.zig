const std = @import("std");
const lis_lcs = @import("lis_lcs");

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

        pub fn init(allocator: std.mem.Allocator, source: []const T, target: []const T) !DPatchEncoder(T) {
            const lcs = try lis_lcs.longestCommonSubsequence(T, allocator, source, target);

            return DPatchEncoder(T){
                .allocator = allocator,
                .source = source,
                .target = target,
                .lcs = lcs,
                .source_index = 0,
                .target_index = 0,
                .lcs_index = 0,
            };
        }

        pub fn deinit(self: *DPatchEncoder(T)) void {
            self.allocator.free(self.lcs);
        }

        pub fn next(self: *DPatchEncoder(T)) !?DPatchInstruction {
            if (self.target_index >= self.target.len) {
                return null;
            }

            if (self.lcs_index >= self.lcs.len) {
                const insert_data = self.target[self.target_index..];
                self.target_index = self.target.len;
                return DPatchInstruction{ .insert = .{ .data = insert_data } };
            }

            const s_match_rel = std.mem.indexOf(T, self.source[self.source_index..], &[_]T{self.lcs[self.lcs_index]}) orelse {
                return error.LcsMismatch;
            };
            const s_match_idx = self.source_index + s_match_rel;

            const t_match_rel = std.mem.indexOf(T, self.target[self.target_index..], &[_]T{self.lcs[self.lcs_index]}) orelse {
                return error.LcsMismatch;
            };
            const t_match_idx = self.target_index + t_match_rel;

            if (t_match_idx > self.target_index) {
                const insert_data = self.target[self.target_index..t_match_idx];
                self.source_index = s_match_idx;
                self.target_index = t_match_idx;
                return DPatchInstruction{ .insert = .{ .data = insert_data } };
            }

            var common_len: usize = 0;
            while (s_match_idx + common_len < self.source.len and
                t_match_idx + common_len < self.target.len and
                std.mem.eql(T, &.{self.source[s_match_idx + common_len]}, &.{self.target[t_match_idx + common_len]}))
            {
                common_len += 1;
            }

            const common_block = self.source[s_match_idx .. s_match_idx + common_len];
            var lcs_consumed: usize = 0;
            var search_offset: usize = 0;
            while (self.lcs_index + lcs_consumed < self.lcs.len and search_offset < common_block.len) {
                const lcs_char = self.lcs[self.lcs_index + lcs_consumed];
                if (std.mem.indexOf(T, common_block[search_offset..], &.{lcs_char})) |rel_idx| {
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
    const allocator = std.testing.allocator;
    const T = u8;

    const source = "sea";
    const target = "eat";

    var encoder = try DPatchEncoder(T).init(allocator, source, target);
    defer encoder.deinit();

    try std.testing.expectEqualSlices(T, source, encoder.source);
    try std.testing.expectEqualSlices(T, target, encoder.target);

    const expected_lcs = "ea";
    try std.testing.expectEqualSlices(T, expected_lcs, encoder.lcs);
}

test "DPatchEncoder next" {
    const allocator = std.testing.allocator;
    const T = u8;

    const source = "sea";
    const target = "eat";

    var encoder = try DPatchEncoder(T).init(allocator, source, target);
    defer encoder.deinit();

    const inst1 = try encoder.next();
    try std.testing.expect(inst1 != null);
    try std.testing.expect(inst1.?.copy.start == 1);
    try std.testing.expect(inst1.?.copy.len == 2);

    const inst2 = try encoder.next();
    try std.testing.expect(inst2 != null);
    try std.testing.expectEqualSlices(u8, "t", inst2.?.insert.data);

    const inst3 = try encoder.next();
    try std.testing.expect(inst3 == null);
}
