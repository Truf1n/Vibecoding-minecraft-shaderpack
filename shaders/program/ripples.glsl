// Interactive ripple simulation step (shadowcomp2, compute; see lib/materials/ripples.glsl).
// Wave equation on two grids around the player (fine near, coarse far):
//   h_new = (2 h - h_old + a * laplacian(h)) * damping - push * (occupied - occupied_before)
// rgba: r height now, g height a step ago, b how much of the cell was occupied last frame.
// Only a change of occupation pushes the water, so still entities make no waves. Cells whose
// spot just came into range (the grids wrap around the world) start flat.

#include "/lib/common.glsl"
#include "/lib/materials/ripples.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(16, 48, 1); // x: 256 cells; y: 256 per grid, three grids

uniform vec3 previousCameraPosition;

layout(rgba16f) uniform image2D rippleImg;
layout(r32ui) uniform readonly uimage2D rippleHighImg; // 1 where an entity crosses the water (rippleSources)

// World cell held by a texel, for a window centred on a camera position.
ivec2 WindowCell(ivec2 texel, vec3 camera, float cellsPerBlock) {
    ivec2 origin = RippleCellOf(camera.xz, cellsPerBlock) - RIPPLE_SIZE / 2;
    return origin + ivec2(mod(vec2(texel - origin), float(RIPPLE_SIZE)));
}

// The image starts out with whatever was in the memory: never let a bad value in.
float Clean(float x) { return isnan(x) || isinf(x) ? 0.0 : clamp(x, -0.3, 0.3); }

// How much of the area around a world point (radius ~0.2 block) entities occupy, 0..1.
float Occupied(vec2 xz) {
    ivec2 center = RippleCellOf(xz, RIPPLE_MASK_CELLS);
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += float(imageLoad(rippleHighImg, RippleWrap(center + ivec2(x, y), RIPPLE_MASK_SIZE)).r);
        }
    }
    return saturate(sum / 3.0);
}

void main() {
    ivec2 id = ivec2(gl_GlobalInvocationID.xy);
    int grid = id.y / RIPPLE_SIZE;
    ivec2 texel = ivec2(id.x, id.y % RIPPLE_SIZE);
    float cellsPerBlock = RippleCellsPerBlock(grid);
    ivec2 readBase = RippleBase(grid, 1 - RippleCurrentHalf()), writeBase = RippleBase(grid, RippleCurrentHalf());

    // This texel's spot moved into the window since last frame: start flat.
    ivec2 cell = WindowCell(texel, cameraPosition, cellsPerBlock);
    if (cell != WindowCell(texel, previousCameraPosition, cellsPerBlock)) {
        imageStore(rippleImg, texel + writeBase, vec4(0.0));
        return;
    }

    vec4 here = imageLoad(rippleImg, texel + readBase);
    here = vec4(Clean(here.r), Clean(here.g), saturate(Clean(here.b)), 0.0);
    ivec2 size = ivec2(RIPPLE_SIZE);
    float neighbours = Clean(imageLoad(rippleImg, (texel + ivec2(-1, 0) + size) % size + readBase).r)
                     + Clean(imageLoad(rippleImg, (texel + ivec2(1, 0) + size) % size + readBase).r)
                     + Clean(imageLoad(rippleImg, (texel + ivec2(0, -1) + size) % size + readBase).r)
                     + Clean(imageLoad(rippleImg, (texel + ivec2(0, 1) + size) % size + readBase).r);

    float dt = clamp(frameTime, 0.0, 0.05);
    const float waveSpeed = 2.2; // blocks per second
    float a = min(pow(waveSpeed * dt * cellsPerBlock, 2.0), 0.45);
    // Damping: rings fade over ~2.5 s (they get ~6 blocks out); near the grid's border it
    // gets much stronger, so waves are absorbed there instead of wrapping around to the
    // other side and interfering.
    vec2 fromCenter = abs((vec2(cell) + 0.5) / cellsPerBlock - cameraPosition.xz);
    float border = smoothstep(0.7, 0.95, max(fromCenter.x, fromCenter.y) / RippleRange(grid));
    float h = (2.0 * here.r - here.g + a * (neighbours - 4.0 * here.r)) * exp(-dt * (1.6 + 30.0 * border));

    // Something moving into (or out of) the water here: push the surface down (or let it
    // spring back up).
    float occupied = Occupied((vec2(cell) + 0.5) / cellsPerBlock);
    h -= 0.08 * (occupied - here.b);
    // The last of a ring snaps to flat instead of shrinking forever.
    if (abs(h) < 0.0015 && abs(here.r) < 0.0015) h = 0.0;

    imageStore(rippleImg, texel + writeBase, vec4(Clean(h), here.r, occupied, 0.0));
}
