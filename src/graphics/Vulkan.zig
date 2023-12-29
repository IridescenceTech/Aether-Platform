const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("types");
const zwin = @import("zwin");
const Self = @This();

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    _ = ctx;
    try zwin.init(.Vulkan, 1, 3);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);
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
        },
    };
}
