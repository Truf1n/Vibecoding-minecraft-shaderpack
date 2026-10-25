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

// Clouds seen in a world-space direction (for reflections and the view out of the water):
// looked up where that direction appears on screen. rgb scatter, a transmittance; no
// clouds if the direction is off screen (faded near the edges).
vec4 CloudsInDirection(vec3 dir) {
    vec3 viewDir = mat3(gbufferModelView) * dir;
    if (viewDir.z > -0.05) return vec4(0.0, 0.0, 0.0, 1.0);
    vec4 clip = gbufferProjection * vec4(viewDir, 1.0);
    vec2 uv = clip.xy / clip.w * 0.5 + 0.5;
    vec2 edge = smoothstep(vec2(0.0), vec2(0.1), uv) * smoothstep(vec2(0.0), vec2(0.1), 1.0 - uv);
    float w = edge.x * edge.y;
    if (w <= 0.0) return vec4(0.0, 0.0, 0.0, 1.0);
    vec4 c = SampleClouds(uv);
    return vec4(c.rgb * w, mix(1.0, c.a, w));
}

#endif
