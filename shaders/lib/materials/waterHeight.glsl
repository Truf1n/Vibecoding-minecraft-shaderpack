#ifndef WATER_HEIGHT_GLSL
#define WATER_HEIGHT_GLSL

// World-space water height map: the shadow pass records the top of every water surface
// around the player into a 1024x1024 grid of blocks that wraps around the world, and
// lighting reads it to tell whether - and how deep - a point is under water. Unlike the
// shadow map, it is not hidden by glass or ice sitting on top of the water.
// Iris clears it every frame and the shadow pass refills it before anything reads it, so
// it never holds stale data; atomic max keeps the highest surface when several share a
// column, so the result does not depend on draw order.

const int WATER_HEIGHT_SIZE = 1024;      // must match image.waterHeightImg in shaders.properties
const float WATER_HEIGHT_RANGE = 500.0;  // blocks from the camera; stays clear of the wrap-around

ivec2 WaterHeightCell(vec2 blockXZ) { return ivec2(mod(blockXZ, float(WATER_HEIGHT_SIZE))); }

// 0 means "no water here"; 1/64 block steps.
uint EncodeWaterHeight(float y) { return uint(clamp((y + 1024.0) * 64.0, 1.0, 4.0e9)); }
float DecodeWaterHeight(uint v) { return float(v) / 64.0 - 1024.0; }

#ifdef WATER_HEIGHT_WRITER
    layout(r32ui) uniform uimage2D waterHeightImg;

    // Called per vertex of an upward water face; blockCenter is from at_midBlock.
    void WriteWaterHeight(vec3 worldPos, vec3 blockCenter) {
        if (any(greaterThan(abs(blockCenter.xz - cameraPosition.xz), vec2(WATER_HEIGHT_RANGE)))) return;
        imageAtomicMax(waterHeightImg, WaterHeightCell(floor(blockCenter.xz)), EncodeWaterHeight(worldPos.y));
    }
#else
    uniform usampler2D waterHeightSampler;

    // Height of the water surface above this world position, or -1e6 if there is none.
    float WaterSurfaceHeight(vec3 worldPos) {
        if (any(greaterThan(abs(worldPos.xz - cameraPosition.xz), vec2(WATER_HEIGHT_RANGE)))) return -1e6;
        uint v = texelFetch(waterHeightSampler, WaterHeightCell(floor(worldPos.xz)), 0).r;
        return v == 0u ? -1e6 : DecodeWaterHeight(v);
    }
#endif

#endif
