// Deferred resolve: draws the sky behind everything, lights every opaque G-buffer pixel
// once, then composites the pre-deferred overlay (vanilla clouds, glint, glowing eyes,
// beacon beams).

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
#include "/lib/lighting/basicLighting.glsl"
#include "/lib/lighting/basicFog.glsl"

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

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    float depth = texelFetch(depthtex0, pixel, 0).r;
    int shadingModel = DecodeId(texelFetch(colortex3, pixel, 0).r);
    vec3 playerPos = ViewToPlayer(ScreenToView(texCoord, depth));

    if (depth == 1.0) {
        // Sky: colortex0 holds only what vanilla drew on top (sun, moon), cleared to black.
        vec3 dir = normalize(playerPos);
        color += GetSky(dir, sunDir, true);
        color = ApplyFog(color, playerPos, sunDir, true);
    } else if (shadingModel != SM_KEEP) {
        vec4 albedoAo = texelFetch(colortex1, pixel, 0);
        vec4 normalLight = texelFetch(colortex2, pixel, 0);
        vec4 material = texelFetch(colortex3, pixel, 0);

        vec3 albedo = SrgbToLinear(albedoAo.rgb);
        vec3 normal = DecodeNormal(normalLight.xy);

        vec2 lm = normalLight.zw;
        lm.x = max(lm.x, HeldLight(length(playerPos)));

        bool foliage = shadingModel == SM_FOLIAGE || shadingModel == SM_LEAVES;
        float NdotL = foliage ? abs(dot(normal, lightDir)) : saturate(dot(normal, lightDir));

        color = albedo * GetBasicLighting(lm, NdotL, albedoAo.a, foliage, sunDir);
        color += albedo * material.g * EMISSION_BRIGHTNESS;
        color = ApplyFog(color, playerPos, sunDir, false);
    }

    vec4 overlay = texelFetch(colortex4, pixel, 0);
    color = color * (1.0 - overlay.a) + overlay.rgb;

    outColor = vec4(color, 1.0);
}

#endif
