// Waving plants (plan items V1, V2, V4, V6): grass, flowers, crops and bushes sway from
// their base, tall plants as one piece, leaves and vines rustle, lily pads bob with the
// water. Used by the terrain pass and the shadow pass, so shadows wave along.
// Needs: common.glsl, blockIds.glsl.

// Gusty wind at a world position: mostly along +x, a little along z, strongest in rain.
vec3 Wind(vec3 worldPos, float speed) {
    float t = frameTimeCounter * WAVING_SPEED * speed;
    float gust = 0.65 + 0.35 * sin(t * 0.35 + worldPos.x * 0.04 + worldPos.z * 0.03);
    float x = sin(t * 1.7 + worldPos.x * 0.45 + worldPos.z * 0.30) + 0.45 * sin(t * 3.1 + worldPos.x * 0.9 - worldPos.z * 0.7);
    float z = sin(t * 1.3 + worldPos.z * 0.50 - worldPos.x * 0.20) * 0.55;
    float y = sin(t * 2.3 + worldPos.x * 0.7 + worldPos.z * 0.6) * 0.25;
    return vec3(x + 0.6, y, z) * gust;
}

// World-space offset of a terrain vertex. top: the vertex is at the top of its sprite
// (texCoord above the sprite centre). skylight: 0..1 at the vertex.
vec3 WavingOffset(int id, vec3 worldPos, bool top, float skylight) {
    #ifdef WAVING_LILY_PADS
        if (id == BLOCK_LILY_PAD) {
            // Rides the same swell as the water surface (gbuffers_forward.glsl).
            #ifdef WAVING_WATER_VERTEX
                float t = frameTimeCounter * WATER_WAVE_SPEED;
                float wave = sin(worldPos.x * 0.65 + t * 1.3) * sin(worldPos.z * 0.55 + t * 1.1) * 0.5 + 0.5;
                return vec3(0.0, -wave * 0.05, 0.0);
            #endif
        }
    #endif
    float amount = WAVING_INTENSITY * mix(1.0, WAVING_RAIN, rainStrength);
    #ifdef NO_WAVING_INDOORS
        amount *= smoothstep(0.45, 0.75, skylight);
    #endif
    if (amount <= 0.0) return vec3(0.0);

    #ifdef WAVING_PLANTS
        // Short plants bend from the ground: only their top corners move. Tall plants: the
        // lower half bends like a short one, the upper half follows it and bends further.
        if (id == BLOCK_PLANT_GROUND || id == BLOCK_PLANT_TALL_LOWER || id == BLOCK_BUSH) {
            return top ? Wind(worldPos, 1.0) * (0.09 * amount) : vec3(0.0);
        }
        if (id == BLOCK_PLANT_TALL_UPPER) {
            return Wind(worldPos, 1.0) * ((top ? 0.16 : 0.09) * amount);
        }
    #endif
    #ifdef WAVING_LEAVES
        if (id == BLOCK_LEAVES) return Wind(worldPos, 0.8) * (0.035 * amount);
        if (id == BLOCK_PLANT_HANGING) return Wind(worldPos, 0.9) * vec3(0.06, 0.0, 0.06) * amount;
    #endif
    return vec3(0.0);
}
