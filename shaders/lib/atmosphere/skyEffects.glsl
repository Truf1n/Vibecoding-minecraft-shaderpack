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
// of the curtain layer; each slice adds light where the curtain pattern runs. The slices
// start at a random offset per pixel and frame (TAA blends them into one smooth glow), and
// the pattern shifts and changes with height, so the curtains bend and fray instead of
// looking extruded straight up.
vec3 Aurora(vec3 dir, vec3 sunDir) {
    float amount = AuroraAmount(sunDir);
    if (amount <= 0.0 || dir.y <= 0.02) return vec3(0.0);
    float t = frameTimeCounter * 0.025;
    const int slices = 20;
    float jitter = Hash13(vec3(dir.xz * 4000.0, float(frameCounter % 64)));
    vec3 sum = vec3(0.0);
    for (int i = 0; i < slices; i++) {
        float h = (float(i) + jitter) / float(slices);
        float height = 1.0 + h * 1.1;                  // lower edge at 1, top at 2.1
        vec2 p = dir.xz / dir.y * height * 0.9;         // where the ray crosses this slice
        p += vec2(0.35, -0.2) * h;                      // curtains lean and drift with height
        // Colour: shades from blue-green through green to yellow-green, with pink notes in
        // places (mostly near the top, sometimes along the lower edge).
        float shade = SkyNoise3D(vec3(p * 0.18, t * 0.7 + 4.0));
        vec3 green = mix(vec3(0.05, 0.95, 0.55), vec3(0.30, 1.00, 0.20), smoothstep(0.25, 0.75, shade));
        green = mix(green, vec3(0.10, 0.75, 0.70), smoothstep(0.65, 0.9, SkyNoise3D(vec3(p * 0.3 + 13.0, t))));
        float pinkPatch = smoothstep(0.55, 0.85, SkyNoise3D(vec3(p * 0.22 + 31.0, t * 0.6)));
        float pink = saturate(smoothstep(0.35, 1.0, h) * (0.5 + pinkPatch) + pinkPatch * 0.35 * (1.0 - h));
        #if AURORA == 1
            // Curtains: bright folded lines.
            vec2 w = p + vec2(SkyNoise3D(vec3(p * 0.6, t * 2.0 + h * 0.6)), SkyNoise3D(vec3(p * 0.6 + 5.0, t * 2.0 + h * 0.6))) * 1.2;
            float line = 1.0 - abs(SkyNoise3D(vec3(w * vec2(0.9, 2.4), t + h * 0.45)) * 2.0 - 1.0);
            float curtain = pow(line, 8.0) * smoothstep(0.3, 0.6, SkyNoise3D(vec3(w * 0.35, t * 0.5 + h * 0.3)));
            vec3 color = mix(green, vec3(0.85, 0.25, 0.75), pink);
        #else
            // Bands: wide, soft arcs.
            float arc = sin(p.y * 2.2 + SkyNoise3D(vec3(p * 0.5, t + h * 0.4)) * 4.0 + t * 3.0) * 0.5 + 0.5;
            float curtain = pow(arc, 5.0) * smoothstep(0.3, 0.7, SkyNoise3D(vec3(p * 0.3, t * 0.4 + h * 0.3)));
            vec3 color = mix(mix(green, vec3(0.45, 0.35, 1.00), 0.35), vec3(0.85, 0.30, 0.80), pink * 0.8);
        #endif
        // Brightest just above the lower edge, fading out smoothly towards the top.
        float profile = smoothstep(0.0, 0.08, h) * pow(1.0 - h, 1.6);
        sum += color * curtain * profile;
    }
    float horizonFade = smoothstep(0.02, 0.25, dir.y);
    return sum / float(slices) * amount * horizonFade * 0.45;
}

// ---- Rainbows --------------------------------------------------------------------------

// A rainbow around the point opposite the sun (42 degrees out), for a couple of minutes
// after rain or always, when the sun is low enough (below about 40 degrees) for the bow
// to rise above the horizon.
vec3 Rainbow(vec3 dir, vec3 sunDir) {
    #if RAINBOWS == 0 || !defined WORLD_OVERWORLD
        return vec3(0.0);
    #else
        #if RAINBOWS == 1
            float amount = saturate((afterRain - rainStrength) * 2.5);
        #else
            float amount = 0.5 + 0.5 * saturate((afterRain - rainStrength) * 2.5);
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
        // Brightest against the darker sky low down, fading towards its top.
        float height = 1.0 - smoothstep(0.2, 0.7, dir.y) * 0.5;
        return spectrum * edge * amount * height * SunLightColor(sunDir.y) * 0.16;
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
