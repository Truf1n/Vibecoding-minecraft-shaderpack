#ifndef FAR_SHADOWS_GLSL
#define FAR_SHADOWS_GLSL

// Far shadows (W4, plan item Q10; Distant Horizons style): beyond the shadow map, terrain
// still shadows terrain. The shadow pass (which draws the world out to FAR_SHADOW_RANGE
// times the shadow distance for this) records the highest top face in every 2x2-block
// column (farHeightImg, 512x512 columns = 1024 blocks, wrapping around the world like the
// column maps). Far pixels march over it towards the sun with growing steps, softly: so
// distant mountains shade each other, valleys go dark at sunset and the far side of a
// ridge falls into shadow.
// The map is kept between frames (not cleared): far chunks are not always all drawn in the
// shadow pass every frame (Sodium culls asynchronously), and a map rebuilt each frame
// would flicker. Each column carries a tag for which 1024-block tile of the world it
// describes, so after the wrap-around brings a new spot into it, the old heights are
// replaced, never read.

const float FAR_CELL = 2.0;      // blocks per height-map column
const int FAR_SIZE = 512;        // columns per side
const float FAR_REACH = 500.0;   // blocks from the camera the map is trusted

ivec2 FarColumn(vec2 worldXZ) { return ivec2(floor(worldXZ / FAR_CELL)); }
ivec2 FarCell(ivec2 column) { return ivec2(mod(vec2(column), float(FAR_SIZE))); }
uint FarTag(ivec2 column) {
    ivec2 tile = ivec2(floor(vec2(column) / float(FAR_SIZE)));
    return uint(tile.x & 255) << 8 | uint(tile.y & 255);
}
// Packed: tag (16 bits) | height (16 bits, 1/8 block, never 0).
uint PackFarHeight(uint tag, float y) { return tag << 16 | uint(clamp((y + 128.0) * 8.0, 1.0, 65535.0)); }

#ifdef FAR_HEIGHT_WRITER
    layout(r32ui) uniform uimage2D farHeightImg;
    void WriteFarHeight(vec3 worldPos) {
        if (any(greaterThan(abs(worldPos.xz - cameraPosition.xz), vec2(FAR_REACH)))) return;
        ivec2 column = FarColumn(worldPos.xz);
        ivec2 cell = FarCell(column);
        uint tag = FarTag(column);
        uint value = PackFarHeight(tag, worldPos.y);
        // A column from elsewhere in the world (or never written): take it over.
        uint current = imageLoad(farHeightImg, cell).r;
        if (current >> 16 != tag || (current & 65535u) == 0u) imageAtomicCompSwap(farHeightImg, cell, current, value);
        imageAtomicMax(farHeightImg, cell, value);
    }
#else
    uniform usampler2D farHeightSampler;

    // Highest top in a column (very low if the map holds nothing for it).
    float FarHeight(vec2 worldXZ) {
        ivec2 column = FarColumn(worldXZ);
        uint v = texelFetch(farHeightSampler, FarCell(column), 0).r;
        if (v >> 16 != FarTag(column) || (v & 65535u) == 0u) return -1e6;
        return float(v & 65535u) / 8.0 - 128.0;
    }

    // Sunlight reaching a far point, 0..1. worldPos: absolute; L: towards the sun/moon.
    float FarShadow(vec3 worldPos, vec3 L) {
        if (L.y < 0.01) return 0.0;
        float vis = 1.0;
        float t = 3.0;
        // Shadows blur with distance from their caster (the sun is a disc), and there is
        // no point being sharper than the 2-block columns.
        float softness = 0.03 * (1.0 + 4.0 * stormRain) * SHADOW_PENUMBRA + 0.02;
        vec3 start = worldPos + vec3(0.0, 0.6, 0.0); // its own column's top is (about) here
        for (int i = 0; i < 24; i++) {
            vec3 p = start + L * t;
            if (any(greaterThan(abs(p.xz - cameraPosition.xz), vec2(FAR_REACH))) || p.y > 320.0) break;
            float h = FarHeight(p.xz);
            vis = min(vis, saturate((p.y - h) / (t * softness) + 0.5));
            if (vis <= 0.0) break;
            t = t * 1.2 + 1.0;
        }
        return vis;
    }
#endif

#endif
