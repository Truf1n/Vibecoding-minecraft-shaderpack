// Interim lighting model: sun/moon + sky ambient + blocklight, no shadow map yet (M1).
// Colours come from lib/atmosphere/sky.glsl so lighting matches the sky.

vec3 BlocklightColor() { return vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B) * BLOCKLIGHT_I; }

// Dynamic handheld light (plan item L14): vanilla light level minus distance, like vanilla falloff.
float HeldLight(float distToCamera) {
    float level = float(max(heldBlockLightValue, heldBlockLightValue2));
    return saturate((level - distToCamera) / 15.0);
}

// Blocklight falloff: steep near the source, long soft tail (vanilla levels are linear-ish).
float BlocklightFalloff(float lmBlock) {
    float l = lmBlock * lmBlock;
    return l * (0.25 + 0.75 * l) * 1.6;
}

// lm: (block, sky) in [0,1]. NdotL < 0 means "no meaningful normal" (particles).
vec3 GetBasicLighting(vec2 lm, float NdotL, float ao, bool foliage, vec3 sunDir) {
    vec3 light = BlocklightColor() * BlocklightFalloff(lm.x);
    float diffuse = NdotL < 0.0 ? 0.45 : (foliage ? 0.35 + 0.65 * NdotL : NdotL);

    #if defined WORLD_NETHER
        light += vec3(0.30, 0.13, 0.07) * 0.55 * AMBIENT_MULT;
    #elif defined WORLD_END
        light += vec3(0.16, 0.12, 0.22) * 0.55 * AMBIENT_MULT;
        light += vec3(0.42, 0.34, 0.55) * 0.45 * diffuse;
    #else
        float sunUp = sunDir.y;
        // Until real shadows exist, approximate "is this in the open" with sky light.
        float skyOpen = lm.y * lm.y;
        float sunReach = skyOpen * skyOpen;
        light += SunLightColor(sunUp) * diffuse * sunReach;
        light += SkyAmbientColor(sunUp) * 0.85 * skyOpen * AMBIENT_MULT;
    #endif

    light += vec3(0.0035 * CAVE_LIGHTING) + vec3(0.25 * nightVision);
    return light * ao;
}
