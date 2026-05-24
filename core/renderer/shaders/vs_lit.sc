$input a_position, a_normal, a_texcoord0, a_color0
$output v_worldPos, v_normal, v_texcoord0, v_color0

#include <bgfx_shader.sh>

void main()
{
    vec3 worldPos = mul(u_model[0], vec4(a_position, 1.0)).xyz;
    v_worldPos = worldPos;
    v_normal = normalize(mul(u_model[0], vec4(a_normal, 0.0)).xyz);
    v_texcoord0 = a_texcoord0;
    v_color0 = a_color0;
    gl_Position = mul(u_viewProj, vec4(worldPos, 1.0));
}
