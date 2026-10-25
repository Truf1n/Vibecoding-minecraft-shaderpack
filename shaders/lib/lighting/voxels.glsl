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
// Needs: common.glsl.

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

#endif
