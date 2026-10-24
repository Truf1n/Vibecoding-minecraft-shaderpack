#ifndef COLUMN_MAPS_GLSL
#define COLUMN_MAPS_GLSL

// Column maps: what occupies the block spaces near the player, as bit masks. Each map is
// a 512x512 grid of block columns that wraps around the world; each column holds one bit
// per block level, for the 32 levels around the camera height. The shadow pass sets the
// bits (atomic OR, so the result does not depend on draw order) and Iris clears the maps
// at the start of every frame, so they never hold stale data.
//
//   ceiling       block levels whose bottom has a solid block underside flush on it
//   glassCeiling  the same for see-through blocks (glass, ice, slime, honey)
//   glassCells    block levels containing a see-through block (any of its faces drawn)
//   waterCells    block levels containing water with any face drawn (water inside a
//                 body of water has no faces, so it is not marked)
//   waterSurfaces block levels containing an upward water surface
//
// Used to decide how a water surface looks from below (water.glsl), where the surface may
// wave (gbuffers_forward.glsl), and by the column-map underwater light method.

const int COLUMN_MAP_SIZE = 512;      // must match the images in shaders.properties
const float COLUMN_MAP_RANGE = 250.0; // blocks from the camera; stays clear of the wrap-around

int ColumnBaseLevel() { return int(floor(cameraPosition.y)) - 16; }

// Bit index of a block level, or -1 outside the 32 levels covered.
int ColumnBit(float level) {
    int bit = int(level) - ColumnBaseLevel();
    return bit >= 0 && bit < 32 ? bit : -1;
}

bool InColumnRange(vec2 worldXZ) { return all(lessThan(abs(worldXZ - cameraPosition.xz), vec2(COLUMN_MAP_RANGE))); }
ivec2 ColumnCell(vec2 worldXZ) { return ivec2(mod(floor(worldXZ), float(COLUMN_MAP_SIZE))); }

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
        int bit = ColumnBit(floor(blockCenter.y));
        if (bit < 0 || !InColumnRange(blockCenter.xz)) return;
        ivec2 cell = ColumnCell(blockCenter.xz);
        uint mask = 1u << uint(bit);
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

    // All 32 bits of a column (0 when out of range).
    uint ColumnMask(usampler2D map, vec2 worldXZ) {
        return InColumnRange(worldXZ) ? texelFetch(map, ColumnCell(worldXZ), 0).r : 0u;
    }

    bool ColumnHas(usampler2D map, vec3 worldPos) {
        int bit = ColumnBit(floor(worldPos.y));
        return bit >= 0 && (ColumnMask(map, worldPos.xz) & (1u << uint(bit))) != 0u;
    }

    // Solid / see-through block underside flush on the bottom of this block space.
    bool HasCeiling(vec3 worldPos) { return ColumnHas(ceilingSampler, worldPos); }
    bool HasGlassCeiling(vec3 worldPos) { return ColumnHas(glassCeilingSampler, worldPos); }

    // Is there water on top of the see-through blocks stacked from this block space up?
    // (glass sunk in water vs glass at the surface with air above it)
    bool WaterAboveGlassStack(vec3 worldPos) {
        int bit = ColumnBit(floor(worldPos.y));
        if (bit < 0) return false;
        uint glass = ColumnMask(glassCellsSampler, worldPos.xz);
        uint water = ColumnMask(waterCellsSampler, worldPos.xz);
        while (bit < 32 && (glass & (1u << uint(bit))) != 0u) bit++;
        return bit < 32 && (water & (1u << uint(bit))) != 0u;
    }

    // Height of the water surface above a point, following the column upwards to the first
    // water surface; -1e6 if a solid block comes first or the column is out of range.
    // (The point is assumed to be in water when a surface is found; points in dry caves
    // under a lake are in the shadow of the rock anyway.) A full block's surface sits 8/9 up.
    float ColumnWaterSurface(vec3 worldPos) {
        int bit = ColumnBit(floor(worldPos.y + 0.01));
        if (bit < 0) return -1e6;
        uint surfaces = ColumnMask(waterSurfacesSampler, worldPos.xz);
        uint ceiling = ColumnMask(ceilingSampler, worldPos.xz);
        for (int b = bit; b < 32; b++) {
            if ((surfaces & (1u << uint(b))) != 0u) return float(ColumnBaseLevel() + b) + 8.0 / 9.0;
            if (b + 1 < 32 && (ceiling & (1u << uint(b + 1))) != 0u) return -1e6;
        }
        return -1e6;
    }
#endif

#endif
