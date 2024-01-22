#version 450

layout(location = 0) in vec4 v_color;
layout(location = 1) in vec2 v_uv;
layout(location = 2) in flat uint v_id;
layout(location = 3) in flat uint v_flags;

layout(location = 0) out vec4 f_color;

layout(binding = 1) uniform sampler2D tex_sampler[128];

void main() {

    // Check if texture exists
    if ((v_flags & 1u) != 0) {
        if((v_flags & 2u) != 0) {
            f_color = v_color * texture(tex_sampler[v_id], v_uv);
        } else {
            f_color = texture(tex_sampler[v_id], v_uv);
        }
    } else if ((v_flags & 2u) != 0) {
        f_color = v_color;
    } else { 
        f_color = vec4(0.0, 0.0, 0.0, 1.0);
    }
} 