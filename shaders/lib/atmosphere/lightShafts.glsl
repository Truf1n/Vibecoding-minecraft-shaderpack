#ifndef LIGHT_SHAFTS_GLSL
#define LIGHT_SHAFTS_GLSL

// Light shafts (plan items F5, F8): sun/moon light scattered by haze along the view ray,
// wherever the shadow map (and the clouds) let it through. Marched at half resolution in
// composite1 with a per-pixel, per-frame dither that TAA smooths out. Under water the
// shafts take the water's colour, fade with depth and carry the caustics.
// Needs: common.glsl, sky.glsl, shadowSpace.glsl, shadows.glsl, clouds.glsl.

#if VL_QUALITY == 1
    const int VL_STEPS = 8;
#elif VL_QUALITY == 2
    const int VL_STEPS = 12;
#else
    const int VL_STEPS = 18;
#endif

const float VL_MAX_DIST = 160.0;      // blocks marched in air
const float VL_MAX_DIST_WATER = 48.0; // blocks marched under water

// Overall strength in air for the current time and weather: strongest at sunrise and
// sunset, gentle at noon, faint by moonlight, and less when the camera is shut indoors.
float LightShaftStrength(vec3 sunDir) {
    float sunUp = sunDir.y;
    float day = DayFactor(sunUp);
    float time = mix(0.35, 1.0, SunsetFactor(sunUp)) * day + 0.45 * (1.0 - day);
    float skyAtEye = eyeBrightnessSmooth.y / 240.0;
    float indoor = mix(0.45, 1.0, skyAtEye);
    return time * indoor * (1.0 - rainStrength * 0.5) * VL_STRENGTH;
}

// Visibility of the sun/moon at a point for the shafts: one shadow-map tap (the march
// itself averages many), coloured by glass, dimmed by clouds.
vec3 ShaftVisibility(vec3 playerPos, vec3 lightDir) {
    vec3 clip = (shadowProjection * vec4((shadowModelView * vec4(playerPos, 1.0)).xyz, 1.0)).xyz;
    if (length(clip.xy) > 0.98) return vec3(1.0);
    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
    float opaque = texture(shadowtex1HW, coord);
    vec3 vis = vec3(opaque);
    #ifdef COLORED_SHADOWS
        float allVis = texture(shadowtex0HW, coord);
        if (allVis < opaque - 0.01) {
            ivec2 texel = ivec2(coord.xy * float(shadowMapResolution));
            if (texelFetch(shadowcolor1, texel, 0).r < 0.5) {
                vec4 glass = texelFetch(shadowcolor0, texel, 0);
                vis = vec3(allVis) + (opaque - allVis) * mix(vec3(1.0), SrgbToLinear(glass.rgb), glass.a);
            }
        }
    #endif
    #if VL_QUALITY >= 2
        vis *= CloudShadow(playerPos + cameraPosition, lightDir);
    #endif
    return vis;
}

// Light scattered towards the camera along the ray to a point (player space).
vec3 MarchLightShafts(vec3 endPos, bool sky, vec3 sunDir, vec3 lightDir, float dither) {
    float endDist = sky ? 1e9 : length(endPos);
    vec3 dir = endPos / max(length(endPos), 1e-4);
    float VdotL = dot(dir, lightDir);

    if (isEyeInWater == 1) {
        // Under water: scattering by the water itself, with absorption along the way.
        float dist = min(endDist, VL_MAX_DIST_WATER);
        float stepLen = dist / float(VL_STEPS);
        vec3 L = ShadowLightDir();
        vec3 sum = vec3(0.0);
        for (int i = 0; i < VL_STEPS; i++) {
            float t = (float(i) + dither) * stepLen;
            vec3 p = dir * t;
            vec3 clip = (shadowProjection * vec4((shadowModelView * vec4(p, 1.0)).xyz, 1.0)).xyz;
            if (length(clip.xy) > 0.98) continue;
            vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
            float vis = texture(shadowtex1HW, coord);
            if (vis <= 0.0) continue;
            // Path of the light through the water down to this point.
            float surfaceDepth = texture(shadowtex0, coord.xy).r;
            float path = max(ShadowDepthToBlocks(coord.z - surfaceDepth), 0.0);
            vec3 light = UnderwaterLight(path, (p + cameraPosition).xz + L.xz * path, 1.0);
            sum += vis * light * exp(-t * WaterAbsorption());
        }
        float phase = 0.6 + 1.4 * HG(VdotL, 0.6) * 0.25;
        vec3 waterTint = vec3(UNDERWATER_COLOR_R, UNDERWATER_COLOR_G, UNDERWATER_COLOR_B) * vec3(0.35, 0.75, 0.85);
        return sum * stepLen * 0.012 * phase * waterTint * SunLightColor(sunDir.y) * VL_STRENGTH;
    }

    float dist = min(endDist, VL_MAX_DIST);
    float stepLen = dist / float(VL_STEPS);
    vec3 sum = vec3(0.0);
    for (int i = 0; i < VL_STEPS; i++) {
        float t = (float(i) + dither) * stepLen;
        vec3 p = dir * t;
        // Haze is thicker low down: densest around sea level, thinning with height.
        float y = p.y + cameraPosition.y;
        float density = exp(-max(y - 63.0, 0.0) / 60.0) * (1.0 + rainStrength);
        sum += ShaftVisibility(p, lightDir) * density;
    }
    // Forward scattering towards the sun, plus a little all around.
    float phase = 0.15 + HG(VdotL, 0.75) * 0.06;
    return sum * stepLen * 0.0035 * phase * SunLightColor(sunDir.y) * LightShaftStrength(sunDir);
}

#endif
