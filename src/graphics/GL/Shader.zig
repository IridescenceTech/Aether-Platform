const std = @import("std");
const Shader = @This();
const Allocator = @import("../../allocator.zig");
const glad = @import("glad");

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

const vShaderES =
    \\#version 300 es
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

const fShaderES =
    \\#version 300 es
    \\precision mediump float;
    \\out vec4 FragColor;
    \\in vec4 vertexColor;
    \\in vec2 uv;
    \\
    \\uniform sampler2D tex;
    \\
    \\void main()
    \\{
    \\    FragColor = vertexColor * texture(tex, uv);
    \\}
;

program: u32 = 0,

pub fn init(self: *Shader, gles: bool) !void {
    var vertex = glad.glCreateShader(glad.GL_VERTEX_SHADER);
    defer glad.glDeleteShader(vertex);

    var fragment = glad.glCreateShader(glad.GL_FRAGMENT_SHADER);
    defer glad.glDeleteShader(fragment);

    var alloc = try Allocator.allocator();

    var vShaderSource = try alloc.dupeZ(u8, if (gles) vShaderES else vShader);
    defer alloc.free(vShaderSource);

    var fShaderSource = try alloc.dupeZ(u8, if (gles) fShaderES else fShader);
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

    var texLoc = glad.glGetUniformLocation(self.program, "tex");
    glad.glUniform1i(texLoc, 0);

    std.log.info("Shader initialized", .{});
}

pub fn use(self: *Shader) void {
    glad.glUseProgram(self.program);
}
