const std = @import("std");
const Shader = @This();
const Allocator = @import("../../allocator.zig");
const glad = @import("glad");

const vShader =
    \\#version 460 core
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec4 aCol;
    \\layout (location = 2) in vec2 aTex;
    \\
    \\layout (std140) uniform Matrices {
    \\  mat4 projection;
    \\  mat4 view;
    \\};
    \\
    \\uniform mat4 model;
    \\
    \\out VS_OUT {
    \\  vec4 vertexColor;
    \\  vec2 uv;
    \\} vs_out;
    \\
    \\uniform uint flags;
    \\
    \\void main()
    \\{
    \\    vec3 pos = aPos;
    \\    if((flags & 4u) != 0) {
    \\       // We're in 5 bit fixed point (1/32)
    \\       pos = vec3(aPos.x / 32.0, aPos.y / 32.0, aPos.z / 32.0);
    \\    }
    \\    gl_Position = projection * view * model * vec4(aPos, 1.0);
    \\    vs_out.vertexColor = aCol;
    \\    vs_out.uv = aTex;
    \\}
;

const vShaderES =
    \\#version 320 es
    \\layout (location = 0) in vec3 aPos;
    \\layout (location = 1) in vec4 aCol;
    \\layout (location = 2) in vec2 aTex;
    \\
    \\layout (std140) uniform Matrices {
    \\  mat4 projection;
    \\  mat4 view;
    \\};
    \\
    \\uniform mat4 model;
    \\
    \\out VS_OUT {
    \\  vec4 vertexColor;
    \\  vec2 uv;
    \\  flat uint flags;
    \\} vs_out;
    \\
    \\uniform uint flags;
    \\
    \\void main()
    \\{
    \\    vec3 pos = aPos;
    \\    if((flags & 4u) != 0u) {
    \\       // We're in 5 bit fixed point (1/32)
    \\       pos = vec3(aPos.x / 32.0, aPos.y / 32.0, aPos.z / 32.0);
    \\    }
    \\    gl_Position = projection * view * model * vec4(aPos, 1.0);
    \\    vs_out.vertexColor = aCol;
    \\    vs_out.uv = aTex;
    \\    vs_out.flags = flags;
    \\}
;

const fShader =
    \\#version 460 core
    \\out vec4 FragColor;
    \\
    \\in VS_OUT {
    \\  vec4 vertexColor;
    \\  vec2 uv;
    \\} fs_in;
    \\
    \\uniform sampler2D tex;
    \\uniform uint flags;
    \\
    \\void main()
    \\{
    \\
    \\  // Check if texture exists
    \\  if ((flags & 1u) != 0) {
    \\      // Check if color exists
    \\      if((flags & 2u) != 0) {
    \\          FragColor = fs_in.vertexColor * texture(tex, fs_in.uv);
    \\      } else {
    \\          FragColor = texture(tex, fs_in.uv);
    \\      }
    \\  } else if ((flags & 2u) != 0) {
    \\      FragColor = fs_in.vertexColor;
    \\  } else {
    \\      FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    \\  }
    \\}
;

const fShaderES =
    \\#version 320 es
    \\precision mediump float;
    \\out vec4 FragColor;
    \\
    \\in VS_OUT {
    \\  vec4 vertexColor;
    \\  vec2 uv;
    \\  flat uint flags;
    \\} fs_in;
    \\
    \\uniform sampler2D tex;
    \\
    \\void main()
    \\{
    \\
    \\  // Check if texture exists
    \\  if ((fs_in.flags & 1u) != 0u) {
    \\      // Check if color exists
    \\      if((fs_in.flags & 2u) != 0u) {
    \\          FragColor = fs_in.vertexColor * texture(tex, fs_in.uv);
    \\      } else {
    \\          FragColor = texture(tex, fs_in.uv);
    \\      }
    \\  } else if ((fs_in.flags & 2u) != 0u) {
    \\      FragColor = fs_in.vertexColor;
    \\  } else {
    \\      FragColor = vec4(0.0, 0.0, 0.0, 1.0);
    \\  }
    \\}
;

pub const Uniforms = struct {
    projection: [16]f32,
    view: [16]f32,
};

pub var program: u32 = 0;
var modelLoc: i32 = 0;
var flagsLoc: i32 = 0;
var ubo: u32 = 0;

const identity = [_]f32{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
};

pub fn init(gles: bool) !void {
    const vertex = glad.glCreateShader(glad.GL_VERTEX_SHADER);
    defer glad.glDeleteShader(vertex);

    const fragment = glad.glCreateShader(glad.GL_FRAGMENT_SHADER);
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
        const infoLog = try alloc.alloc(u8, 512);
        defer alloc.free(infoLog);

        glad.glGetShaderInfoLog(vertex, 512, null, infoLog.ptr);
        std.log.err("Vertex shader compilation failed: {s}", .{infoLog});
        return error.ShaderCompileError;
    }

    glad.glGetShaderiv(fragment, glad.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        const infoLog = try alloc.alloc(u8, 512);
        defer alloc.free(infoLog);

        glad.glGetShaderInfoLog(fragment, 512, null, infoLog.ptr);
        std.log.err("Fragment shader compilation failed: {s}", .{infoLog});
        return error.ShaderCompileError;
    }

    program = glad.glCreateProgram();
    glad.glAttachShader(program, vertex);
    glad.glAttachShader(program, fragment);
    glad.glLinkProgram(program);

    glad.glGetProgramiv(program, glad.GL_LINK_STATUS, &success);
    if (success == 0) {
        const infoLog = try alloc.alloc(u8, 512);
        defer alloc.free(infoLog);

        glad.glGetProgramInfoLog(program, 512, null, infoLog.ptr);
        std.log.err("Shader linking failed: {s}", .{infoLog});
        return error.ShaderLinkError;
    }

    glad.glDeleteShader(vertex);
    glad.glDeleteShader(fragment);

    use();

    const texLoc = glad.glGetUniformLocation(program, "tex");
    glad.glUniform1i(texLoc, 0);

    modelLoc = glad.glGetUniformLocation(program, "model");
    flagsLoc = glad.glGetUniformLocation(program, "flags");

    glad.glGenBuffers(1, &ubo);
    glad.glBindBuffer(glad.GL_UNIFORM_BUFFER, ubo);
    glad.glBufferData(glad.GL_UNIFORM_BUFFER, @sizeOf(Uniforms), null, glad.GL_STATIC_DRAW);
    const blockIndex = glad.glGetUniformBlockIndex(program, "Matrices");
    glad.glBindBufferBase(glad.GL_UNIFORM_BUFFER, blockIndex, ubo);

    set_model(&identity);
    set_projection(&identity);
    set_view(&identity);

    std.log.info("Shader initialized", .{});
}

pub fn use() void {
    glad.glUseProgram(program);
}

pub fn set_flags(flags: *const u32) void {
    glad.glUniform1ui(flagsLoc, flags.*);
}

pub fn set_model(model: [*]const f32) void {
    glad.glUniformMatrix4fv(modelLoc, 1, 0, model);
}

pub fn set_view(view: [*]const f32) void {
    glad.glBufferSubData(glad.GL_UNIFORM_BUFFER, 16 * @sizeOf(f32), 16 * @sizeOf(f32), view);
}

pub fn set_projection(projection: [*]const f32) void {
    glad.glBufferSubData(glad.GL_UNIFORM_BUFFER, 0, 16 * @sizeOf(f32), projection);
}
