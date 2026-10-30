// Artistic (non-physical) sky shared by the sky pass, fog, water reflections and the
// ambient light term, so all of them agree. Directions are world space (y up).
// Needs: common.glsl, and sunPathRotation (lib/gbuffer/layout.glsl) for the star frame.

float Hash13(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

// 0 at night, 1 by day, with a short twilight.
float DayFactor(float sunUp) { return smoothstep(-0.10, 0.20, sunUp); }
// Peaks while the sun is near the horizon.
float SunsetFactor(float sunUp) { return smoothstep(-0.18, 0.0, sunUp) * (1.0 - smoothstep(0.0, 0.35, sunUp)); }

#include "/lib/atmosphere/colorMultipliers.glsl"
#include "/lib/atmosphere/weather.glsl"

// The sky colours, the sky's light and the sun's light are the same for every pixel in a
// frame: the begin pass works them out once (these *Model functions) and stores them in
// the world state; everything else reads them from there.
void OverworldSkyColorsModel(float sunUp, out vec3 zenith, out vec3 horizon) {
    float day = DayFactor(sunUp);
    float sunset = SunsetFactor(sunUp);

    vec3 dayZenith = vec3(0.075, 0.24, 0.85);
    vec3 dayHorizon = vec3(0.42, 0.62, 0.90);
    vec3 nightZenith = vec3(0.0035, 0.0055, 0.014);
    vec3 nightHorizon = vec3(0.010, 0.015, 0.028);

    zenith = mix(nightZenith, dayZenith, day);
    horizon = mix(nightHorizon, dayHorizon, day);
    zenith = mix(zenith, vec3(0.10, 0.09, 0.24), sunset * 0.6);
    horizon = mix(horizon, vec3(0.80, 0.42, 0.20), sunset * 0.5);

    // Rain: grey, darker, flatter; warmer and lighter or colder and heavier (Rain Style).
    float grey = Luminance(zenith) * 0.55 + Luminance(horizon) * 0.45;
    #if RAIN_STYLE == 1
        vec3 rainGrey = vec3(grey) * vec3(0.86, 0.95, 1.10) * 0.8;
    #else
        vec3 rainGrey = vec3(grey) * vec3(1.04, 1.00, 0.94);
    #endif
    // (Follows the slowly smoothed rain, like the clouds turning overcast.)
    zenith = mix(zenith, rainGrey * 0.55, stormRain * 0.85);
    horizon = mix(horizon, rainGrey * 0.65, stormRain * 0.85);
    // Thunderstorms: darker still.
    zenith *= StormDim();
    horizon *= StormDim();
}

// Light reaching shaded surfaces from the whole sky (no sun disc).
vec3 SkyAmbientColorModel(float sunUp) {
    vec3 zenith, horizon;
    OverworldSkyColorsModel(sunUp, zenith, horizon);
    return mix(horizon, zenith, 0.55) * LightMultiplier(sunUp);
}

// 1 at full moon, 0 at new moon.
float MoonFullness() { return abs(float(moonPhase) - 4.0) / 4.0; }

vec3 SunLightColorModel(float sunUp) {
    float day = DayFactor(sunUp);
    float sunset = SunsetFactor(sunUp);
    vec3 sun = mix(vec3(1.00, 0.93, 0.82) * 1.6, vec3(1.00, 0.48, 0.18) * 1.1, sunset);
    vec3 moon = vec3(0.30, 0.40, 0.62) * 0.07;
    #ifdef MOON_PHASE_LIGHTING
        moon *= 0.35 + 0.65 * MoonFullness();
    #endif
    return mix(moon, sun, day) * (1.0 - 0.8 * stormRain) * StormDim() * LightMultiplier(sunUp);
}

// The frame's values (sunUp is the frame's sun elevation everywhere they are used).
void OverworldSkyColors(float sunUp, out vec3 zenith, out vec3 horizon) {
    zenith = wsSkyZenith.rgb;
    horizon = wsSkyHorizon.rgb;
}
vec3 SkyAmbientColor(float sunUp) { return wsSkyAmbient.rgb; }
vec3 SunLightColor(float sunUp) { return wsSun.rgb; }

float ValueNoise2(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    float a = Hash13(vec3(i, 0.0)), b = Hash13(vec3(i + vec2(1, 0), 0.0));
    float c = Hash13(vec3(i + vec2(0, 1), 0.0)), d = Hash13(vec3(i + vec2(1, 1), 0.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Axis the sun and moon turn around (the sun path is tilted by sunPathRotation).
vec3 CelestialAxis() {
    float tilt = radians(sunPathRotation);
    return vec3(0.0, -sin(tilt), cos(tilt));
}

// Point stars on a sphere that turns with the sun path. `footprint` is the angular size
// (radians) one pixel covers in this direction: when it is larger than a star (distant
// pixels, or reflections on wavy water), the star is spread over it and dimmed so its
// total light stays the same. That prefiltering is what keeps stars from flickering.
vec3 Stars(vec3 dir, vec3 sunDir, float density, float brightness, float footprint) {
    if (density <= 0.0) return vec3(0.0);
    const float cellsPerRadian = 260.0;
    vec3 axis = CelestialAxis();
    vec3 side = normalize(cross(axis, sunDir));
    vec3 c = vec3(dot(dir, sunDir), dot(dir, side), dot(dir, axis)) * cellsPerRadian;

    vec3 cell = floor(c);
    float h = Hash13(cell);
    if (h < 1.0 - density) return vec3(0.0);

    // Soft Gaussian star, never narrower than ~1.5 pixels: a star smaller than a pixel
    // shimmers as the sky turns and it crosses pixel centres. Wider than its true size
    // means dimmer (same total light). (No fading out at large pixel sizes: at 4K that
    // limit sat just past the normal field of view, and sprinting or flying, which widens
    // it, made every star vanish.) The drawn width stays inside the star's cell.
    const float starRadius = 0.16; // in cells
    float wanted = max(starRadius, footprint * cellsPerRadian * 1.5);
    float spread = min(wanted, 0.38);
    float energy = (starRadius * starRadius) / (wanted * wanted);
    vec3 d = fract(c) - 0.5;
    float shape = exp(-2.0 * dot(d, d) / (spread * spread));
    vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), fract(h * 37.0));
    return tint * shape * energy * brightness * (0.6 + 0.8 * fract(h * 113.0)) * 4.0;
}

float StarDensity() {
    #if STAR_AMOUNT == 0
        return 0.0;
    #elif STAR_AMOUNT == 1
        return 0.003;
    #elif STAR_AMOUNT == 2
        return 0.006;
    #elif STAR_AMOUNT == 3
        return 0.010;
    #else
        return 0.016;
    #endif
}

// Unbound-style sun: a bright disc (the tonemapper turns it white with a warm rim).
vec3 SunDisc(vec3 dir, vec3 sunDir) {
    const float radius = 0.030; // radians
    float d = acos(clamp(dot(dir, sunDir), -1.0, 1.0));
    float disc = smoothstep(radius, radius * 0.85, d);
    return SunLightColor(sunDir.y) * disc * 30.0;
}

// Moon disc with real phases (moonPhase) and darker "seas".
vec3 MoonDisc(vec3 dir, vec3 moonDir) {
    const float radius = 0.034;
    float cosD = dot(dir, moonDir);
    if (cosD < cos(radius * 1.2)) return vec3(0.0);

    vec3 u = normalize(cross(moonDir, CelestialAxis()));
    vec3 v = cross(u, moonDir);
    vec2 p = vec2(dot(dir, u), dot(dir, v)) / radius; // disc coordinates, unit radius
    float r2 = dot(p, p);
    if (r2 > 1.0) return vec3(0.0);
    vec3 n = vec3(p, sqrt(1.0 - r2));

    float phaseAngle = float(moonPhase) / 8.0 * TAU;
    vec3 L = vec3(sin(phaseAngle), 0.0, cos(phaseAngle));
    float lit = smoothstep(-0.03, 0.10, dot(n, L));

    float seas = ValueNoise2(p * 2.2 + 3.0) * 0.6 + ValueNoise2(p * 5.0 + 11.0) * 0.4;
    float albedo = mix(0.55, 1.0, smoothstep(0.35, 0.65, seas));
    float edge = smoothstep(1.0, 0.92, r2);
    return vec3(0.75, 0.82, 0.95) * albedo * (lit * 1.6 + 0.02) * edge;
}

#include "/lib/atmosphere/skyEffects.glsl"

// starFootprint < 0: no stars or sun/moon discs (used for fog). The discs are also left out
// of reflections, where the specular glint stands in for them. effects: nebulae, aurora
// and rainbows.
vec3 OverworldSky(vec3 dir, vec3 sunDir, float starFootprint, bool discs, bool effects) {
    float sunUp = sunDir.y;
    vec3 zenith, horizon;
    OverworldSkyColors(sunUp, zenith, horizon);

    float up = dir.y;
    vec3 sky = mix(horizon, zenith, pow(saturate(up), 0.45));

    float VdotS = dot(dir, sunDir);
    float day = DayFactor(sunUp);
    float clearSky = 1.0 - rainStrength;

    // Sunset/sunrise glow, strongest near the horizon on the sun's side.
    float sunset = SunsetFactor(sunUp);
    float horizonBand = exp(-abs(up) * 5.0);
    float sunSide = pow(saturate(VdotS * 0.5 + 0.5), 3.0);
    sky += vec3(1.00, 0.40, 0.12) * sunset * horizonBand * sunSide * 1.4 * clearSky;

    // Forward-scattering halo around the sun (and a faint one around the moon).
    sky += SunLightColor(sunUp) * pow(saturate(VdotS), 12.0) * 0.35 * day * clearSky;
    sky += vec3(0.10, 0.13, 0.20) * pow(saturate(-VdotS), 20.0) * 0.15 * (1.0 - day) * clearSky;

    // Below the horizon: fade towards a darker ground colour.
    sky = mix(sky, horizon * 0.35, smoothstep(0.0, -0.25, up));
    sky *= AtmosphereMultiplier(sunUp);
    // Snowstorms and sandstorms: the sky disappears into the storm (so does everything that
    // takes its colour from the sky: the haze, reflections).
    float storm = StormAmount();
    if (storm > 0.0) sky = mix(sky, StormColor(sunUp), smoothstep(0.0, 0.6, storm));
    // Lightning lights up the whole sky for a moment.
    sky += LightningFlashColor() * 0.35;

    if (effects) sky += Nebulae(dir, sunDir) + Aurora(dir, sunDir) + Rainbow(dir, sunDir);

    // Stars and the sun/moon discs (left out of reflections, where they would sparkle).
    if (starFootprint >= 0.0) {
        float starVis = (1.0 - day) * clearSky * smoothstep(-0.05, 0.15, up);
        if (starVis > 0.0) sky += Stars(dir, sunDir, StarDensity(), 0.6, starFootprint) * starVis;

        #if SUN_MOON_STYLE == 1
            float discVis = discs ? 1.0 : 0.0;
            #ifdef SUN_MOON_HORIZON
                discVis *= smoothstep(-0.01, 0.01, up);
            #endif
            #ifndef SUN_MOON_DURING_RAIN
                discVis *= clearSky;
            #endif
            if (discVis > 0.0) {
                sky += SunDisc(dir, sunDir) * discVis;
                sky += MoonDisc(dir, -sunDir) * discVis;
            }
        #endif
    }
    return sky;
}

vec3 EndSky(vec3 dir, float starFootprint) {
    float horizon = pow(1.0 - abs(dir.y), 4.0);
    vec3 sky = mix(vec3(0.010, 0.006, 0.020), vec3(0.075, 0.040, 0.110), horizon);
    sky *= AtmosphereMultiplier(0.0);
    if (starFootprint >= 0.0) {
        sky += Stars(dir, vec3(1.0, 0.0, 0.0), 0.010, 0.9 * END_STAR_INTENSITY, starFootprint) * vec3(0.9, 0.8, 1.0);
        sky += EndBeams(dir);
    }
    sky += EndFlashSky(dir);
    return sky;
}

// Nether fog/sky colour per biome (weights are smoothed custom uniforms), so it does not
// depend on vanilla's fog colour. Unknown (modded) biomes fall back to Nether Wastes.
vec3 NetherSky() {
    vec3 c = vec3(0.110, 0.028, 0.012) * inNetherWastes
           + vec3(0.130, 0.018, 0.012) * inCrimsonForest
           + vec3(0.020, 0.050, 0.055) * inWarpedForest
           + vec3(0.060, 0.052, 0.058) * inBasaltDeltas
           + vec3(0.022, 0.048, 0.058) * inSoulValley;
    float w = inNetherWastes + inCrimsonForest + inWarpedForest + inBasaltDeltas + inSoulValley;
    return (w > 0.01 ? c / w : vec3(0.110, 0.028, 0.012)) * AtmosphereMultiplier(0.0);
}

// Angular size of one screen pixel (radians), for star prefiltering.
float PixelAngle() { return 2.0 / (gbufferProjection[1][1] * viewHeight); }

// Sky in a given direction for the current dimension. starFootprint: angular pixel size
// for stars and the sun/moon discs, or a negative value to leave them out.
vec3 GetSky(vec3 dir, vec3 sunDir, float starFootprint) {
    #if defined WORLD_NETHER
        return NetherSky();
    #elif defined WORLD_END
        return EndSky(dir, starFootprint);
    #else
        return OverworldSky(dir, sunDir, starFootprint, true, starFootprint >= 0.0);
    #endif
}

// Sky as seen in a reflection: prefiltered stars, but no sun/moon discs.
vec3 GetSkyReflection(vec3 dir, vec3 sunDir, float starFootprint) {
    #if defined WORLD_NETHER
        return NetherSky();
    #elif defined WORLD_END
        return EndSky(dir, starFootprint);
    #else
        return OverworldSky(dir, sunDir, starFootprint, false, SKY_EFFECT_REFLECTIONS >= 1);
    #endif
}

// Sky as seen in a reflection on blocks (puddles, polished blocks, ice): sky effects only
// with Sky Effects in Reflections set to water and blocks.
vec3 GetBlockSkyReflection(vec3 dir, vec3 sunDir, float starFootprint) {
    #if defined WORLD_NETHER
        return NetherSky();
    #elif defined WORLD_END
        return EndSky(dir, starFootprint);
    #else
        return OverworldSky(dir, sunDir, starFootprint, false, SKY_EFFECT_REFLECTIONS == 2);
    #endif
}

// Sky seen from under water, through the surface or a gap in it: the sun, moon and stars
// show, but dimmed, as they would through the water and its ripples.
vec3 GetSkyFromUnderwater(vec3 dir, vec3 sunDir) {
    vec3 plain = GetSky(dir, sunDir, -1.0);
    return plain + (GetSky(dir, sunDir, PixelAngle()) - plain) * 0.35;
}
