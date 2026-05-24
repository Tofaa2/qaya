$input v_worldPos, v_normal, v_texcoord0, v_color0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);

// Directional light
uniform vec4 u_lightDir;       // xyz = direction, w = unused
uniform vec4 u_lightColor;     // rgb = color, w = intensity

// Point lights (up to 4)
uniform vec4 u_lightPos[4];    // xyz = position, w = radius
uniform vec4 u_lightPosColor[4]; // rgb = color, w = intensity

// Counts and ambient
uniform vec4 u_lightCounts;    // x = num point lights, y = has directional (1.0/0.0)
uniform vec4 u_ambientColor;   // rgb = color, w = strength

// Camera and surface properties
uniform vec4 u_cameraPos;      // xyz = camera world position
uniform vec4 u_surfaceProps;   // x = shininess (0 = default 32), y = specular strength (0 = default 0.5)
uniform vec4 u_baseColor;      // rgba = base color (used when no texture)

void main()
{
    vec3 N = normalize(v_normal);
    vec3 V = normalize(u_cameraPos.xyz - v_worldPos);

    // Sample albedo from texture, modulated by base color
    vec4 texColor = texture2D(s_texColor, v_texcoord0);
    vec4 albedo = vec4(texColor.rgb * u_baseColor.rgb, texColor.a * u_baseColor.a);

    float shininess    = u_surfaceProps.x > 0.0 ? u_surfaceProps.x : 32.0;
    float specStrength = u_surfaceProps.y > 0.0 ? u_surfaceProps.y : 0.5;

    // Ambient
    vec3 ambient = u_ambientColor.rgb * u_ambientColor.w;

    vec3 totalDiffuse  = vec3_splat(0.0);
    vec3 totalSpecular = vec3_splat(0.0);

    // Directional light
    if (u_lightCounts.y > 0.5)
    {
        vec3 L = normalize(-u_lightDir.xyz);
        float diff = max(dot(N, L), 0.0);
        totalDiffuse += u_lightColor.rgb * u_lightColor.w * diff;

        vec3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), shininess);
        totalSpecular += u_lightColor.rgb * u_lightColor.w * spec * specStrength;
    }

    // Point lights
    int numPointLights = int(u_lightCounts.x);
    for (int i = 0; i < 4; i++)
    {
        if (i >= numPointLights) break;

        vec3 lightPos = u_lightPos[i].xyz;
        float radius  = u_lightPos[i].w;
        vec3 lColor   = u_lightPosColor[i].rgb;
        float lIntensity = u_lightPosColor[i].w;

        vec3 L = lightPos - v_worldPos;
        float dist = length(L);
        L = normalize(L);

        // Attenuation: smooth falloff
        float atten = clamp(1.0 - dist / radius, 0.0, 1.0);
        atten *= atten;

        float diff = max(dot(N, L), 0.0);
        totalDiffuse += lColor * lIntensity * diff * atten;

        vec3 H = normalize(L + V);
        float spec = pow(max(dot(N, H), 0.0), shininess);
        totalSpecular += lColor * lIntensity * spec * specStrength * atten;
    }

    vec3 finalColor = (ambient + totalDiffuse) * albedo.rgb + totalSpecular;
    gl_FragColor = vec4(finalColor, albedo.a);
}
