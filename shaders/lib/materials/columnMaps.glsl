#ifndef COLUMN_MAPS_GLSL
#define COLUMN_MAPS_GLSL

// Column maps: what occupies the block spaces near the player, as bit masks. Each map is
// a 512x512 grid of block columns that wraps around the world; each column holds one bit
// per block level, for the 128 levels around the camera height (64 below, 64 above),
// stored as four 32-bit words stacked down the image. The shadow pass sets the bits
// (atomic OR, so the result does not depend on draw order) and Iris clears the maps at
// the start of every frame, so they never hold stale data.
//
//   ceiling       block levels whose bottom has a solid block underside flush on it
//   glassCeiling  the same for see-through blocks (glass, ice, slime, honey)
//   glassCells    block levels containing a see-through block (any of its faces drawn)
//   waterCells    block levels containing water with any face drawn (water in the middle
//                 of a body of water has no faces, so it is not marked)
//   waterSurfaces block levels containing an upward water surface
//
// Used to decide how a water surface looks from below (water.glsl), where the surface may
// wave (gbuffers_forward.glsl), to find the water under glass for caustics (shadows.glsl)
// and to tell whether glass is under water (gbuffers_forward.glsl).

const int COLUMN_MAP_SIZE = 512;      // must match the images in shaders.properties (512 x 2048)
const int COLUMN_MAP_WORDS = 4;       // 32 levels each
const int COLUMN_MAP_LEVELS = 128;
const float COLUMN_MAP_RANGE = 250.0; // blocks from the camera; stays clear of the wrap-around

int ColumnBaseLevel() { return int(floor(cameraPosition.y)) - COLUMN_MAP_LEVELS / 2; }

// Bit index of a block level, or -1 outside the levels covered.
int ColumnBit(float level) {
    int bit = int(floor(level)) - ColumnBaseLevel();
    return bit >= 0 && bit < COLUMN_MAP_LEVELS ? bit : -1;
}

bool InColumnRange(vec2 worldXZ) { return all(lessThan(abs(worldXZ - cameraPosition.xz), vec2(COLUMN_MAP_RANGE))); }
ivec2 ColumnCell(vec2 worldXZ, int word) {
    return ivec2(mod(floor(worldXZ), float(COLUMN_MAP_SIZE))) + ivec2(0, word * COLUMN_MAP_SIZE);
}

#ifdef COLUMN_MAP_WRITER
    layout(r32ui) uniform uimage2D ceilingImg;
    layout(r32ui) uniform uimage2D glassCeilingImg;
    layout(r32ui) uniform uimage2D glassCellsImg;
    layout(r32ui) uniform uimage2D waterCellsImg;
    layout(r32ui) uniform uimage2D waterSurfacesImg;

    #define MAP_CEILING       0
    #define MAP_GLASS_CEILING 1
    #define MAP_GLASS_CELLS   2
    #define MAP_WATER_CELLS   3
    #define MAP_WATER_SURFACE 4

    // Marks the block space with this centre in one of the maps.
    void MarkColumn(int map, vec3 blockCenter) {
        int bit = ColumnBit(blockCenter.y);
        if (bit < 0 || !InColumnRange(blockCenter.xz)) return;
        ivec2 cell = ColumnCell(blockCenter.xz, bit >> 5);
        uint mask = 1u << uint(bit & 31);
        if (map == MAP_CEILING) imageAtomicOr(ceilingImg, cell, mask);
        else if (map == MAP_GLASS_CEILING) imageAtomicOr(glassCeilingImg, cell, mask);
        else if (map == MAP_GLASS_CELLS) imageAtomicOr(glassCellsImg, cell, mask);
        else if (map == MAP_WATER_CELLS) imageAtomicOr(waterCellsImg, cell, mask);
        else imageAtomicOr(waterSurfacesImg, cell, mask);
    }
