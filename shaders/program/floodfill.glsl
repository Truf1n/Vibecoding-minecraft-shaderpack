// Coloured-light floodfill (shadowcomp, compute; plan item A1). Each frame, half the block
// spaces in the voxel volume (alternating, P9) take the brightest light of their six
// neighbours from the previous frame, dimmed by one step and tinted by what fills them
// (stained glass, leaves, water); solid blocks stop it, light sources set their own colour.
// All six neighbours of a cell are of the other half, updated the frame before, so light
// still spreads a block per frame; it fades over about 15 blocks, like vanilla block light. Two volumes
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
#include "/lib/lighting/voxelBricks.glsl"

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
layout(rgba16f) uniform image3D bounceImgA;
layout(rgba16f) uniform image3D bounceImgB;
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
// Four taps about a third of a block apart: one tap flips between lit and shadowed as the
// (coarse, far away) shadow map shifts with the camera, and the bounce would flicker.
float SunVisibility(ivec3 v) {
    vec3 playerPos = vec3(v + VoxelOrigin()) + 0.5 - cameraPosition;
    vec3 shadowView = (shadowModelView * vec4(playerPos, 1.0)).xyz;
    float vis = 0.0;
    for (int i = 0; i < 4; i++) {
        vec2 o = vec2(i & 1, i >> 1) * 0.6 - 0.3;
        vec3 clip = (shadowProjection * vec4(shadowView + vec3(o, 0.0), 1.0)).xyz;
        if (length(clip.xy) > 0.98) { vis += 1.0; continue; }
        vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
        vis += texture(shadowtex1HW, coord - vec3(0.0, 0.0, 0.0005));
    }
    return vis * 0.25;
}

// The full update of one block space: light (block light, rgb) and bounce (rgb sun bounce,
// a sky visibility).
void UpdateCell(ivec3 v, ivec3 prev, bool fromA, out vec3 light, out vec4 bounce) {
    sunLightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
    uint voxel = imageLoad(voxelImg, v).r;
    uint priority = VoxelPriority(voxel);
    int id = VoxelBlockId(voxel);

    light = vec3(0.0);
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
    // Only the Overworld's lighting uses them (and only with Sun Bounce or Sky Occlusion on):
    // elsewhere the volume holds "dark, open sky" without working anything out.
    bounce = vec4(0.0, 0.0, 0.0, 1.0);
    bool lightVolume = false;
    #ifdef WORLD_OVERWORLD
        lightVolume = SUN_BOUNCE > 0.0 || VOXEL_SKY_OCCLUSION > 0.0;
    #endif
    if (!lightVolume) return;
    bounce = vec4(0.0);
    if (priority != VOXEL_PRIORITY_SOLID) {
        // Sky: falls straight down unhindered, spreads sideways and (a little) upwards with
        // losses; see-through blocks let part of it through.
        #ifdef OPT_FLOOD_SINGLE_READS
            // Each neighbour read once, for both its sky and its bounce (B5).
            vec4 n[6];
            for (int i = 0; i < 6; i++) n[i] = PreviousBounce(prev + dirs6(i), fromA);
            float sky = n[2].a; // dirs6: +x, -x, +y, -y, +z, -z
            sky = max(sky, max(max(n[0].a, n[1].a), max(n[4].a, n[5].a)) * SKY_SIDE);
            sky = max(sky, n[3].a * SKY_UP);
        #else
            float sky = PreviousBounce(prev + ivec3(0, 1, 0), fromA).a;
            sky = max(sky, PreviousBounce(prev + ivec3(1, 0, 0), fromA).a * SKY_SIDE);
            sky = max(sky, PreviousBounce(prev - ivec3(1, 0, 0), fromA).a * SKY_SIDE);
            sky = max(sky, PreviousBounce(prev + ivec3(0, 0, 1), fromA).a * SKY_SIDE);
            sky = max(sky, PreviousBounce(prev - ivec3(0, 0, 1), fromA).a * SKY_SIDE);
            sky = max(sky, PreviousBounce(prev - ivec3(0, 1, 0), fromA).a * SKY_UP);
        #endif
        if (priority == VOXEL_PRIORITY_TINT) sky *= id == BLOCK_LEAVES ? 0.8 : 0.92;
        else if (priority == VOXEL_PRIORITY_WATER) sky *= 0.9;

        // Bounce: the brightest of the neighbours' bounced light, spreading out...
        vec3 bounced = vec3(0.0);
        #ifdef OPT_FLOOD_SINGLE_READS
            for (int i = 0; i < 6; i++) bounced = max(bounced, n[i].rgb);
        #else
            for (int i = 0; i < 6; i++) bounced = max(bounced, PreviousBounce(prev + dirs6(i), fromA).rgb);
        #endif
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
        // Smoothed over a fraction of a second, so nothing in it flickers (the spreading
        // above still settles within a few frames).
        vec4 before = PreviousBounce(prev, fromA);
        // (Each cell is updated every other frame: two frames' worth.)
        if (InVolume(prev)) bounce = mix(before, bounce, 1.0 - exp(-clamp(2.0 * frameTime, 0.0, 0.2) / 0.2));
    }

}

