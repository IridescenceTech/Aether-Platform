#version 450

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec4 a_color;
layout(location = 2) in vec2 a_texcoord;

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_uv;

layout(binding = 0) uniform UniformBufferObject {
    mat4 proj;
    mat4 view;
} ubo;

void main() {
    gl_Position = ubo.proj * ubo.view * vec4(a_pos, 1.0);
    v_color = a_color;
    v_uv = a_texcoord;
}