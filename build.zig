const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const use_llvm = b.option(bool, "llvm", "Use the LLVM backend");

    const lis_lcs_pkg = b.dependency("lis_lcs", .{ .target = target, .optimize = optimize });
    const lis_lcs_mod = lis_lcs_pkg.module("lis_lcs");

    const mod = b.addModule("dpatch", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "lis_lcs", .module = lis_lcs_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "dpatch",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dpatch", .module = mod },
                .{ .name = "lis_lcs", .module = lis_lcs_mod },
            },
        }),
        .use_llvm = use_llvm,
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .use_llvm = use_llvm,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
        .use_llvm = use_llvm,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    const zbench_pkg = b.dependency("zbench", .{ .target = target, .optimize = optimize });
    const zbench_mod = zbench_pkg.module("zbench");

    const bench_exe = b.addExecutable(.{
        .name = "benchmarks",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "dpatch", .module = mod },
                .{ .name = "zbench", .module = zbench_mod },
                .{ .name = "lis_lcs", .module = lis_lcs_mod },
            },
        }),
    });

    b.installArtifact(bench_exe);

    const bench_cmd = b.addRunArtifact(bench_exe);

    const bench_step = b.step("bench", "Run benchmarks");
    bench_step.dependOn(&bench_cmd.step);
}
