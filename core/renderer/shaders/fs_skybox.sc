$input v_skyDir

#include <bgfx_shader.sh>

SAMPLER2D(s_envMap, 0);

uniform vec4 u_envIntensity;

vec2 dirToLatLong(vec3 dir)
{
    vec2 uv = vec2(atan2(dir.z, dir.x), asin(dir.y));
    uv *= vec2(0.5 / 3.14159265, 1.0 / 3.14159265);
    uv += 0.5;
    return uv;
}

void main()
{
    vec2 uv = dirToLatLong(normalize(v_skyDir));
    uv.y = 1.0 - uv.y;
    vec3 env = texture2D(s_envMap, uv).rgb * u_envIntensity.x;
    gl_FragColor = vec4(env, 1.0);
}
