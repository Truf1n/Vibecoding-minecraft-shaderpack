// Placeholder fog for M0: border fog and in-fluid fog. Replaced by the M2 atmosphere.

vec3 ApplyFog(vec3 color, vec3 playerPos, bool isSky) {
    float dist = length(playerPos);

    if (isEyeInWater == 1) {
        float f = 1.0 - exp(-dist * 0.06);
        return mix(color, vec3(0.010, 0.045, 0.060), f);
    }
    if (isEyeInWater == 2) return mix(color, vec3(1.2, 0.30, 0.05), saturate(dist * 0.5));
    if (isEyeInWater == 3) return mix(color, vec3(0.55, 0.62, 0.70), saturate(dist * 0.5));

    float effects = max(blindness, darknessFactor);
    if (effects > 0.0) color = mix(color, vec3(0.0), saturate(dist / 6.0) * effects);

    #ifdef BORDER_FOG
        if (!isSky) {
            float f = smoothstep(far * 0.70, far, dist);
            color = mix(color, SrgbToLinear(fogColor), f * f);
        }
    #endif
    return color;
}
