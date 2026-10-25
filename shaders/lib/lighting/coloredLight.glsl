#ifndef COLORED_LIGHT_GLSL
#define COLORED_LIGHT_GLSL

// Colour of block light at a point (plan items A1-A3, A5). With Coloured Lighting on, the
// hue comes from the floodfilled voxel volume (program/floodfill.glsl). Near coloured
// glass, straight lines are traced from the surface to each nearby light (listed by
// program/lightClusters.glsl): the light that crosses glass on the way takes its colour,
// so glass casts clean coloured shapes. Light held in the hand takes the held item's colour.
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
    uniform usampler3D glassNearSamplerA;
    uniform usampler3D glassNearSamplerB;
    uniform usampler3D lightClusterSampler;
    uniform usampler3D voxelSampler;
    uniform int heldItemId;
    uniform int heldItemId2;

    bool InVoxelVolume(ivec3 p) { return all(greaterThanEqual(p, ivec3(0))) && all(lessThan(p, VOXEL_SIZE)); }

    // The floodfill wrote B on even frames and A on odd ones.
    vec3 FloodLight(ivec3 p) {
        if (!InVoxelVolume(p)) return vec3(0.0);
        return (frameCounter & 1) == 0 ? texelFetch(floodSamplerB, p, 0).rgb : texelFetch(floodSamplerA, p, 0).rgb;
    }
    uint GlassNear(ivec3 p) {
        if (!InVoxelVolume(p)) return 0u;
        return (frameCounter & 1) == 0 ? texelFetch(glassNearSamplerB, p, 0).r : texelFetch(glassNearSamplerA, p, 0).r;
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

    // Tint of the coloured glass in a block space for the part of a line inside it (from +
    // dir * t, t0 to t1): a pane only where the line crosses it.
    vec3 CellTint(uint voxel, ivec3 cell, vec3 from, vec3 dir, float t0, float t1) {
        int id = VoxelBlockId(voxel);
        if (VoxelPriority(voxel) != VOXEL_PRIORITY_TINT || !IsLineTint(id)) return vec3(1.0);
        if (IsStainedPane(id) && (voxel & (VOXEL_PANE_X | VOXEL_PANE_Z)) != 0u) {
            vec3 mid = vec3(cell) + 0.5;
            bool crossed = false;
            for (int axis = 0; axis < 3; axis += 2) {
                if ((voxel & (axis == 0 ? VOXEL_PANE_Z : VOXEL_PANE_X)) == 0u) continue;
                if (abs(dir[axis]) < 1e-5) {
                    crossed = crossed || abs(from[axis] - mid[axis]) < 0.0625;
                } else {
                    float t = (mid[axis] - from[axis]) / dir[axis];
                    crossed = crossed || (t >= t0 && t <= t1);
                }
            }
            if (!crossed) return vec3(1.0);
        }
        return VoxelTint(VOXEL_PRIORITY_TINT, id);
    }

    // Colour picked up along the straight line from a point to the centre of a light's
    // block (volume coordinates): the product of the coloured glass crossed, counting the
    // block the point sits in. w = 0 when a solid block is in the way (that light only
    // gets here around corners, if at all).
    vec4 TintAlongLine(vec3 from, ivec3 target) {
        ivec3 cell = ivec3(floor(from));
        vec3 dir = vec3(target) + 0.5 - from;
        vec3 stepSign = sign(dir);
        vec3 invDir = 1.0 / max(abs(dir), vec3(1e-5));
        vec3 tMax = (stepSign * (vec3(cell) - from) + max(stepSign, 0.0)) * invDir;
        tMax = mix(vec3(1e9), tMax, abs(stepSign)); // never step along an axis the line doesn't move in
        ivec3 cellStep = ivec3(stepSign);

        // Walk the blocks along the line (3D DDA), stopping at the light's own block.
        float tEnter = 0.0;
        vec3 tint = vec3(1.0);
        for (int i = 0; i < 48 && cell != target; i++) {
            uint voxel = texelFetch(voxelSampler, cell, 0).r;
            if (i > 0 && VoxelPriority(voxel) == VOXEL_PRIORITY_SOLID) return vec4(1.0, 1.0, 1.0, 0.0);
            float tExit = min(tMax.x, min(tMax.y, tMax.z));
            tint *= CellTint(voxel, cell, from, dir, tEnter, tExit);
            tEnter = tExit;
            if (tMax.x < tMax.y && tMax.x < tMax.z) { cell.x += cellStep.x; tMax.x += invDir.x; }
            else if (tMax.y < tMax.z) { cell.y += cellStep.y; tMax.y += invDir.y; }
            else { cell.z += cellStep.z; tMax.z += invDir.z; }
            if (!InVoxelVolume(cell)) break;
        }
        return vec4(tint, 1.0);
    }

    // How coloured glass changes the block light at a point (volume coordinates), per
    // colour channel: the nearby lights' direct light with the glass on each line, over
    // the same without it. 1 away from coloured glass.
    vec3 GlassLightFilter(vec3 from) {
        ivec3 cell = ivec3(floor(from));
        if (GlassNear(cell) == 0u) return vec3(1.0);
        ivec3 cluster = cell / CLUSTER_SIZE;
        int base = cluster.z * CLUSTER_STRIDE;
        vec3 direct = vec3(0.0), filtered = vec3(0.0);
        for (int k = 0; k < CLUSTER_LIGHTS; k++) {
            uint light = texelFetch(lightClusterSampler, ivec3(cluster.xy, base + 1 + k), 0).r;
            if (light == 0u) break;
            ivec3 lightCell = LightCell(light);
            vec3 d = abs(vec3(lightCell) + 0.5 - from); // continuous, so the weights have no block steps
            float level = float(LightEmission(light)) - (d.x + d.y + d.z);
            if (level <= 0.0) continue;
            vec4 tint = TintAlongLine(from, lightCell);
            if (tint.w == 0.0) continue;
            vec3 color = LightSourceColor(VoxelBlockId(texelFetch(voxelSampler, lightCell, 0).r)) * (level * level);
            direct += color;
            filtered += color * tint.rgb;
        }
        return (filtered + 1e-4) / (direct + 1e-4);
    }

    // Colour of light from a held item (torch, soul lantern, coloured candle, ...).
    vec3 HeldLightColor() {
        int id = heldBlockLightValue >= heldBlockLightValue2 ? heldItemId : heldItemId2;
        return GradeLightColor(IsLightSource(id) ? LightSourceColor(id) : FireColor());
    }

    // Colour (and, through tinted glass, dimming) of the world's block light reaching a
    // surface. playerPos: camera-relative position; normal: zero for sprites.
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal) {
        // Look half a block off the surface, into the space the light arrives through.
        vec3 p = playerPos + cameraPosition + normal * 0.5 - vec3(VoxelOrigin());
        vec3 light = VoxelLight(p);
        float peak = max(light.r, max(light.g, light.b));
        vec3 hue = peak > 0.003 ? light / peak : FireColor();

        // Coloured glass between the surface and its lights shifts the colour towards the
        // glass's own (Glass Light Colouring) and takes some brightness with what it filters
        // out; dark (tinted) glass dims it most.
        vec3 glass = GlassLightFilter(playerPos + cameraPosition + normal * 0.05 - vec3(VoxelOrigin()));
        vec3 filtered = hue * mix(vec3(1.0), glass, GLASS_LIGHT_TINT);
        float keep = mix(1.0, Luminance(filtered) / max(Luminance(hue), 1e-3), 0.5);
        float fp = max(filtered.r, max(filtered.g, filtered.b));
        return GradeLightColor(fp > 1e-4 ? filtered / fp : hue) * keep;
    }
#else
    vec3 HeldLightColor() { return DefaultBlocklightColor(); }
    vec3 WorldBlocklightColor(vec3 playerPos, vec3 normal) { return DefaultBlocklightColor(); }
#endif

#endif
