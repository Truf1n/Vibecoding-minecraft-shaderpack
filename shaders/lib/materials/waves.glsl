#ifndef WAVES_GLSL
#define WAVES_GLSL

// The water's wave field (docs/WORLD_MODEL.md system D): one analytic sum of travelling
// waves, used for the surface normals, the vertex swell, the caustics under the water and
// the surface roughness, so all of them agree. Each wave has an exact slope and curvature,
// so there are no finite differences: the normal costs one evaluation, and the caustics
// get the curvature they need for free.
//
// The waves come from the world state:
//   wind sea  - waves raised by the wind, on 12 fixed headings; each heading is as strong as
//               the wind blows along it (a directional spectrum), so when the wind veers the
//               sea changes which waves are big instead of rotating (rotating waves would
//               sweep across the world far from the origin); in drifting wave groups
//   ripples   - short capillary waves, strongest where a gust is passing (cat's paws), and
//               an irregular noise chop on top
//   swell     - long waves on big water only, from the day's prevailing wind
// They travel at deep-water speed for their length (long waves faster: a real sea), slowed
// down for Minecraft's scale. Calm where there is no wind (caves, under roofs) and on small
// ponds (fetch).
// Needs: common.glsl (world state), noise.glsl.

const float WAVE_GRAVITY = 9.8;     // blocks/s^2
const float WAVE_TIME_SCALE = 0.22; // waves in a block world look best slower than real

struct WaveSample {
    float height;
    vec2 slope;   // dh/dx, dh/dz
    vec3 hessian; // d2h/dx2, d2h/dz2, d2h/dxdz
    float unresolvedSlope2; // slope variance of waves too small to show at this distance
};

// What drives the waves at a spot.
struct WaveConditions {
    float windSea;  // steepness scale of the wind sea
    float ripples;  // steepness scale of the ripples
    float swell;    // steepness scale of the swell
};

void AddWave(inout WaveSample w, vec2 p, float t, vec2 dir, float wavelength, float steepness, float phase0, float footprint) {
    wavelength *= WATER_WAVE_SIZE;
    float k = TAU / wavelength;
    float amp = steepness / k * WATER_WAVE_STRENGTH;
    // Waves much smaller than a pixel are not drawn; they roughen the surface instead.
    float resolved = smoothstep(2.0, 4.0, wavelength / max(footprint, 1e-4));
    w.unresolvedSlope2 += 0.5 * pow(amp * k * (1.0 - resolved), 2.0);
    amp *= resolved;
    if (amp <= 0.0) return;
    float omega = sqrt(WAVE_GRAVITY * k) * WAVE_TIME_SCALE * WATER_WAVE_SPEED;
    float theta = k * dot(dir, p) - omega * t + phase0;
    float s = sin(theta), c = cos(theta);
    w.height += amp * s;
    w.slope += amp * k * c * dir;
    w.hessian -= amp * k * k * s * vec3(dir.x * dir.x, dir.y * dir.y, dir.x * dir.y);
}

float WaveHash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

vec2 Heading(float degrees) { float a = radians(degrees); return vec2(cos(a), sin(a)); }

// Conditions from the world state. shelter: 0 no wind reaches (caves, roofs) ... 1 open sky;
// fetch: 0 a small pond ... 1 open water; gust: the local gust field.
WaveConditions GetWaveConditions(float shelter, float fetch, float gust) {
    WaveConditions c;
    float wind = clamp(0.6 + 0.06 * WindSpeed(), 0.6, 1.15); // rain and storms: rougher, not wild
    c.windSea = 0.045 * wind * shelter * (0.35 + 0.65 * fetch);
    c.ripples = 0.040 * shelter * (0.45 + 0.8 * gust);
    c.swell = 0.014 * fetch * fetch * (1.0 + stormThunder) * shelter;
    return c;
}

// The gust field at a spot (0..1), drifting with the surface air (same as the plants).
float GustAt(vec2 xz) {
    vec2 g = (xz - wsWindOffset.xy) / 14.0;
    return SmoothNoise(g) * 0.65 + SmoothNoise(g * 2.3 + 7.1) * 0.35;
}

// Background chop: an irregular, drifting noise surface on top of the waves, so the sea is
// never a clean pattern of a few sine waves. It drifts with the surface air (no rotation:
// noise looks the same in every direction). Slope only, by finite differences.
vec2 ChopSlope(vec2 p, float strength) {
    vec2 drift = wsWindOffset.xy * 0.12;
    const float e = 0.12;
    vec2 q = (p - drift) / (1.7 * WATER_WAVE_SIZE);
    float h0 = SmoothNoise(q) * 0.6 + SmoothNoise(q * 2.1 + 5.3) * 0.4;
    vec2 qx = (p + vec2(e, 0.0) - drift) / (1.7 * WATER_WAVE_SIZE);
    vec2 qz = (p + vec2(0.0, e) - drift) / (1.7 * WATER_WAVE_SIZE);
    float hx = SmoothNoise(qx) * 0.6 + SmoothNoise(qx * 2.1 + 5.3) * 0.4;
    float hz = SmoothNoise(qz) * 0.6 + SmoothNoise(qz * 2.1 + 5.3) * 0.4;
    return vec2(hx - h0, hz - h0) / e * strength;
}

