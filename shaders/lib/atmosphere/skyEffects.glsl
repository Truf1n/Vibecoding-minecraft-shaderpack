// Sky effects (plan items S6-S8, E1, E3): night nebulae, aurora, rainbows, End beams and
// End flashes. All drawn into the sky directly, so they also show in reflections that
// ask for them (Sky Effects in Reflections).
// Needs: common.glsl, and Hash13 / CelestialAxis / DayFactor (sky.glsl, which includes
// this file).

// Smooth 3D value noise from two slices of the noise texture (linear filtering does the
// blending within a slice).
float SkyNoise3D(vec3 p) {
    float z = floor(p.z);
    float f = p.z - z;
    f = f * f * (3.0 - 2.0 * f);
    vec2 a = p.xy + z * vec2(37.0, 17.0);
    vec2 b = a + vec2(37.0, 17.0);
    float na = textureLod(noisetex, (a + 0.5) / float(noiseTextureResolution), 0.0).r;
    float nb = textureLod(noisetex, (b + 0.5) / float(noiseTextureResolution), 0.0).r;
    return mix(na, nb, f);
}

// ---- Nebulae ---------------------------------------------------------------------------

// Faint coloured gas along a band across the night sky, different every night: the band's
// tilt, the shapes and the two colours all come from the day number. Turns with the stars.
vec3 Nebulae(vec3 dir, vec3 sunDir) {
    #if defined WORLD_OVERWORLD
    if (NEBULAE <= 0.0) return vec3(0.0);
    float night = (1.0 - DayFactor(sunDir.y)) * (1.0 - rainStrength) * smoothstep(-0.05, 0.2, dir.y);
    if (night <= 0.0) return vec3(0.0);

    float seed = float(worldDay);
    vec3 axis = CelestialAxis();
    vec3 side = normalize(cross(axis, sunDir));
    vec3 c = vec3(dot(dir, sunDir), dot(dir, side), dot(dir, axis));

    // The band: a great circle tilted by a random angle each night.
    float tilt = Hash13(vec3(seed, 1.7, 4.2)) * TAU;
    vec3 bandNormal = normalize(vec3(cos(tilt) * 0.6, sin(tilt) * 0.6, 1.0));
    float band = exp(-pow(dot(c, bandNormal) * 3.2, 2.0));

    vec3 q = c * 3.0 + vec3(seed * 13.7, seed * 7.3, 0.0);
    float n = SkyNoise3D(q) * 0.5 + SkyNoise3D(q * 2.1 + 3.1) * 0.3 + SkyNoise3D(q * 4.3 + 7.7) * 0.2;
    float gas = smoothstep(0.38, 0.85, n) * band;
    float dust = smoothstep(0.55, 0.75, SkyNoise3D(q * 1.7 + 11.3)); // dark lanes
    float tone = SkyNoise3D(q * 0.8 + 19.1);

    vec3 colorA = mix(vec3(0.55, 0.25, 0.85), vec3(0.20, 0.45, 0.95), Hash13(vec3(seed, 3.3, 8.8)));
    vec3 colorB = mix(vec3(0.95, 0.35, 0.55), vec3(0.25, 0.85, 0.75), Hash13(vec3(seed, 9.1, 2.4)));
    vec3 color = mix(colorA, colorB, smoothstep(0.3, 0.7, tone));
    return color * gas * (1.0 - dust * 0.7) * night * NEBULAE * 0.012;
    #else
    return vec3(0.0);
    #endif
}

// ---- Aurora ----------------------------------------------------------------------------

// How strongly the aurora shows tonight (Aurora Condition).
float AuroraAmount(vec3 sunDir) {
    #if AURORA == 0 || !defined WORLD_OVERWORLD
        return 0.0;
    #else
        float night = 1.0 - DayFactor(sunDir.y + 0.1);
        float fullMoon = moonPhase == 0 ? 1.0 : 0.0;
        #if AURORA_CONDITION == 0
            float condition = 1.0;
        #elif AURORA_CONDITION == 1
            float condition = fullMoon;
        #elif AURORA_CONDITION == 2
            float condition = inSnowyBiome;
        #else
            float condition = max(fullMoon, inSnowyBiome);
        #endif
        return night * condition * (1.0 - rainStrength);
    #endif
}

