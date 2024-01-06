const std = @import("std");
const glad = @import("glad");
const Allocator = @import("../allocator.zig");
const t = @import("../types.zig");
const zwin = @import("zwin");
const Self = @This();
const stbi = @import("stbi");

const vShader =
    \\#version 460 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec4 aCol;
    \\layout (location = 2) in vec2 aTex;
    \\out vec4 vertexColor;
    \\out vec2 uv;
    \\void main()
    \\{
    \\    gl_Position = vec4(aPos, 1.0);
    \\    vertexColor = aCol;
    \\    uv = aTex;
    \\}
;

const fShader =
    \\#version 460 core
    \\out vec4 FragColor;
    \\in vec4 vertexColor;
    \\in vec2 uv;
    \\
    \\uniform sampler2D tex;
    \\
    \\void main()
    \\{
    \\    FragColor = vertexColor;
    \\    FragColor *= texture(tex, uv);
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
            std.log.err("Vertex shader compilation failed: {s}", .{infoLog});
            return error.ShaderCompileError;
        }

        glad.glGetShaderiv(fragment, glad.GL_COMPILE_STATUS, &success);
        if (success == 0) {
            var infoLog = try alloc.alloc(u8, 512);
            defer alloc.free(infoLog);

            glad.glGetShaderInfoLog(fragment, 512, null, infoLog.ptr);
            std.log.err("Fragment shader compilation failed: {s}", .{infoLog});
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
            std.log.err("Shader linking failed: {s}", .{infoLog});
            return error.ShaderLinkError;
        }

        glad.glDeleteShader(vertex);
        glad.glDeleteShader(fragment);

        self.use();
        std.log.info("Shader initialized", .{});
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
    dead: bool = false,

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
        glad.glBufferData(glad.GL_ARRAY_BUFFER, @intCast(vert_size), vertices, glad.GL_STATIC_DRAW);

        if (layout.vertex) |entry| {
            glad.glEnableVertexAttribArray(0);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
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
            glad.glVertexAttribPointer(
                1,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_TRUE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        if (layout.texture) |entry| {
            glad.glEnableVertexAttribArray(2);

            const dims = entry.dimensions;
            const size = layout.size;
            const offset = entry.offset;
            glad.glVertexAttribPointer(
                2,
                @intCast(dims),
                get_gltype(entry.backing_type),
                glad.GL_FALSE,
                @intCast(size),
                @ptrFromInt(offset),
            );
        }

        glad.glBindBuffer(glad.GL_ELEMENT_ARRAY_BUFFER, self.ebo);

        const ind_size = ind_count * @sizeOf(u16);
        self.index_count = ind_count;
        glad.glBufferData(glad.GL_ELEMENT_ARRAY_BUFFER, @intCast(ind_size), indices, glad.GL_STATIC_DRAW);

        glad.glBindVertexArray(0);
    }

    fn draw(ctx: *anyopaque) void {
        const self = t.coerce_ptr(Mesh, ctx);
        glad.glBindVertexArray(self.vao);
        const count = self.index_count;
        glad.glDrawElements(glad.GL_TRIANGLES, @intCast(count), glad.GL_UNSIGNED_SHORT, null);
    }

    fn deinit(ctx: *anyopaque) void {
        var self = t.coerce_ptr(Mesh, ctx);
        self.dead = true;
    }

    fn gc(self: *Mesh) void {
        if (self.dead) {
            glad.glDeleteVertexArrays(1, &self.vao);
            glad.glDeleteBuffers(1, &self.vbo);
            glad.glDeleteBuffers(1, &self.ebo);
        }
    }

    fn interface(self: *Mesh) t.MeshInternal {
        return .{
            .ptr = self,
            .size = @sizeOf(Mesh),
            .tab = .{
                .update = update,
                .draw = draw,
                .deinit = Mesh.deinit,
            },
        };
    }
};

const MeshManager = struct {
    list: std.ArrayList(*Mesh) = undefined,

    pub fn init(self: *MeshManager) !void {
        self.list = std.ArrayList(*Mesh).init(try Allocator.allocator());
    }

    pub fn gc(self: *MeshManager) void {
        const alloc = Allocator.allocator() catch unreachable;
        var new_list = std.ArrayList(*Mesh).init(alloc);

        for (self.list.items) |mesh| {
            if (mesh.dead) {
                mesh.gc();
                alloc.destroy(mesh);
            } else {
                new_list.append(mesh) catch unreachable;
            }
        }

        self.list.clearAndFree();
        self.list = new_list;
    }

    pub fn deinit(self: *MeshManager) void {
        for (self.list.items) |mesh| {
            glad.glDeleteVertexArrays(1, &mesh.vao);
            glad.glDeleteBuffers(1, &mesh.vbo);
            glad.glDeleteBuffers(1, &mesh.ebo);

            const alloc = Allocator.allocator() catch unreachable;
            alloc.destroy(mesh);
        }

        self.list.clearAndFree();
        self.list.deinit();
    }
};

const Texture = struct {
    id: u32 = 0,
    width: u16 = 0,
    height: u16 = 0,

    path_hash: u32 = 0,
    hash: u32 = 0,
    ref_count: u32 = 0,
};

