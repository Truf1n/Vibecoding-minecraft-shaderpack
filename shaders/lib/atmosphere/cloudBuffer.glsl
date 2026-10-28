#ifndef CLOUD_BUFFER_GLSL
#define CLOUD_BUFFER_GLSL

// Reading the cloud pass results (program/clouds.glsl). colortex9/10 are allocated at
// 1/CLOUD_RES_DIV of the screen size (size.buffer in shaders.properties):
//   colortex9  rgb light scattered by the clouds, a transmittance (1 = no cloud)
//   colortex10 r   typical distance of the cloud along the view ray
// Needs: common.glsl.

uniform sampler2D colortex9;
uniform sampler2D colortex10;


// Screen uv -> cloud buffer uv (kept half a texel inside, so bilinear filtering never
// wraps around the edge).
vec2 CloudBufferUV(vec2 uv) {
    vec2 halfTexel = 0.5 / vec2(textureSize(colortex9, 0));
    return clamp(uv, halfTexel, 1.0 - halfTexel);
}

vec4 SampleClouds(vec2 uv) { return texture(colortex9, CloudBufferUV(uv)); }
float SampleCloudDistance(vec2 uv) { return texture(colortex10, CloudBufferUV(uv)).r; }

// Clouds seen in a world-space direction (for reflections and the view out of the water),
// from the cloud panorama (program/skyView.glsl), so they are there whether or not that
// direction is on screen. rgb scatter, a transmittance. Below the horizon: none.
#include "/lib/atmosphere/skyView.glsl"
uniform sampler2D skyViewSampler;

vec4 SkyViewTexel(ivec2 t) {
    t.x = (t.x + SKY_VIEW_SIZE.x) % SKY_VIEW_SIZE.x;
    t.y = clamp(t.y, 0, SKY_VIEW_SIZE.y - 1);
    return texelFetch(skyViewSampler, t, 0);
}

vec4 CloudsInDirection(vec3 dir) {
    if (dir.y <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
    vec2 pos = SkyViewCoord(dir) * vec2(SKY_VIEW_SIZE) - 0.5;
    ivec2 base = ivec2(floor(pos));
    vec2 f = pos - vec2(base);
    vec4 c = mix(mix(SkyViewTexel(base), SkyViewTexel(base + ivec2(1, 0)), f.x),
                 mix(SkyViewTexel(base + ivec2(0, 1)), SkyViewTexel(base + ivec2(1, 1)), f.x), f.y);
    // Fade in just above the horizon (the panorama's lowest row).
    float w = smoothstep(0.0, 0.03, dir.y);
    return vec4(c.rgb * w, mix(1.0, c.a, w));
}

#endif
