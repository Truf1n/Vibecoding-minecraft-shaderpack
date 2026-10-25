// Coloured-light floodfill (shadowcomp, compute; plan item A1). Each frame, every block
// space in the voxel volume takes the brightest light of its six neighbours from the
// previous frame, dimmed by one step and tinted by what fills it (stained glass, leaves,
// water); solid blocks stop it, light sources set their own colour. Light so spreads one
// block per frame and fades over about 15 blocks, like vanilla block light. Two volumes
// take turns (read one, write the other); the volume follows the camera, so the previous
// one is read shifted by how far the camera moved. Alongside, it keeps how close each block
// space is to lit coloured glass and lists the lights near it (voxels.glsl).

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
layout(r8ui) uniform uimage3D glassNearImgA; // closeness to lit coloured glass
layout(r8ui) uniform uimage3D glassNearImgB;
layout(r32ui) uniform uimage2D lightListImg;   // texel 0: count; then PackLight entries
layout(r32ui) uniform uimage3D lightClusterImg;

const float LIGHT_STEP = 0.86; // light kept per block travelled

bool InVolume(ivec3 p) { return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, VOXEL_SIZE)); }

vec3 PreviousLight(ivec3 p, bool fromA) {
    if (!InVolume(p)) return vec3(0.0);
    return fromA ? imageLoad(floodImgA, p).rgb : imageLoad(floodImgB, p).rgb;
}

uint PreviousGlassNear(ivec3 p, bool fromA) {
    if (!InVolume(p)) return 0u;
    return fromA ? imageLoad(glassNearImgA, p).r : imageLoad(glassNearImgB, p).r;
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

    const ivec3 dirs[6] = ivec3[6](ivec3(1, 0, 0), ivec3(-1, 0, 0), ivec3(0, 1, 0),
                                   ivec3(0, -1, 0), ivec3(0, 0, 1), ivec3(0, 0, -1));
    vec3 light = vec3(0.0);
    uint near = 0u;
    if (priority != VOXEL_PRIORITY_SOLID) {
        // Brightest of the six neighbours, per colour channel so different lights mix.
        for (int i = 0; i < 6; i++) {
            light = max(light, PreviousLight(prev + dirs[i], fromA));
            near = max(near, PreviousGlassNear(prev + dirs[i], fromA));
        }
        light *= LIGHT_STEP;
        bool lineTint = priority == VOXEL_PRIORITY_TINT && IsLineTint(id);
        if ((priority == VOXEL_PRIORITY_TINT || priority == VOXEL_PRIORITY_WATER) && !lineTint) light *= VoxelTint(priority, id);
        near = near > 0u ? near - 1u : 0u;
        if (lineTint && max(light.r, max(light.g, light.b)) > 0.02) near = GLASS_REACH;
    }
    int emission = VoxelEmission(voxel);
    if (emission > 0) light = max(light, LightSourceColor(id) * (float(emission) / 15.0));

    if (near > 0u) {
        ivec3 cluster = v / CLUSTER_SIZE;
        imageAtomicOr(lightClusterImg, ivec3(cluster.xy, cluster.z * CLUSTER_STRIDE), 1u);
        // A light near coloured glass, with somewhere for its light to go, is listed for
        // the per-pixel lines.
        if (emission > 0) {
            bool open = false;
            for (int i = 0; i < 6; i++) {
                ivec3 n = v + dirs[i];
                if (InVolume(n) && VoxelPriority(imageLoad(voxelImg, n).r) < VOXEL_PRIORITY_SOLID) open = true;
            }
            if (open) {
                uint index = imageAtomicAdd(lightListImg, ivec2(0), 1u);
                if (index < uint(MAX_LISTED_LIGHTS)) imageStore(lightListImg, ivec2(int(index) + 1, 0), uvec4(PackLight(v, emission)));
            }
        }
    }

    if (fromA) {
        imageStore(floodImgB, v, vec4(light, 1.0));
        imageStore(glassNearImgB, v, uvec4(near));
    } else {
        imageStore(floodImgA, v, vec4(light, 1.0));
        imageStore(glassNearImgA, v, uvec4(near));
    }
}
