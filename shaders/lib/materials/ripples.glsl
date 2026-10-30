#ifndef RIPPLES_GLSL
#define RIPPLES_GLSL

// Interactive ripples (plan item Q15): a wave simulation on the water around the player, so
// swimming, wading, mobs and boats leave rings and wakes. One grid, 16 cells per block and
// 64 blocks across (a single simulation everywhere, so there is no seam between finer and
// coarser parts). Rings fade out within about 6 blocks of where they started; the water
// shows them up to ~20 blocks from the player and nothing at all beyond ~24, and the grid's
// border, further out still, absorbs whatever gets that far, so nothing comes back.
//   1. The shadow pass records, per eighth-of-a-block cell, the lowest and highest point of
//      any entity (the player included) above it (rippleLowImg / rippleHighImg, cleared
//      every frame).
//   2. shadowcomp1 (program/rippleSources.glsl) turns that into "an entity crosses the
//      water surface here" (checked against the column maps), stored back in rippleHighImg.
//   3. shadowcomp2 (program/ripples.glsl) steps the wave equation. Only a *change* of what
//      is in the water makes waves (an entity moving in or out of a cell), so someone
//      standing still makes none. Rings spread at ~2.2 blocks/s; a little viscosity smooths
//      away the jagged short waves a grid would otherwise leave trailing behind each ring.
//      Two halves take turns (read one, write the other).
//   4. The water reads the heights, smoothly interpolated, for extra slope (water.glsl).
// The grid wraps around the world (like the column maps), so it needs no shifting as the
// player moves: a cell is reset when its spot comes back into range from the far side.

const int RIPPLE_SIZE = 1024;           // cells per side (shaders.properties)
const float RIPPLE_CELLS = 16.0;        // cells per block
const float RIPPLE_RANGE = float(RIPPLE_SIZE) * 0.5 / RIPPLE_CELLS - 0.5; // blocks from the camera
const float RIPPLE_SHOWN = 20.0;        // blocks: fully shown up to here, gone by RIPPLE_SHOWN + 4
const float RIPPLE_MASK_CELLS = 8.0;    // entity records: cells per block
const int RIPPLE_MASK_SIZE = 512;       // ... per side (64 blocks)

ivec2 RippleCellOf(vec2 worldXZ, float cellsPerBlock) { return ivec2(floor(worldXZ * cellsPerBlock)); }
ivec2 RippleWrap(ivec2 cell, int size) { return ivec2(mod(vec2(cell), float(size))); }

// Image rows: half k at rows k * 1024.
int RippleCurrentHalf() { return frameCounter & 1; }
ivec2 RippleBase(int half_) { return ivec2(0, half_ * RIPPLE_SIZE); }

// Entity heights, relative to the camera, packed so that both records use atomic max on an
// image cleared to 0 ("nothing here"): high = height, low = inverted height.
uint PackRippleHeight(float y) { return uint(clamp((y - cameraPosition.y + 128.0) * 256.0, 1.0, 65535.0 * 256.0)); }
float UnpackRippleHeight(uint q) { return float(q) / 256.0 - 128.0 + cameraPosition.y; }

#ifdef RIPPLE_READER
    #include "/lib/world/frameFlags.glsl"
    uniform sampler2D rippleSampler;

    float RippleTexel(ivec2 cell) {
        return texelFetch(rippleSampler, RippleWrap(cell, RIPPLE_SIZE) + RippleBase(RippleCurrentHalf()), 0).r;
    }

    // Height at a world position, interpolated between the four nearest cells.
    float RippleHeightAt(vec2 worldXZ) {
        vec2 pos = worldXZ * RIPPLE_CELLS - 0.5;
        ivec2 base = ivec2(floor(pos));
        vec2 f = pos - vec2(base);
        f = f * f * (3.0 - 2.0 * f); // smooth, so the slope has no creases at cell edges
        float a = RippleTexel(base), b = RippleTexel(base + ivec2(1, 0));
        float c = RippleTexel(base + ivec2(0, 1)), d = RippleTexel(base + ivec2(1, 1));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    // Slope (dh/dx, dh/dz) of the simulated ripples at a world position, fading out beyond
    // RIPPLE_SHOWN blocks from the camera.
    vec2 RippleSlope(vec2 worldXZ) {
        #ifdef OPT_RIPPLE_IDLE
            if (rippleWaves[frameCounter % 4] == 0u) return vec2(0.0); // flat this frame (A3)
        #endif
        vec2 d = abs(worldXZ - cameraPosition.xz);
        float fade = 1.0 - smoothstep(RIPPLE_SHOWN, RIPPLE_SHOWN + 4.0, max(d.x, d.y));
        if (fade <= 0.0) return vec2(0.0);
        const float e = 0.75 / RIPPLE_CELLS;
        float dx = RippleHeightAt(worldXZ + vec2(e, 0.0)) - RippleHeightAt(worldXZ - vec2(e, 0.0));
        float dz = RippleHeightAt(worldXZ + vec2(0.0, e)) - RippleHeightAt(worldXZ - vec2(0.0, e));
        return vec2(dx, dz) / (2.0 * e) * fade;
    }
#endif

#endif
