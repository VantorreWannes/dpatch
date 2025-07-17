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

        pub fn init(allocator: std.mem.Allocator, source: []const T, target: []const T) !DPatchEncoder(T) {
            const lcs = try lis_lcs.longestCommonSubsequence(T, allocator, source, target);

            return DPatchEncoder(T){
                .allocator = allocator,
                .source = source,
                .target = target,
                .lcs = lcs,
            };
        }

        pub fn deinit(self: *DPatchEncoder(T)) void {
            self.allocator.free(self.lcs);
        }
    };
}

test "DPatchEncoder init" {
    const allocator = std.testing.allocator;
    const T = u8;

    const source = "sea";
    const target = "eat";

    const encoder = try DPatchEncoder(T).init(allocator, source, target);
    defer encoder.deinit();

    try std.testing.expectEqualSlices(T, source, encoder.source);
    try std.testing.expectEqualSlices(T, target, encoder.target);

    const expected_lcs = "ea";
    try std.testing.expectEqualSlices(T, expected_lcs, encoder.lcs);
}
