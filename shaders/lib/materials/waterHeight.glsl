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

// Ceiling maps: for each column, one bit per block level within 16 blocks of the camera
// height, set where a block's underside sits flush on the bottom of its block space.
// Underwater, a water surface right under a solid block is treated as covered; under a
// see-through block (glass, ice) it stays a real surface, just without waves.
const int CEILING_SIZE = 512; // must match image.ceilingImg in shaders.properties
const float CEILING_RANGE = 250.0;
int CeilingBaseY() { return int(floor(cameraPosition.y)) - 16; }

#ifdef WATER_HEIGHT_WRITER
    layout(r32ui) uniform uimage2D waterHeightImg;
    layout(r32ui) uniform uimage2D ceilingImg;
    layout(r32ui) uniform uimage2D glassCeilingImg;

    // Called per vertex of a downward face that is flush with the bottom of its block.
    void WriteCeiling(vec3 blockCenter, bool seeThrough) {
        int bit = int(floor(blockCenter.y)) - CeilingBaseY();
        if (bit < 0 || bit > 31) return;
        if (any(greaterThan(abs(blockCenter.xz - cameraPosition.xz), vec2(CEILING_RANGE)))) return;
        ivec2 cell = ivec2(mod(floor(blockCenter.xz), float(CEILING_SIZE)));
        if (seeThrough) imageAtomicOr(glassCeilingImg, cell, 1u << uint(bit));
        else imageAtomicOr(ceilingImg, cell, 1u << uint(bit));
    }

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

    uniform usampler2D ceilingSampler;
    uniform usampler2D glassCeilingSampler;

    bool CeilingBit(usampler2D map, vec3 worldPos) {
        int bit = int(floor(worldPos.y)) - CeilingBaseY();
        if (bit < 0 || bit > 31) return false;
        if (any(greaterThan(abs(worldPos.xz - cameraPosition.xz), vec2(CEILING_RANGE)))) return false;
        uint v = texelFetch(map, ivec2(mod(floor(worldPos.xz), float(CEILING_SIZE))), 0).r;
        return (v & (1u << uint(bit))) != 0u;
    }

    // True if the block space at this world position has a solid (or see-through) block
    // underside flush on its bottom. Unknown far away or more than 16 blocks above/below
    // the camera: false.
    bool HasCeiling(vec3 worldPos) { return CeilingBit(ceilingSampler, worldPos); }
    bool HasGlassCeiling(vec3 worldPos) { return CeilingBit(glassCeilingSampler, worldPos); }
#endif

#endif
