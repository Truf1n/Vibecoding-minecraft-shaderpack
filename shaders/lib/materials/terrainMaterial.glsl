// Per-block material evaluation for deferred geometry (plan items M1, M5, M6). Runs in the
// gbuffers fragment stage, where the texture is available; the G-buffer only carries the
// result: shading model, emission, smoothness, metalness.
// Needs: common.glsl, blockIds.glsl.

struct Material {
    int shadingModel;
    float emission;   // 0..1, scaled to HDR in the lighting pass
    float smoothness; // 0 rough .. 1 mirror
    float metalness;  // 0 dielectric .. 1 metal (reflections tinted by the albedo)
};

Material DefaultMaterial(int shadingModel) {
    Material m;
    m.shadingModel = shadingModel;
    m.emission = 0.0;
    m.smoothness = 0.0;
    m.metalness = 0.0;
    return m;
}

float Saturation(vec3 c) { return max(c.r, max(c.g, c.b)) - min(c.r, min(c.g, c.b)); }

// Which texels of an ore texture are the ore itself (not the stone around it), 0..1.
float OreMask(int id, vec3 c) {
    float lum = Luminance(c);
    if (id == ORE_NETHER_QUARTZ) return smoothstep(0.55, 0.75, lum);                 // white specks on netherrack
    if (id == ORE_NETHER_GOLD || id == ORE_GILDED) return smoothstep(0.08, 0.2, c.g - c.b) * smoothstep(0.35, 0.55, c.g); // yellow
    if (id == ORE_ANCIENT_DEBRIS) return smoothstep(0.30, 0.45, lum);
    return smoothstep(0.10, 0.22, Saturation(c));                                    // colourful specks on grey stone
}

// Glowing ores (M5): each type can be switched on its own.
bool OreGlows(int id) {
    #ifndef GLOWING_ORES
        return false;
    #else
        if (id == ORE_IRON) {
            #ifdef GLOW_ORE_IRON
                return true;
            #endif
        }
        if (id == ORE_GOLD) {
            #ifdef GLOW_ORE_GOLD
                return true;
            #endif
        }
        if (id == ORE_COPPER) {
            #ifdef GLOW_ORE_COPPER
                return true;
            #endif
        }
        if (id == ORE_REDSTONE) {
            #ifdef GLOW_ORE_REDSTONE
                return true;
            #endif
        }
        if (id == ORE_LAPIS) {
            #ifdef GLOW_ORE_LAPIS
                return true;
            #endif
        }
        if (id == ORE_EMERALD) {
            #ifdef GLOW_ORE_EMERALD
                return true;
            #endif
        }
        if (id == ORE_DIAMOND) {
            #ifdef GLOW_ORE_DIAMOND
                return true;
            #endif
        }
        if (id == ORE_NETHER_QUARTZ) {
            #ifdef GLOW_ORE_NETHER_QUARTZ
                return true;
            #endif
        }
        if (id == ORE_NETHER_GOLD || id == ORE_GILDED) {
            #ifdef GLOW_ORE_NETHER_GOLD
                return true;
            #endif
        }
        if (id == ORE_ANCIENT_DEBRIS) {
            #ifdef GLOW_ORE_ANCIENT_DEBRIS
                return true;
            #endif
        }
        return false;
    #endif
}

