// Fog (plan items F1-F4, N2, End haze). Needs sky.glsl.
// All fog colours come from the sky, so distant terrain melts into the sky behind it.

vec3 WaterFogColor(vec3 sunDir) {
    #ifdef WORLD_OVERWORLD
        return vec3(0.010, 0.050, 0.070) * (0.2 + 0.8 * DayFactor(sunDir.y));
    #else
        return vec3(0.010, 0.050, 0.070) * 0.4;
    #endif
}

// Border fog amount at a distance (0 near, 1 at the render distance edge).
float BorderFogAmount(float dist) {
    #ifdef BORDER_FOG
        #ifdef WORLD_NETHER
            float edge = min(far, NETHER_VIEW_LIMIT);
        #else
            float edge = far;
        #endif
        float f = smoothstep(edge * 0.72, edge, dist);
        return f * f;
    #else
        return 0.0;
    #endif
}

// Exponential height fog integrated along the view ray: dense near ATM_FOG_ALTITUDE,
// thinning with height, scaled to the render distance.
float AtmosphericFogAmount(vec3 playerPos) {
    float dist = length(playerPos);
    vec3 dir = playerPos / max(dist, 1e-4);
    const float scaleHeight = 40.0;

    float density = 0.9 * ATM_FOG_MULT / (max(far, 64.0) * ATM_FOG_DISTANCE);
    density *= 1.0 + 1.5 * rainStrength;
    float camHeight = cameraPosition.y - float(ATM_FOG_ALTITUDE);
    density *= exp(clamp(-camHeight / scaleHeight, -8.0, 3.0));

    float k = dir.y * dist / scaleHeight;
    float integral = abs(k) < 1e-3 ? 1.0 : (1.0 - exp(-k)) / k;
    float amount = 1.0 - exp(-density * dist * integral);
    return amount * (1.0 - caveFactor);
}

vec3 ApplyFog(vec3 color, vec3 playerPos, vec3 sunDir, bool isSky) {
    float dist = length(playerPos);
    vec3 dir = playerPos / max(dist, 1e-4);

    // Inside fluids: only the fluid's own fog.
    if (isEyeInWater == 1) return mix(color, WaterFogColor(sunDir), 1.0 - exp(-dist * 0.06));
    #ifdef LESS_LAVA_FOG
        const float denseFogRate = 0.15;
    #else
        const float denseFogRate = 0.5;
    #endif
    if (isEyeInWater == 2) return mix(color, vec3(1.2, 0.30, 0.05), saturate(dist * denseFogRate));
    if (isEyeInWater == 3) return mix(color, vec3(0.55, 0.62, 0.70), saturate(dist * denseFogRate));

    if (!isSky) {
        #if defined WORLD_OVERWORLD
            // Haze takes the sky colour near the horizon in that direction (blue by day,
            // warm towards a sunset).
            float atm = AtmosphericFogAmount(playerPos);
            if (atm > 0.0) color = mix(color, GetSky(normalize(vec3(dir.x, 0.04, dir.z)), sunDir, false), atm);
        #elif defined WORLD_NETHER
            color = mix(color, NetherSky(), 1.0 - exp(-dist * 0.006));
        #elif defined WORLD_END
            color = mix(color, EndSky(normalize(vec3(dir.x, 0.0, dir.z))) * 0.8, 1.0 - exp(-dist * 0.004));
        #endif

        float border = BorderFogAmount(dist);
        if (border > 0.0) color = mix(color, GetSky(dir, sunDir, false), border);

        #if defined CAVE_FOG && defined WORLD_OVERWORLD
            if (caveFactor > 0.0) color = mix(color, vec3(0.010, 0.011, 0.014), caveFactor * (1.0 - exp(-dist * 0.03)));
        #endif
    }

    float effects = max(blindness, darknessFactor);
    if (effects > 0.0) color = mix(color, vec3(0.0), saturate(dist / 6.0) * effects);
    return color;
}
