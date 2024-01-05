const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("../types.zig");
const zwin = @import("zwin");
const Self = @This();

const vShader =
    \\#version 460 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec4 aCol;
    \\out vec4 vertexColor;
    \\void main()
    \\{
    \\    gl_Position = vec4(aPos, 1.0);
    \\    vertexColor = aCol;
    \\}
;

const fShader =
    \\#version 460 core
    \\out vec4 FragColor;
    \\in vec4 vertexColor;
    \\void main()
    \\{
    \\    FragColor = vertexColor;
    \\}
;

const Shader = struct {
    program: u32 = 0,

    pub fn init(self: *Shader) !void {
        var vertex = glad.glCreateShader(glad.GL_VERTEX_SHADER);
        defer glad.glDeleteShader(vertex);

        var fragment = glad.glCreateShader(glad.GL_FRAGMENT_SHADER);
        defer glad.glDeleteShader(fragment);

        var alloc = try Allocator.allocator();

        var vShaderSource = try alloc.dupeZ(u8, vShader);
        defer alloc.free(vShaderSource);

        var fShaderSource = try alloc.dupeZ(u8, fShader);
        defer alloc.free(fShaderSource);

        glad.glShaderSource(vertex, 1, &vShaderSource.ptr, null);
        glad.glShaderSource(fragment, 1, &fShaderSource.ptr, null);

        glad.glCompileShader(vertex);
        glad.glCompileShader(fragment);

        var success: i32 = 0;
        glad.glGetShaderiv(vertex, glad.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var infoLog = try alloc.alloc(u8, 512);
            defer alloc.free(infoLog);

            glad.glGetShaderInfoLog(vertex, 512, null, infoLog.ptr);
            std.log.err("Vertex shader compilation failed: {s}\n", .{infoLog});
            return error.ShaderCompileError;
        }

        glad.glGetShaderiv(fragment, glad.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var infoLog = try alloc.alloc(u8, 512);
            defer alloc.free(infoLog);

            glad.glGetShaderInfoLog(fragment, 512, null, infoLog.ptr);
            std.log.err("Fragment shader compilation failed: {s}\n", .{infoLog});
            return error.ShaderCompileError;
        }

        self.program = glad.glCreateProgram();
        glad.glAttachShader(self.program, vertex);
        glad.glAttachShader(self.program, fragment);
        glad.glLinkProgram(self.program);

        glad.glGetProgramiv(self.program, glad.GL_LINK_STATUS, &success);
        if (success == 0) {
            var infoLog = try alloc.alloc(u8, 512);
            defer alloc.free(infoLog);

            glad.glGetProgramInfoLog(self.program, 512, null, infoLog.ptr);
            std.log.err("Shader linking failed: {s}\n", .{infoLog});
            return error.ShaderLinkError;
        }

        glad.glDeleteShader(vertex);
        glad.glDeleteShader(fragment);

        self.use();
        std.log.info("Shader initialized\n", .{});
    }

    pub fn use(self: *Shader) void {
        glad.glUseProgram(self.program);
    }
};

const Mesh = struct {
    vao: u32 = 0,
    vbo: u32 = 0,
    ebo: u32 = 0,
    index_count: usize = 0,

    fn get_gltype(kind: t.VertexLayout.Type) u32 {
        return switch (kind) {
            .Float => glad.GL_FLOAT,
            .UByte => glad.GL_UNSIGNED_BYTE,
            .UShort => glad.GL_UNSIGNED_SHORT,
        };
    }

    fn update(ctx: *anyopaque, vertices: *anyopaque, vert_count: usize, indices: *anyopaque, ind_count: usize, layout: *const t.VertexLayout) void {
        var self = t.coerce_ptr(Mesh, ctx);

        if (self.vao == 0) {
            glad.glGenVertexArrays(1, &self.vao);
        }

        if (self.vbo == 0) {
            glad.glGenBuffers(1, &self.vbo);
        }

        if (self.ebo == 0) {
            glad.glGenBuffers(1, &self.ebo);
        }

        glad.glBindVertexArray(self.vao);

        glad.glBindBuffer(glad.GL_ARRAY_BUFFER, self.vbo);
        const vert_size = vert_count * layout.size;
        std.log.info("Vertex size: {d}\n", .{vert_size});
        glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(vert_size), vertices, glad.GL_STATIC_DRAW);

        if (layout.vertex) |entry| {
            glad.glEnableVertexAttribArray(0);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            std.log.info("Vertex layout: {d} {d} {d}\n", .{ dims, size, offset });
            glad.glVertexAttribPointer(
                0,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_FALSE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        if (layout.color) |entry| {
            glad.glEnableVertexAttribArray(1);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            std.log.info("Color layout: {d} {d} {d}\n", .{ dims, size, offset });
            glad.glVertexAttribPointer(
                1,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_TRUE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, self.ebo);

        const ind_size = ind_count * @sizeOf(u16);
        self.index_count = ind_count;
        std.log.info("Index size: {d}\n", .{ind_size});
        glad.glBufferData(glad.GL_ELEMENT_ARRAY_BUFFER, @intCast(ind_size), indices, glad.GL_STATIC_DRAW);

        glad.glBindVertexArray(0);

        std.log.info("VAO {d} VBO {d} EBO {d}\n", .{ self.vao, self.vbo, self.ebo });
    }

    fn draw(ctx: *anyopaque) void {
        const self = t.coerce_ptr(Mesh, ctx);
        glad.glBindVertexArray(self.vao);
        const count = self.index_count;
        glad.glDrawElements(glad.GL_TRIANGLES, @intCast(count), glad.GL_UNSIGNED_SHORT, null);
    }

    fn interface(self: *Mesh) t.MeshInternal {
        return .{
            .ptr = self,
            .size = @sizeOf(Mesh),
            .tab = .{
                .update = update,
                .draw = draw,
            },
        };
    }
};

shader: Shader = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);
    try zwin.init(.OpenGL, 4, 6);

    const alloc = try Allocator.allocator();
    var copy = try alloc.dupeZ(u8, title);
    defer alloc.free(copy);

    try zwin.createWindow(width, height, copy, false);
    if (glad.gladLoadGL(@ptrCast(&zwin.getGLProcAddr)) == 0) {
        return error.OGLLoadError;
    }

    glad.glViewport(0, 0, width, height);
    // glad.glEnable(glad.GL_DEPTH_TEST);
    // glad.glEnable(glad.GL_CULL_FACE);
    // glad.glCullFace(glad.GL_BACK);
    // glad.glFrontFace(glad.GL_CCW);
    // glad.glClearColor(1.0, 1.0, 1.0, 1.0);

    var str = glad.glGetString(glad.GL_VERSION);
    std.debug.print("OpenGL Version: {s}\n", .{str});

    try self.shader.init();
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
    var alloc = Allocator.allocator() catch unreachable;
    var mesh = alloc.create(Mesh) catch unreachable;
    mesh.* = Mesh{};

    return mesh.interface();
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
