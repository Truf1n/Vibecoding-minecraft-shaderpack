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

    // Colour of light from a held item (torch, soul lantern, coloured candle, ...).
    vec3 HeldLightColor() {
        int id = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
        return GradeLightColor(IsLightSource(id) ? LightSourceColor(id) : FireColor());
    }

    // Colour of the world's block light reaching a surface. playerPos: camera-relative
    // position; normal: zero for sprites.
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal) {
        // Look half a block off the surface, into the space the light arrives through.
        vec3 p = playerPos + cameraPosition + normal * 0.5 - vec3(VoxelOrigin());
        vec3 light = VoxelLight(p);
        float peak = max(light.r, max(light.g, light.b));
        return GradeLightColor(peak > 0.003 ? light / peak : FireColor());
    }
#else
    vec3 HeldLightColor() { return DefaultBlocklightColor(); }
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal) { return DefaultBlocklightColor(); }
#endif

#endif
