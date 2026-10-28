#ifndef WATER_STYLES_GLSL
#define WATER_STYLES_GLSL

// Per-biome water looks: the colour of the water body, how fast it swallows light (how
// clear it is) and the fog seen from inside it.
//
// The water surface picks its look from its own biome colour (the vertex tint Minecraft
// gives it: swamps, mangroves, warm/lukewarm/cold/frozen oceans, meadows, cherry groves
// and pale gardens each have their own), blending smoothly where biomes meet. Biomes whose
// water has the plain default colour (deserts, badlands, jungles, mushroom fields, snowy
// lands) are told apart by the biome the camera is in. The view from under water uses the
// camera's biome throughout.
// Needs: common.glsl (custom uniforms in shaders.properties).

struct WaterStyle {
    vec3 scatter;    // colour of light scattered inside the water (lit by the scene)
    vec3 absorption; // light absorbed per block, per colour channel
    vec3 fogColor;   // underwater fog (before lighting)
    float fogDensity;
};

WaterStyle MakeWaterStyle(vec3 scatter, vec3 absorption, vec3 fogColor, float fogDensity) {
    WaterStyle s;
    s.scatter = scatter; s.absorption = absorption; s.fogColor = fogColor; s.fogDensity = fogDensity;
    return s;
}

void AddWaterStyle(inout WaterStyle sum, WaterStyle s, float w) {
    sum.scatter += s.scatter * w;
    sum.absorption += s.absorption * w;
    sum.fogColor += s.fogColor * w;
    sum.fogDensity += s.fogDensity * w;
}

// ---- The looks ------------------------------------------------------------------------
//                                         scatter                       absorption                  fog colour                  fog
WaterStyle StyleDefault()  { return MakeWaterStyle(vec3(0.005, 0.024, 0.055), vec3(0.30, 0.085, 0.060), vec3(0.010, 0.050, 0.070), 0.060); }
// Cold and frozen: rich deep blue, clearer.
WaterStyle StyleCold()     { return MakeWaterStyle(vec3(0.003, 0.020, 0.075), vec3(0.30, 0.060, 0.030), vec3(0.006, 0.034, 0.092), 0.040); }
// Swamp: murky olive green, short visibility.
WaterStyle StyleSwamp()    { return MakeWaterStyle(vec3(0.014, 0.020, 0.008), vec3(0.60, 0.36, 0.55), vec3(0.020, 0.028, 0.012), 0.140); }
// Mangrove: murky teal-green.
WaterStyle StyleMangrove() { return MakeWaterStyle(vec3(0.008, 0.022, 0.015), vec3(0.55, 0.28, 0.34), vec3(0.012, 0.032, 0.024), 0.120); }
// Warm ocean: bright tropical turquoise, very clear.
WaterStyle StyleWarm()     { return MakeWaterStyle(vec3(0.006, 0.055, 0.060), vec3(0.30, 0.040, 0.050), vec3(0.012, 0.075, 0.080), 0.035); }
// Lukewarm ocean: between tropical and temperate, a clear sea blue.
WaterStyle StyleLukewarm() { return MakeWaterStyle(vec3(0.005, 0.040, 0.066), vec3(0.30, 0.055, 0.048), vec3(0.010, 0.060, 0.085), 0.045); }
// Desert: pale and very clear.
WaterStyle StyleDesert()   { return MakeWaterStyle(vec3(0.022, 0.050, 0.056), vec3(0.20, 0.050, 0.045), vec3(0.030, 0.070, 0.075), 0.035); }
// Badlands: silty, with a warm clay tint.
WaterStyle StyleBadlands() { return MakeWaterStyle(vec3(0.030, 0.032, 0.026), vec3(0.30, 0.18, 0.16), vec3(0.040, 0.040, 0.032), 0.090); }
// Jungle: green-tinted and a little murky.
WaterStyle StyleJungle()   { return MakeWaterStyle(vec3(0.006, 0.034, 0.032), vec3(0.36, 0.12, 0.11), vec3(0.010, 0.050, 0.045), 0.075); }
// Meadow: deep, clear alpine blue.
WaterStyle StyleMeadow()   { return MakeWaterStyle(vec3(0.003, 0.024, 0.078), vec3(0.28, 0.055, 0.028), vec3(0.006, 0.040, 0.095), 0.035); }
// Cherry grove: soft light blue, clear.
WaterStyle StyleCherry()   { return MakeWaterStyle(vec3(0.012, 0.046, 0.072), vec3(0.24, 0.055, 0.042), vec3(0.020, 0.065, 0.090), 0.040); }
// Pale garden: dull grey-blue, still and dim.
WaterStyle StylePale()     { return MakeWaterStyle(vec3(0.011, 0.016, 0.020), vec3(0.42, 0.30, 0.26), vec3(0.016, 0.020, 0.024), 0.100); }
// Mushroom fields: a faint violet murk.
WaterStyle StyleMushroom() { return MakeWaterStyle(vec3(0.014, 0.020, 0.040), vec3(0.32, 0.16, 0.08), vec3(0.020, 0.028, 0.055), 0.070); }

