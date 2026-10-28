#ifndef AIR_GLSL
#define AIR_GLSL

// The air medium (W5, docs/WORLD_MODEL.md system G): what the air holds besides the
// everyday haze (fog.glsl), shared by the fog applied to every pixel and by the air march
// (lightShafts.glsl), so the two always agree.
//   Mist (Q24)       - from the world state (still, humid nights; dawn; after rain): lies
//                      thick up to a few blocks above sea level and thins above, in patches
//                      that drift with the wind. The fog gives it its sky-lit colour and
//                      hides what is behind it; the march adds the sunlight scattered in
//                      it, shadowed (light shafts through trees in morning mist).
//   Rain curtains (Q19) - grey sheets of falling rain in the distance, under the denser
//                      parts of the clouds, moving with the clouds.
// Needs: common.glsl, sky.glsl, noise.glsl.

// Mist extinction (per block) at a world position.
float MistDensity(vec3 worldPos) {
    #if defined WORLD_OVERWORLD && MIST > 0
        float mist = wsMist.x * (1.0 - caveFactor);
        if (mist <= 0.001) return 0.0;
        float height = exp(-max(worldPos.y - wsMist.y, 0.0) / 6.0);
        // Patches, drifting with the surface wind.
        vec2 p = (worldPos.xz - wsWindOffset.xy) * 0.035;
        float patches = 0.35 + 1.1 * SmoothNoise(p) * SmoothNoise(p * 2.3 + 17.0);
        return 0.05 * float(MIST) * 0.01 * mist * height * patches;
    #else
        return 0.0;
    #endif
}

// Mist along the view ray from the camera, worked out exactly for the height profile
// (flat up to wsMist.y, thinning above), with the patches of one point along the way.
// Returns the optical depth.
float MistOpticalDepth(vec3 dir, float dist) {
    #if defined WORLD_OVERWORLD && MIST > 0
        float mist = wsMist.x * (1.0 - caveFactor);
        if (mist <= 0.001) return 0.0;
        const float H = 6.0;
        float y0 = cameraPosition.y, top = wsMist.y;
        // The part of the ray below the top (thick) and above it (thinning).
        float below, above;
        if (abs(dir.y) < 1e-4) {
            below = y0 < top ? dist : 0.0;
            above = y0 < top ? 0.0 : dist * exp(-(y0 - top) / H);
        } else {
            float tTop = clamp((top - y0) / dir.y, 0.0, dist);
            float a0, a1;
            if (dir.y > 0.0) { below = tTop; a0 = tTop; a1 = dist; }
            else { below = dist - tTop; a0 = 0.0; a1 = tTop; }
            float e0 = exp(-max(y0 + a0 * dir.y - top, 0.0) / H);
            float e1 = exp(-max(y0 + a1 * dir.y - top, 0.0) / H);
            above = abs(e0 - e1) * H / abs(dir.y);
        }
        vec3 probe = cameraPosition + dir * min(dist, 24.0);
        vec2 p = (probe.xz - wsWindOffset.xy) * 0.035;
        float patches = 0.35 + 1.1 * SmoothNoise(p) * SmoothNoise(p * 2.3 + 17.0);
        return 0.05 * float(MIST) * 0.01 * mist * patches * (below + above);
    #else
        return 0.0;
    #endif
}

// Colour of the mist's light without direct sun (the march adds that, shadowed): the
// sky's light, slightly brightened by scattering within it.
vec3 MistColor(vec3 sunDir) {
    vec3 c = SkyAmbientColor(sunDir.y) * 1.15;
    #if VL_QUALITY == 0
        // No air march: give it a share of the sunlight here instead (unshadowed).
        c += SunLightColor(sunDir.y) * 0.2;
    #endif
    return c;
}

// Rain curtains: how much of the view in a direction is hidden by distant falling rain,
// 0..1, for a ray of the given length (the sky counts as far).
float RainCurtain(vec3 dir, float dist) {
    #ifdef RAIN_CURTAINS
    #ifdef WORLD_OVERWORLD
        float rain = VisibleRain() * (1.0 - inSnowyBiome * 0.5) * (1.0 - inDryBiome) * (1.0 - caveFactor);
        if (rain <= 0.001 || dist < 48.0) return 0.0;
        // Sheets hang under the clouds: only near the horizon for the sky.
        float low = 1.0 - smoothstep(0.02, 0.25, dir.y);
        // Where the ray is ~200 blocks out, moving with the clouds.
        vec2 at = cameraPosition.xz + normalize(dir.xz + vec2(1e-4)) * min(dist, 220.0);
        vec2 p = (at + wsWindOffset.zw * 0.25 * CLOUD_SPEED) * 0.006;
        float sheet = smoothstep(0.42, 0.75, SmoothNoise(p) * 0.7 + SmoothNoise(p * 3.1 + 5.0) * 0.3);
        float depth = 1.0 - exp(-max(dist - 48.0, 0.0) * 0.006);
        return rain * low * sheet * depth * 0.75;
    #else
        return 0.0;
    #endif
    #else
        return 0.0;
    #endif
}

vec3 RainCurtainColor(vec3 sunDir) {
    vec3 ambient = SkyAmbientColor(sunDir.y);
    return mix(ambient, vec3(Luminance(ambient)), 0.5) * 0.9;
}

#endif
