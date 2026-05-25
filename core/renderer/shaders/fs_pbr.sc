$input v_worldPos, v_normal, v_texcoord0, v_color0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 1);
SAMPLER2D(s_envMap, 0);

uniform vec4 u_lightDir;
uniform vec4 u_lightColor;
uniform vec4 u_ambientColor;
uniform vec4 u_cameraPos;
uniform vec4 u_lightCounts;
uniform vec4 u_lightPos[4];
uniform vec4 u_lightPosColor[4];
uniform vec4 u_metallicRoughness;
uniform vec4 u_baseColor;
uniform vec4 u_envIntensity;

#define PI 3.14159265358979

vec2 dirToLatLong(vec3 dir)
{
    vec2 uv = vec2(atan2(dir.z, dir.x), asin(dir.y));
    uv *= vec2(0.5 / PI, 1.0 / PI);
    uv += 0.5;
    return uv;
}

vec3 sampleEnv(vec3 dir)
{
    vec2 uv = dirToLatLong(normalize(dir));
    uv.y = 1.0 - uv.y;
    return texture2D(s_envMap, uv).rgb * u_envIntensity.x;
}

vec3 sampleEnvRough(vec3 dir, float roughness)
{
    vec3 color = sampleEnv(dir);
    if (roughness > 0.02)
    {
        vec3 u = normalize(cross(dir, vec3(0.0, 1.0, 0.0)));
        if (length(u) < 0.01) u = normalize(cross(dir, vec3(1.0, 0.0, 0.0)));
        vec3 v = cross(dir, u);

        float offset = roughness * 0.15;
        color += sampleEnv(dir + u * offset);
        color += sampleEnv(dir - u * offset);
        color += sampleEnv(dir + v * offset);
        color += sampleEnv(dir - v * offset);
        color /= 5.0;
    }
    return color;
}

vec3 sampleEnvDiffuse(vec3 N)
{
    return sampleEnvRough(N, 0.8);
}

float D_GGX(float NdotH, float roughness)
{
    float a  = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (PI * denom * denom);
}

vec3 F_Schlick(float cosTheta, vec3 F0)
{
    return F0 + (vec3_splat(1.0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float G_Schlick(float NdotV, float NdotL, float roughness)
{
    float k  = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float gv = NdotV / (NdotV * (1.0 - k) + k);
    float gl = NdotL / (NdotL * (1.0 - k) + k);
    return gv * gl;
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3_splat(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

// Lazarov 2013 — better BRDF LUT approximation than Karis
vec2 integrateBRDF(float NdotV, float roughness)
{
    vec4 c0 = vec4(-1.0, -0.0275, -0.572,  0.022);
    vec4 c1 = vec4( 1.0,  0.0425,  1.04,  -0.04);
    vec4 r  = roughness * c0 + c1;
    float a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
    return vec2(-1.04, 1.04) * a004 + r.zw;
}

float getAttenuation(float dist, float radius)
{
    float x = clamp(dist / radius, 0.0, 1.0);
    x = 1.0 - x;
    return x * x;
}

// ACES fitted tonemapping (Narkowicz 2015)
vec3 ACESFilm(vec3 x)
{
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main()
{
    vec3 N = normalize(v_normal);
    vec3 V = normalize(u_cameraPos.xyz - v_worldPos);
    vec3 R = reflect(-V, N);

    float NdotV = max(dot(N, V), 0.0001);

    vec4 texColor = texture2D(s_texColor, v_texcoord0);
    vec3 albedo   = pow(texColor.rgb * u_baseColor.rgb, vec3_splat(2.2)); // sRGB -> linear
    float alpha   = texColor.a * u_baseColor.a;
    float metallic  = u_metallicRoughness.x;
    float roughness = max(u_metallicRoughness.y, 0.04);

    // Metals use albedo as F0; dielectrics use 0.04
    vec3 F0 = mix(vec3_splat(0.04), albedo, metallic);

    // IBL — actual HDR equirectangular sampling
    vec3 irradiance  = sampleEnvDiffuse(N);
    vec3 prefiltered = sampleEnvRough(R, roughness);

    vec3 F_env = fresnelSchlickRoughness(NdotV, F0, roughness);
    vec3 kD    = (vec3_splat(1.0) - F_env) * (1.0 - metallic);

    vec2 brdf = integrateBRDF(NdotV, roughness);

    vec3 diffuse_ibl  = kD * albedo * irradiance;
    vec3 specular_ibl = prefiltered * (F_env * brdf.x + brdf.y);

    vec3 ambient = diffuse_ibl + specular_ibl;

    // Direct lighting accumulation
    vec3 Lo = vec3_splat(0.0);

    // Directional light
    if (u_lightCounts.y > 0.5)
    {
        vec3 L        = normalize(-u_lightDir.xyz);
        vec3 radiance = u_lightColor.rgb * u_lightColor.w;
        float NdotL   = max(dot(N, L), 0.0);

        if (NdotL > 0.0)
        {
            vec3  H     = normalize(L + V);
            float NdotH = max(dot(N, H), 0.0);
            float HdotV = max(dot(H, V), 0.0);

            float D = D_GGX(NdotH, roughness);
            float G = G_Schlick(NdotV, NdotL, roughness);
            vec3  F = F_Schlick(HdotV, F0);

            // Correct Cook-Torrance specular — includes denominator 4*NdotV*NdotL
            vec3 spec = F * D * G / max(4.0 * NdotV * NdotL, 0.001);

            vec3 kd = (vec3_splat(1.0) - F) * (1.0 - metallic);
            Lo += (kd * albedo / PI + spec) * radiance * NdotL;
        }
    }

    // Point lights
    int numPointLights = int(u_lightCounts.x);
    for (int i = 0; i < 4; i++)
    {
        if (i >= numPointLights) break;

        vec3  lightPos   = u_lightPos[i].xyz;
        float radius     = u_lightPos[i].w;
        vec3  lColor     = u_lightPosColor[i].rgb;
        float lIntensity = u_lightPosColor[i].w;

        vec3  L    = lightPos - v_worldPos;
        float dist = length(L);
        L = normalize(L);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0)
        {
            float attenuation = getAttenuation(dist, radius);
            vec3  radiance    = lColor * lIntensity * attenuation;

            vec3  H     = normalize(L + V);
            float NdotH = max(dot(N, H), 0.0);
            float HdotV = max(dot(H, V), 0.0);

            float D = D_GGX(NdotH, roughness);
            float G = G_Schlick(NdotV, NdotL, roughness);
            vec3  F = F_Schlick(HdotV, F0);

            vec3 spec = F * D * G / max(4.0 * NdotV * NdotL, 0.001);

            vec3 kd = (vec3_splat(1.0) - F) * (1.0 - metallic);
            Lo += (kd * albedo / PI + spec) * radiance * NdotL;
        }
    }

    // Combine IBL ambient + direct lighting
    vec3 colour = ambient + Lo;

    // ACES filmic tonemapping (HDR -> LDR)
    colour = ACESFilm(colour);

    // Gamma correction (linear -> sRGB)
    colour = pow(colour, vec3_splat(1.0 / 2.2));

    gl_FragColor = vec4(colour, alpha);
}
