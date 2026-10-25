// Coloured-light floodfill (shadowcomp, compute; plan item A1). Each frame, every block
// space in the voxel volume takes the brightest light of its six neighbours from the
// previous frame, dimmed by one step and tinted by what fills it (stained glass, leaves,
// water); solid blocks stop it, light sources set their own colour. Light so spreads one
// block per frame and fades over about 15 blocks, like vanilla block light. Two volumes
// take turns (read one, write the other); the volume follows the camera, so the previous
// one is read shifted by how far the camera moved.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/lightColors.glsl"
#include "/lib/lighting/voxels.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
#if COLORED_LIGHT_RANGE == 2
    const ivec3 workGroups = ivec3(32, 16, 32);
#else
    const ivec3 workGroups = ivec3(16, 8, 16);
#endif

uniform vec3 previousCameraPosition;

layout(r32ui) uniform readonly uimage3D voxelImg;
layout(r11f_g11f_b10f) uniform image3D floodImgA;
layout(r11f_g11f_b10f) uniform image3D floodImgB;

const float LIGHT_STEP = 0.86; // light kept per block travelled

// How light passing through a block space is coloured / dimmed.
vec3 VoxelTint(uint priority, int id) {
    if (priority == VOXEL_PRIORITY_WATER) return vec3(0.80, 0.90, 0.95);
    if (IsStainedGlass(id)) return mix(vec3(1.0), DyeColor(id - BLOCK_STAINED_GLASS), 0.85);
    if (IsStainedPane(id)) return mix(vec3(1.0), DyeColor(id - BLOCK_STAINED_PANE), 0.85);
    if (id == BLOCK_TINTED_GLASS) return vec3(0.15);
    if (id == BLOCK_GLASS || id == BLOCK_GLASS_PANE) return vec3(0.97);
    if (id == BLOCK_ICE) return vec3(0.85, 0.92, 1.00);
    if (id == BLOCK_LEAVES) return vec3(0.60, 0.70, 0.55);
    return vec3(0.75);
}

vec3 PreviousLight(ivec3 p, bool fromA) {
    if (any(lessThan(p, ivec3(0))) || any(greaterThanEqual(p, VOXEL_SIZE))) return vec3(0.0);
    return fromA ? imageLoad(floodImgA, p).rgb : imageLoad(floodImgB, p).rgb;
}

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(v, VOXEL_SIZE))) return;

    // Even frames read A and write B; odd frames the other way round (coloredLight.glsl
    // reads whichever was written this frame).
    bool fromA = (frameCounter & 1) == 0;
    ivec3 shift = ivec3(floor(cameraPosition)) - ivec3(floor(previousCameraPosition));
    ivec3 prev = v + shift;

    uint voxel = imageLoad(voxelImg, v).r;
    uint priority = VoxelPriority(voxel);
    int id = VoxelBlockId(voxel);

    vec3 light = vec3(0.0);
    if (priority != VOXEL_PRIORITY_SOLID) {
        vec3 brightest = PreviousLight(prev + ivec3(1, 0, 0), fromA);
        brightest = max(brightest, PreviousLight(prev - ivec3(1, 0, 0), fromA));
        brightest = max(brightest, PreviousLight(prev + ivec3(0, 1, 0), fromA));
        brightest = max(brightest, PreviousLight(prev - ivec3(0, 1, 0), fromA));
        brightest = max(brightest, PreviousLight(prev + ivec3(0, 0, 1), fromA));
        brightest = max(brightest, PreviousLight(prev - ivec3(0, 0, 1), fromA));
        light = brightest * LIGHT_STEP;
        if (priority == VOXEL_PRIORITY_TINT || priority == VOXEL_PRIORITY_WATER) light *= VoxelTint(priority, id);
    }
    int emission = VoxelEmission(voxel);
    if (emission > 0) light = max(light, LightSourceColor(id) * (float(emission) / 15.0));

    if (fromA) imageStore(floodImgB, v, vec4(light, 1.0));
    else imageStore(floodImgA, v, vec4(light, 1.0));
}
