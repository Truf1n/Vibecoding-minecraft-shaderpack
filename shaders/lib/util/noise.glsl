#ifndef NOISE_GLSL
#define NOISE_GLSL

// Smooth value noise from Iris's noise texture (cubic interpolation: no faceted ridges).

uniform sampler2D noisetex;
const int noiseTextureResolution = 256;

float SmoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    ivec2 c = ivec2(mod(i, float(noiseTextureResolution)));
    ivec2 c1 = ivec2(mod(i + 1.0, float(noiseTextureResolution)));
    float a = texelFetch(noisetex, c, 0).r;
    float b = texelFetch(noisetex, ivec2(c1.x, c.y), 0).r;
    float d = texelFetch(noisetex, ivec2(c.x, c1.y), 0).r;
    float e = texelFetch(noisetex, c1, 0).r;
    return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

#endif