#else
    uniform usampler2D ceilingSampler;
    uniform usampler2D glassCeilingSampler;
    uniform usampler2D glassCellsSampler;
    uniform usampler2D waterCellsSampler;
    uniform usampler2D waterSurfacesSampler;

    uint ColumnWord(usampler2D map, vec2 worldXZ, int word) {
        return texelFetch(map, ColumnCell(worldXZ, word), 0).r;
    }

    bool ColumnHas(usampler2D map, vec3 worldPos) {
        int bit = ColumnBit(worldPos.y);
        if (bit < 0 || !InColumnRange(worldPos.xz)) return false;
        return (ColumnWord(map, worldPos.xz, bit >> 5) & (1u << uint(bit & 31))) != 0u;
    }

    // Lowest level at or above `fromBit` whose bit is set (or, with `inverted`, clear) in
    // this column; COLUMN_MAP_LEVELS if none.
    int FirstColumnBit(usampler2D map, vec2 worldXZ, int fromBit, bool inverted) {
        for (int word = fromBit >> 5; word < COLUMN_MAP_WORDS; word++) {
            uint bits = ColumnWord(map, worldXZ, word);
            if (inverted) bits = ~bits;
            int start = max(fromBit - word * 32, 0);
            if (start > 0) bits &= ~((1u << uint(start)) - 1u);
            if (bits != 0u) return word * 32 + findLSB(bits);
        }
        return COLUMN_MAP_LEVELS;
    }

    // Solid / see-through block underside flush on the bottom of this block space.
    bool HasCeiling(vec3 worldPos) { return ColumnHas(ceilingSampler, worldPos); }
    bool HasGlassCeiling(vec3 worldPos) { return ColumnHas(glassCeilingSampler, worldPos); }

    // How open the water is ("fetch"): the share of water surface at the same level in two
    // rings (5 and 12 blocks) around the point. Ponds stay calm, lakes and the sea get waves.
    float WaterFetch(vec3 worldPos) {
        vec3 p = vec3(worldPos.x, worldPos.y - 0.2, worldPos.z);
        float count = 0.0;
        for (int i = 0; i < 8; i++) {
            vec2 d = vec2(cos(float(i) * 0.785398), sin(float(i) * 0.785398));
            count += ColumnHas(waterSurfacesSampler, p + vec3(d.x * 5.0, 0.0, d.y * 5.0)) ? 1.0 : 0.0;
            count += ColumnHas(waterSurfacesSampler, p + vec3(d.x * 12.0, 0.0, d.y * 12.0)) ? 1.0 : 0.0;
        }
        return smoothstep(0.3, 0.95, count / 16.0);
    }

    // Is there water on top of the see-through blocks stacked from this block space up?
    // (glass sunk in water vs glass at the surface with air above it)
    bool WaterAboveGlassStack(vec3 worldPos) {
        int bit = ColumnBit(worldPos.y);
        if (bit < 0 || !InColumnRange(worldPos.xz)) return false;
        int top = FirstColumnBit(glassCellsSampler, worldPos.xz, bit, true); // first non-glass level
        if (top >= COLUMN_MAP_LEVELS) return false;
        return (ColumnWord(waterCellsSampler, worldPos.xz, top >> 5) & (1u << uint(top & 31))) != 0u;
    }

    // Height of the water surface above a point, following the column upwards to the first
    // water surface; -1e6 if a solid block comes first or the column is out of range.
    // (The point is assumed to be in water when a surface is found; points in dry caves
    // under a lake are in the shadow of the rock anyway.) A full block's surface sits 8/9 up.
    float ColumnWaterSurface(vec3 worldPos) {
        int bit = ColumnBit(worldPos.y + 0.01);
        if (bit < 0 || !InColumnRange(worldPos.xz)) return -1e6;
        int surface = FirstColumnBit(waterSurfacesSampler, worldPos.xz, bit, false);
        int solid = FirstColumnBit(ceilingSampler, worldPos.xz, bit + 1, false); // block resting on level solid-1
        if (surface >= COLUMN_MAP_LEVELS || solid <= surface) return -1e6;
        return float(ColumnBaseLevel() + surface) + 8.0 / 9.0;
    }
#endif

#endif
