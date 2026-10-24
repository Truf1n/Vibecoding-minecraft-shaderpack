// Camera-centred grid of glass blocks (8-bit glass code per block, 0 = none), written
// in the shadow pass and read by glass shading to find same-glass neighbours.
// Indices are relative to the camera's integer block position; both the writer and the
// reader use cameraPositionFract, so they always agree.

const ivec3 GLASS_VOXEL_SIZE = ivec3(128, 64, 128); // must match image.glassVoxelImg in shaders.properties
const ivec3 GLASS_VOXEL_HALF = GLASS_VOXEL_SIZE / 2;

// Block containing a camera-relative position, as a voxel index (may be out of range).
ivec3 GlassVoxelIndex(vec3 playerPos) { return ivec3(floor(playerPos + cameraPositionFract)) + GLASS_VOXEL_HALF; }

bool InGlassGrid(ivec3 v) { return all(greaterThanEqual(v, ivec3(0))) && all(lessThan(v, GLASS_VOXEL_SIZE)); }
