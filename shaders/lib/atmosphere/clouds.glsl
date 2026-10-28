#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

// Volumetric clouds (plan items C1-C7), ray marched at reduced resolution in the first
// deferred pass and blended with the previous frames (program/clouds.glsl). Also cloud
// shadows on the ground.
//
// The sky holds up to three layers at different altitudes, picked by CLOUD_PRESET. A layer
// is either volumetric (marched through its thickness: cumulus, stratocumulus, stratus,
// altocumulus) or a thin sheet (one sample where the view ray crosses it: cirrus,
// altostratus). Cloud Altitude / Thickness / Amount / Size / Density shape the main layer
// and scale the others with it.
// Needs: common.glsl, sky.glsl. Overworld only.

#include "/lib/util/noise.glsl"

const float CLOUD_FAR = 3000.0;        // longest stretch of a layer marched (blocks)
const float CLOUD_FADE_DIST = 1650.0;  // distance scale of the fade into the sky haze
const float CLOUD_NONE_DIST = 60000.0; // distance stored where there is no cloud

#if CLOUD_QUALITY == 1
    const int CLOUD_STEPS = 14;
    const int CLOUD_LIGHT_STEPS = 3;
#elif CLOUD_QUALITY == 2
    const int CLOUD_STEPS = 22;
    const int CLOUD_LIGHT_STEPS = 4;
#else
    const int CLOUD_STEPS = 32;
    const int CLOUD_LIGHT_STEPS = 5;
#endif

struct CloudLayer {
    float bottom, thickness;
    float scale;       // blocks per cell of the coverage noise
    float amount;      // how much of the sky it covers, 0..1
    float softness;    // width of the fade at the edge of the cover
    float dome;        // 0 flat sheet of even thickness ... 1 tall rounded cumulus tops
    float erosion;     // strength of the small-scale 3D detail cut into the edges
    float detailScale; // blocks per cell of the detail noise
    float density;     // extinction per block where fully covered
    vec2 stretch;      // horizontal stretch of the pattern (cirrus streaks)
    float wind;        // speed relative to the main layer (higher layers drift faster)
    bool sheet;        // thin layer: a single sample instead of a march
};

CloudLayer MakeLayer(float bottom, float thickness, float scale, float amount, float softness,
                     float dome, float erosion, float detailScale, float density, vec2 stretch,
                     float wind, bool sheet) {
    CloudLayer l;
    l.bottom = bottom; l.thickness = thickness; l.scale = scale * CLOUD_SIZE;
    l.amount = amount; l.softness = softness; l.dome = dome; l.erosion = erosion;
    l.detailScale = detailScale * CLOUD_SIZE; l.density = density * CLOUD_DENSITY;
    l.stretch = stretch; l.wind = wind; l.sheet = sheet;
    return l;
}

// ---- Styles -------------------------------------------------------------------------
// Rain adds cover to every style, and turns every style into an overcast sky over a minute
// or two (stormRain, a slowly smoothed rain strength); thunderstorms make the deck
// thicker and darker still (stormThunder).
// Cover also varies from day to day and builds up on fair afternoons (world state).
float CloudAmount() { return CLOUD_AMOUNT + wsAir.z + stormRain * 0.25; }

// Overcast: a thick, nearly unbroken stratus deck under a high grey altostratus sheet.
CloudLayer OvercastLayer(int i) {
    float a = float(CLOUD_ALTITUDE), amount = CloudAmount();
    if (i == 0) return MakeLayer(a - 24.0, CLOUD_THICKNESS * 0.7, 150.0, 0.62 + amount * 0.4, 0.45, 0.0, 0.18, 20.0, 0.06, vec2(1.3, 1.0), 0.8, false);
    return MakeLayer(a + 210.0, 10.0, 320.0, 0.55 + amount * 0.3, 0.6, 0.0, 0.0, 0.0, 0.03, vec2(2.0, 1.0), 1.5, true);
}

#if CLOUD_PRESET == 1
    // Stratocumulus: a wide, flat-topped deck broken into lumpy cells, with fibrous cirrus
    // streaks high above.
    const int CLOUD_LAYERS = 2;
    CloudLayer PresetLayer(int i) {
        float a = float(CLOUD_ALTITUDE), amount = CloudAmount();
        if (i == 0) return MakeLayer(a - 16.0, CLOUD_THICKNESS * 0.55, 120.0, amount + 0.18, 0.40, 0.25, 0.32, 13.0, 0.075, vec2(1.6, 1.0), 1.0, false);
        return MakeLayer(a + 220.0, 8.0, 150.0, CIRRUS_AMOUNT, 0.45, 0.0, 0.0, 0.0, 0.05, vec2(6.0, 1.0), 2.4, true);
    }
