// Applies translucent tints and order-independent layers: scene * colortex5 + colortex6,
// then the volumetric clouds in front of anything farther away than them - terrain, water,
// glass, particles - e.g. when flying through a cloud. (The sky already has its clouds.)

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
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
    outColor = vec4(color, 1.0);
}

#endif
