const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("../types.zig");
const zwin = @import("zwin");
const Self = @This();

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    _ = ctx;
    try zwin.init(.GLES, 3, 2);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);
    if (glad.gladLoadGLES2(@ptrCast(&zwin.getGLProcAddr)) == 0) {
        return error.OGLLoadError;
    }

    glad.glViewport(0, 0, width, height);
    glad.glEnable(glad.GL_DEPTH_TEST);
    glad.glEnable(glad.GL_CULL_FACE);
    glad.glCullFace(glad.GL_BACK);
    glad.glFrontFace(glad.GL_CCW);
    glad.glClearColor(1.0, 1.0, 1.0, 1.0);

    var str = glad.glGetString(glad.GL_VERSION);
    std.debug.print("OpenGL Version: {s}\n", .{str});
}

pub fn deinit(ctx: *anyopaque) void {
    _ = ctx;

    zwin.deinit();
}

pub fn start_frame(ctx: *anyopaque) void {
    _ = ctx;
    glad.glClear(glad.GL_COLOR_BUFFER_BIT | glad.GL_DEPTH_BUFFER_BIT);
}

pub fn end_frame(ctx: *anyopaque) void {
    _ = ctx;
    zwin.render();
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
        },
    };
}
