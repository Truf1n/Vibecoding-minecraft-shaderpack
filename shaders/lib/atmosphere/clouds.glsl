#ifndef CLOUDS_GLSL
#define CLOUDS_GLSL

// Volumetric clouds (plan items C1-C7): one layer of soft cumulus with flat bottoms and
// puffy tops, ray marched at reduced resolution in the first deferred pass and blended
// with the previous frames (deferred_clouds.glsl). Also cloud shadows on the ground.
// Needs: common.glsl, sky.glsl. Overworld only.

#include "/lib/util/noise.glsl"

const float CLOUD_BOTTOM = float(CLOUD_ALTITUDE);
const float CLOUD_TOP = float(CLOUD_ALTITUDE) + CLOUD_THICKNESS;
const float CLOUD_FAR = 3000.0;       // longest stretch of the layer marched (blocks)
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

// World-space drift: the wind moves all clouds the same way.
vec2 CloudWind() {
    #ifdef CLOUD_WORLD_TIME
        float t = (float(worldDay) * 24000.0 + float(worldTime)) / 20.0; // seconds of game time
    #else
        float t = frameTimeCounter;
    #endif
    return vec2(1.0, 0.35) * t * CLOUD_SPEED;
}

// Smooth value noise in one texture read: the noise texture is linearly filtered, so
// feeding it smoothstep-shaped coordinates gives the same result as SmoothNoise.
float CloudNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = p - i;
    f = f * f * (3.0 - 2.0 * f);
    return textureLod(noisetex, (i + f + 0.5) / float(noiseTextureResolution), 0.0).r;
}

// How cloudy the sky is at a spot, 0..1 (more in rain).
float CloudCoverage(vec2 xz) {
    vec2 p = (xz + CloudWind()) / (64.0 * CLOUD_SIZE);
    float n = CloudNoise(p) * 0.56
            + CloudNoise(p * 2.13 + vec2(17.3, 5.1)) * 0.29
            + CloudNoise(p * 4.41 + vec2(-3.7, 11.9)) * 0.15;
    float amount = CLOUD_AMOUNT + rainStrength * 0.25;
    return smoothstep(1.0 - amount, 1.0 - amount + 0.28, n);
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

// Extinction per block at a point. `detail` adds the small-scale erosion that shapes the
// puffy edges (left out of the cheap light and shadow lookups).
float CloudDensity(vec3 pos, bool detail) {
    float h = (pos.y - CLOUD_BOTTOM) / CLOUD_THICKNESS;
    if (h <= 0.0 || h >= 1.0) return 0.0;
    float cov = CloudCoverage(pos.xz);
    if (cov <= 0.0) return 0.0;

    // Denser cover reaches higher: flat soft bottoms, rounded tops.
    float top = sqrt(cov) * 0.95;
    float shape = smoothstep(0.0, 0.08, h) * smoothstep(top, top - 0.35, h) * cov;
    if (detail && shape > 0.0) {
        vec3 q = (pos + vec3(CloudWind().x, 0.0, CloudWind().y) * 1.3) / (9.0 * CLOUD_SIZE);
        float erosion = CloudNoise3D(q) * 0.65 + CloudNoise3D(q * 2.7) * 0.35;
        shape = saturate(shape - erosion * 0.42 * (1.0 - shape * 0.5));
    }
    return shape * 0.09 * CLOUD_DENSITY;
}

// Distances along a ray where it is inside the cloud layer; false if it misses.
bool CloudLayerSpan(float startY, vec3 dir, out float tNear, out float tFar) {
    if (abs(dir.y) < 1e-4) {
        tNear = 0.0;
        tFar = CLOUD_FAR;
        return startY > CLOUD_BOTTOM && startY < CLOUD_TOP;
    }
    float tb = (CLOUD_BOTTOM - startY) / dir.y;
    float tt = (CLOUD_TOP - startY) / dir.y;
    tNear = max(min(tb, tt), 0.0);
    tFar = min(max(tb, tt), tNear + CLOUD_FAR);
    return tFar > tNear;
}

// Henyey-Greenstein phase (not normalised to 1/4pi: scaled so isotropic = 1).
float HG(float cosTheta, float g) {
    float g2 = g * g;
    return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * cosTheta, 1.5);
}