Material GetTerrainMaterial(int blockId, vec3 albedoSrgb) {
    Material m = DefaultMaterial(SM_DEFAULT);
    float lum = Luminance(albedoSrgb);

    if (IsPlant(blockId)) {
        m.shadingModel = blockId == BLOCK_LEAVES ? SM_LEAVES : SM_FOLIAGE;
        m.smoothness = blockId == BLOCK_LEAVES ? 0.12 : 0.08; // a soft sheen, no traced reflections
    } else if (IsLightSource(blockId)) {
        // Only the bright texels of a light block glow (the flame, not the stick).
        m.emission = blockId == BLOCK_LIGHT_LAVA ? 1.0 : smoothstep(0.55, 0.95, lum);
        // Whole glowing blocks (froglights, sea lanterns, glowstone, ...) glow over their
        // full face: keep them from blowing out to white.
        bool fullBlock = blockId == BLOCK_LIGHT_GLOWSTONE || blockId == BLOCK_LIGHT_SEA_LANTERN
                      || blockId == BLOCK_LIGHT_CRYING || blockId == BLOCK_LIGHT_COPPER_BULB
                      || (blockId >= BLOCK_LIGHT_FROG_OCHRE && blockId <= BLOCK_LIGHT_FROG_PEARL);
        if (fullBlock) m.emission *= 0.4;
        if (blockId == BLOCK_LIGHT_AMETHYST) m.smoothness = 0.8;
        #if GLOW_LICHEN == 0
            if (blockId == BLOCK_LIGHT_LICHEN) m.emission = 0.0;
        #endif
    } else if (blockId >= 5001 && blockId <= 5031) {
        // Smoothness follows the texture a little: brighter texels are the polished bits.
        float detail = mix(0.75, 1.0, smoothstep(0.1, 0.7, lum));
        if (blockId == MAT_IRON)                 { m.smoothness = 0.72 * detail; m.metalness = 1.0; }
        else if (blockId == MAT_GOLD)            { m.smoothness = 0.82 * detail; m.metalness = 1.0; }
        else if (blockId == MAT_COPPER)          { m.smoothness = 0.70 * detail; m.metalness = 1.0; }
        else if (blockId == MAT_COPPER_OXIDIZED) { m.smoothness = 0.30 * detail; m.metalness = 0.4; }
        else if (blockId == MAT_NETHERITE)       { m.smoothness = 0.65 * detail; m.metalness = 1.0; }
        else if (blockId == MAT_RAW_METAL)       { m.smoothness = 0.35 * detail; m.metalness = 0.6; }
        else if (blockId == MAT_GEM)             { m.smoothness = 0.88 * detail; }
        else if (blockId == MAT_LAPIS_BLOCK)     { m.smoothness = 0.55 * detail; }
        else if (blockId == MAT_REDSTONE_BLOCK)  { m.smoothness = 0.50 * detail; }
        else if (blockId == MAT_AMETHYST_BLOCK)  { m.smoothness = 0.60 * detail; }
        else if (blockId == MAT_POLISHED_STONE)  { m.smoothness = 0.45 * detail; }
        else if (blockId == MAT_QUARTZ)          { m.smoothness = 0.60 * detail; }
        else if (blockId == MAT_CONCRETE)        { m.smoothness = 0.35; }
        else if (blockId == MAT_GLAZED)          { m.smoothness = 0.75; }
        else if (blockId == MAT_PRISMARINE)      { m.smoothness = 0.45 * detail; }
        else if (blockId == MAT_TERRACOTTA)      { m.smoothness = 0.15; }
        else if (blockId == MAT_OBSIDIAN)        { m.smoothness = 0.78 * detail; }
        else if (blockId == MAT_PACKED_ICE)      { m.smoothness = 0.85; }
        else if (blockId == MAT_SNOW)            { m.smoothness = 0.20; }
        else if (blockId == MAT_PURPUR)          { m.smoothness = 0.30 * detail; }
        else if (blockId == MAT_PLANKS)          { m.smoothness = 0.20 * detail; }
        else if (blockId == MAT_LOGS)            { m.smoothness = 0.06; }

        // Optional glowing blocks (M6).
        #ifdef EMISSIVE_REDSTONE_BLOCK
            if (blockId == MAT_REDSTONE_BLOCK) m.emission = 0.35 * smoothstep(0.2, 0.6, lum);
        #endif
        #ifdef EMISSIVE_LAPIS_BLOCK
            if (blockId == MAT_LAPIS_BLOCK) m.emission = 0.25 * smoothstep(0.25, 0.6, lum);
        #endif
        #if GLOWING_AMETHYST == 2
            if (blockId == MAT_AMETHYST_BLOCK) m.emission = 0.25 * smoothstep(0.45, 0.8, lum);
        #endif
    } else if (IsOre(blockId)) {
        float ore = OreMask(blockId, albedoSrgb);
        bool gem = blockId == ORE_DIAMOND || blockId == ORE_EMERALD || blockId == ORE_LAPIS || blockId == ORE_NETHER_QUARTZ;
        bool metal = blockId == ORE_IRON || blockId == ORE_GOLD || blockId == ORE_COPPER || blockId == ORE_NETHER_GOLD || blockId == ORE_GILDED;
        m.smoothness = ore * (gem ? 0.85 : metal ? 0.6 : 0.3);
        m.metalness = metal ? ore * 0.8 : 0.0;
        if (OreGlows(blockId)) m.emission = ore * 0.35 * GLOWING_ORES_STRENGTH;
    }

    #if GLOWING_AMETHYST == 0
        if (blockId == BLOCK_LIGHT_AMETHYST) m.emission = 0.0;
    #endif
    return m;
}
