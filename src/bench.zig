const std = @import("std");
const zbench = @import("zbench");
const dpatch_encoder = @import("encoder.zig");

fn randomArray(random: *std.Random, comptime length: comptime_int, comptime alphabet_size: comptime_int) [length]u8 {
    var array: [length]u8 = undefined;
    for (&array) |*num| {
        num.* = random.int(u8) % alphabet_size;
    }
    return array;
}

fn DPatchEncoderBenchmark(comptime length: comptime_int, comptime alphabet_size: comptime_int) type {
    return struct {
        source: [length]u8,
        target: [length]u8,

        fn init(random: *std.Random) @This() {
            return .{
                .source = randomArray(random, length, alphabet_size),
                .target = randomArray(random, length, alphabet_size),
            };
        }

        pub fn run(self: @This(), _: std.mem.Allocator) void {
            const allocator = std.heap.smp_allocator;
            var encoder = dpatch_encoder.DPatchEncoder(u8).init(&self.source, &self.target, allocator) catch unreachable;
            defer encoder.deinit();
            while (encoder.next() catch unreachable) |instruction| {
                std.mem.doNotOptimizeAway(instruction);
            }
        }
    };
}

pub fn main() !void {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var random = prng.random();

    const stdout = std.io.getStdOut().writer();

    const allocator = std.heap.smp_allocator;

    var bench = zbench.Benchmark.init(allocator, .{});
    defer bench.deinit();

    const lengths = [_]comptime_int{ 10, 100, 250 };
    const alphabet_sizes = [_]comptime_int{ 1, 16, 32 };

    inline for (lengths) |length| {
        inline for (alphabet_sizes) |alphabet_size| {
            const name = std.fmt.comptimePrint(
                "encoder_L{d}_A{d}",
                .{ length, alphabet_size },
            );
            const benchmark = DPatchEncoderBenchmark(length, alphabet_size).init(&random);
            try bench.addParam(name, &benchmark, .{ .time_budget_ns = 20_000_000 * (length * 4) });
        }
    }

    try stdout.writeAll("\n");
    try bench.run(stdout);
}
