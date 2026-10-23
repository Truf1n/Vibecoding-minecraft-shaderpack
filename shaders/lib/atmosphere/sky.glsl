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

void OverworldSkyColors(float sunUp, out vec3 zenith, out vec3 horizon) {
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

    // Rain: grey, darker, flatter.
    float grey = Luminance(zenith) * 0.55 + Luminance(horizon) * 0.45;
    zenith = mix(zenith, vec3(grey) * 0.55, rainStrength * 0.85);
    horizon = mix(horizon, vec3(grey) * 0.65, rainStrength * 0.85);
}

// Light reaching shaded surfaces from the whole sky (no sun disc).
vec3 SkyAmbientColor(float sunUp) {
    vec3 zenith, horizon;
    OverworldSkyColors(sunUp, zenith, horizon);
    return mix(horizon, zenith, 0.55);
}

vec3 SunLightColor(float sunUp) {
    float day = DayFactor(sunUp);
    float sunset = SunsetFactor(sunUp);
    vec3 sun = mix(vec3(1.00, 0.93, 0.82) * 1.6, vec3(1.00, 0.48, 0.18) * 1.1, sunset);
    vec3 moon = vec3(0.30, 0.40, 0.62) * 0.07;
    return mix(moon, sun, day) * (1.0 - 0.8 * rainStrength);
}

// Point stars on a sphere that turns with the sun path.
vec3 Stars(vec3 dir, vec3 sunDir, float density, float brightness) {
    float tilt = radians(sunPathRotation);
    vec3 axis = vec3(0.0, -sin(tilt), cos(tilt));
    vec3 side = normalize(cross(axis, sunDir));
    vec3 c = vec3(dot(dir, sunDir), dot(dir, side), dot(dir, axis)) * 260.0;

    vec3 cell = floor(c);
    float h = Hash13(cell);
    if (h < 1.0 - density) return vec3(0.0);
    float shape = smoothstep(0.42, 0.05, length(fract(c) - 0.5));
    float twinkle = 0.75 + 0.25 * sin(frameTimeCounter * (2.0 + 4.0 * h) + h * 50.0);
    vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.85, 0.7), fract(h * 37.0));
    return tint * shape * twinkle * brightness;
}

vec3 OverworldSky(vec3 dir, vec3 sunDir, bool withStars) {
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

    if (withStars) {
        float starVis = (1.0 - day) * clearSky * smoothstep(-0.05, 0.15, up);
        if (starVis > 0.0) sky += Stars(dir, sunDir, 0.006, 0.6) * starVis;
    }
    return sky;
}

vec3 EndSky(vec3 dir) {
    float horizon = pow(1.0 - abs(dir.y), 4.0);
    vec3 sky = mix(vec3(0.010, 0.006, 0.020), vec3(0.075, 0.040, 0.110), horizon);
    sky += Stars(dir, vec3(1.0, 0.0, 0.0), 0.010, 0.9) * vec3(0.9, 0.8, 1.0);
    return sky;
}

vec3 NetherSky() { return SrgbToLinear(fogColor) * 0.6; }

// Sky in a given direction for the current dimension.
vec3 GetSky(vec3 dir, vec3 sunDir, bool withStars) {
    #if defined WORLD_NETHER
        return NetherSky();
    #elif defined WORLD_END
        return EndSky(dir);
    #else
        return OverworldSky(dir, sunDir, withStars);
    #endif
}