#elif CLOUD_PRESET == 3
    const int CLOUD_LAYERS = 2;
    CloudLayer PresetLayer(int i) { return OvercastLayer(i); }
#else
    // Cumulus (M5): one layer of soft puffy clouds with flat bottoms; the high sheet only
    // forms in rain.
    const int CLOUD_LAYERS = 2;
    CloudLayer PresetLayer(int i) {
        if (i == 0) return MakeLayer(float(CLOUD_ALTITUDE), CLOUD_THICKNESS, 64.0, CloudAmount(), 0.28, 1.0, 0.42, 9.0, 0.09, vec2(1.0), 1.0, false);
        CloudLayer l = OvercastLayer(1);
        l.amount = 0.0;
        return l;
    }
#endif

CloudLayer MixLayers(CloudLayer a, CloudLayer b, float t) {
    CloudLayer l = a;
    l.bottom = mix(a.bottom, b.bottom, t);
    l.thickness = mix(a.thickness, b.thickness, t);
    l.scale = mix(a.scale, b.scale, t);
    l.amount = mix(a.amount, b.amount, t);
    l.softness = mix(a.softness, b.softness, t);
    l.dome = mix(a.dome, b.dome, t);
    l.erosion = mix(a.erosion, b.erosion, t);
    l.detailScale = mix(a.detailScale, b.detailScale, t);
    l.density = mix(a.density, b.density, t);
    l.stretch = mix(a.stretch, b.stretch, t);
    l.wind = mix(a.wind, b.wind, t);
    return l;
}

CloudLayer GetCloudLayer(int i) {
    CloudLayer l = PresetLayer(i);
    #ifdef RAIN_OVERCAST
    #if CLOUD_PRESET != 3
        if (stormRain > 0.001) l = MixLayers(l, OvercastLayer(i), stormRain);
    #endif
    #endif
    // Thunderstorms: a lower, thicker, denser (darker underneath) deck.
    if (i == 0) {
        l.bottom -= 12.0 * stormThunder;
        l.thickness *= 1.0 + 0.6 * stormThunder;
        l.density *= 1.0 + 1.2 * stormThunder;
        l.amount += 0.15 * stormThunder;
    }
    return l;
}

// ---- Density --------------------------------------------------------------------------

// World-space drift: the distance the air aloft has moved (world state); layers differ only
// in speed. Synced to world time: a fixed drift from the clock instead, the same for everyone.
vec2 CloudWind() {
    #ifdef CLOUD_WORLD_TIME
        float t = (float(worldDay) * 24000.0 + float(worldTime)) / 20.0; // seconds of game time
        return vec2(1.0, 0.35) * t * CLOUD_SPEED;
    #else
        // (Sampled at position + this, so the pattern moves the opposite way: minus the
        // drift moves the clouds along with the wind.)
        return -wsWindOffset.zw * 0.25 * CLOUD_SPEED;
    #endif
}

// Smooth value noise in one texture read: the noise texture is linearly filtered, so
// feeding it smoothstep-shaped coordinates gives the same result as SmoothNoise.
float CloudNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    f = f * f * (3.0 - 2.0 * f);
    return textureLod(noisetex, (i + f + 0.5) / float(noiseTextureResolution), 0.0).r;
}

// 3D value noise from two slices of the 2D noise texture.
float CloudNoise3D(vec3 p) {
    float z = floor(p.y);
    float f = p.y - z;
    f = f * f * (3.0 - 2.0 * f);
    float a = CloudNoise(p.xz + z * vec2(37.0, 17.0));
    float b = CloudNoise(p.xz + (z + 1.0) * vec2(37.0, 17.0));
    return mix(a, b, f);
}

// How covered a layer is at a spot, 0..1. The pattern is domain-warped (bent by a second,
// larger noise) so it forms irregular streets and cells instead of round blobs.
float LayerCoverage(CloudLayer l, int index, vec2 xz) {
    vec2 p = (xz + CloudWind() * l.wind) / l.scale / l.stretch + float(index) * vec2(53.1, 91.7);
    vec2 warp = vec2(CloudNoise(p * 0.45 + 31.7), CloudNoise(p * 0.45 + 77.1)) - 0.5;
    p += warp * 1.4;
    float n = CloudNoise(p) * 0.52
            + CloudNoise(p * 2.13 + vec2(17.3, 5.1)) * 0.29
            + CloudNoise(p * 4.41 + vec2(-3.7, 11.9)) * 0.19;
    float cov = smoothstep(1.0 - l.amount, 1.0 - l.amount + l.softness, n);
    if (l.sheet && cov > 0.0) {
        // Thin sheets are fibrous: fine lines along the stretch direction (cirrus).
        float fibres = CloudNoise(p * vec2(1.5, 14.0) + 7.3) * 0.6 + CloudNoise(p * vec2(3.0, 31.0) + 2.9) * 0.4;
        cov *= smoothstep(0.25, 0.75, fibres);
    }
    return cov;
}

