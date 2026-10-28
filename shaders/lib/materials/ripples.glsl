#ifndef RIPPLES_GLSL
#define RIPPLES_GLSL

// Interactive ripples (plan item Q15): a small wave simulation on the water around the
// player - 256 x 256 cells of a quarter block (64 blocks across) - so swimming, wading,
// mobs and boats leave rings and wakes.
//   - The shadow pass records, per cell, the lowest and highest point of any entity (the
//     player included) above it (rippleLowImg / rippleHighImg, cleared every frame).
//   - shadowcomp1 (program/ripples.glsl) checks those against the water surface there
//     (column maps): where an entity crosses the surface, the water is pushed down. Then it
//     steps the wave equation: the disturbance spreads out at ~2.5 blocks/s and dies out
//     over a couple of seconds. Two halves of rippleImg take turns (read one, write the other).
//   - The water reads the height around it for extra slope (water.glsl).
// The grid wraps around the world (like the column maps), so it needs no shifting as the
// player moves: a cell is reset when its spot comes back into range from the far side.

const int RIPPLE_SIZE = 256;          // cells per side (must match shaders.properties)
const float RIPPLE_CELLS_PER_BLOCK = 4.0;
const float RIPPLE_RANGE = 31.0;      // blocks from the camera that are simulated

ivec2 RippleCellOf(vec2 worldXZ) { return ivec2(floor(worldXZ * RIPPLE_CELLS_PER_BLOCK)); }
ivec2 RippleTexel(ivec2 cell) { return ivec2(mod(vec2(cell), float(RIPPLE_SIZE))); }
bool InRippleRange(vec2 worldXZ) { return all(lessThan(abs(worldXZ - cameraPosition.xz), vec2(RIPPLE_RANGE))); }

// The half written this frame (read by the water) / the one written last frame.
int RippleCurrentHalf() { return frameCounter & 1; }

// Entity heights, relative to the camera, packed so that both records use atomic max on an
// image cleared to 0 ("nothing here"): high = height, low = inverted height.
uint PackRippleHeight(float y) { return uint(clamp((y - cameraPosition.y + 128.0) * 256.0, 1.0, 65535.0 * 256.0)); }
float UnpackRippleHeight(uint q) { return float(q) / 256.0 - 128.0 + cameraPosition.y; }

#ifdef RIPPLE_READER
    uniform sampler2D rippleSampler;

    float RippleHeight(ivec2 cell) {
        ivec2 t = RippleTexel(cell) + ivec2(0, RIPPLE_SIZE * RippleCurrentHalf());
        return texelFetch(rippleSampler, t, 0).r;
    }

    // Slope (dh/dx, dh/dz) of the simulated ripples at a world position.
    vec2 RippleSlope(vec2 worldXZ) {
        if (!InRippleRange(worldXZ)) return vec2(0.0);
        ivec2 c = RippleCellOf(worldXZ);
        float dx = RippleHeight(c + ivec2(1, 0)) - RippleHeight(c - ivec2(1, 0));
        float dz = RippleHeight(c + ivec2(0, 1)) - RippleHeight(c - ivec2(0, 1));
        float fade = 1.0 - smoothstep(RIPPLE_RANGE - 6.0, RIPPLE_RANGE, max(abs(worldXZ.x - cameraPosition.x), abs(worldXZ.y - cameraPosition.z)));
        return vec2(dx, dz) * (RIPPLE_CELLS_PER_BLOCK * 0.5) * fade;
    }
#endif

#endif
