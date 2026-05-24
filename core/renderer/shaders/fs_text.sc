$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);
uniform vec4 u_color;

void main()
{
    vec4 texel = texture2D(s_texColor, v_texcoord0);
    gl_FragColor = vec4(u_color.rgb, texel.a * u_color.a);
}
