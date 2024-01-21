const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("../types.zig");
const zwin = @import("zwin");
const Self = @This();
const builtin = @import("builtin");

// Graphics Engine

const Shader = @import("GL/Shader.zig");
const Texture = @import("GL/Texture.zig").Texture;
const TextureManager = @import("GL/Texture.zig").TextureManager;
const MeshManager = @import("GL/Mesh.zig").MeshManager;
const Mesh = @import("GL/Mesh.zig").Mesh;

meshes: MeshManager = undefined,
textures: TextureManager = undefined,
gles: bool = false,

//typedef void (APIENTRY *DEBUGPROC)(GLenum source,
// GLenum type,
// GLuint id,
// GLenum severity,
// GLsizei length,
// const GLchar *message,
// const void *userParam);
fn debugger(source: c_uint, kind: c_uint, id: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, userParam: ?*const anyopaque) callconv(.C) void {
    _ = length;
    _ = id;
    _ = kind;
    _ = source;
    _ = userParam;
    if (severity == glad.GL_DEBUG_SEVERITY_NOTIFICATION) {
        return;
    }

    std.debug.print("{s}\n", .{message});
}

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);

    if (self.gles) {
        try zwin.init(.GLES, 3, 2);
    } else {
        try zwin.init(.OpenGL, 4, 6);
    }

    const alloc = try Allocator.allocator();
    const copy = try alloc.dupeZ(u8, title);
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

    if (builtin.mode == .Debug and self.gles == false) {
        glad.glEnable(glad.GL_DEBUG_OUTPUT);
        glad.glDebugMessageCallback(&debugger, null);
    }

    const str = glad.glGetString(glad.GL_VERSION);
    std.debug.print("OpenGL Version: {s}\n", .{str});

    try Shader.init(self.gles);
    std.log.debug("Shader created", .{});
    check_error();
    try self.meshes.init();
    std.log.debug("Meshes created", .{});
    check_error();
    try self.textures.init();
    std.log.debug("Textures created", .{});
    check_error();
}

fn check_error() void {
    const err = glad.glGetError();
    if (err != glad.GL_NO_ERROR) {
        std.log.err("OpenGL Error: {d}", .{err});
    }
}

pub fn deinit(ctx: *anyopaque) void {
    const self = t.coerce_ptr(Self, ctx);
    self.meshes.deinit();
    self.textures.deinit();
    glad.glDeleteProgram(Shader.program);

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

    const texture = self.textures.load_texture(path) catch self.textures.undefined_texture;
    if (texture.id == self.textures.undefined_texture.id) {
        std.log.warn("Texture not found: {s}", .{path});
    }

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

    const texture = self.textures.load_texture_from_buffer(buffer, null) catch unreachable;

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
