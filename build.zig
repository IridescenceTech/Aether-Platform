const std = @import("std");
const vkgen = @import("ext/vulkan/generator/index.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw = b.addModule("glfw", .{
        .source_file = .{ .path = "ext/zwin/glfw/src/glfw.zig" },
    });

    const zwin = b.addModule("zwin", .{
        .source_file = .{ .path = "ext/zwin/src/zwin.zig" },
        .dependencies = &.{
            .{ .name = "glfw", .module = glfw },
        },
    });

    const glad = b.addModule("glad", .{
        .source_file = .{ .path = "ext/glad/c.zig" },
    });

    const types = b.addModule(
        "types",
        .{ .source_file = .{ .path = "src/types.zig" } },
    );

    const gen = vkgen.VkGenerateStep.create(b, "ext/vk.xml");

    const platform = b.addModule("platform", .{
        .source_file = .{ .path = "src/platform.zig" },
        .dependencies = &.{
            .{ .name = "types", .module = types },
            .{ .name = "zwin", .module = zwin },
            .{ .name = "glad", .module = glad },
            .{ .name = "vulkan", .module = gen.getModule() },
        },
    });

    const exe = b.addExecutable(.{
        .name = "Aether-Platform",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("platform", platform);
    exe.linkLibC();
    exe.linkSystemLibrary("glfw");
    exe.addIncludePath(.{ .path = "ext/glad/include" });
    exe.addCSourceFile(.{
        .file = .{ .path = "ext/glad/src/gl.c" },
        .flags = &[_][]const u8{"-Iext/glad/include"},
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