shared bool brickBusy;
shared bool brickLit;
shared bool brickSkip;

void main() {
    ivec3 v = ivec3(gl_GlobalInvocationID);

    // Even frames read A and write B; odd frames the other way round (coloredLight.glsl
    // reads whichever was written this frame).
    bool fromA = (frameCounter & 1) == 0;
    ivec3 shift = ivec3(floor(cameraPosition)) - ivec3(floor(previousCameraPosition));
    ivec3 prev = v + shift;

    // Sparse update (P17, voxelBricks.glsl): this workgroup is one brick. It needs work if
    // it holds blocks now, or if anything within a block of where it was last frame was
    // not trivially dark open sky.
    ivec3 brick = ivec3(gl_WorkGroupID);
    int current = (frameCounter & 1) * VOXEL_BRICK_COUNT, other = VOXEL_BRICK_COUNT - current;
    if (gl_LocalInvocationIndex == 0u) {
        bool busy = brickVoxels[current + BrickIndex(brick)] != 0u;
        ivec3 lo = ivec3(floor(vec3(brick * 8 + shift - 1) / 8.0));
        ivec3 hi = ivec3(floor(vec3(brick * 8 + shift + 8) / 8.0));
        for (int z = lo.z; z <= hi.z && !busy; z++) {
            for (int y = lo.y; y <= hi.y && !busy; y++) {
                for (int x = lo.x; x <= hi.x && !busy; x++) {
                    ivec3 b = ivec3(x, y, z);
                    if (InBricks(b) && brickActive[other + BrickIndex(b)] == 1u) busy = true;
                }
            }
        }
        brickBusy = busy;
        brickLit = false;
        // An idle brick that already holds the idle values in the volume written this frame
        // (it was idle when that volume was last written, two frames ago: flag 2) need not
        // write them again (B4): 12 bytes per cell, mostly empty air, every frame.
        brickSkip = false;
        #ifdef OPT_FLOOD_IDLE_SKIP
            brickSkip = !busy && brickActive[current + BrickIndex(brick)] == 2u;
        #endif
        // Next frame's shadow pass marks the other half of the flags afresh.
        brickVoxels[other + BrickIndex(brick)] = 0u;
    }
    barrier();

    vec3 light = vec3(0.0);
    vec4 bounce = vec4(0.0, 0.0, 0.0, 1.0); // dark, open sky
    if (brickBusy && all(lessThan(v, VOXEL_SIZE))) {
        // Half the volume per frame (P9), in a checkerboard that alternates: the other half
        // carries its values over (moved with the camera). A cell's six neighbours are all
        // of the half updated last frame, so light still spreads a block per frame.
        if (((v.x + v.y + v.z + frameCounter) & 1) == 1) {
            light = PreviousLight(prev, fromA);
            if (InVolume(prev)) bounce = PreviousBounce(prev, fromA);
        } else {
            UpdateCell(v, prev, fromA, light, bounce);
        }
        bool trivial = max(light.r, max(light.g, light.b)) < 0.004 && max(bounce.r, max(bounce.g, bounce.b)) < 0.004 && bounce.a > 0.995;
        if (!trivial) brickLit = true;
    }

    if (!brickSkip) {
        if (fromA) {
            imageStore(floodImgB, v, vec4(light, 1.0));
            imageStore(bounceImgB, v, bounce);
        } else {
            imageStore(floodImgA, v, vec4(light, 1.0));
            imageStore(bounceImgA, v, bounce);
        }
    }
    barrier();
    // 1: lit (neighbours must update); 0: dark but worked out; 2: idle, holding exactly the
    // idle values (B4).
    if (gl_LocalInvocationIndex == 0u) {
        uint state = brickLit ? 1u : 0u;
        #ifdef OPT_FLOOD_IDLE_SKIP
            if (!brickBusy) state = 2u;
        #endif
        brickActive[current + BrickIndex(brick)] = state;
    }
}
