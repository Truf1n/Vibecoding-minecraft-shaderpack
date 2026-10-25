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
// Flags: which way a glass pane runs (its broad faces), so lines are tinted only where they
// actually cross the pane.
const uint VOXEL_PANE_X = 1u << 20; // runs along x (faces point along z)
const uint VOXEL_PANE_Z = 1u << 21; // runs along z
uint VoxelPriority(uint v) { return v >> 28; }
int VoxelEmission(uint v) { return int((v >> 16) & 15u); }
int VoxelBlockId(uint v) { return int(v & 65535u); }

// Coloured glass (and slime/honey) colours light along straight lines, traced per pixel
// to each nearby light (coloredLight.glsl), so the floodfill passes it uncoloured. The
// floodfill marks how close each block space is to lit coloured glass (GLASS_REACH = in
// it, counting down by one per block) and lists the lights near such glass; lightClusters
// sorts them into 8x8x8-block clusters, up to CLUSTER_LIGHTS each.
bool IsLineTint(int id) { return IsStainedGlass(id) || IsStainedPane(id) || id == BLOCK_TINTED_GLASS || id == BLOCK_SLIME_HONEY; }
const uint GLASS_REACH = 16u;
const int MAX_LISTED_LIGHTS = 4095; // texel 0 of the list holds the count
const int CLUSTER_SIZE = 8;
const ivec3 CLUSTER_COUNT = VOXEL_SIZE / CLUSTER_SIZE;
const int CLUSTER_LIGHTS = 8;
const int CLUSTER_STRIDE = CLUSTER_LIGHTS + 1; // layer 0: "near coloured glass" flag
// A listed light: block (volume coordinates) and emission; 0 = none.
uint PackLight(ivec3 cell, int emission) {
    return 0x80000000u | uint(cell.x) | (uint(cell.y) << 9) | (uint(cell.z) << 17) | (uint(emission) << 26);
}
ivec3 LightCell(uint v) { return ivec3(int(v & 511u), int((v >> 9) & 255u), int((v >> 17) & 511u)); }
int LightEmission(uint v) { return int((v >> 26) & 15u); }

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
