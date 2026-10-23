// Deferred resolve: lights every opaque G-buffer pixel once, then composites the
// pre-deferred overlay (vanilla clouds, glint, glowing eyes, beacon beams).

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texCoord;
flat out vec3 lightDirWorld;

void main() {
    gl_Position = ftransform();
    texCoord = gl_MultiTexCoord0.xy;
    lightDirWorld = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"
#include "/lib/lighting/basicLighting.glsl"
#include "/lib/lighting/basicFog.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D depthtex0;

in vec2 texCoord;
flat in vec3 lightDirWorld;

#define EMISSION_BRIGHTNESS 4.0

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    int shadingModel = DecodeId(texelFetch(colortex3, pixel, 0).r);

    #ifdef WORLD_NETHER
        // No sky geometry in the Nether: background pixels still hold the (sRGB) clear colour.
        if (texelFetch(depthtex0, pixel, 0).r == 1.0) color = SrgbToLinear(fogColor);
    #endif

    if (shadingModel != SM_KEEP) {
        vec4 albedoAo = texelFetch(colortex1, pixel, 0);
        vec4 normalLight = texelFetch(colortex2, pixel, 0);
        float emission = texelFetch(colortex3, pixel, 0).g;

        vec3 albedo = SrgbToLinear(albedoAo.rgb);
        vec3 normal = DecodeNormal(normalLight.xy);
        vec3 playerPos = ViewToPlayer(ScreenToView(texCoord, texelFetch(depthtex0, pixel, 0).r));

        vec2 lm = normalLight.zw;
        lm.x = max(lm.x, HeldLight(length(playerPos)));

        bool foliage = shadingModel == SM_FOLIAGE || shadingModel == SM_LEAVES;
        float NdotL = foliage ? abs(dot(normal, lightDirWorld)) : saturate(dot(normal, lightDirWorld));

        color = albedo * GetBasicLighting(lm, NdotL, albedoAo.a, foliage);
        color += albedo * emission * EMISSION_BRIGHTNESS;
        color = ApplyFog(color, playerPos, false);
    }

    vec4 overlay = texelFetch(colortex4, pixel, 0);
    color = color * (1.0 - overlay.a) + overlay.rgb;

    outColor = vec4(color, 1.0);
}

#endif
