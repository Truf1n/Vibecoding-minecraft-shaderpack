// Ripple sources (shadowcomp1, compute; see lib/materials/ripples.glsl): for each
// eighth-of-a-block cell around the player where the shadow pass saw an entity, check
// against the water surface there (column maps) whether the entity crosses it. The answer
// (1 or 0) replaces the cell's height record in rippleHighImg, for the simulation step.

#include "/lib/common.glsl"
#include "/lib/materials/ripples.glsl"
#include "/lib/materials/columnMaps.glsl"
#include "/lib/world/frameFlags.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(32, 32, 1);

layout(r32ui) uniform readonly uimage2D rippleLowImg;
layout(r32ui) uniform uimage2D rippleHighImg;

void main() {
    ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(texel, ivec2(RIPPLE_MASK_SIZE)))) return;
    uint high = imageLoad(rippleHighImg, texel).r;
    if (high == 0u) return;

    // The world cell this texel holds (the window around the camera, wrapped).
    ivec2 origin = RippleCellOf(cameraPosition.xz, RIPPLE_MASK_CELLS) - RIPPLE_MASK_SIZE / 2;
    ivec2 cell = origin + ivec2(mod(vec2(texel - origin), float(RIPPLE_MASK_SIZE)));
    vec2 xz = (vec2(cell) + 0.5) / RIPPLE_MASK_CELLS;

    float top = UnpackRippleHeight(high);
    float bottom = UnpackRippleHeight(0xFFFFFFFFu - imageLoad(rippleLowImg, texel).r);
    float surface = ColumnWaterSurface(vec3(xz.x, bottom - 1.0, xz.y));
    // It has to actually dip into the water (standing on a block next to the water, or
    // leaning over it, does not count).
    bool crosses = surface > -1e5 && bottom < surface - 0.05 && top > surface - 0.3;
    imageStore(rippleHighImg, texel, uvec4(crosses ? 1u : 0u));
    #ifdef OPT_RIPPLE_IDLE
        if (crosses) rippleSource[frameCounter % 4] = 1u; // wakes the simulation (A3)
    #endif
}
