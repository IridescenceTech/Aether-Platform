#version 450

layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec4 a_color;
layout(location = 2) in vec2 a_texcoord;

layout(location = 0) out vec4 v_color;
layout(location = 1) out vec2 v_uv;
layout(location = 2) out flat uint v_id;
layout(location = 3) out flat uint v_flags;

layout(binding = 0) uniform UniformBufferObject {
    mat4 proj;
    mat4 view;
} ubo;

layout (push_constant) uniform PushConstants {
    mat4 model;
    uint flags;
    uint tex_id;
} constants;

void main() {

    vec3 pos = a_pos;
    if((constants.flags & 4u) != 0) {
        pos = vec3(a_pos.x / 32.0, a_pos.y / 32.0, a_pos.z / 32.0);
    }

    gl_Position = ubo.proj * ubo.view * constants.model * vec4(pos, 1.0);
    v_color = a_color;
    v_uv = a_texcoord;
    v_id = constants.tex_id;
    v_flags = constants.flags;
}