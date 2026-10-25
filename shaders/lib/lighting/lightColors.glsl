#ifndef LIGHT_COLORS_GLSL
#define LIGHT_COLORS_GLSL

// Colour of the light each light-emitting block gives off (plan items A3, A5), by the IDs
// in block.properties / item.properties. Linear RGB, brightest channel 1.
// Needs: common.glsl, blockIds.glsl.

// Dye colours, in stained-glass order (white orange magenta light_blue yellow lime pink
// gray light_gray cyan purple blue brown green red black): candle flames and the tint of
// stained glass for light passing through.
vec3 DyeColor(int index) {
    const vec3 colors[16] = vec3[16](
        vec3(1.00, 0.78, 0.55), vec3(1.00, 0.55, 0.20), vec3(1.00, 0.35, 0.85), vec3(0.45, 0.70, 1.00),
        vec3(1.00, 0.85, 0.30), vec3(0.60, 1.00, 0.30), vec3(1.00, 0.50, 0.70), vec3(0.75, 0.70, 0.65),
        vec3(0.95, 0.85, 0.75), vec3(0.30, 0.90, 0.95), vec3(0.70, 0.35, 1.00), vec3(0.35, 0.45, 1.00),
        vec3(1.00, 0.60, 0.35), vec3(0.55, 0.85, 0.30), vec3(1.00, 0.25, 0.20), vec3(0.65, 0.50, 0.60));
    return colors[clamp(index, 0, 15)];
}

// Flame colour: FIRE_WARMTH pushes it from a neutral warm white towards deep orange.
vec3 FireColor() { return mix(vec3(1.00, 0.78, 0.55), vec3(1.00, 0.45, 0.15), FIRE_WARMTH); }

vec3 LightSourceColor(int id) {
    if (id == BLOCK_LIGHT_SOUL) return vec3(0.30, 0.78, 1.00);
    if (id == BLOCK_LIGHT_GLOWSTONE) return vec3(1.00, 0.78, 0.48);
    if (id == BLOCK_LIGHT_SEA_LANTERN) return vec3(0.72, 0.90, 1.00);
    if (id == BLOCK_LIGHT_LAVA) return vec3(1.00, 0.38, 0.08);
    if (id == BLOCK_LIGHT_REDSTONE) return vec3(1.00, 0.12, 0.06);
    if (id == BLOCK_LIGHT_COPPER) return vec3(0.45, 1.00, 0.55);
    if (id == BLOCK_LIGHT_AMETHYST) return vec3(0.75, 0.42, 1.00);
    if (id == BLOCK_LIGHT_LICHEN) return vec3(0.62, 0.92, 0.72);
    if (id == BLOCK_LIGHT_CRYING) return vec3(0.58, 0.22, 1.00);
    if (id == BLOCK_NETHER_PORTAL) return vec3(0.62, 0.28, 1.00);
    if (id == BLOCK_LIGHT_FROG_OCHRE) return vec3(1.00, 0.85, 0.45);
    if (id == BLOCK_LIGHT_FROG_VERDANT) return vec3(0.55, 1.00, 0.55);
    if (id == BLOCK_LIGHT_FROG_PEARL) return vec3(1.00, 0.60, 0.90);
    if (id == BLOCK_LIGHT_SEA_PICKLE) return vec3(0.45, 1.00, 0.80);
    if (id == BLOCK_LIGHT_SCULK) return vec3(0.25, 0.85, 1.00);
    if (id == BLOCK_LIGHT_ENCHANT) return vec3(0.70, 0.45, 1.00);
    if (id == BLOCK_LIGHT_TRIAL) return vec3(1.00, 0.55, 0.20);
    if (id == BLOCK_LIGHT_OMINOUS) return vec3(0.35, 0.75, 1.00);
    if (id == BLOCK_LIGHT_COPPER_BULB) return vec3(1.00, 0.85, 0.65);
    if (id == BLOCK_PLANT_HANGING) return vec3(1.00, 0.72, 0.30); // glow berries
    if (id == BLOCK_PLANT_GROUND) return vec3(0.85, 1.00, 0.40);  // firefly bush
    if (id >= BLOCK_LIGHT_CANDLE && id <= BLOCK_LIGHT_CANDLE + 16) {
        #ifdef COLORED_CANDLES
            if (id > BLOCK_LIGHT_CANDLE) return DyeColor(id - BLOCK_LIGHT_CANDLE - 1);
        #endif
        return FireColor();
    }
    // Torches, lanterns, fire, and anything else that glows.
    return FireColor();
}

#endif
