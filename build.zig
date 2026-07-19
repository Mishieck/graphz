const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("graphz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const examples = [_][]const u8{ "node", "tree_node", "graph_node_conversions", "traversal" };
    inline for (examples) |name| addExample(b, target, optimize, name, mod);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}

fn addExample(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime name: []const u8,
    mod: *std.Build.Module,
) void {
    const examples_node = b.addExecutable(.{
        .name = "example_" ++ name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/" ++ name ++ ".zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "graphz", .module = mod },
            },
        }),
    });

    b.installArtifact(examples_node);

    const run_step = b.step("example_" ++ name, "Run the " ++ name ++ " example.");

    const run_cmd = b.addRunArtifact(examples_node);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
}
