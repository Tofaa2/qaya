$input a_position
$output v_skyDir

#include <bgfx_shader.sh>

void main()
{
    vec4 world_pos = mul(u_model[0], vec4(a_position, 1.0));
    v_skyDir = a_position;
    gl_Position = mul(u_viewProj, world_pos).xyww;
}