// Extinction per block at a point of a volumetric layer. `detail` adds the small-scale
// erosion that shapes the edges (left out of the cheap light and shadow lookups).
float LayerDensity(CloudLayer l, int index, vec3 pos, bool detail) {
    float h = (pos.y - l.bottom) / l.thickness;
    if (h <= 0.0 || h >= 1.0) return 0.0;
    float cov = LayerCoverage(l, index, pos.xz);
    if (cov <= 0.0) return 0.0;

    // Cumulus: denser cover reaches higher (rounded tops, flat bottoms). Sheets: even
    // thickness with soft top and bottom.
    float top = mix(0.85, sqrt(cov) * 0.95, l.dome);
    float bottomSoft = mix(0.30, 0.08, l.dome);
    float shape = smoothstep(0.0, bottomSoft, h) * smoothstep(top, top - mix(0.45, 0.35, l.dome), h) * cov;
    if (detail && shape > 0.0 && l.erosion > 0.0) {
        vec3 q = (pos + vec3(CloudWind().x, 0.0, CloudWind().y) * l.wind * 1.3) / l.detailScale;
        float erosion = CloudNoise3D(q) * 0.65 + CloudNoise3D(q * 2.7) * 0.35;
        shape = saturate(shape - erosion * l.erosion * (1.0 - shape * 0.5));
    }
    return shape * l.density;
}

// Distances along a ray where it is inside a layer; false if it misses.
bool LayerSpan(CloudLayer l, float startY, vec3 dir, out float tNear, out float tFar) {
    float top = l.bottom + l.thickness;
    if (abs(dir.y) < 1e-4) {
        tNear = 0.0;
        tFar = CLOUD_FAR;
        return startY > l.bottom && startY < top;
    }
    float tb = (l.bottom - startY) / dir.y;
    float tt = (top - startY) / dir.y;
    tNear = max(min(tb, tt), 0.0);
    tFar = min(max(tb, tt), tNear + CLOUD_FAR);
    return tFar > tNear && tNear < CLOUD_FADE_DIST * 4.0;
}

