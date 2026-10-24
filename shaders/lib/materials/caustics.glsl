#ifndef CAUSTICS_GLSL
#define CAUSTICS_GLSL

// Light travelling through water: per-channel absorption and caustics (plan item W2).
// Shared by the water surface and by shadow lookups for anything under water.

#include "/lib/util/noise.glsl"

// Light absorbed per block of water (red goes first, so deep water turns blue-green).
vec3 WaterAbsorption() { return vec3(0.30, 0.085, 0.060) * WATER_FOG_MULT; }

// Bright moving lines where wave crests focus light. Two drifting noise layers; their
// difference is near zero along thin curves, which become the web. Averages about 1.
float Caustics(vec2 worldXZ) {
    float t = frameTimeCounter * WATER_WAVE_SPEED;
    vec2 p = worldXZ / WATER_WAVE_SIZE;
    float a = SmoothNoise(p * 0.85 + vec2(0.31, 0.22) * t);
    float b = SmoothNoise(p * 1.25 + vec2(-0.27, 0.18) * t + 17.0);
    float lines = pow(saturate(1.0 - abs(a - b) * 3.2), 5.0);
    return 0.45 + lines * 2.4;
}

// Sunlight reaching a point `depth` blocks under the surface; surfaceXZ is where the
// light ray entered the water.
vec3 UnderwaterLight(float depth, vec2 surfaceXZ) {
    vec3 light = exp(-depth * WaterAbsorption());
    #ifdef WATER_CAUSTICS
        light *= mix(1.0, Caustics(surfaceXZ), saturate(depth * 1.5));
    #endif
    return light;
}

#endif
