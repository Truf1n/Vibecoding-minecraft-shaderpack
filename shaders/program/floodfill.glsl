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
layout(r16ui) uniform uimage3D floodSrcImgA; // offset to the source of the brightest light
layout(r16ui) uniform uimage3D floodSrcImgB;

const float LIGHT_STEP = 0.86; // light kept per block travelled

bool InVolume(ivec3 p) { return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, VOXEL_SIZE)); }

vec3 PreviousLight(ivec3 p, bool fromA) {
    if (!InVolume(p)) return vec3(0.0);
    return fromA ? imageLoad(floodImgA, p).rgb : imageLoad(floodImgB, p).rgb;
}

uint PreviousSource(ivec3 p, bool fromA) {
    if (!InVolume(p)) return 0u;
    return fromA ? imageLoad(floodSrcImgA, p).r : imageLoad(floodSrcImgB, p).r;
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
    uint source = 0u;
    if (priority != VOXEL_PRIORITY_SOLID) {
        // Brightest of the six neighbours (per colour channel, so different lights mix),
        // and where the single brightest one's light comes from.
        const ivec3 dirs[6] = ivec3[6](ivec3(1, 0, 0), ivec3(-1, 0, 0), ivec3(0, 1, 0),
                                       ivec3(0, -1, 0), ivec3(0, 0, 1), ivec3(0, 0, -1));
        float bestPeak = 0.0;
        for (int i = 0; i < 6; i++) {
            vec3 n = PreviousLight(prev + dirs[i], fromA);
            light = max(light, n);
            float peak = max(n.r, max(n.g, n.b));
            if (peak > bestPeak) {
                uint s = PreviousSource(prev + dirs[i], fromA);
                if (HasSourceOffset(s)) {
                    ivec3 o = DecodeSourceOffset(s) + dirs[i];
                    if (all(lessThanEqual(abs(o), ivec3(VOXEL_MAX_OFFSET)))) {
                        bestPeak = peak;
                        source = EncodeSourceOffset(o);
                    }
                }
            }
        }
        light *= LIGHT_STEP;
        if (priority == VOXEL_PRIORITY_TINT || priority == VOXEL_PRIORITY_WATER) light *= VoxelTint(priority, id);
    }
    int emission = VoxelEmission(voxel);
    if (emission > 0) {
        vec3 own = LightSourceColor(id) * (float(emission) / 15.0);
        if (max(own.r, max(own.g, own.b)) >= max(light.r, max(light.g, light.b))) source = EncodeSourceOffset(ivec3(0));
        light = max(light, own);
    }

    if (fromA) {
        imageStore(floodImgB, v, vec4(light, 1.0));
        imageStore(floodSrcImgB, v, uvec4(source));
    } else {
        imageStore(floodImgA, v, vec4(light, 1.0));
        imageStore(floodSrcImgA, v, uvec4(source));
    }
}
