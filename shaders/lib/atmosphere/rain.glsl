// Rain drawn by the pack (Realistic Rain, plan item R4): thin, soft streaks falling on a
// few cylinders around the camera, from an arm's length out to about 30 blocks. Drawn in
// composite, after the translucent pass, so unlike the vanilla rain texture it shows behind
// glass (it is hidden only by opaque blocks), and kept out from under roofs and out of
// water using the column maps. The streaks fall in world space, so jumping or flying
// doesn't drag them along.
// Needs: common.glsl, sky.glsl, columnMaps.glsl (reader).

const int RAIN_LAYERS = 6;

// Is this point under a roof (any block underside above it in its column)?
bool UnderRoof(vec3 worldPos) {
    int bit = ColumnBit(worldPos.y);
    if (bit < 0 || !InColumnRange(worldPos.xz)) return false;
    return FirstColumnBit(ceilingSampler, worldPos.xz, bit + 1, false) < COLUMN_MAP_LEVELS;
}

// Rain in front of a scene point: light to add and how much of the scene it covers.
// dir: view direction (player space); sceneDist: distance to the first opaque surface.
vec4 RainStreaks(vec3 dir, float sceneDist, vec3 sunDir) {
    float amount = VisibleRain() * (1.0 - inSnowyBiome) * (1.0 - inSandyBiome);
    if (amount <= 0.001 || isEyeInWater != 0) return vec4(0.0);
    float horizontal = length(dir.xz);
    if (horizontal < 0.08) return vec4(0.0); // looking straight up or down

    float t0 = frameTimeCounter;
    vec2 wind = vec2(0.30, 0.10) * mix(1.0, 1.6, thunderStrength);
    float pixelAngle = PixelAngle();
    float coverage = 0.0;
    for (int k = 0; k < RAIN_LAYERS; k++) {
        float radius = 1.3 * pow(1.75, float(k));
        float t = radius / horizontal;
        if (t > sceneDist) break; // this layer and all further ones are behind the scene
        vec3 p = dir * t; // from the eye
        vec3 world = p + cameraPosition + gbufferModelViewInverse[3].xyz;
        if (UnderRoof(world) || ColumnHas(waterCellsSampler, world)) continue;

        // Position on the cylinder: arc length around it (whole number of columns, so the
        // pattern meets itself seamlessly) and height, leaning with the wind.
        float columns = max(floor(TAU * radius / (0.16 + 0.05 * float(k))), 8.0);
        float spacing = TAU * radius / columns;
        float angle = atan(p.z, p.x);
        float lean = dot(wind, vec2(-sin(angle), cos(angle)));
        float u = angle * radius + world.y * lean;
        float column = floor(u / spacing);
        float seed = Hash13(vec3(column, float(k) * 7.31, 3.7));
        if (seed > 0.35 + 0.45 * amount) continue; // fewer drops in light rain

        float across = (fract(u / spacing) - 0.5 - (Hash13(vec3(column, float(k), 9.1)) - 0.5) * 0.6) * spacing;
        // Falling drops: each column holds drops spaced a few blocks apart, falling at 10-14
        // blocks per second, each a streak about half a block long (motion blur).
        float speed = 10.0 + 4.0 * Hash13(vec3(column, float(k), 1.3));
        float period = 2.5 + 2.0 * Hash13(vec3(column, float(k), 5.9));
        float phase = fract((world.y + t0 * speed) / period + seed * 7.0);
        float len = 0.55 / period;
        if (phase > len) continue;
        float along = phase / len; // 0 head ... 1 tail
        float streak = smoothstep(0.0, 0.12, along) * (1.0 - along);

        // Thin and soft, never thinner than a pixel (thin far streaks fade rather than
        // shimmer).
        float footprint = pixelAngle * t;
        float width = max(0.006, footprint * 0.75);
        float line = exp(-across * across / (width * width)) * (0.006 / width);
        coverage += line * streak * (1.0 - coverage);
    }
    coverage *= 0.45;
    vec3 light = SkyAmbientColor(sunDir.y) * 1.3 + SunLightColor(sunDir.y) * 0.25 + LightningFlashColor() * 2.0;
    return vec4(light, saturate(coverage));
}
