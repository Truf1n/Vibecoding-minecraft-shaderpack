// Interim fog: border fog that fades into the sky, plus in-fluid and blindness fog.
// Replaced by the full atmosphere (atmospheric/cave fog, light shafts) in M2/M5.
// Needs lib/atmosphere/sky.glsl.

vec3 WaterFogColor(vec3 sunDir) {
    #ifdef WORLD_OVERWORLD
        return vec3(0.010, 0.050, 0.070) * (0.2 + 0.8 * DayFactor(sunDir.y));
    #else
        return vec3(0.010, 0.050, 0.070) * 0.4;
    #endif
}

vec3 ApplyFog(vec3 color, vec3 playerPos, vec3 sunDir, bool isSky) {
    float dist = length(playerPos);

    if (isEyeInWater == 1) return mix(color, WaterFogColor(sunDir), 1.0 - exp(-dist * 0.06));
    if (isEyeInWater == 2) return mix(color, vec3(1.2, 0.30, 0.05), saturate(dist * 0.5));
    if (isEyeInWater == 3) return mix(color, vec3(0.55, 0.62, 0.70), saturate(dist * 0.5));

    float effects = max(blindness, darknessFactor);
    if (effects > 0.0) color = mix(color, vec3(0.0), saturate(dist / 6.0) * effects);

    if (isSky) return color;

    #ifdef BORDER_FOG
        float f = smoothstep(far * 0.72, far, dist);
        if (f > 0.0) {
            vec3 dir = playerPos / max(dist, 1e-4);
            color = mix(color, GetSky(dir, sunDir, false), f * f);
        }
    #endif

    #ifdef WORLD_NETHER
        // The Nether is always hazy.
        color = mix(color, NetherSky(), 1.0 - exp(-dist * 0.006));
    #endif
    return color;
}
