// Deferred resolve (deferred1, after the cloud pass): draws the sky behind everything,
// lights every opaque G-buffer pixel once, adds the volumetric clouds to the sky (so water
// reflects and refracts them), then composites the pre-deferred overlay (vanilla clouds,
// glint, glowing eyes, beacon beams).

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texCoord;
flat out vec3 sunDir;
flat out vec3 lightDir;

void main() {
    gl_Position = ftransform();
    texCoord = gl_MultiTexCoord0.xy;
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"
#include "/lib/atmosphere/sky.glsl"
#ifndef WORLD_NETHER
    #include "/lib/lighting/shadowSpace.glsl"
    #include "/lib/lighting/shadows.glsl"
#endif
#include "/lib/lighting/lighting.glsl"
#include "/lib/lighting/specular.glsl"
#include "/lib/atmosphere/fog.glsl"
#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
    #define VOLUMETRIC_CLOUDS
    #include "/lib/atmosphere/cloudBuffer.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

in vec2 texCoord;
flat in vec3 sunDir;
flat in vec3 lightDir;

#define EMISSION_BRIGHTNESS 2.5

/* RENDERTARGETS: 0,7 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSceneCopy; // read by screen-space reflections

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    float depth = texelFetch(depthtex0, pixel, 0).r;
    int shadingModel = DecodeId(texelFetch(colortex3, pixel, 0).r);
    vec3 playerPos = ViewToPlayer(ScreenToView(texCoord, depth));

    if (depth == 1.0) {
        // Sky: colortex0 holds only what vanilla drew on top (sun, moon), cleared to black.
        vec3 dir = normalize(playerPos);
        color += isEyeInWater == 1 ? GetSkyFromUnderwater(dir, sunDir) : GetSky(dir, sunDir, PixelAngle());
        #ifdef VOLUMETRIC_CLOUDS
            vec4 clouds = SampleClouds(texCoord);
            color = color * clouds.a + clouds.rgb;
        #endif
        color = ApplyFog(color, playerPos, sunDir, true);
    } else if (shadingModel != SM_KEEP) {
        vec4 albedoAo = texelFetch(colortex1, pixel, 0);
        vec4 normalLight = texelFetch(colortex2, pixel, 0);
        vec4 material = texelFetch(colortex3, pixel, 0);

        vec3 albedo = SrgbToLinear(albedoAo.rgb);
        vec3 normal = DecodeNormal(normalLight.xy);

        vec2 lm = normalLight.zw;

        Surface surf;
        surf.playerPos = playerPos;
        surf.normal = normal;
        surf.lm = lm;
        surf.ao = albedoAo.a;
        surf.foliage = shadingModel == SM_FOLIAGE || shadingModel == SM_LEAVES;
        surf.useShadowMap = shadingModel != SM_HAND; // hand depth uses its own projection

        vec3 sunLight;
        vec3 light = GetLighting(surf, sunDir, lightDir, sunLight);

        // Specular (X1): metals give most of their light back as reflection, so they keep
        // only a little diffuse light; what the surface reflects is added by the reflection
        // passes (deferred2/3), the sun/moon highlight here.
        float smoothness = material.b, metalness = material.a;
        vec3 V = -normalize(playerPos);
        float roughness = RoughnessFromSmoothness(smoothness);
        vec3 f0 = SpecularF0(albedo, metalness);
        vec3 F = FresnelRoughness(dot(normal, V), f0, roughness);
        float diffuseScale = 1.0 - metalness * 0.8;
        #if BLOCK_REFLECTIONS == 2
            diffuseScale *= 1.0 - Luminance(F) * smoothness;
        #endif
        color = albedo * light * diffuseScale;
        #if BLOCK_REFLECTIONS >= 1
            if (smoothness > 0.05) color += sunLight * SpecularHighlight(normal, V, lightDir, roughness, f0) * smoothness;
        #endif
        color += albedo * material.g * EMISSION_BRIGHTNESS;
        color = ApplyFog(color, playerPos, sunDir, false);
    }

    // (Clouds in front of terrain, water and everything else are added in composite, after
    // the translucent pass.)

    vec4 overlay = texelFetch(colortex4, pixel, 0);
    color = color * (1.0 - overlay.a) + overlay.rgb;

    outColor = vec4(color, 1.0);
    outSceneCopy = vec4(color, 1.0);
}

#endif
