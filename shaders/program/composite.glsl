// Applies translucent tints and order-independent layers: scene * colortex5 + colortex6,
// then the volumetric clouds in front of anything farther away than them - terrain, water,
// glass, particles - e.g. when flying through a cloud. (The sky already has its clouds.)
// Also draws the pack's rain (rain.glsl), over glass as well as behind it.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

flat out vec3 sunDir;

void main() {
    gl_Position = ftransform();
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/space.glsl"
#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
    #define VOLUMETRIC_CLOUDS
    #include "/lib/atmosphere/cloudBuffer.glsl"
    uniform sampler2D depthtex0;
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex5;
uniform sampler2D colortex6;

#ifdef REALISTIC_RAIN
#ifdef WORLD_OVERWORLD
    #define PACK_RAIN
    #include "/lib/atmosphere/sky.glsl"
    #include "/lib/materials/columnMaps.glsl"
    #include "/lib/atmosphere/rain.glsl"
    uniform sampler2D depthtex1;
#endif
#endif

flat in vec3 sunDir;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    #ifdef UNDERWATER_DISTORTION
        if (isEyeInWater == 1) {
            // Gentle wobble while the camera is under water.
            float t = frameTimeCounter;
            uv += vec2(sin(uv.y * 18.0 + t * 1.7), cos(uv.x * 14.0 + t * 1.3)) * 0.0018;
            uv = clamp(uv, vec2(0.0), vec2(1.0));
            pixel = ivec2(uv * vec2(viewWidth, viewHeight));
        }
    #endif

    vec3 color = textureLod(colortex0, uv, 0.0).rgb;
    color = color * texelFetch(colortex5, pixel, 0).rgb + texelFetch(colortex6, pixel, 0).rgb;

    #ifdef VOLUMETRIC_CLOUDS
        float depth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
        vec2 screenUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
        if (depth < 1.0 && length(ScreenToView(screenUV, depth)) > SampleCloudDistance(screenUV)) {
            vec4 clouds = SampleClouds(screenUV);
            color = color * clouds.a + clouds.rgb;
        }
    #endif
    #ifdef PACK_RAIN
        if (rainStrength > 0.001) {
            float opaqueDepth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
            vec2 rainUV = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
            vec3 rainView = ScreenToView(rainUV, opaqueDepth);
            vec4 rain = RainStreaks(normalize(ViewToPlayerDir(rainView)), opaqueDepth >= 1.0 ? 1e6 : length(rainView), sunDir);
            color = mix(color, rain.rgb, rain.a);
        }
    #endif
    outColor = vec4(color, 1.0);
}

#endif
