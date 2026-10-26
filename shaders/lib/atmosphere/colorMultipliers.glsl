// Light and atmosphere colour multipliers (plan items H1, H2): one RGB + intensity per
// condition (sunrise/sunset, noon, night, rain, Nether, End) from the Colour menu, blended
// by the time of day and the weather.
// Needs: common.glsl, and DayFactor / SunsetFactor (sky.glsl, which includes this file).

vec3 BlendConditions(vec3 sunset, vec3 noon, vec3 night, vec3 rain, float sunUp) {
    vec3 c = mix(night, noon, DayFactor(sunUp));
    c = mix(c, sunset, SunsetFactor(sunUp));
    return mix(c, rain, rainStrength);
}

// Sun, moon and sky light on surfaces.
vec3 LightMultiplier(float sunUp) {
    #if defined WORLD_NETHER
        return vec3(LIGHT_NETHER_R, LIGHT_NETHER_G, LIGHT_NETHER_B) * LIGHT_NETHER_I;
    #elif defined WORLD_END
        return vec3(LIGHT_END_R, LIGHT_END_G, LIGHT_END_B) * LIGHT_END_I;
    #else
        vec3 sunset = vec3(LIGHT_SUNSET_R, LIGHT_SUNSET_G, LIGHT_SUNSET_B) * LIGHT_SUNSET_I;
        vec3 noon = vec3(LIGHT_NOON_R, LIGHT_NOON_G, LIGHT_NOON_B) * LIGHT_NOON_I;
        vec3 night = vec3(LIGHT_NIGHT_R, LIGHT_NIGHT_G, LIGHT_NIGHT_B) * LIGHT_NIGHT_I;
        vec3 rain = vec3(LIGHT_RAIN_R, LIGHT_RAIN_G, LIGHT_RAIN_B) * LIGHT_RAIN_I;
        return BlendConditions(sunset, noon, night, rain, sunUp);
    #endif
}

// Sky and fog.
vec3 AtmosphereMultiplier(float sunUp) {
    #if defined WORLD_NETHER
        return vec3(ATMO_NETHER_R, ATMO_NETHER_G, ATMO_NETHER_B) * ATMO_NETHER_I;
    #elif defined WORLD_END
        return vec3(ATMO_END_R, ATMO_END_G, ATMO_END_B) * ATMO_END_I;
    #else
        vec3 sunset = vec3(ATMO_SUNSET_R, ATMO_SUNSET_G, ATMO_SUNSET_B) * ATMO_SUNSET_I;
        vec3 noon = vec3(ATMO_NOON_R, ATMO_NOON_G, ATMO_NOON_B) * ATMO_NOON_I;
        vec3 night = vec3(ATMO_NIGHT_R, ATMO_NIGHT_G, ATMO_NIGHT_B) * ATMO_NIGHT_I;
        vec3 rain = vec3(ATMO_RAIN_R, ATMO_RAIN_G, ATMO_RAIN_B) * ATMO_RAIN_I;
        return BlendConditions(sunset, noon, night, rain, sunUp);
    #endif
}
