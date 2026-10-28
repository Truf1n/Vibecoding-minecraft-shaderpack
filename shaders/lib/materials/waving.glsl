// Waving plants (plan items V1, V2, V4, V6): grass, flowers, crops and bushes sway from
// their base, tall plants as one piece, leaves and vines rustle, lily pads bob with the
// water. Used by the terrain pass and the shadow pass, so shadows wave along.
// Needs: common.glsl, blockIds.glsl.

#include "/lib/util/noise.glsl"

// Wind on a plant (world state system C): the world's wind direction and speed, with gusts
// - patches of stronger wind carried along by the air (the distance it has moved), so a
// gust sweeps across a field the way it ruffles the water and tilts the rain - plus the
// plant's own fluttering at its natural rate. response: how quickly this kind of plant
// moves (leaves flutter faster than tall plants sway).
vec3 Wind(vec3 worldPos, float response) {
    vec2 dir = WindDir();
    vec2 g = (worldPos.xz - wsWindOffset.xy) / 14.0;
    float gust = SmoothNoise(g) * 0.65 + SmoothNoise(g * 2.3 + 7.1) * 0.35;
    float strength = WindSpeed() / 3.0 * max(1.0 + wsWind.w * (gust * 2.0 - 0.8), 0.2);

    float t = frameTimeCounter * WAVING_SPEED * response;
    float phase = dot(worldPos.xz, vec2(0.45, 0.31));
    float flutter = sin(t * 1.9 + phase) * 0.6 + sin(t * 3.3 + phase * 1.7) * 0.3;
    float along = strength * (0.6 + flutter * 0.5) + flutter * 0.15;
    float across = flutter * 0.25 * (0.4 + strength * 0.4) * sin(t * 1.1 + phase * 0.6);
    vec2 xz = dir * along + vec2(-dir.y, dir.x) * across;
    return vec3(xz.x, -abs(along) * 0.15, xz.y); // leaning over also bends down a little
}

// World-space offset of a terrain vertex. top: the vertex is at the top of its sprite
// (texCoord above the sprite centre). skylight: 0..1 at the vertex.
vec3 WavingOffset(int id, vec3 worldPos, bool top, float skylight) {
    #ifdef WAVING_LILY_PADS
        if (id == BLOCK_LILY_PAD) {
            // Rides the same swell as the water surface (gbuffers_forward.glsl).
            #ifdef WAVING_WATER_VERTEX
                float t = wsJet.z * WATER_WAVE_SPEED;
                float wave = sin(worldPos.x * 0.65 + t * 1.3) * sin(worldPos.z * 0.55 + t * 1.1) * 0.5 + 0.5;
                return vec3(0.0, -wave * 0.05, 0.0);
            #endif
        }
    #endif
    // (The wind itself is stronger in rain; Waving in Rain adds to that.)
    float amount = WAVING_INTENSITY * mix(1.0, WAVING_RAIN, rainStrength * 0.5);
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