// ---- Choosing ---------------------------------------------------------------------------

// The look for default-coloured water, from the biome the camera is in.
WaterStyle CameraDefaultWaterStyle() {
    #ifdef BIOME_WATER
        float others = watDesert + watBadlands + watJungle + watMushroom + inSnowyBiome;
        WaterStyle s = MakeWaterStyle(vec3(0.0), vec3(0.0), vec3(0.0), 0.0);
        AddWaterStyle(s, StyleDefault(), max(1.0 - others, 0.0));
        AddWaterStyle(s, StyleDesert(), watDesert);
        AddWaterStyle(s, StyleBadlands(), watBadlands);
        AddWaterStyle(s, StyleJungle(), watJungle);
        AddWaterStyle(s, StyleMushroom(), watMushroom);
        AddWaterStyle(s, StyleCold(), inSnowyBiome);
        float total = max(others, 1.0);
        s.scatter /= total; s.absorption /= total; s.fogColor /= total; s.fogDensity /= total;
        return s;
    #else
        return StyleDefault();
    #endif
}

// The look of the water the camera is in (underwater fog, caustics, light shafts), blended
// from the biome weights. Worked out once per frame by the begin pass (P4); everything else
// reads the result from the world state (CameraWaterStyle below).
WaterStyle CameraWaterStyleModel() {
    #ifdef BIOME_WATER
        float tinted = watSwamp + watMangrove + watWarm + watLukewarm + watCold + watMeadow + watCherry + watPale;
        WaterStyle s = MakeWaterStyle(vec3(0.0), vec3(0.0), vec3(0.0), 0.0);
        AddWaterStyle(s, CameraDefaultWaterStyle(), max(1.0 - tinted, 0.0));
        AddWaterStyle(s, StyleSwamp(), watSwamp);
        AddWaterStyle(s, StyleMangrove(), watMangrove);
        AddWaterStyle(s, StyleWarm(), watWarm);
        AddWaterStyle(s, StyleLukewarm(), watLukewarm);
        AddWaterStyle(s, StyleCold(), watCold);
        AddWaterStyle(s, StyleMeadow(), watMeadow);
        AddWaterStyle(s, StyleCherry(), watCherry);
        AddWaterStyle(s, StylePale(), watPale);
        float total = max(tinted, 1.0);
        s.scatter /= total; s.absorption /= total; s.fogColor /= total; s.fogDensity /= total;
        return s;
    #else
        return StyleDefault();
    #endif
}

WaterStyle CameraWaterStyle() {
    #ifdef WORLD_STATE_WRITER
        return CameraWaterStyleModel();
    #else
        return MakeWaterStyle(wsWaterScatter.rgb, wsWaterAbsorb.rgb, wsWaterFog.rgb, wsWaterScatter.a);
    #endif
}

// The look of a water surface from its biome tint (vertex colour, sRGB).
WaterStyle SurfaceWaterStyle(vec3 tint) {
    #ifdef BIOME_WATER
        // Vanilla water colours of the biomes with their own look; each match weighs in by
        // how close the tint is, so biome borders (where Minecraft blends the tints) blend.
        const vec3 refs[9] = vec3[9](
            vec3(0.247, 0.463, 0.894),  // default
            vec3(0.380, 0.482, 0.392),  // swamp
            vec3(0.227, 0.478, 0.416),  // mangrove swamp
            vec3(0.263, 0.835, 0.933),  // warm ocean
            vec3(0.271, 0.678, 0.949),  // lukewarm ocean
            vec3(0.239, 0.341, 0.839),  // cold ocean, snowy taiga and beach
            vec3(0.224, 0.220, 0.788),  // frozen ocean and river
            vec3(0.055, 0.306, 0.812),  // meadow
            vec3(0.365, 0.718, 0.937)); // cherry grove
        WaterStyle s = MakeWaterStyle(vec3(0.0), vec3(0.0), vec3(0.0), 0.0);
        float total = 0.0;
        for (int i = 0; i < 10; i++) {
            vec3 ref = i < 9 ? refs[i] : vec3(0.463, 0.533, 0.616); // pale garden
            vec3 d = tint - ref;
            float w = exp(-dot(d, d) / (0.06 * 0.06));
            if (w < 1e-3) continue;
            WaterStyle style;
            if (i == 0) style = CameraDefaultWaterStyle();
            else if (i == 1) style = StyleSwamp();
            else if (i == 2) style = StyleMangrove();
            else if (i == 3) style = StyleWarm();
            else if (i == 4) style = StyleLukewarm();
            else if (i == 5 || i == 6) style = StyleCold();
            else if (i == 7) style = StyleMeadow();
            else if (i == 8) style = StyleCherry();
            else style = StylePale();
            AddWaterStyle(s, style, w);
            total += w;
        }
        // Modded or unknown water colours: the default look.
        if (total < 0.05) { AddWaterStyle(s, CameraDefaultWaterStyle(), 0.05 - total); total = 0.05; }
        s.scatter /= total; s.absorption /= total; s.fogColor /= total; s.fogDensity /= total;
        return s;
    #else
        return StyleDefault();
    #endif
}

#endif
