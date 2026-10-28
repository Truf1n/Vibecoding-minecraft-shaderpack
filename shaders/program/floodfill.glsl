// Coloured-light floodfill (shadowcomp, compute; plan item A1). Each frame, every block
// space in the voxel volume takes the brightest light of its six neighbours from the
// previous frame, dimmed by one step and tinted by what fills it (stained glass, leaves,
// water); solid blocks stop it, light sources set their own colour. Light so spreads one
// block per frame and fades over about 15 blocks, like vanilla block light. Two volumes
// take turns (read one, write the other); the volume follows the camera, so the previous
// one is read shifted by how far the camera moved.
// The same pass keeps the rest of the light volume (docs/WORLD_MODEL.md F1): how much of
// the sky each block space can see, and sunlight bounced off sunlit blocks, in their colour.

#include "/lib/common.glsl"
#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"
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
// Light volume (docs/WORLD_MODEL.md F1): rgb sun bounce (per unit of sunlight), a sky visibility.
layout(rgba8) uniform image3D bounceImgA;
layout(rgba8) uniform image3D bounceImgB;
layout(r32ui) uniform readonly uimage3D albedoImg; // packed (voxels.glsl)
uniform sampler2DShadow shadowtex1HW;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

const float LIGHT_STEP = 0.86;  // light kept per block travelled
const float BOUNCE_STEP = 0.78; // bounced sunlight kept per block (it spreads out faster)
const float SKY_SIDE = 0.82;    // sky visibility kept per block sideways (falling straight down: all)
const float SKY_UP = 0.55;      // ... per block upwards (light from the sky bending up under ledges)

bool InVolume(ivec3 p) { return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, VOXEL_SIZE)); }

ivec3 dirs6(int i) {
    const ivec3 d[6] = ivec3[6](ivec3(1, 0, 0), ivec3(-1, 0, 0), ivec3(0, 1, 0), ivec3(0, -1, 0), ivec3(0, 0, 1), ivec3(0, 0, -1));
    return d[i];
}

vec3 sunLightDir; // world space, towards the sun (or moon)

vec3 PreviousLight(ivec3 p, bool fromA) {
    if (!InVolume(p)) return vec3(0.0);
    return fromA ? imageLoad(floodImgA, p).rgb : imageLoad(floodImgB, p).rgb;
}

vec4 PreviousBounce(ivec3 p, bool fromA) {
    if (!InVolume(p)) return p.y >= VOXEL_SIZE.y ? vec4(0.0, 0.0, 0.0, 1.0) : vec4(0.0); // above the volume: open sky
    return fromA ? imageLoad(bounceImgA, p) : imageLoad(bounceImgB, p);
}

