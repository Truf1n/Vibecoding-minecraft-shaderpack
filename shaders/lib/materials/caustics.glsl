#ifndef CAUSTICS_GLSL
#define CAUSTICS_GLSL

// Light travelling through water: per-channel absorption and caustics (plan items W2, Q13,
// Q14), the caustics worked out from the same wave field as the surface (waves.glsl).
// Shared by the water surface and by shadow lookups for anything under water.

#include "/lib/util/noise.glsl"
#include "/lib/materials/waterStyles.glsl"
#include "/lib/materials/waves.glsl"

// Light absorbed per block of water (red goes first, so deep water turns blue-green), for
// the water the camera is in (per-biome looks: waterStyles.glsl).
vec3 WaterAbsorption() { return CameraWaterStyle().absorption * WATER_FOG_MULT; }

// Sunlight reaching a point `depth` blocks under the surface; surfaceXZ is where the
// light ray entered the water. causticStrength < 1 when something flat (glass, ice)
// covers the surface and calms the light.
vec3 UnderwaterLight(float depth, vec2 surfaceXZ, float causticStrength) {
    vec3 light = exp(-depth * WaterAbsorption());
    #ifdef WATER_CAUSTICS
        // From the wave field above (waves.glsl), assuming open water: light only reaches
        // here through water the sun can see.
        WaveConditions conditions = GetWaveConditions(1.0, 0.6, GustAt(surfaceXZ));
        light *= mix(vec3(1.0), WaveCaustics(Waves(surfaceXZ, conditions, 0.0, false), depth), causticStrength);
    #endif
    return light;
}

#endif
