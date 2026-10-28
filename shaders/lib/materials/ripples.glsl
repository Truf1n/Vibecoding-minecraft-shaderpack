#ifndef RIPPLES_GLSL
#define RIPPLES_GLSL

// Interactive ripples (plan item Q15): wave simulations on the water around the player, so
// swimming, wading, mobs and boats leave rings and wakes. Three nested grids, like shadow
// cascades: fine close by (16 cells per block, 16 blocks across) for crisp rings at your
// feet, medium (8 per block, 32 across) and coarse (4 per block, 64 across) for wakes
// further out. All simulate the same disturbances; the water blends smoothly from one to
// the next. Each grid's border absorbs the waves (instead of letting them wrap around and
// come back), and rings die out within about 6 blocks of where they started.
//   1. The shadow pass records, per eighth-of-a-block cell, the lowest and highest point of
//      any entity (the player included) above it (rippleLowImg / rippleHighImg, cleared
//      every frame).
//   2. shadowcomp1 (program/rippleSources.glsl) turns that into "an entity crosses the
//      water surface here" (checked against the column maps), stored back in rippleHighImg.
//   3. shadowcomp2 (program/ripples.glsl) steps the wave equation on both grids. Only a
//      *change* of what is in the water makes waves (an entity moving in or out of a cell),
//      so someone standing still makes none. Rings spread at ~2.2 blocks/s and fade within
//      a few seconds. Two halves per grid take turns (read one, write the other).
//   4. The water reads the heights, smoothly interpolated, for extra slope (water.glsl).
// The grids wrap around the world (like the column maps), so they need no shifting as the
// player moves: a cell is reset when its spot comes back into range from the far side.

const int RIPPLE_SIZE = 256;            // cells per side of each grid (shaders.properties)
const float RIPPLE_MASK_CELLS = 8.0;    // entity records: cells per block
const int RIPPLE_MASK_SIZE = 512;       // ... per side (64 blocks)

// Grid 0: fine, near; 1: medium; 2: coarse, far.
const int RIPPLE_GRIDS = 3;
float RippleCellsPerBlock(int grid) { return grid == 0 ? 16.0 : (grid == 1 ? 8.0 : 4.0); }
float RippleRange(int grid) { return float(RIPPLE_SIZE) * 0.5 / RippleCellsPerBlock(grid) - 0.5; } // blocks from the camera

ivec2 RippleCellOf(vec2 worldXZ, float cellsPerBlock) { return ivec2(floor(worldXZ * cellsPerBlock)); }
ivec2 RippleWrap(ivec2 cell, int size) { return ivec2(mod(vec2(cell), float(size))); }

// Image rows: grid g, half k at rows (2g + k) * 256.
int RippleCurrentHalf() { return frameCounter & 1; }
ivec2 RippleBase(int grid, int half_) { return ivec2(0, (2 * grid + half_) * RIPPLE_SIZE); }

// Entity heights, relative to the camera, packed so that both records use atomic max on an
// image cleared to 0 ("nothing here"): high = height, low = inverted height.
uint PackRippleHeight(float y) { return uint(clamp((y - cameraPosition.y + 128.0) * 256.0, 1.0, 65535.0 * 256.0)); }
float UnpackRippleHeight(uint q) { return float(q) / 256.0 - 128.0 + cameraPosition.y; }

#ifdef RIPPLE_READER
    uniform sampler2D rippleSampler;

    float RippleTexel(int grid, ivec2 cell) {
        return texelFetch(rippleSampler, RippleWrap(cell, RIPPLE_SIZE) + RippleBase(grid, RippleCurrentHalf()), 0).r;
    }

    // Height at a world position, interpolated between the four nearest cells.
    float RippleHeightAt(int grid, vec2 worldXZ) {
        vec2 pos = worldXZ * RippleCellsPerBlock(grid) - 0.5;
        ivec2 base = ivec2(floor(pos));
        vec2 f = pos - vec2(base);
        f = f * f * (3.0 - 2.0 * f); // smooth, so the slope has no creases at cell edges
        float a = RippleTexel(grid, base), b = RippleTexel(grid, base + ivec2(1, 0));
        float c = RippleTexel(grid, base + ivec2(0, 1)), d = RippleTexel(grid, base + ivec2(1, 1));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    vec2 RippleGridSlope(int grid, vec2 worldXZ) {
        float e = 0.75 / RippleCellsPerBlock(grid);
        float dx = RippleHeightAt(grid, worldXZ + vec2(e, 0.0)) - RippleHeightAt(grid, worldXZ - vec2(e, 0.0));
        float dz = RippleHeightAt(grid, worldXZ + vec2(0.0, e)) - RippleHeightAt(grid, worldXZ - vec2(0.0, e));
        return vec2(dx, dz) / (2.0 * e);
    }

    // Slope (dh/dx, dh/dz) of the simulated ripples at a world position: the finest grid
    // that covers the spot, blending over a wide band into the next one out (well inside
    // its absorbing border), fading out towards the edge of the coarse one.
    vec2 RippleSlope(vec2 worldXZ) {
        vec2 d = abs(worldXZ - cameraPosition.xz);
        float r = max(d.x, d.y);
        if (r > RippleRange(2)) return vec2(0.0);
        float w0 = 1.0 - smoothstep(RippleRange(0) * 0.45, RippleRange(0) * 0.8, r);
        float w1 = (1.0 - w0) * (1.0 - smoothstep(RippleRange(1) * 0.45, RippleRange(1) * 0.8, r));
        float w2 = 1.0 - w0 - w1;
        vec2 slope = vec2(0.0);
        if (w0 > 0.0) slope += RippleGridSlope(0, worldXZ) * w0;
        if (w1 > 0.0) slope += RippleGridSlope(1, worldXZ) * w1;
        if (w2 > 0.0) slope += RippleGridSlope(2, worldXZ) * w2;
        return slope * (1.0 - smoothstep(RippleRange(2) * 0.6, RippleRange(2) * 0.8, r));
    }
#endif

#endif