struct CloudSample {
    vec3 scatter;        // light scattered towards the camera
    float transmittance; // how much of what is behind still shows
    float distance;      // typical distance of the cloud along the ray (CLOUD_NONE_DIST if none)
};

// March the cloud layer along a view ray from the camera. dither: 0..1 offset of the
// first step (varies per pixel and frame; the temporal blend smooths it).
CloudSample MarchClouds(vec3 dir, vec3 sunDir, vec3 lightDir, float dither) {
    CloudSample c;
    c.scatter = vec3(0.0);
    c.transmittance = 1.0;
    c.distance = CLOUD_NONE_DIST;

    vec3 camera = cameraPosition;
    float tNear, tFar;
    if (!CloudLayerSpan(camera.y, dir, tNear, tFar)) return c;

    float stepLen = (tFar - tNear) / float(CLOUD_STEPS);
    float t = tNear + stepLen * dither;

    vec3 sunColor = SunLightColor(sunDir.y) * 1.25;
    vec3 ambient = SkyAmbientColor(sunDir.y) * 1.1;
    float VdotL = dot(dir, lightDir);
    float phase = mix(HG(VdotL, 0.55), HG(VdotL, -0.25), 0.3);
    float lightUp = max(lightDir.y, 0.05);

    float weightSum = 0.0, distSum = 0.0;
    for (int i = 0; i < CLOUD_STEPS; i++, t += stepLen) {
        vec3 pos = camera + dir * t;
        float density = CloudDensity(pos, true);
        if (density <= 0.0) continue;

        // Light from the sun/moon: optical depth along a few growing steps towards it.
        float od = 0.0;
        float ls = 4.0 * CLOUD_SIZE;
        vec3 lp = pos;
        for (int j = 0; j < CLOUD_LIGHT_STEPS; j++) {
            lp += lightDir * ls;
            od += CloudDensity(lp, false) * ls;
            ls *= 1.9;
        }
        // Multiple scattering approximation: a weaker, slower-falling second term.
        float sunT = max(exp(-od), exp(-od * 0.25) * 0.35);
        float powder = 1.0 - exp(-density * 18.0);
        float h = (pos.y - CLOUD_BOTTOM) / CLOUD_THICKNESS;

        vec3 S = sunColor * sunT * phase * mix(0.6, 1.0, powder) + ambient * (0.45 + 0.55 * h);
        float sampleT = exp(-density * stepLen);
        float absorbed = c.transmittance * (1.0 - sampleT);
        c.scatter += S * absorbed;
        weightSum += absorbed;
        distSum += absorbed * t;
        c.transmittance *= sampleT;
        if (c.transmittance < 0.02) break;
    }

    if (weightSum > 0.001) {
        c.distance = distSum / weightSum;
        // Far clouds fade into the haze of the sky.
        float fade = 1.0 - exp(-c.distance / (CLOUD_FAR * 0.55));
        fade = fade * fade;
        c.scatter *= 1.0 - fade;
        c.transmittance = 1.0 - (1.0 - c.transmittance) * (1.0 - fade);
    }
    return c;
}

// Fraction of sun/moon light that gets past the clouds to a point (cloud shadows).
float CloudShadow(vec3 worldPos, vec3 lightDir) {
    #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1 && CLOUD_SHADOWS > 0
        if (lightDir.y < 0.02 || worldPos.y > CLOUD_BOTTOM) return 1.0;
        float od = 0.0;
        for (int i = 0; i < 2; i++) {
            float y = CLOUD_BOTTOM + CLOUD_THICKNESS * (0.2 + 0.35 * float(i));
            vec3 p = worldPos + lightDir * ((y - worldPos.y) / lightDir.y);
            od += CloudDensity(p, false) * CLOUD_THICKNESS * 0.5 / lightDir.y;
        }
        return mix(1.0, exp(-od), float(CLOUD_SHADOWS) * 0.01 * smoothstep(0.02, 0.15, lightDir.y));
    #else
        return 1.0;
    #endif
}

#endif
