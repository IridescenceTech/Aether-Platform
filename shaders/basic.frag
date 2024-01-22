#version 450

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_id;

layout(location = 0) out vec4 f_color;

layout(binding = 1) uniform sampler2D tex_sampler[128];

void main() {
    f_color = vec4(texture(tex_sampler[v_id + 1], v_uv));
} 