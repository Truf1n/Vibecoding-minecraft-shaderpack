#ifndef COLORED_LIGHT_GLSL
#define COLORED_LIGHT_GLSL

// Colour of block light at a point (plan items A1-A3, A5). With Coloured Lighting on, the
// hue comes from the floodfilled voxel volume (program/floodfill.glsl) and light held in
// the hand from the held item; the brightness always comes from Minecraft's light level.
// Needs: common.glsl, blockIds.glsl.

#include "/lib/lighting/lightColors.glsl"

vec3 DefaultBlocklightColor() { return vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B); }

#ifdef COLORED_LIGHTING
    #include "/lib/lighting/voxels.glsl"

    uniform sampler3D floodSamplerA;
    uniform sampler3D floodSamplerB;
    uniform int heldItemId;
    uniform int heldItemId2;

    vec3 FloodLight(ivec3 p) {
        if (any(lessThan(p, ivec3(0))) || any(greaterThanEqual(p, VOXEL_SIZE))) return vec3(0.0);
        // The floodfill wrote B on even frames and A on odd ones.
        return (frameCounter & 1) == 0 ? texelFetch(floodSamplerB, p, 0).rgb : texelFetch(floodSamplerA, p, 0).rgb;
    }

    // Light in the volume at a world position, blended between the eight nearest blocks.
    vec3 VoxelLight(vec3 worldPos) {
        vec3 p = worldPos - vec3(VoxelOrigin()) - 0.5;
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
        return IsLightSource(id) ? LightSourceColor(id) : FireColor();
    }
#endif

// Colour of the block light reaching a surface; its brightness is applied by the caller.
// playerPos: camera-relative position; normal: zero for sprites; lmBlock: block light
// level 0..1 before any held light; held: light level from a held item 0..1.
vec3 BlocklightColorAt(vec3 playerPos, vec3 normal, float lmBlock, float held) {
    #ifdef COLORED_LIGHTING
        // Look half a block off the surface, into the space the light arrives through.
        vec3 light = VoxelLight(playerPos + cameraPosition + normal * 0.5);
        float peak = max(light.r, max(light.g, light.b));
        vec3 hue = peak > 0.003 ? light / peak : FireColor();
        if (held > lmBlock) hue = mix(hue, HeldLightColor(), saturate((held - lmBlock) * 4.0));

        hue = max(mix(vec3(Luminance(hue)), hue, COLORED_LIGHT_SATURATION), 0.0);
        // Deep colours (red, blue) carry less brightness; give part of it back so they do
        // not read as much dimmer than torchlight.
        hue *= sqrt(Luminance(DefaultBlocklightColor()) / max(Luminance(hue), 0.08));
        return hue;
    #else
        return DefaultBlocklightColor();
    #endif
}

#endif