// Sunlight reaching the middle of a block space (shadow map; outside it: assumed lit).
float SunVisibility(ivec3 v) {
    vec3 playerPos = vec3(v + VoxelOrigin()) + 0.5 - cameraPosition;
    vec3 clip = (shadowProjection * vec4((shadowModelView * vec4(playerPos, 1.0)).xyz, 1.0)).xyz;
    if (length(clip.xy) > 0.98) return 1.0;
    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
    return texture(shadowtex1HW, coord - vec3(0.0, 0.0, 0.0005));
}

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);
    if (any(greaterThanEqual(v, VOXEL_SIZE))) return;

    // Even frames read A and write B; odd frames the other way round (coloredLight.glsl
    // reads whichever was written this frame).
    bool fromA = (frameCounter & 1) == 0;
    ivec3 shift = ivec3(floor(cameraPosition)) - ivec3(floor(previousCameraPosition));
    ivec3 prev = v + shift;

    sunLightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
    uint voxel = imageLoad(voxelImg, v).r;
    uint priority = VoxelPriority(voxel);
    int id = VoxelBlockId(voxel);

    vec3 light = vec3(0.0);
    if (priority != VOXEL_PRIORITY_SOLID) {
        // Brightest of the six neighbours, per colour channel so different lights mix.
        light = max(light, PreviousLight(prev + ivec3(1, 0, 0), fromA));
        light = max(light, PreviousLight(prev - ivec3(1, 0, 0), fromA));
        light = max(light, PreviousLight(prev + ivec3(0, 1, 0), fromA));
        light = max(light, PreviousLight(prev - ivec3(0, 1, 0), fromA));
        light = max(light, PreviousLight(prev + ivec3(0, 0, 1), fromA));
        light = max(light, PreviousLight(prev - ivec3(0, 0, 1), fromA));
        light *= LIGHT_STEP;
        // Stained glass passes only its own colour (voxels.glsl).
        if (priority == VOXEL_PRIORITY_TINT || priority == VOXEL_PRIORITY_WATER) light *= VoxelTint(priority, id);
    }
    int emission = VoxelEmission(voxel);
    if (emission > 0) light = max(light, LightSourceColor(id) * (float(emission) / 15.0));

    // ---- Light volume: sky visibility and sun bounce --------------------------------------
    vec4 bounce = vec4(0.0);
    if (priority != VOXEL_PRIORITY_SOLID) {
        // Sky: falls straight down unhindered, spreads sideways and (a little) upwards with
        // losses; see-through blocks let part of it through.
        float sky = PreviousBounce(prev + ivec3(0, 1, 0), fromA).a;
        sky = max(sky, PreviousBounce(prev + ivec3(1, 0, 0), fromA).a * SKY_SIDE);
        sky = max(sky, PreviousBounce(prev - ivec3(1, 0, 0), fromA).a * SKY_SIDE);
        sky = max(sky, PreviousBounce(prev + ivec3(0, 0, 1), fromA).a * SKY_SIDE);
        sky = max(sky, PreviousBounce(prev - ivec3(0, 0, 1), fromA).a * SKY_SIDE);
        sky = max(sky, PreviousBounce(prev - ivec3(0, 1, 0), fromA).a * SKY_UP);
        if (priority == VOXEL_PRIORITY_TINT) sky *= id == BLOCK_LEAVES ? 0.8 : 0.92;
        else if (priority == VOXEL_PRIORITY_WATER) sky *= 0.9;

        // Bounce: the brightest of the neighbours' bounced light, spreading out...
        vec3 bounced = vec3(0.0);
        for (int i = 0; i < 6; i++) bounced = max(bounced, PreviousBounce(prev + dirs6(i), fromA).rgb);
        bounced *= BOUNCE_STEP;
        // ... and new light from sunlit faces next to this space: a solid neighbour whose
        // face towards this space looks at the sun bounces its colour (only where the sky,
        // and so possibly the sun, can reach).
        if (sky > 0.05 && sunLightDir.y > 0.0) {
            vec3 injected = vec3(0.0);
            for (int i = 0; i < 6; i++) {
                ivec3 n = v + dirs6(i);
                if (!InVolume(n)) continue;
                uint nVoxel = imageLoad(voxelImg, n).r;
                uint nPriority = VoxelPriority(nVoxel);
                if (nPriority != VOXEL_PRIORITY_SOLID && nPriority != VOXEL_PRIORITY_TINT) continue;
                float facing = dot(-vec3(dirs6(i)), sunLightDir); // the face's normal points from it to here
                if (facing <= 0.0) continue;
                vec3 albedo = SrgbToLinear(UnpackVoxelAlbedo(imageLoad(albedoImg, n).r));
                injected = max(injected, albedo * facing);
            }
            if (max(injected.r, max(injected.g, injected.b)) > 0.01) bounced = max(bounced, injected * SunVisibility(v) * 0.7);
        }
        bounce = vec4(bounced, saturate(sky));
    }

    if (fromA) {
        imageStore(floodImgB, v, vec4(light, 1.0));
        imageStore(bounceImgB, v, bounce);
    } else {
        imageStore(floodImgA, v, vec4(light, 1.0));
        imageStore(bounceImgA, v, bounce);
    }
}