// The wave field at world position p (xz). footprint: blocks covered by one pixel there
// (0 for the full detail); lowDetail: only the long waves (vertex motion, light shafts).
WaveSample Waves(vec2 p, WaveConditions c, float footprint, bool lowDetail) {
    WaveSample w;
    w.height = 0.0; w.slope = vec2(0.0); w.hessian = vec3(0.0); w.unresolvedSlope2 = 0.0;
    float t = wsJet.z;
    vec2 wind = WindDir();

    // Swell: two long waves from the day's prevailing wind (fixed through the day).
    if (c.swell > 0.0) {
        float day = float(worldDay);
        float a = WaveHash(vec3(day, 1.3, 17.31)) * 360.0;
        AddWave(w, p, t, Heading(a), 37.0, c.swell, 0.0, footprint);
        AddWave(w, p, t, Heading(a + 23.0), 23.0, c.swell * 0.8, 2.1, footprint);
    }

    // Wind sea: twelve irregularly spaced headings, each with a long and a short wave of
    // its own random length; strength by how well each lines up with the wind (cos^4
    // spreading, normalised), so the sea runs with the wind with a natural spread instead
    // of two or three crossing wave trains. Wave groups: the height swells and fades from
    // place to place as patches drift downwind.
    if (c.windSea > 0.0) {
        float groups = 0.55 + 0.9 * SmoothNoise((p - wsWindOffset.xy * 0.08) / (22.0 * WATER_WAVE_SIZE));
        for (int i = 0; i < 12; i++) {
            float fi = float(i);
            vec2 dir = Heading(fi * 30.0 + (WaveHash(vec3(fi, 3.1, 7.7)) - 0.5) * 24.0);
            float along = max(dot(dir, wind), 0.0);
            float weight = along * along * along * along / 2.25; // the weights sum to ~2.25
            if (weight < 0.01) continue;
            float longLength = 3.5 * pow(2.2, WaveHash(vec3(fi, 5.9, 1.3)));
            float shortLength = 1.5 * pow(2.1, WaveHash(vec3(fi, 8.3, 4.1)));
            AddWave(w, p, t, dir, longLength, c.windSea * weight * groups, fi * 1.7, footprint);
            AddWave(w, p, t, dir, shortLength, c.windSea * weight * 0.75 * groups, fi * 2.9 + 1.0, footprint);
        }
    }

    // Ripples: short waves on random headings, mostly along the wind, raised by gusts.
    if (!lowDetail && c.ripples > 0.0) {
        for (int i = 0; i < 6; i++) {
            float fi = float(i);
            vec2 dir = Heading(WaveHash(vec3(fi, 11.3, 2.9)) * 360.0);
            float along = max(dot(dir, wind), 0.0);
            float weight = 0.35 + 0.65 * along * along;
            float rippleLength = 0.4 * pow(3.0, WaveHash(vec3(fi, 6.1, 9.4)));
            AddWave(w, p, t, dir, rippleLength, c.ripples * weight * 0.55, fi * 3.7, footprint);
        }
        // And the irregular background chop on top.
        w.slope += ChopSlope(p, c.ripples * 1.6) * WATER_WAVE_STRENGTH * (1.0 - smoothstep(0.2, 0.6, footprint));
    }
    return w;
}

// Surface normal of the wave field (plus extra slope, e.g. rain rings).
vec3 WaveSurfaceNormal(vec2 slope) { return normalize(vec3(-slope.x, 1.0, -slope.y)); }

// Caustics (plan items Q13, Q14): light entering the surface bends towards the normal, so
// a crest acts as a converging lens and a trough as a diverging one. For light that has
// gone a depth d into the water, the area it entered through is stretched by
// det(I + d c H) (H: the surface's curvature, c = 1 - 1/n), and its brightness is spread
// over that area: brightness = 1 / |det|. Per colour channel, with water's refractive
// index for red / green / blue (1.331 / 1.333 / 1.338), so the focus differs a little by
// colour and the lines get colour fringes that widen with depth (Caustic Dispersion
// exaggerates it). The sun's size blurs them out with depth; cloud cover flattens them.
vec3 WaveCaustics(WaveSample w, float depth) {
    const vec3 n = vec3(1.331, 1.333, 1.338);
    vec3 c = 1.0 - 1.0 / n;
    c = c.g + (c - c.g) * CAUSTIC_DISPERSION;
    vec3 result;
    for (int i = 0; i < 3; i++) {
        float dc = depth * c[i];
        float det = (1.0 + dc * w.hessian.x) * (1.0 + dc * w.hessian.y) - dc * dc * w.hessian.z * w.hessian.z;
        result[i] = 1.0 / max(abs(det), 0.12);
    }
    // Contrast: none at the very surface, fading out with depth (sun disc blur) and under
    // a cloudy sky (diffuse light makes no caustics).
    float contrast = smoothstep(0.0, 0.8, depth) * exp(-depth / 22.0) * (1.0 - 0.8 * stormRain);
    return mix(vec3(1.0), min(result, vec3(5.0)), contrast);
}

#endif
