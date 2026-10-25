#ifndef VOXELS_GLSL
#define VOXELS_GLSL

// Voxel volume around the camera for coloured lighting (plan item A1). The shadow pass
// writes what fills each block space; the shadowcomp pass spreads coloured light through
// it (floodfill); lighting reads the colour back (coloredLight.glsl). Brightness keeps
// coming from Minecraft's own light levels, so a mistake in the volume can only shift a
// colour, never let light through a wall.
//
// One r32ui per block: (priority << 28) | (flags << 20) | (emission << 16) | block id.
// Several things can share a block space (a waterlogged lantern), so writers use atomic
// max and the highest priority wins: light source > solid > see-through > water.
// The floodfill also keeps, per block, where its brightest light comes from (offset to the
// source, 5 bits per axis), so lighting can trace a straight line back to it through the
// volume and pick up the colour of any glass on the way (sharp coloured light).
// Needs: common.glsl, blockIds.glsl.

#include "/lib/lighting/lightColors.glsl"

#if COLORED_LIGHT_RANGE == 2
    const ivec3 VOXEL_SIZE = ivec3(256, 128, 256); // must match the images in shaders.properties
#else
    const ivec3 VOXEL_SIZE = ivec3(128, 64, 128);
#endif

#define VOXEL_PRIORITY_WATER  1u
#define VOXEL_PRIORITY_TINT   2u
#define VOXEL_PRIORITY_SOLID  3u
#define VOXEL_PRIORITY_SOURCE 4u

// Block coordinates of the volume's corner for the current / previous frame's camera.
ivec3 VoxelOrigin() { return ivec3(floor(cameraPosition)) - VOXEL_SIZE / 2; }

uint EncodeVoxel(uint priority, int blockId, int emission) {
    return (priority << 28) | (uint(clamp(emission, 0, 15)) << 16) | uint(clamp(blockId, 0, 65535));
}
uint VoxelPriority(uint v) { return v >> 28; }
int VoxelEmission(uint v) { return int((v >> 16) & 15u); }
int VoxelBlockId(uint v) { return int(v & 65535u); }

// Offset from a block to the source of its light: 0 = unknown.
const int VOXEL_MAX_OFFSET = 15;
uint EncodeSourceOffset(ivec3 o) {
    o = clamp(o, ivec3(-VOXEL_MAX_OFFSET), ivec3(VOXEL_MAX_OFFSET)) + 16;
    return 0x8000u | uint(o.x) | (uint(o.y) << 5) | (uint(o.z) << 10);
}
bool HasSourceOffset(uint v) { return (v & 0x8000u) != 0u; }
ivec3 DecodeSourceOffset(uint v) { return ivec3(int(v & 31u), int((v >> 5) & 31u), int((v >> 10) & 31u)) - 16; }

// How light passing through a block space is coloured / dimmed (stained glass passes only
// its own colour).
vec3 VoxelTint(uint priority, int id) {
    if (priority == VOXEL_PRIORITY_WATER) return vec3(0.80, 0.90, 0.95);
    if (IsStainedGlass(id)) return DyeColor(id - BLOCK_STAINED_GLASS);
    if (IsStainedPane(id)) return DyeColor(id - BLOCK_STAINED_PANE);
    if (id == BLOCK_TINTED_GLASS) return vec3(0.12, 0.10, 0.14);
    if (id == BLOCK_GLASS || id == BLOCK_GLASS_PANE) return vec3(0.97);
    if (id == BLOCK_ICE) return vec3(0.80, 0.90, 1.00);
    if (id == BLOCK_SLIME_HONEY) return vec3(1.00, 0.75, 0.35);
    if (id == BLOCK_LEAVES) return vec3(0.60, 0.70, 0.55);
    return vec3(0.75);
}

#endif
