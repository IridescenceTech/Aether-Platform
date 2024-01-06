const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("../types.zig");
const zwin = @import("zwin");
const Self = @This();

// Graphics Engine

const Shader = @import("GL/Shader.zig");
const Texture = @import("GL/Texture.zig").Texture;
const TextureManager = @import("GL/Texture.zig").TextureManager;
const MeshManager = @import("GL/Mesh.zig").MeshManager;
const Mesh = @import("GL/Mesh.zig").Mesh;

shader: Shader = undefined,
meshes: MeshManager = undefined,
textures: TextureManager = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);
    try zwin.init(.GLES, 3, 2);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);
    std.log.info("Window created", .{});
    if (glad.aether_loadgl() == 0) {
        return error.OGLLoadError;
    }

    glad.glViewport(0, 0, width, height);
    glad.glEnable(glad.GL_DEPTH_TEST);
    glad.glEnable(glad.GL_CULL_FACE);
    glad.glCullFace(glad.GL_BACK);
    glad.glFrontFace(glad.GL_CCW);
    glad.glEnable(glad.GL_FRAMEBUFFER_SRGB);
    glad.glClearColor(1.0, 1.0, 1.0, 1.0);

    var str = glad.glGetString(glad.GL_VERSION);
    std.debug.print("OpenGL Version: {s}\n", .{str});

    try self.shader.init(true);
    try self.meshes.init();
    try self.textures.init();

    check_error();
}

fn check_error() void {
    var err = glad.glGetError();
    if (err != glad.GL_NO_ERROR) {
        std.log.err("OpenGL Error: {d}\n", .{err});
    }
}

pub fn deinit(ctx: *anyopaque) void {
    var self = t.coerce_ptr(Self, ctx);
    self.meshes.deinit();
    self.textures.deinit();
    glad.glDeleteProgram(self.shader.program);

    zwin.deinit();
}

pub fn start_frame(ctx: *anyopaque) void {
    _ = ctx;
    glad.glClear(glad.GL_COLOR_BUFFER_BIT | glad.GL_DEPTH_BUFFER_BIT);
    check_error();
}

pub fn end_frame(ctx: *anyopaque) void {
    var self = t.coerce_ptr(Self, ctx);
    zwin.render();

    self.meshes.gc();
    check_error();
}

pub fn set_vsync(ctx: *anyopaque, vsync: bool) void {
    _ = ctx;
    zwin.setVsync(vsync);
    check_error();
}

pub fn should_close(ctx: *anyopaque) bool {
    _ = ctx;
    check_error();
    return zwin.shouldClose();
}

pub fn create_mesh_internal(ctx: *anyopaque) t.MeshInternal {
    var self = t.coerce_ptr(Self, ctx);
    var alloc = Allocator.allocator() catch unreachable;
    var mesh = alloc.create(Mesh) catch unreachable;
    mesh.* = Mesh{};

    self.meshes.list.append(mesh) catch unreachable;

    check_error();
    return mesh.interface();
}

/// Loads a texture from the given path
pub fn load_texture(ctx: *anyopaque, path: []const u8) t.Texture {
    var self = t.coerce_ptr(Self, ctx);

    var texture = self.textures.load_texture(path) catch unreachable;

    check_error();
    return .{
        .index = texture.id,
        .width = texture.width,
        .height = texture.height,
    };
}

/// Loads a texture from a buffer
pub fn load_texture_from_buffer(ctx: *anyopaque, buffer: []const u8) t.Texture {
    var self = t.coerce_ptr(Self, ctx);

    var texture = self.textures.load_texture_from_buffer(buffer, null) catch unreachable;

    check_error();
    return .{
        .index = texture.id,
        .width = texture.width,
        .height = texture.height,
    };
}

/// Set the texture to be used for rendering
pub fn set_texture(ctx: *anyopaque, texture: t.Texture) void {
    var self = t.coerce_ptr(Self, ctx);
    self.textures.bind(texture);
    check_error();
}

/// Destroys a texture
pub fn destroy_texture(ctx: *anyopaque, texture: t.Texture) void {
    var self = t.coerce_ptr(Self, ctx);
    self.textures.delete(texture);
    check_error();
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
