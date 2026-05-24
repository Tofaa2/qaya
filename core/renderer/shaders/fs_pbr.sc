$input v_worldPos, v_normal, v_texcoord0, v_color0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);
SAMPLER2D(s_envMap, 1);

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

float D_GGX(float NdotH, float roughness)
{
    float a = roughness * roughness;
    float a2 = a * a;
    float denom = NdotH * NdotH * (a2 - 1.0) + 1.0;
    return a2 / (denom * denom);
}

vec3 F_Schlick(float cosTheta, vec3 F0)
{
    return F0 + (vec3_splat(1.0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float G_Schlick(float NdotV, float NdotL, float roughness)
{
    float k = (roughness + 1.0) * (roughness + 1.0) / 8.0;
    float gv = NdotV / (NdotV * (1.0 - k) + k);
    float gl = NdotL / (NdotL * (1.0 - k) + k);
    return gv * gl;
}

vec3 fresnelSchlickRoughness(float cosTheta, vec3 F0, float roughness)
{
    return F0 + (max(vec3_splat(1.0 - roughness), F0) - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}

float getAttenuation(float dist, float radius)
{
    float x = clamp(dist / radius, 0.0, 1.0);
    x = 1.0 - x;
    return x * x;
}

vec2 dirToLatLong(vec3 dir)
{
    vec2 uv = vec2(atan2(dir.z, dir.x), asin(dir.y));
    uv *= vec2(0.5 / 3.14159265, 1.0 / 3.14159265);
    uv += 0.5;
    return uv;
}

vec3 sampleEnvironment(vec3 dir)
{
    if (u_envIntensity.w > 0.5)
    {
        vec2 uv = dirToLatLong(dir);
        return texture2D(s_envMap, uv).rgb * u_envIntensity.x;
    }

    float hemi = dir.y * 0.5 + 0.5;
    vec3 sky = u_ambientColor.rgb * u_ambientColor.w;
    vec3 env = mix(vec3_splat(0.18), sky, hemi);

    vec3 sunDir = normalize(-u_lightDir.xyz);
    float sun = pow(max(dot(dir, sunDir), 0.0), 64.0);
    env += u_lightColor.rgb * u_lightColor.w * sun * 2.0;

    float horizonGlow = pow(1.0 - abs(dir.y), 3.0);
    env += sky * horizonGlow * 0.3;

    return env;
}

void main()
{
    vec3 N = normalize(v_normal);
    vec3 V = normalize(u_cameraPos.xyz - v_worldPos);
    vec3 R = reflect(-V, N);

    vec4 texColor = texture2D(s_texColor, v_texcoord0);
    vec3 albedo = texColor.rgb * u_baseColor.rgb;
    float alpha = texColor.a * u_baseColor.a;

    float metallic = u_metallicRoughness.x;
    float roughness = max(u_metallicRoughness.y, 0.04);

    vec3 F0 = mix(vec3_splat(0.04), albedo, metallic);

    vec3 diffuse_acc = vec3_splat(0.0);
    vec3 specular_acc = vec3_splat(0.0);

    // IBL: environment reflected on the surface
    vec3 irradiance = sampleEnvironment(N);
    vec3 prefiltered = sampleEnvironment(R);

    vec3 F_env = fresnelSchlickRoughness(max(dot(N, V), 0.0), F0, roughness);
    vec3 kD = (vec3_splat(1.0) - F_env) * (1.0 - metallic);

    vec2 brdf = vec2(0.04, 1.0);

    vec3 diffuse_ibl = kD * albedo * irradiance;
    vec3 specular_ibl = prefiltered * (F_env * brdf.x + brdf.y);
    vec3 ambient = diffuse_ibl + specular_ibl;

    // Directional light
    if (u_lightCounts.y > 0.5)
    {
        vec3 L = normalize(-u_lightDir.xyz);
        vec3 radiance = u_lightColor.rgb * u_lightColor.w;

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0)
        {
            vec3 H = normalize(L + V);
            float NdotH = max(dot(N, H), 0.0);
            float NdotV = max(dot(N, V), 0.0);
            float HdotV = max(dot(H, V), 0.0);

            float D = D_GGX(NdotH, roughness);
            float G = G_Schlick(NdotV, NdotL, roughness);
            vec3 F = F_Schlick(HdotV, F0);

            diffuse_acc += albedo * radiance * NdotL * (1.0 - metallic);
            specular_acc += F * radiance * D * G * NdotL;
        }
    }

    // Point lights
    int numPointLights = int(u_lightCounts.x);
    for (int i = 0; i < 4; i++)
    {
        if (i >= numPointLights) break;

        vec3 lightPos = u_lightPos[i].xyz;
        float radius = u_lightPos[i].w;
        vec3 lColor = u_lightPosColor[i].rgb;
        float lIntensity = u_lightPosColor[i].w;

        vec3 L = lightPos - v_worldPos;
        float dist = length(L);
        L = normalize(L);

        float NdotL = max(dot(N, L), 0.0);
        if (NdotL > 0.0)
        {
            float attenuation = getAttenuation(dist, radius);
            vec3 radiance = lColor * lIntensity * attenuation;

            vec3 H = normalize(L + V);
            float NdotH = max(dot(N, H), 0.0);
            float NdotV = max(dot(N, V), 0.0);
            float HdotV = max(dot(H, V), 0.0);

            float D = D_GGX(NdotH, roughness);
            float G = G_Schlick(NdotV, NdotL, roughness);
            vec3 F = F_Schlick(HdotV, F0);

            diffuse_acc += albedo * radiance * NdotL * (1.0 - metallic);
            specular_acc += F * radiance * D * G * NdotL;
        }
    }

    vec3 colour = ambient + diffuse_acc + specular_acc;
    colour = max(colour, vec3_splat(0.005));
    gl_FragColor = vec4(colour, alpha);
}
