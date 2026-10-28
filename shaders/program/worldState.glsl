// World state update (begin pass, compute, one thread; docs/WORLD_MODEL.md system A).
// Runs at the start of every frame, before the shadow pass, and moves the shared state
// (lib/world/worldState.glsl) one frame forward:
//   weather   - vanilla rain/thunder, smoothed into what the sky shows
//   wind      - the day's prevailing direction, veering through the day; speed from the
//               biome, altitude and weather; the distance the air has moved (integrated, so
//               a change of speed never makes clouds or waves jump)
//   air       - temperature, humidity, cloud cover of the day and afternoon convection
//   surface   - wetness (rain soaks in, sun and wind dry it), snow depth, swell direction
//   light     - sun and sky colours for the frame (worked out once instead of per pixel)
// Deterministic choices (wind of the day, cloudiness of the day) are seeded by the world
// day, so they are the same for everyone on a server.

#include "/lib/common.glsl"
#include "/lib/gbuffer/layout.glsl"
#include "/lib/atmosphere/sky.glsl"

layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

float dt;
bool firstFrame;

// Moves a value towards a target with time constant tau (seconds); jumps on the first frame.
float Approach(float current, float target, float tau) {
    return firstFrame ? target : mix(current, target, 1.0 - exp(-dt / max(tau, 1e-3)));
}
vec3 Approach(vec3 current, vec3 target, float tau) {
    return firstFrame ? target : mix(current, target, 1.0 - exp(-dt / max(tau, 1e-3)));
}

float DayHash(float salt) { return Hash13(vec3(float(worldDay), salt, 17.31)); }

vec2 Rotate(vec2 v, float a) { float c = cos(a), s = sin(a); return vec2(c * v.x - s * v.y, s * v.x + c * v.y); }

