#ifndef COLORED_LIGHT_GLSL
#define COLORED_LIGHT_GLSL

// Colour of block light at a point (plan items A1-A3, A5). With Coloured Lighting on, the
// hue comes from the floodfilled voxel volume (program/floodfill.glsl), which stained glass
// colours on the way through; light held in the hand takes the held item's colour.
// The brightness always comes from Minecraft's light level.
// Needs: common.glsl, blockIds.glsl.

#include "/lib/lighting/lightColors.glsl"

vec3 DefaultBlocklightColor() { return vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B); }

// Saturation setting, and part of the brightness that deep colours (red, blue) lose given
// back, so they do not read as much dimmer than torchlight.
vec3 GradeLightColor(vec3 hue) {
    hue = max(mix(vec3(Luminance(hue)), hue, COLORED_LIGHT_SATURATION), 0.0);
    return hue * sqrt(Luminance(DefaultBlocklightColor()) / max(Luminance(hue), 0.08));
}

#ifdef COLORED_LIGHTING
    #include "/lib/lighting/voxels.glsl"

    uniform sampler3D floodSamplerA;
    uniform sampler3D floodSamplerB;
    uniform sampler3D bounceSamplerA;
    uniform sampler3D bounceSamplerB;
    uniform int heldItemId;
    uniform int heldItemId2;

    bool InVoxelVolume(ivec3 p) { return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, VOXEL_SIZE)); }

    // The floodfill wrote B on even frames and A on odd ones.
    vec3 FloodLight(ivec3 p) {
        if (!InVoxelVolume(p)) return vec3(0.0);
        return (frameCounter & 1) == 0 ? texelFetch(floodSamplerB, p, 0).rgb : texelFetch(floodSamplerA, p, 0).rgb;
    }

    // Light in the volume at a position (volume coordinates), blended between the eight
    // nearest blocks.
    vec3 VoxelLight(vec3 p) {
        p -= 0.5;
        ivec3 base = ivec3(floor(p));
        vec3 f = p - vec3(base);
        vec3 c00 = mix(FloodLight(base), FloodLight(base + ivec3(1, 0, 0)), f.x);
        vec3 c10 = mix(FloodLight(base + ivec3(0, 1, 0)), FloodLight(base + ivec3(1, 1, 0)), f.x);
        vec3 c01 = mix(FloodLight(base + ivec3(0, 0, 1)), FloodLight(base + ivec3(1, 0, 1)), f.x);
        vec3 c11 = mix(FloodLight(base + ivec3(0, 1, 1)), FloodLight(base + ivec3(1, 1, 1)), f.x);
        return mix(mix(c00, c10, f.y), mix(c01, c11, f.y), f.z);
    }

    // Light volume (docs/WORLD_MODEL.md F1): sun bounce (rgb, per unit of sunlight) and sky
    // visibility (a) at a position (volume coordinates), blended between the eight nearest
    // blocks. Outside the volume: no bounce, open sky.
    vec4 BounceTexel(ivec3 p) {
        if (!InVoxelVolume(p)) return vec4(0.0, 0.0, 0.0, 1.0);
        return (frameCounter & 1) == 0 ? texelFetch(bounceSamplerB, p, 0) : texelFetch(bounceSamplerA, p, 0);
    }
    vec4 VolumeBounceSky(vec3 p) {
        p -= 0.5;
        ivec3 base = ivec3(floor(p));
        vec3 f = p - vec3(base);
        vec4 c00 = mix(BounceTexel(base), BounceTexel(base + ivec3(1, 0, 0)), f.x);
        vec4 c10 = mix(BounceTexel(base + ivec3(0, 1, 0)), BounceTexel(base + ivec3(1, 1, 0)), f.x);
        vec4 c01 = mix(BounceTexel(base + ivec3(0, 0, 1)), BounceTexel(base + ivec3(1, 0, 1)), f.x);
        vec4 c11 = mix(BounceTexel(base + ivec3(0, 1, 1)), BounceTexel(base + ivec3(1, 1, 1)), f.x);
        vec4 value = mix(mix(c00, c10, f.y), mix(c01, c11, f.y), f.z);
        // Fades out over the last 12 blocks towards the volume's edges (it ends 64 blocks
        // above and below the camera, 128 to the sides), so there is never a visible edge
        // where it stops, e.g. when flying up away from the ground.
        vec3 toEdge = min(p, vec3(VOXEL_SIZE) - 1.0 - p);
        float fade = saturate(min(toEdge.x, min(toEdge.y, toEdge.z)) / 12.0);
        return mix(vec4(0.0, 0.0, 0.0, 1.0), value, fade);
    }
    // At a surface: looked up half a block off it, into the space the light arrives through.
    vec4 SurfaceBounceSky(vec3 playerPos, vec3 normal) {
        return VolumeBounceSky(playerPos + cameraPosition + normal * 0.5 - vec3(VoxelOrigin()));
    }

    // Which way the block light comes from at a surface (Q4): the direction in which the
    // volume's light grows, from its slope across the space in front of the surface; w: how
    // clear that direction is (0 = light from all around).
    vec4 BlocklightDirection(vec3 playerPos, vec3 normal) {
        vec3 p = playerPos + cameraPosition + normal * 0.6 - vec3(VoxelOrigin());
        const float e = 0.5;
        float level = Luminance(VoxelLight(p));
        vec3 g = vec3(Luminance(VoxelLight(p + vec3(e, 0.0, 0.0))), Luminance(VoxelLight(p + vec3(0.0, e, 0.0))),
                      Luminance(VoxelLight(p + vec3(0.0, 0.0, e)))) - level;
        float len = length(g);
        // Light from one side falls by ~7% over half a block; lights all around cancel out.
        return len > 1e-6 && level > 1e-4 ? vec4(g / len, saturate(len / (level * 0.07))) : vec4(0.0, 1.0, 0.0, 0.0);
    }

    // Colour of light from a held item (torch, soul lantern, coloured candle, ...).
    vec3 HeldLightColor() {
        int id = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
        return GradeLightColor(IsLightSource(id) ? LightSourceColor(id) : FireColor());
    }

    // Colour of the world's block light reaching a surface. playerPos: camera-relative
    // position; normal: zero for sprites; lmBlock: Minecraft's block light there, 0..1.
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal, float lmBlock) {
        // Look half a block off the surface, into the space the light arrives through.
        vec3 p = playerPos + cameraPosition + normal * 0.5 - vec3(VoxelOrigin());
        vec3 light = VoxelLight(p);
        float peak = max(light.r, max(light.g, light.b));
        // Where the volume holds much less light than Minecraft's light level says is here
        // (light that came a way the volume does not know, or from outside it), its colour
        // is not trusted: fade smoothly to the default instead of switching at a hard edge.
        float expected = pow(0.86, 15.0 * (1.0 - lmBlock));
        float trust = smoothstep(0.08, 0.45, peak / expected);
        vec3 hue = peak > 1e-4 ? light / peak : FireColor();
        return GradeLightColor(mix(FireColor(), hue, trust));
    }

    #ifdef LIGHTNING_SHADOWS
        uniform usampler3D voxelSampler;

        // Lightning shadows (W4, plan item Q23): during a flash, whether the bolt can be seen
        // from a surface, by stepping through the voxel volume towards the bolt (aimed a
        // little up its length, where most of its light comes from): hills, trees and
        // buildings throw hard shadows for an instant. Leaves let some through. Beyond 40
        // blocks of path, or outside the volume, counted as clear.
        float LightningVoxelShadow(vec3 playerPos, vec3 normal) {
            vec3 bolt = lightningBoltPosition.xyz;
            float across = length(bolt.xz - playerPos.xz);
            vec3 target = vec3(bolt.x, clamp(playerPos.y + across * 0.5 + 4.0, bolt.y, bolt.y + 220.0), bolt.z);
            vec3 p = playerPos + cameraPosition + normal * 0.6 - vec3(VoxelOrigin());
            vec3 dir = normalize(target - playerPos);
            float pathLength = min(length(target - playerPos), 40.0);
            float vis = 1.0;
            for (float t = 0.5; t < pathLength; t += 0.7) {
                ivec3 v = ivec3(floor(p + dir * t));
                if (!InVoxelVolume(v)) break;
                uint voxel = texelFetch(voxelSampler, v, 0).r;
                uint priority = VoxelPriority(voxel);
                if (priority == VOXEL_PRIORITY_SOLID) return 0.0;
                if (priority == VOXEL_PRIORITY_TINT && VoxelBlockId(voxel) == BLOCK_LEAVES) vis *= 0.7;
            }
            return vis;
        }
    #endif
#else
    vec4 SurfaceBounceSky(vec3 playerPos, vec3 normal) { return vec4(0.0, 0.0, 0.0, 1.0); }
    vec4 BlocklightDirection(vec3 playerPos, vec3 normal) { return vec4(0.0, 1.0, 0.0, 0.0); }
    vec3 HeldLightColor() { return DefaultBlocklightColor(); }
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal, float lmBlock) { return DefaultBlocklightColor(); }
#endif

#endif
