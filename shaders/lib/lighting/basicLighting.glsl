// Placeholder lighting model for M0: lightmap-driven, no shadows.
// Replaced by the real lighting model (shadows, sky ambient, SSS) in M1.

vec2 RemapLightmap(vec2 lm) { return saturate((lm - 0.5 / 16.0) * (16.0 / 15.0)); }

vec3 BlocklightColor() { return vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B) * BLOCKLIGHT_I; }

// Dynamic handheld light (plan item L14): vanilla light level minus distance, like vanilla falloff.
float HeldLight(float distToCamera) {
    float level = float(max(heldBlockLightValue, heldBlockLightValue2));
    return saturate((level - distToCamera) / 15.0);
}

// lm: (block, sky) in [0,1]. NdotL < 0 means "no meaningful normal" (particles).
vec3 GetBasicLighting(vec2 lm, float NdotL, float ao, bool foliage) {
    float block = lm.x * lm.x * (0.4 + 1.6 * lm.x * lm.x);
    vec3 light = BlocklightColor() * block;

    #if defined WORLD_NETHER
        light += vec3(0.32, 0.14, 0.07) * 0.6 * AMBIENT_MULT;
    #elif defined WORLD_END
        light += vec3(0.20, 0.15, 0.28) * 0.7 * AMBIENT_MULT;
        light += vec3(0.55, 0.45, 0.70) * (NdotL < 0.0 ? 0.5 : NdotL) * 0.6;
    #else
        float elevation = SunElevation();
        float day = smoothstep(-0.12, 0.18, elevation);
        float sunsetTint = 1.0 - smoothstep(0.0, 0.45, elevation);
        vec3 sunColor = mix(vec3(1.00, 0.96, 0.90), vec3(1.00, 0.55, 0.30), sunsetTint) * 3.0;
        vec3 moonColor = vec3(0.10, 0.13, 0.20) * 0.6;
        vec3 direct = mix(moonColor, sunColor, day) * (1.0 - 0.75 * rainStrength);

        vec3 ambient = mix(vec3(0.03, 0.04, 0.07), vec3(0.50, 0.62, 0.80), day) * (1.0 - 0.4 * rainStrength);

        float diffuse = NdotL < 0.0 ? 0.5 : (foliage ? 0.35 + 0.65 * NdotL : NdotL);
        float skyOpen = lm.y * lm.y;
        light += direct * diffuse * skyOpen * skyOpen + ambient * skyOpen * AMBIENT_MULT;
    #endif

    light += vec3(0.0035 * CAVE_LIGHTING) + vec3(0.25 * nightVision);
    return light * ao;
}