void main() {
    dt = clamp(frameTime, 0.0, 0.25);
    firstFrame = wsHeader.x < 0.5;
    float timeOfDay = float(worldTime) / 24000.0; // 0 sunrise, 0.25 noon, 0.5 sunset
    float sunUp = SunElevation();
    float day = DayFactor(sunUp);

    // ---- Weather (half-lives as in M9: clouds set in over a minute or two) -------------
    stormRain = Approach(stormRain, rainStrength, rainStrength > stormRain ? 87.0 : 173.0);
    stormThunder = Approach(stormThunder, thunderStrength, thunderStrength > stormThunder ? 43.0 : 130.0);
    afterRain = Approach(afterRain, rainStrength, rainStrength > afterRain ? 3.0 : 173.0);
    float precipitation = min(rainStrength, stormRain);

    // ---- Wind -------------------------------------------------------------------------
    // Direction: the day's prevailing wind, veering by up to ~40 degrees through the day,
    // swinging about in thunderstorms.
    float angle = DayHash(1.3) * TAU
                + 0.7 * sin(timeOfDay * TAU + DayHash(2.9) * TAU)
                + stormThunder * 0.6 * sin(frameTimeCounter * 0.03);
    vec2 targetDir = vec2(cos(angle), sin(angle));
    vec2 dir = firstFrame || dot(wsWind.xy, wsWind.xy) < 0.5 ? targetDir : normalize(mix(wsWind.xy, targetDir, 1.0 - exp(-dt / 60.0)));
    // Speed (blocks per second): a light breeze that differs from day to day and by biome,
    // calmer at night, stronger higher up, much stronger in rain and storms.
    float breeze = (1.2 + 2.3 * DayHash(4.1)) * max(biomeWindiness, 0.3) * mix(0.75, 1.0, day);
    float altitude = 1.0 + max(cameraPosition.y - 70.0, 0.0) / 150.0;
    float targetSpeed = breeze * altitude + stormRain * 4.0 + stormThunder * 9.0;
    float speed = Approach(wsWind.z, targetSpeed, 20.0);
    float gustiness = Approach(wsWind.w, 0.3 + 0.2 * stormRain + 0.4 * stormThunder, 20.0);
    wsWind = vec4(dir, speed, gustiness);

    // Distances the air has moved. Aloft the wind is faster and turned clockwise (seen from
    // above) by friction-free flow, ~25 degrees; the jet stream faster and turned more.
    if (firstFrame) { wsWindOffset = vec4(0.0); wsJet = vec4(0.0); }
    wsWindOffset.xy += dir * speed * dt;
    wsWindOffset.zw += Rotate(dir, -0.44) * (speed * 2.5 + 2.0) * dt;
    wsJet.xy += Rotate(dir, -0.7) * (speed * 2.0 + 8.0) * dt;
    // Wave clock: each wave's speed comes from its length (waves.glsl); the clock itself
    // runs faster in stronger wind (integrated, so a change of wind never makes waves jump).
    wsJet.z += dt * (0.8 + 0.05 * speed);

    // ---- Air ---------------------------------------------------------------------------
    // Temperature in rough degrees: vanilla's biome temperature (snow below 0.15) cooled with
    // height like vanilla's snow line, a few degrees warmer by day.
    float temperatureC = (temperature - 0.15) * 25.0 - max(cameraPosition.y - 80.0, 0.0) * 0.04 + (day - 0.5) * 4.0;
    // Humidity: the biome's rainfall, recent rain, and the damp of dawn.
    float fromDawn = abs(fract(timeOfDay + 0.02 + 0.5) - 0.5); // days from just before sunrise
    float dawn = exp(-pow(fromDawn / 0.06, 2.0));
    float humidity = saturate(rainfall * 0.6 + wetness * 0.3 + stormRain * 0.3 + dawn * 0.15);
    // Clouds: some days are cloudier than others; fair-weather cumulus build up over the
    // afternoon (convection), not while it rains.
    float dailyCover = (DayHash(6.7) - 0.5) * 0.24;
    float convection = exp(-pow((timeOfDay - 0.32) / 0.12, 2.0)) * (1.0 - stormRain) * 0.12;
    wsAir = vec4(Approach(wsAir.x, temperatureC, 30.0), Approach(wsAir.y, humidity, 30.0),
                 Approach(wsAir.z, dailyCover + convection, 120.0), convection);

    // ---- Surfaces ----------------------------------------------------------------------
    // Rain soaks things in about half a minute; sun, wind and dry air dry them over minutes.
    float drying = (0.004 + 0.008 * day * (1.0 - stormRain) + 0.0008 * speed) * (1.0 - 0.5 * humidity);
    wetness = saturate(firstFrame ? precipitation : wetness + precipitation * dt / 30.0 - drying * dt * (1.0 - precipitation));
    // Snow builds up while it snows (below freezing) and melts above it, faster in sun and rain.
    float snowing = precipitation * step(wsAir.x, 0.0);
    float melting = step(0.0, wsAir.x) * (0.002 + 0.006 * day + 0.01 * precipitation);
    wsSurface.y = saturate(wsSurface.y + snowing * dt / 180.0 - melting * dt);
    // The ocean swell slowly follows the prevailing wind.
    float windAngle = atan(dir.y, dir.x);
    float swell = firstFrame ? windAngle : wsSurface.z;
    float diff = mod(windAngle - swell + PI, TAU) - PI;
    wsSurface.z = mod(swell + diff * (1.0 - exp(-dt / 600.0)), TAU);

    // ---- Light -------------------------------------------------------------------------
    vec3 zenith, horizon;
    OverworldSkyColorsModel(sunUp, zenith, horizon);
    wsSkyZenith = vec4(zenith, 1.0);
    wsSkyHorizon = vec4(horizon, 1.0);
    wsSkyAmbient = vec4(SkyAmbientColorModel(sunUp), 1.0);
    wsSun = vec4(SunLightColorModel(sunUp), sunUp);

    if (firstFrame) wsExposure = vec4(1.0, 1.0, 0.3, 0.0);
    wsHeader.x = 1.0;
}
