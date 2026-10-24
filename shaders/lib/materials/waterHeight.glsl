#ifndef WATER_HEIGHT_GLSL
#define WATER_HEIGHT_GLSL

// World-space water height map: every visible water surface writes its height into a
// 512x512 grid of blocks that wraps around the world (toroidal addressing), and lighting
// reads it to tell whether - and how deep - a point is under water. Unlike the shadow
// map, it is not hidden by glass or ice sitting on top of the water.
// Each cell stores (surface y, frame written, block x, block z) so stale or wrapped
// entries are rejected. Written in gbuffers_water, read the following frame.

const int WATER_HEIGHT_SIZE = 512; // must match image.waterHeightImg in shaders.properties
const float WATER_HEIGHT_MAX_AGE = 1200.0; // frames before an unrefreshed entry expires

ivec2 WaterHeightCell(vec2 blockXZ) { return ivec2(mod(blockXZ, float(WATER_HEIGHT_SIZE))); }

uniform sampler2D waterHeightSampler;

// Height of the water surface above this world position, or -1e6 if unknown.
float WaterSurfaceHeight(vec3 worldPos) {
    vec2 block = floor(worldPos.xz);
    vec4 v = texelFetch(waterHeightSampler, WaterHeightCell(block), 0);
    bool sameBlock = all(lessThan(abs(v.zw - block), vec2(0.5)));
    bool fresh = float(frameCounter) - v.y < WATER_HEIGHT_MAX_AGE && float(frameCounter) >= v.y;
    return sameBlock && fresh ? v.x : -1e6;
}

#ifdef WATER_HEIGHT_WRITER
    layout(rgba32f) uniform writeonly image2D waterHeightImg;

    void WriteWaterHeight(vec3 worldPos) {
        vec2 block = floor(worldPos.xz);
        imageStore(waterHeightImg, WaterHeightCell(block), vec4(worldPos.y, float(frameCounter), block));
    }
#endif

#endif
