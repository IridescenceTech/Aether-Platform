const std = @import("std");
const t = @import("../types.zig");
const zwin = @import("zwin");
const vk = @import("vulkan");

const Self = @This();
const Allocator = @import("../allocator.zig");

const Context = @import("Vulkan/Context.zig");
const Swapchain = @import("Vulkan/Swapchain.zig").Swapchain;
const Pipeline = @import("Vulkan/Pipeline.zig");

const MeshManager = @import("Vulkan/Mesh.zig").MeshManager;
const Mesh = @import("Vulkan/Mesh.zig").Mesh;

swapchain: Swapchain = undefined,
meshes: MeshManager = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    const self = t.coerce_ptr(Self, ctx);
    try zwin.init(.Vulkan, 1, 3);

    const alloc = try Allocator.allocator();
    const copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);
    try Context.init(copy);

    self.swapchain = try Swapchain.init(.{
        .width = width,
        .height = height,
    });
    std.log.debug("Swapchain Created!", .{});

    try Pipeline.init(self.swapchain);
    std.log.debug("Pipeline Created!", .{});

    extent.width = width;
    extent.height = height;

    viewports[0].width = @floatFromInt(width);
    viewports[0].height = @floatFromInt(height);

    scissors[0].extent = extent;

    try self.meshes.init();
}

pub fn deinit(ctx: *anyopaque) void {
    var self = t.coerce_ptr(Self, ctx);

    Context.vkd.deviceWaitIdle(Context.device) catch unreachable;

    self.meshes.deinit();
    self.swapchain.waitForAllFences() catch unreachable;

    Pipeline.deinit();
    self.swapchain.deinit();

    Context.deinit();

    zwin.deinit();
}

var extent = vk.Extent2D{
    .width = 0,
    .height = 0,
};

var scissors = [_]vk.Rect2D{
    .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = .{ .width = 0, .height = 0 },
    },
};

var viewports = [_]vk.Viewport{
    vk.Viewport{
        .x = 0,
        .y = 0,
        .width = 960,
        .height = 544,
        .min_depth = 0,
        .max_depth = 1,
    },
};

pub fn start_frame(ctx: *anyopaque) void {
    const self = t.coerce_ptr(Self, ctx);
    Pipeline.current_cmd_buffer = &Pipeline.cmd_buffers[self.swapchain.image_index];

    self.swapchain.start_frame() catch unreachable;

    const cmdbuf = Pipeline.current_cmd_buffer.?.*;
    Context.vkd.beginCommandBuffer(cmdbuf, &.{}) catch unreachable;

    Context.vkd.cmdSetViewport(
        cmdbuf,
        0,
        viewports.len,
        &viewports,
    );

    Context.vkd.cmdSetScissor(
        cmdbuf,
        0,
        scissors.len,
        &scissors,
    );

    const render_area = vk.Rect2D{
        .offset = .{ .x = 0, .y = 0 },
        .extent = extent,
    };

    const clear_vals = [_]vk.ClearValue{
        .{ .color = .{ .float_32 = .{ 1, 1, 1, 1 } } },
    };

    Context.vkd.cmdBeginRenderPass(cmdbuf, &.{
        .render_pass = Pipeline.render_pass,
        .framebuffer = Pipeline.framebuffers[self.swapchain.image_index],
        .render_area = render_area,
        .clear_value_count = clear_vals.len,
        .p_clear_values = &clear_vals,
    }, .@"inline");

    Context.vkd.cmdBindPipeline(cmdbuf, .graphics, Pipeline.pipeline);

    Context.vkd.cmdBindDescriptorSets(cmdbuf, .graphics, Pipeline.pipeline_layout, 0, 1, &Pipeline.descriptor_sets, 0, null);
}

pub fn end_frame(ctx: *anyopaque) void {
    var self = t.coerce_ptr(Self, ctx);
    const cmdbuf = Pipeline.current_cmd_buffer.?.*;

    Context.vkd.cmdEndRenderPass(cmdbuf);
    Context.vkd.endCommandBuffer(cmdbuf) catch unreachable;

    _ = self.swapchain.present_frame(cmdbuf) catch unreachable;
}

pub fn set_vsync(ctx: *anyopaque, vsync: bool) void {
    _ = ctx;
    zwin.setVsync(vsync);
}

pub fn should_close(ctx: *anyopaque) bool {
    _ = ctx;
    return zwin.shouldClose();
}

pub fn create_mesh_internal(ctx: *anyopaque) t.MeshInternal {
    var self = t.coerce_ptr(Self, ctx);
    var alloc = Allocator.allocator() catch unreachable;
    var mesh = alloc.create(Mesh) catch unreachable;
    mesh.* = Mesh{};

    self.meshes.list.append(mesh) catch unreachable;
    return mesh.interface();
}

/// Loads a texture from the given path
pub fn load_texture(ctx: *anyopaque, path: []const u8) t.Texture {
    _ = path;
    _ = ctx;

    return .{
        .index = 0,
        .width = 0,
        .height = 0,
    };
}

/// Loads a texture from a buffer
pub fn load_texture_from_buffer(ctx: *anyopaque, buffer: []const u8) t.Texture {
    _ = buffer;
    _ = ctx;

    return .{
        .index = 0,
        .width = 0,
        .height = 0,
    };
}

/// Set the texture to be used for rendering
pub fn set_texture(ctx: *anyopaque, texture: t.Texture) void {
    _ = texture;
    _ = ctx;
}

/// Destroys a texture
pub fn destroy_texture(ctx: *anyopaque, texture: t.Texture) void {
    _ = texture;
    _ = ctx;
}

pub fn interface(self: *Self) t.GraphicsEngine {
    return .{
        .ptr = self,
        .tab = .{
            .init = init,
            .deinit = deinit,
            .start_frame = start_frame,
            .end_frame = end_frame,
            .set_vsync = set_vsync,
            .should_close = should_close,
            .create_mesh_internal = create_mesh_internal,
            .load_texture = load_texture,
            .load_texture_from_buffer = load_texture_from_buffer,
            .set_texture = set_texture,
            .destroy_texture = destroy_texture,
        },
    };
}
