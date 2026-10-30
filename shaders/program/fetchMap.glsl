// Water openness map (shadowcomp3, compute, after the shadow pass filled the column maps;
// B7): see lib/materials/fetchMap.glsl.

#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(16, 16, 1); // a quarter of the 512 x 512 corners per frame

#ifdef OPT_FETCH_MAP
    #include "/lib/materials/columnMaps.glsl"
    #define FETCH_MAP_WRITER
    #include "/lib/materials/fetchMap.glsl"

    // Highest level with a water surface in a column (block level), or -10000 if none.
    int TopWaterSurface(vec2 xz) {
        for (int word = COLUMN_MAP_WORDS - 1; word >= 0; word--) {
            uint bits = ColumnWord(waterSurfacesSampler, xz, word);
            if (bits != 0u) return ColumnBaseLevel() + word * 32 + findMSB(bits);
        }
        return -10000;
    }

    void main() {
        // This frame's quarter: every other corner each way, in turn.
        ivec2 phase = ivec2(frameCounter & 1, (frameCounter >> 1) & 1);
        ivec2 slot = ivec2(gl_GlobalInvocationID.xy) * 2 + phase; // place in the wrapped grid
        // The corner it holds: the one within the 512 corners around the camera.
        ivec2 lo = ivec2(floor(cameraPosition.xz)) - FETCH_MAP_SIZE / 2;
        ivec2 corner = lo + ivec2(mod(vec2(slot - lo), float(FETCH_MAP_SIZE)));
        uvec2 entry = uvec2(FetchMapTag(corner), 0u);
        if (InColumnRange(vec2(corner))) {
            // The topmost water surface of the four columns meeting at this corner.
            int level = -10000;
            for (int i = 0; i < 4; i++) level = max(level, TopWaterSurface(vec2(corner) - vec2(i & 1, i >> 1) + 0.5));
            if (level > -10000) {
                // As a water vertex there asks for it (WaterFetch looks 0.2 below the vertex).
                float fetch = WaterFetch(vec3(float(corner.x), float(level) + 0.89, float(corner.y)));
                entry.y = uint(level + 2048) & 0xFFFu | 0x1000u | (uint(saturate(fetch) * 65535.0 + 0.5) << 16);
            }
        }
        fetchCells[FetchMapIndex(corner)] = entry;
    }
#else
    void main() {}
#endif
