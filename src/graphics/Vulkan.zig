const std = @import("std");
const t = @import("../types.zig");
const zwin = @import("zwin");
const vk = @import("vulkan");

const Self = @This();
const Allocator = @import("../allocator.zig");
const Context = @import("Vulkan/Context.zig");
const Swapchain = @import("Vulkan/Swapchain.zig");

context: Context = Context{},
swapchain: Swapchain = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);
    try zwin.init(.Vulkan, 1, 3);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);

    try self.context.init(copy);

    var extent = vk.Extent2D{ .width = width, .height = height };
    var swapchain = try Swapchain.init(&self.context, alloc, extent);
    defer swapchain.deinit();
}

pub fn deinit(ctx: *anyopaque) void {
    _ = ctx;

    zwin.deinit();
}

pub fn start_frame(ctx: *anyopaque) void {
    _ = ctx;
}

pub fn end_frame(ctx: *anyopaque) void {
    _ = ctx;
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
    _ = ctx;
    var tmesh: t.MeshInternal = undefined;
    return tmesh;
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
