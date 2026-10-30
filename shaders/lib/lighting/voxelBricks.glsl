#ifndef VOXEL_BRICKS_GLSL
#define VOXEL_BRICKS_GLSL

// Sparse light volume (P17): the voxel volume in bricks of 8x8x8 block spaces (one
// floodfill workgroup each), with two flags per brick in a storage buffer (bufferObject.1),
// each kept for this frame and the next (by frame parity):
//   voxels - the shadow pass put a block in it, or in a block space next to it;
//   active - 1: last frame, something in it was not trivially dark open sky (block light,
//            bounced light, or less than full sky); 0: it was; 2: it was idle and holds
//            exactly "dark, open sky" in the volume written that frame (B4: not rewritten).
// A brick with no blocks whose surroundings were all trivial last frame cannot have
// anything happen in it this frame: the floodfill writes "dark, open sky" there without
// gathering anything (most of the air above the terrain).
// Needs: voxels.glsl.

const ivec3 VOXEL_BRICKS = VOXEL_SIZE / 8;
const int VOXEL_BRICK_COUNT = VOXEL_BRICKS.x * VOXEL_BRICKS.y * VOXEL_BRICKS.z;

layout(std430, binding = 1) buffer VoxelBrickFlags {
    uint brickVoxels[2 * 16384]; // [parity * count + brick]
    uint brickActive[2 * 16384];
};

int BrickIndex(ivec3 brick) { return (brick.z * VOXEL_BRICKS.y + brick.y) * VOXEL_BRICKS.x + brick.x; }
bool InBricks(ivec3 brick) { return all(greaterThanEqual(brick, ivec3(0))) && all(lessThan(brick, VOXEL_BRICKS)); }

#ifdef VOXEL_BRICK_WRITER
    // A block at this volume position (shadow pass): its brick has blocks, and so do the
    // bricks next to it if it sits on their shared face (the air beside it may need light
    // bounced off it).
    void MarkVoxelBrick(ivec3 coord) {
        int base = (frameCounter & 1) * VOXEL_BRICK_COUNT;
        ivec3 brick = coord / 8;
        brickVoxels[base + BrickIndex(brick)] = 1u;
        ivec3 local = coord - brick * 8;
        for (int axis = 0; axis < 3; axis++) {
            ivec3 step_ = ivec3(axis == 0, axis == 1, axis == 2);
            if (local[axis] == 0 && InBricks(brick - step_)) brickVoxels[base + BrickIndex(brick - step_)] = 1u;
            if (local[axis] == 7 && InBricks(brick + step_)) brickVoxels[base + BrickIndex(brick + step_)] = 1u;
        }
    }
#endif

#endif
