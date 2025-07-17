const std = @import("std");
const dpatch = @import("dpatch");

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
}
