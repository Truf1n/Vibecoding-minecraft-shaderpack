// Lights near coloured glass, sorted into clusters (shadowcomp1, compute; plan item A3).
// The floodfill (shadowcomp) listed every light near lit coloured glass and flagged the
// 8x8x8-block clusters that lie near such glass; each flagged cluster here keeps the
// lights that reach into it most strongly, for the per-pixel lines in coloredLight.glsl.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/lightColors.glsl"
#include "/lib/lighting/voxels.glsl"

layout(local_size_x = 4, local_size_y = 4, local_size_z = 4) in;
#if COLORED_LIGHT_RANGE == 2
    const ivec3 workGroups = ivec3(8, 4, 8);
#else
    const ivec3 workGroups = ivec3(4, 2, 4);
#endif

layout(r32ui) uniform readonly uimage2D lightListImg;
layout(r32ui) uniform uimage3D lightClusterImg;

void main() {
    ivec3 c = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(c, CLUSTER_COUNT))) return;
    int base = c.z * CLUSTER_STRIDE;
    if (imageLoad(lightClusterImg, ivec3(c.xy, base)).r == 0u) return; // no coloured glass near

    // The strongest lights here: emission minus the block distance to the cluster.
    uint best[CLUSTER_LIGHTS];
    int score[CLUSTER_LIGHTS];
    for (int k = 0; k < CLUSTER_LIGHTS; k++) { best[k] = 0u; score[k] = 0; }

    ivec3 lo = c * CLUSTER_SIZE, hi = lo + CLUSTER_SIZE - 1;
    int count = min(int(imageLoad(lightListImg, ivec2(0)).r), MAX_LISTED_LIGHTS);
    for (int i = 1; i <= count; i++) {
        uint light = imageLoad(lightListImg, ivec2(i, 0)).r;
        ivec3 cell = LightCell(light);
        ivec3 d = max(lo - cell, 0) + max(cell - hi, 0);
        int s = LightEmission(light) - (d.x + d.y + d.z);
        if (s <= score[CLUSTER_LIGHTS - 1]) continue;
        // Insert, keeping the list sorted strongest first.
        int k = CLUSTER_LIGHTS - 1;
        while (k > 0 && score[k - 1] < s) {
            best[k] = best[k - 1];
            score[k] = score[k - 1];
            k--;
        }
        best[k] = light;
        score[k] = s;
    }
    for (int k = 0; k < CLUSTER_LIGHTS; k++) imageStore(lightClusterImg, ivec3(c.xy, base + 1 + k), uvec4(best[k]));
}
