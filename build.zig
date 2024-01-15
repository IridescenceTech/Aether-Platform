const std = @import("std");
const builtin = @import("builtin");
const vkgen = @import("ext/vulkan/generator/index.zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw = b.addModule("glfw", .{
        .root_source_file = .{ .path = "ext/zwin/glfw/src/glfw.zig" },
    });

    const zwin = b.addModule("zwin", .{
        .root_source_file = .{ .path = "ext/zwin/src/zwin.zig" },
        .imports = &.{
            .{ .name = "glfw", .module = glfw },
        },
    });

    const glad = b.addModule("glad", .{
        .root_source_file = .{ .path = "ext/glad/c.zig" },
    });
    glad.addIncludePath(.{ .path = "ext/glad/include" });
    glad.addIncludePath(.{ .path = "ext/glad/" });

    const stbi = b.addModule("stbi", .{
        .root_source_file = .{ .path = "ext/stbi/c.zig" },
    });
    stbi.addIncludePath(.{ .path = "ext/stbi/" });

    const gen = vkgen.VkGenerateStep.create(b, "ext/vk.xml");

    const shaders = vkgen.ShaderCompileStep.create(
        b,
        &[_][]const u8{ "glslc", "--target-env=vulkan1.2" },
        "-o",
    );
    shaders.add("vert", "shaders/basic.vert", .{});
    shaders.add("frag", "shaders/basic.frag", .{});

    const platform = b.addModule("platform", .{
        .root_source_file = .{ .path = "src/platform.zig" },
        .imports = &.{
            .{ .name = "zwin", .module = zwin },
            .{ .name = "glad", .module = glad },
            .{ .name = "vulkan", .module = gen.getModule() },
            .{ .name = "stbi", .module = stbi },
            .{ .name = "shaders", .module = shaders.getModule() },
        },
    });

    const exe = b.addExecutable(.{
        .name = "Aether-Platform",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("platform", platform);
    exe.linkLibC();

    if (builtin.os.tag == .windows) {
        //TODO: Move this somewhere else
        exe.addObjectFile(.{ .path = "libglfw3.a" });
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("gdi32");
    } else {
        exe.linkSystemLibrary("glfw");
    }
    exe.addCSourceFile(.{
        .file = .{ .path = "ext/glad/src/gl.c" },
        .flags = &[_][]const u8{"-Iext/glad/include"},
    });
    exe.addCSourceFile(.{
        .file = .{ .path = "ext/glad/loader.c" },
        .flags = &[_][]const u8{"-Iext/glad/"},
    });
    exe.addCSourceFile(.{
        .file = .{ .path = "ext/stbi/stb_image.c" },
        .flags = &[_][]const u8{"-Iext/stbi/"},
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
