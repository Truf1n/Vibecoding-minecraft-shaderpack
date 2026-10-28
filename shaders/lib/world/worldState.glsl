#ifndef WORLD_STATE_GLSL
#define WORLD_STATE_GLSL

// World state (docs/WORLD_MODEL.md, system A): the physical quantities every effect shares,
// worked out once per frame by the begin pass (program/worldState.glsl) and kept in a
// shader storage buffer between frames, so slow things can be integrated over time
// (wind drift, wetness, snow) instead of being re-derived per pixel from the clock.
// Everything else reads it; only the begin pass and the exposure pass write it.

#ifdef WORLD_STATE_WRITER
    #define WORLD_STATE_ACCESS
#else
    #define WORLD_STATE_ACCESS readonly
#endif

layout(std430, binding = 0) WORLD_STATE_ACCESS buffer WorldStateBuffer {
    vec4 wsHeader;      // x: 1 once initialised
    vec4 wsWind;        // xy: surface wind direction (unit, world xz); z: speed (blocks/s); w: gustiness
    vec4 wsWindOffset;  // xy: distance the surface air has moved (blocks); zw: the air aloft (clouds)
    vec4 wsJet;         // xy: distance the jet stream has moved (cirrus); z: wave clock (s, runs faster in wind)
    vec4 wsAir;         // x: temperature (deg C, rough); y: humidity 0..1; z: cloud cover offset; w: convection
    vec4 wsWeather;     // x: rain, slowly smoothed; y: thunder, smoothed; z: rain lingering for minutes
    vec4 wsSurface;     // x: wetness 0..1; y: snow depth 0..1; z: swell direction (radians)
    vec4 wsSun;         // rgb: sun/moon light (artistic sky model, multipliers and storms applied)
    vec4 wsSkyZenith;   // rgb: sky colour overhead
    vec4 wsSkyHorizon;  // rgb: sky colour at the horizon
    vec4 wsSkyAmbient;  // rgb: light from the whole sky
    vec4 wsExposure;    // x: exposure in use; y: target; z: average scene luminance
    vec4 wsMist;        // x: mist 0..1; y: height (absolute y) up to which it lies thick
    vec4 wsWaterScatter; // rgb: scattering of the water style at the camera (waterStyles.glsl); a: fog density
    vec4 wsWaterAbsorb;  // rgb: its absorption
    vec4 wsWaterFog;     // rgb: its underwater fog colour
};

// The weather values the effects used to get from custom uniforms.
#define stormRain    (wsWeather.x)
#define stormThunder (wsWeather.y)
#define afterRain    (wsWeather.z)
#define wetness      (wsSurface.x)

vec2 WindDir() { return wsWind.xy; }
float WindSpeed() { return wsWind.z; }

#endif