const TextureManager = struct {
    list: std.ArrayList(Texture) = undefined,
    bound: u32 = 0,

    pub fn init(self: *TextureManager) !void {
        self.list = std.ArrayList(Texture).init(try Allocator.allocator());
    }

    pub fn deinit(self: *TextureManager) void {
        for (self.list.items) |tex| {
            glad.glDeleteTextures(1, &tex.id);
        }

        self.list.clearAndFree();
        self.list.deinit();
    }

    fn hash_bytes(path: []const u8) u32 {
        var hash: u32 = 5381;
        for (path) |c| {
            @setRuntimeSafety(false);
            hash = ((hash << 5) + hash) + c;
        }

        return hash;
    }

    pub fn load_texture(self: *TextureManager, path: []const u8) !Texture {
        // Check if the texture is already loaded
        for (self.list.items) |*tex| {
            if (tex.path_hash == 0) {
                continue;
            }

            if (tex.path_hash == hash_bytes(path)) {
                tex.ref_count += 1;
                return tex.*;
            }
        }

        // Otherwise load the file into a buffer.
        const alloc = try Allocator.allocator();

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var buffer = try alloc.alloc(u8, try file.getEndPos());
        defer alloc.free(buffer);

        _ = try file.read(buffer);

        // Load the texture via the buffer method
        return self.load_texture_from_buffer(buffer, hash_bytes(path));
    }

    pub fn load_texture_from_buffer(self: *TextureManager, buffer: []const u8, phash: ?u32) !Texture {
        var tex: Texture = undefined;
        if (phash) |hash| {
            tex.path_hash = hash;
        }
        tex.hash = hash_bytes(buffer);

        for (self.list.items) |*t_other| {
            if (t_other.hash == tex.hash) {
                t_other.ref_count += 1;
                return t_other.*;
            }
        }

        tex.ref_count = 1;

        var width: i32 = 0;
        var height: i32 = 0;
        var channels: i32 = 0;
        const len = buffer.len;
        var data = stbi.stbi_load_from_memory(buffer.ptr, @intCast(len), &width, &height, &channels, stbi.STBI_rgb_alpha);
        defer stbi.stbi_image_free(data);

        if (data == null) {
            return error.TextureLoadError;
        }

        tex.width = @intCast(width);
        tex.height = @intCast(height);

        var id: u32 = 0;
        // Load the texture into OpenGL

        glad.glGenTextures(1, &id);
        glad.glBindTexture(glad.GL_TEXTURE_2D, id);

        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_S, glad.GL_REPEAT);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_WRAP_T, glad.GL_REPEAT);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MIN_FILTER, glad.GL_NEAREST);
        glad.glTexParameteri(glad.GL_TEXTURE_2D, glad.GL_TEXTURE_MAG_FILTER, glad.GL_NEAREST);

        glad.glTexImage2D(
            glad.GL_TEXTURE_2D,
            0,
            glad.GL_RGBA,
            @intCast(width),
            @intCast(height),
            0,
            glad.GL_RGBA,
            glad.GL_UNSIGNED_BYTE,
            data,
        );

        glad.glGenerateMipmap(glad.GL_TEXTURE_2D);

        try self.list.append(tex);
        return tex;
    }

    pub fn bind(self: *TextureManager, texture: t.Texture) void {
        if (self.bound == texture.index) {
            return;
        }

        glad.glBindTexture(glad.GL_TEXTURE_2D, texture.index);
        self.bound = texture.index;
    }

    pub fn delete(self: *TextureManager, texture: t.Texture) void {
        var remove_index: usize = 65535;
        for (self.list.items, 0..) |*tex, i| {
            _ = i;
            if (tex.id == texture.index) {
                tex.ref_count -= 1;
                if (tex.ref_count == 0) {
                    glad.glDeleteTextures(1, &tex.id);
                    tex.id = 0;
                }
            }
        }

        if (remove_index != 65535) {
            _ = self.list.swapRemove(remove_index);
        }
    }
};

shader: Shader = undefined,
meshes: MeshManager = undefined,
textures: TextureManager = undefined,

pub fn init(ctx: *anyopaque, width: u16, height: u16, title: []const u8) anyerror!void {
    var self = t.coerce_ptr(Self, ctx);
    try zwin.init(.OpenGL, 4, 6);

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
    glad.glClearColor(1.0, 1.0, 1.0, 1.0);

    var str = glad.glGetString(glad.GL_VERSION);
    std.debug.print("OpenGL Version: {s}\n", .{str});

    try self.shader.init();
    try self.meshes.init();
    try self.textures.init();
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
}

pub fn end_frame(ctx: *anyopaque) void {
    var self = t.coerce_ptr(Self, ctx);
    zwin.render();

    self.meshes.gc();
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
    var self = t.coerce_ptr(Self, ctx);

    var texture = self.textures.load_texture(path) catch unreachable;

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
}

/// Destroys a texture
pub fn destroy_texture(ctx: *anyopaque, texture: t.Texture) void {
    var self = t.coerce_ptr(Self, ctx);
    self.textures.delete(texture);
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
