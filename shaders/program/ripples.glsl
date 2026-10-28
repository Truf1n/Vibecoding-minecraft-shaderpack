// Interactive ripple simulation step (shadowcomp2, compute; see lib/materials/ripples.glsl).
// Wave equation on the grid around the player, with a little viscosity:
//   h_new = (2 h - h_old + a * lap(h) + nu * lap(h - h_old)) * damping - push * (occupied - occupied_before)
// rgba: r height now, g height a step ago, b how much of the cell was occupied last frame.
// Only a change of occupation pushes the water, so still entities make no waves. Cells whose
// spot just came into range (the grid wraps around the world) start flat.

#include "/lib/common.glsl"
#include "/lib/materials/ripples.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 64, 1);

uniform vec3 previousCameraPosition;

layout(rgba16f) uniform image2D rippleImg;
layout(r32ui) uniform readonly uimage2D rippleHighImg; // 1 where an entity crosses the water (rippleSources)

// World cell held by a texel, for a window centred on a camera position.
ivec2 WindowCell(ivec2 texel, vec3 camera) {
    ivec2 origin = RippleCellOf(camera.xz, RIPPLE_CELLS) - RIPPLE_SIZE / 2;
    return origin + ivec2(mod(vec2(texel - origin), float(RIPPLE_SIZE)));
}

// The image starts out with whatever was in the memory: never let a bad value in.
float Clean(float x) { return isnan(x) || isinf(x) ? 0.0 : clamp(x, -0.3, 0.3); }
vec2 Clean(vec2 x) { return vec2(Clean(x.x), Clean(x.y)); }

// How much of the area around a world point entities occupy, 0..1: a soft (Gaussian, ~0.2
// block) footprint, so the push has no sharp edges that would ring.
float Occupied(vec2 xz) {
    vec2 pos = xz * RIPPLE_MASK_CELLS - 0.5;
    ivec2 base = ivec2(floor(pos));
    float sum = 0.0;
    for (int y = -1; y <= 2; y++) {
        for (int x = -1; x <= 2; x++) {
            ivec2 c = base + ivec2(x, y);
            if (imageLoad(rippleHighImg, RippleWrap(c, RIPPLE_MASK_SIZE)).r == 0u) continue;
            vec2 d = (vec2(c) - pos) / RIPPLE_MASK_CELLS; // blocks
            sum += exp(-dot(d, d) / (2.0 * 0.12 * 0.12));
        }
    }
    return saturate(sum * 0.6);
}

void main() {
    ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
    ivec2 readBase = RippleBase(1 - RippleCurrentHalf()), writeBase = RippleBase(RippleCurrentHalf());

    // This texel's spot moved into the window since last frame: start flat.
    ivec2 cell = WindowCell(texel, cameraPosition);
    if (cell != WindowCell(texel, previousCameraPosition)) {
        imageStore(rippleImg, texel + writeBase, vec4(0.0));
        return;
    }

    vec4 here = imageLoad(rippleImg, texel + readBase);
    here = vec4(Clean(here.r), Clean(here.g), saturate(Clean(here.b)), 0.0);
    ivec2 size = ivec2(RIPPLE_SIZE);
    vec2 neighbours = Clean(imageLoad(rippleImg, (texel + ivec2(-1, 0) + size) % size + readBase).rg)
                    + Clean(imageLoad(rippleImg, (texel + ivec2(1, 0) + size) % size + readBase).rg)
                    + Clean(imageLoad(rippleImg, (texel + ivec2(0, -1) + size) % size + readBase).rg)
                    + Clean(imageLoad(rippleImg, (texel + ivec2(0, 1) + size) % size + readBase).rg);
    vec2 laplacian = neighbours - 4.0 * here.rg; // of the height now (x) and a step ago (y)

    float dt = clamp(frameTime, 0.0, 0.05);
    const float waveSpeed = 2.2; // blocks per second
    float a = min(pow(waveSpeed * dt * RIPPLE_CELLS, 2.0), 0.4);
    // Viscosity: damps the shortest waves (a cell or two long) within a fraction of a second
    // and barely touches the rings themselves. Kept within the scheme's stability limit
    // (a + 2 nu < 0.5).
    float nu = min(2.5 * dt, (0.5 - a) * 0.45);
    // Damping: rings fade over ~2.5 s (they get ~6 blocks out); towards the grid's border
    // (well beyond where the water shows them) it gets much stronger and absorbs them.
    vec2 fromCenter = abs((vec2(cell) + 0.5) / RIPPLE_CELLS - cameraPosition.xz);
    float border = smoothstep(RIPPLE_SHOWN + 4.0, RIPPLE_RANGE - 1.0, max(fromCenter.x, fromCenter.y));
    float h = (2.0 * here.r - here.g + a * laplacian.x + nu * (laplacian.x - laplacian.y)) * exp(-dt * (1.6 + 20.0 * border));

    // Something moving into (or out of) the water here: push the surface down (or let it
    // spring back up).
    float occupied = Occupied((vec2(cell) + 0.5) / RIPPLE_CELLS);
    h -= 0.08 * (occupied - here.b);
    // The last of a ring snaps to flat instead of shrinking forever.
    if (abs(h) < 0.0015 && abs(here.r) < 0.0015) h = 0.0;

    imageStore(rippleImg, texel + writeBase, vec4(Clean(h), here.r, occupied, 0.0));
}