// Henyey-Greenstein phase (not normalised to 1/4pi: scaled so isotropic = 1).
float HG(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

// ---- Marching ---------------------------------------------------------------------------

struct CloudSample {
    vec3 scatter;        // light scattered towards the camera
    float transmittance; // how much of what is behind still shows
    float distance;      // typical distance of the cloud along the ray (CLOUD_NONE_DIST if none)
};

struct CloudAccum {
    vec3 scatter;       // shown light (already faded into the haze with distance)
    float opacity;      // shown opacity
    float transmittance; // physical transmittance so far, for what lies further on
    float weight, distSum;
};

// Far clouds fade into the haze of the sky.
float CloudFade(float t) {
    float fade = 1.0 - exp(-t / CLOUD_FADE_DIST);
    return fade * fade;
}

// Adds the light a slab of cloud scatters towards the camera.
// t: distance along the ray; horizontal: share of it that is horizontal (clouds right
// overhead never fade, however high they are).
void AccumulateCloud(inout CloudAccum a, vec3 light, float sampleT, float t, float horizontal) {
    float absorbed = a.transmittance * (1.0 - sampleT);
    float shown = absorbed * (1.0 - CloudFade(t * horizontal));
    a.scatter += light * shown;
    a.opacity += shown;
    a.weight += absorbed;
    a.distSum += absorbed * t;
    a.transmittance *= sampleT;
}

void MarchLayer(CloudLayer l, int index, vec3 dir, float tNear, float tFar, int steps,
                vec3 sunColor, vec3 ambient, float phase, vec3 lightDir, float dither, inout CloudAccum a) {
    vec3 camera = cameraPosition;
    if (l.sheet) {
        // One sample where the ray crosses the middle of the sheet.
        float t = (tNear + tFar) * 0.5;
        vec3 pos = camera + dir * t;
        float cov = LayerCoverage(l, index, pos.xz);
        if (cov <= 0.0) return;
        float od = min(cov * l.density * (tFar - tNear), 3.0);
        // Thin ice clouds: bright, lit straight through.
        vec3 light = sunColor * (0.55 + phase * 0.5) + ambient * 1.1;
        AccumulateCloud(a, light, exp(-od), t, length(dir.xz));
        return;
    }

    float stepLen = (tFar - tNear) / float(steps);
    float t = tNear + stepLen * dither;
    for (int i = 0; i < steps; i++, t += stepLen) {
        vec3 pos = camera + dir * t;
        float density = LayerDensity(l, index, pos, true);
        if (density <= 0.0) continue;

        // Light from the sun/moon: optical depth along a few growing steps towards it.
        float od = 0.0;
        float ls = 4.0 * CLOUD_SIZE;
        vec3 lp = pos;
        for (int j = 0; j < CLOUD_LIGHT_STEPS; j++) {
            lp += lightDir * ls;
            od += LayerDensity(l, index, lp, false) * ls;
            ls *= 1.9;
        }
        // Multiple scattering approximation: a weaker, slower-falling second term.
        float sunT = max(exp(-od), exp(-od * 0.25) * 0.35);
        float powder = 1.0 - exp(-density * 18.0);
        float h = (pos.y - l.bottom) / l.thickness;

        vec3 light = sunColor * sunT * phase * mix(0.6, 1.0, powder) + ambient * (0.45 + 0.55 * h);
        AccumulateCloud(a, light, exp(-density * stepLen), t, length(dir.xz));
        if (a.transmittance < 0.02) break;
    }
}

// March all cloud layers along a view ray from the camera, nearest layer first.
// dither: 0..1 offset of the first step (varies per pixel and frame; the temporal blend
// smooths it).
CloudSample MarchClouds(vec3 dir, vec3 sunDir, vec3 lightDir, float dither) {
    CloudAccum a;
    a.scatter = vec3(0.0);
    a.opacity = 0.0;
    a.transmittance = 1.0;
    a.weight = 0.0;
    a.distSum = 0.0;

    vec3 sunColor = SunLightColor(sunDir.y) * 1.25;
    vec3 ambient = SkyAmbientColor(sunDir.y) * 1.1;
    // Lightning lights the clouds from inside.
    ambient += LightningFlashColor() * 1.5;
    float VdotL = dot(dir, lightDir);
    float phase = mix(HG(VdotL, 0.55), HG(VdotL, -0.25), 0.3);

    // Where the ray meets each layer.
    float nearT[3], farT[3];
    bool hit[3];
    for (int i = 0; i < CLOUD_LAYERS; i++) {
        hit[i] = LayerSpan(GetCloudLayer(i), cameraPosition.y, dir, nearT[i], farT[i]);
    }

    // Visit them in order of distance (at most three: pick the nearest unvisited each time).
    bool done[3] = bool[3](false, false, false);
    for (int n = 0; n < CLOUD_LAYERS; n++) {
        int next = -1;
        for (int i = 0; i < CLOUD_LAYERS; i++) {
            if (hit[i] && !done[i] && (next < 0 || nearT[i] < nearT[next])) next = i;
        }
        if (next < 0 || a.transmittance < 0.02) break;
        done[next] = true;

        CloudLayer l = GetCloudLayer(next);
        // The main layer gets the full step count, smaller ones a share of it.
        int steps = next == 0 ? CLOUD_STEPS : max(CLOUD_STEPS / 3, 6);
        MarchLayer(l, next, dir, nearT[next], farT[next], steps, sunColor, ambient, phase, lightDir, dither, a);
    }

    CloudSample c;
    c.scatter = a.scatter;
    c.transmittance = 1.0 - a.opacity;
    c.distance = a.weight > 0.001 ? a.distSum / a.weight : CLOUD_NONE_DIST;
    return c;
}

// Fraction of sun/moon light that gets past the clouds to a point (cloud shadows).
float CloudShadow(vec3 worldPos, vec3 lightDir) {
    #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1 && CLOUD_SHADOWS > 0
        if (lightDir.y < 0.02) return 1.0;
        float od = 0.0;
        for (int i = 0; i < CLOUD_LAYERS; i++) {
            CloudLayer l = GetCloudLayer(i);
            if (worldPos.y > l.bottom) continue;
            if (l.sheet) {
                vec3 p = worldPos + lightDir * ((l.bottom - worldPos.y) / lightDir.y);
                od += LayerCoverage(l, i, p.xz) * l.density * l.thickness / lightDir.y;
            } else {
                for (int j = 0; j < 2; j++) {
                    float y = l.bottom + l.thickness * (0.2 + 0.35 * float(j));
                    vec3 p = worldPos + lightDir * ((y - worldPos.y) / lightDir.y);
                    od += LayerDensity(l, i, p, false) * l.thickness * 0.5 / lightDir.y;
                }
            }
        }
        return mix(1.0, exp(-od), float(CLOUD_SHADOWS) * 0.01 * smoothstep(0.02, 0.15, lightDir.y));
    #else
        return 1.0;
    #endif
}

#endif