// Glowing curtains high in the sky: the view ray crosses a stack of thin horizontal slices
// of the curtain layer; each slice adds light where the curtain pattern runs.
vec3 Aurora(vec3 dir, vec3 sunDir) {
    float amount = AuroraAmount(sunDir);
    if (amount <= 0.0 || dir.y <= 0.02) return vec3(0.0);
    float t = frameTimeCounter * 0.025;
    vec3 sum = vec3(0.0);
    const int slices = 14;
    for (int i = 0; i < slices; i++) {
        float h = float(i) / float(slices);
        float height = 1.0 + h * 0.9;                // the curtain's lower edge is at 1, top at 1.9
        vec2 p = dir.xz / dir.y * height * 0.9;       // where the ray crosses this slice
        #if AURORA == 1
            // Curtains: bright folded lines, green below and pink-purple at the top.
            vec2 w = p + vec2(SkyNoise3D(vec3(p * 0.6, t * 2.0)), SkyNoise3D(vec3(p * 0.6 + 5.0, t * 2.0))) * 1.2;
            float line = 1.0 - abs(SkyNoise3D(vec3(w * vec2(0.9, 2.4), t)) * 2.0 - 1.0);
            float curtain = pow(line, 10.0) * smoothstep(0.35, 0.6, SkyNoise3D(vec3(w * 0.35, t * 0.5)));
            vec3 color = mix(vec3(0.15, 1.00, 0.45), vec3(0.75, 0.25, 0.90), smoothstep(0.35, 1.0, h));
        #else
            // Bands: wide, soft arcs shifting through teal, blue and violet.
            float arc = sin(p.y * 2.2 + SkyNoise3D(vec3(p * 0.5, t)) * 4.0 + t * 3.0) * 0.5 + 0.5;
            float curtain = pow(arc, 6.0) * smoothstep(0.3, 0.7, SkyNoise3D(vec3(p * 0.3, t * 0.4)));
            vec3 color = mix(vec3(0.10, 0.90, 0.80), vec3(0.45, 0.35, 1.00), SkyNoise3D(vec3(p * 0.2, 3.0)));
            color = mix(color, vec3(0.85, 0.30, 0.80), h * 0.6);
        #endif
        sum += color * curtain * (1.0 - h) * (1.0 - h);
    }
    float horizonFade = smoothstep(0.02, 0.25, dir.y);
    return sum / float(slices) * amount * horizonFade * 0.35;
}

// ---- Rainbows --------------------------------------------------------------------------

// A rainbow around the point opposite the sun (42 degrees out), after rain (while the
// ground is still wet but the rain has stopped) or always, when the sun is low enough.
vec3 Rainbow(vec3 dir, vec3 sunDir) {
    #if RAINBOWS == 0 || !defined WORLD_OVERWORLD
        return vec3(0.0);
    #else
        #if RAINBOWS == 1
            float amount = saturate((wetness - rainStrength) * 3.0);
        #else
            float amount = 0.5 + 0.5 * saturate((wetness - rainStrength) * 3.0);
        #endif
        amount *= DayFactor(sunDir.y) * (1.0 - smoothstep(0.35, 0.7, sunDir.y)) * smoothstep(-0.05, 0.05, dir.y);
        if (amount <= 0.0) return vec3(0.0);
        float angle = degrees(acos(clamp(dot(dir, -sunDir), -1.0, 1.0)));
        float x = (angle - 40.6) / 2.0; // 0 violet ... 1 red
        if (x < -0.2 || x > 1.2) return vec3(0.0);
        vec3 spectrum = saturate(vec3(
            1.0 - abs(x - 0.95) * 3.0,
            1.0 - abs(x - 0.55) * 3.0,
            1.0 - abs(x - 0.15) * 3.0)) + vec3(0.35, 0.0, 0.45) * smoothstep(0.2, -0.2, x);
        float edge = smoothstep(-0.2, 0.05, x) * smoothstep(1.2, 0.95, x);
        return spectrum * edge * amount * SunLightColor(sunDir.y) * 0.06;
    #endif
}

// ---- The End ---------------------------------------------------------------------------

// Pale violet beams rising from the void all around the horizon, slowly pulsing (E1).
vec3 EndBeams(vec3 dir) {
    #ifdef END_BEAMS
    #ifdef WORLD_END
        float angle = atan(dir.z, dir.x);
        float t = frameTimeCounter * 0.08;
        float beams = 0.0;
        for (int i = 0; i < 3; i++) {
            float k = 9.0 + float(i) * 7.0;
            float n = SkyNoise3D(vec3(angle * k / TAU * 4.0, float(i) * 11.0, t * (1.0 + float(i) * 0.4)));
            beams += pow(smoothstep(0.55, 1.0, n), 3.0) * (1.0 - float(i) * 0.25);
        }
        float rise = exp(-max(dir.y + 0.15, 0.0) * 2.6) * smoothstep(-0.6, -0.1, dir.y);
        return vec3(0.55, 0.35, 0.95) * beams * rise * 0.22 * END_BEAM_INTENSITY;
    #endif
    #endif
    return vec3(0.0);
}

// Direction (world space) and strength of the End's sky flash (E3, MC 1.21.9+).
vec3 EndFlashDir() { return normalize(mat3(gbufferModelViewInverse) * endFlashPosition); }
float EndFlash() {
    #ifdef END_FLASHES
    #ifdef WORLD_END
        return dot(endFlashPosition, endFlashPosition) > 0.0 ? endFlashIntensity : 0.0;
    #endif
    #endif
    return 0.0;
}
vec3 EndFlashSky(vec3 dir) {
    float flash = EndFlash();
    if (flash <= 0.0) return vec3(0.0);
    float d = max(dot(dir, EndFlashDir()), 0.0);
    return vec3(0.75, 0.55, 1.00) * flash * (pow(d, 40.0) * 3.0 + pow(d, 4.0) * 0.4 + 0.05);
}
