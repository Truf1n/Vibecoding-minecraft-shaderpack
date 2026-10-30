#ifndef FETCH_MAP_GLSL
#define FETCH_MAP_GLSL

// Water openness map (B7; written by program/fetchMap.glsl, shadowcomp3): WaterFetch
// (columnMaps.glsl, 16 column lookups) at every block corner within 256 blocks, for the
// topmost water surface around that corner, so water vertices read one value instead of
// working it out every frame. A quarter of the corners is refreshed per frame (it only
// changes when blocks do). The grid wraps around the world; each entry carries the corner
// it holds, and anything not in it (another level, a corner not refreshed yet, further
// away) is worked out as before.
// Needs: common.glsl; columnMaps.glsl (readers' fallback, and the writer).

const int FETCH_MAP_SIZE = 512;

#ifdef FETCH_MAP_WRITER
    layout(std430, binding = 6) writeonly buffer FetchMapBuffer {
#else
    layout(std430, binding = 6) readonly buffer FetchMapBuffer {
#endif
    uvec2 fetchCells[]; // x: corner (x | z << 16); y: level + 2048 (bits 0-11), valid (bit 12), fetch (bits 16-31)
};

int FetchMapIndex(ivec2 corner) {
    ivec2 i = ivec2(mod(vec2(corner), float(FETCH_MAP_SIZE)));
    return i.y * FETCH_MAP_SIZE + i.x;
}
uint FetchMapTag(ivec2 corner) { return (uint(corner.x) & 0xFFFFu) | (uint(corner.y) << 16); }

#ifndef FETCH_MAP_WRITER
    // WaterFetch at a water vertex (world position), from the map when it holds it.
    float WaterFetchCached(vec3 worldPos) {
        vec2 rounded = floor(worldPos.xz + 0.5);
        if (all(lessThan(abs(worldPos.xz - rounded), vec2(0.01)))) {
            ivec2 corner = ivec2(rounded);
            uvec2 e = fetchCells[FetchMapIndex(corner)];
            int level = int(floor(worldPos.y - 0.2));
            if (e.x == FetchMapTag(corner) && (e.y & 0x1000u) != 0u && int(e.y & 0xFFFu) - 2048 == level)
                return float(e.y >> 16) / 65535.0;
        }
        return WaterFetch(worldPos);
    }
#endif

#endif
