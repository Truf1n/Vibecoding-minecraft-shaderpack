// Weather effects shared by the lighting, sky, clouds, water and terrain (plan items R1,
// R2, R5, +5 and the lightning and storm requests): lightning flashes, storm darkness,
// snowstorms and sandstorms, raindrop ripples, puddles and wet surfaces.
// Needs: common.glsl, Hash13 (sky.glsl, which includes this file).

#include "/lib/util/noise.glsl"

// ---- Lightning -------------------------------------------------------------------------

const vec3 LIGHTNING_COLOR = vec3(0.68, 0.76, 1.00);

// Brightness of a lightning flash right now, 0..1: on while a bolt exists, flickering
// a few times a second like the bolt's own strokes.
float LightningFlicker() {
    if (lightningBoltPosition.w < 0.5) return 0.0;
    float stroke = floor(frameTimeCounter * 24.0);
    return 0.45 + 0.55 * Hash13(vec3(stroke, 7.1, 3.3));
}

// Light the whole sky gives off during a flash (sky, clouds, and everything under the
// open sky, on top of the bolt's own light below).
vec3 LightningFlashColor() {
    return LIGHTNING_COLOR * (LightningFlicker() * 0.5 * LIGHTNING_FLASH);
}

// Light from the bolt itself on a surface. playerPos: camera-relative; normal: zero for
// sprites; skylight: 0..1 (no light reaches deep inside).
vec3 LightningLight(vec3 playerPos, vec3 normal, float skylight) {
    float flicker = LightningFlicker();
    if (flicker <= 0.0 || LIGHTNING_FLASH <= 0.0) return vec3(0.0);
    // Nearest point of the bolt: a vertical line from where it struck up into the clouds.
    vec3 bolt = lightningBoltPosition.xyz;
    vec3 nearest = vec3(bolt.x, clamp(playerPos.y, bolt.y, bolt.y + 220.0), bolt.z);
    vec3 toBolt = nearest - playerPos;
    float dist = length(toBolt);
    float facing = dot(normal, normal) > 0.5 ? saturate(dot(normal, toBolt / max(dist, 1e-3))) * 0.85 + 0.15 : 0.6;
    float falloff = 1.0 / (1.0 + dist * dist / (40.0 * 40.0));
    return LIGHTNING_COLOR * (flicker * falloff * facing * 6.0 * LIGHTNING_FLASH * smoothstep(0.05, 0.5, skylight));
}

// ---- Storms ----------------------------------------------------------------------------

// Rain as seen falling: follows the rain, but builds up only as fast as the clouds set in.
float VisibleRain() { return min(rainStrength, stormRain); }

// How much a thunderstorm darkens the sky and its light (1 = no change).
float StormDim() { return 1.0 - 0.55 * stormThunder * STORM_DARKNESS; }

// Snowstorm / sandstorm strength in the current biome (0 outside one).
float SnowStorm() {
    #ifdef WEATHER_STORMS
        return VisibleRain() * inSnowyBiome;
    #else
        return 0.0;
    #endif
}
float SandStorm() {
    #ifdef WEATHER_STORMS
        return VisibleRain() * inSandyBiome;
    #else
        return 0.0;
    #endif
}

// Strength of a snowstorm or sandstorm here (0 outside one).
float StormAmount() { return max(SnowStorm(), SandStorm()); }

// Colour of the storm's air: bright snow-white or sandy by day, dark at night.
vec3 StormColor(float sunUp) {
    float snow = SnowStorm(), sand = SandStorm();
    vec3 color = (vec3(0.70, 0.76, 0.85) * snow + vec3(0.85, 0.60, 0.36) * sand) / max(snow + sand, 1e-4);
    float light = 0.04 + 0.96 * DayFactor(sunUp);
    return color * light * StormDim() * (1.0 - 0.75 * caveFactor) * AtmosphereMultiplier(sunUp);
}

// ---- Rain on surfaces ------------------------------------------------------------------

// Rain falls here at all: under the open sky, not in snowy or dry biomes.
float RainExposure(float skylight) {
    return smoothstep(0.86, 0.96, skylight) * (1.0 - inSnowyBiome) * (1.0 - inSandyBiome);
}

// Expanding rings from raindrops, as a slope (dh/dx, dh/dz) to add to the surface's own
// (the waves, a flat puddle). Each drop sends out a short train of wavelets that spreads at
// about 1.5 blocks/s and dies out in under a second; the rings of neighbouring drops
// overlap and add up (they interfere), and they ride on whatever the surface does.
// Two overlapping grids of drops, each landing at its own time.
vec2 RainRipples(vec2 p) {
    const float spacing = 0.7;    // blocks between drops in one grid
    const float life = 0.75;      // seconds a ring lasts
    const float speed = 1.5;      // blocks per second
    const float k = TAU / 0.16;   // wavelets 0.16 blocks apart
    vec2 slope = vec2(0.0);
    for (int layer = 0; layer < 2; layer++) {
        vec2 q = p / spacing + float(layer) * vec2(0.37, 0.71);
        vec2 cell = floor(q);
        for (int y = -1; y <= 1; y++) {
            for (int x = -1; x <= 1; x++) {
                vec2 c = cell + vec2(x, y);
                float seed = Hash13(vec3(c, float(layer)));
                float age = fract(frameTimeCounter / life + seed) * life;
                vec2 drop = (c + 0.5 + (vec2(Hash13(vec3(c, 5.3)), Hash13(vec3(c, 9.1))) - 0.5) * 0.8) * spacing;
                vec2 d = p - drop;
                float r = length(d);
                float front = age * speed;
                float x0 = r - front;
                // A packet of a few wavelets around the front, fading as it spreads.
                float envelope = exp(-x0 * x0 / 0.012) * exp(-age * 3.5) / (1.0 + front * 4.0);
                if (envelope < 1e-3) continue;
                float dhdr = envelope * (k * cos(k * x0) - 2.0 * x0 / 0.012 * sin(k * x0));
                slope += d / max(r, 1e-3) * dhdr;
            }
        }
    }
    return slope * 0.006;
}

// Where water collects on a flat, exposed surface (0..1), from a large smooth pattern,
// growing with how long it has rained. worldPos: world position; up: how much the surface
// faces up (normal.y).
float PuddleAmount(vec3 worldPos, float up, float skylight) {
    #if PUDDLES == 0
        return 0.0;
    #else
        float flat_ = smoothstep(0.9, 0.98, up);
        if (flat_ <= 0.0) return 0.0;
        #if PUDDLES == 3
            float wet = 1.0;
            float exposure = smoothstep(0.86, 0.96, skylight) * (1.0 - inSnowyBiome) * (1.0 - inSandyBiome);
        #else
            float wet = wetness;
            float exposure = RainExposure(skylight);
        #endif
        if (wet * exposure <= 0.0) return 0.0;
        #if PUDDLES == 2
            return flat_ * exposure * smoothstep(0.1, 0.6, wet);
        #else
            vec2 p = worldPos.xz / 9.0;
            float n = SmoothNoise(p) * 0.6 + SmoothNoise(p * 2.3 + 5.1) * 0.4;
            // Puddles spread out from the lowest spots as it keeps raining.
            float level = 0.72 - 0.30 * wet;
            return flat_ * exposure * smoothstep(level, level + 0.06, n) * smoothstep(0.05, 0.3, wet);
        #endif
    #endif
}
