#ifndef LIGHT_SHAFTS_GLSL
#define LIGHT_SHAFTS_GLSL

// Light shafts and the air march (plan items F5, F8; W5): light scattered towards the
// camera by the air along the view ray - haze, mist, glowing air around light sources -
// wherever the shadow map (and the clouds) let the sun through. Marched at half resolution
// in composite with per-pixel, per-frame random offsets, accumulated over frames there.
// Under water the shafts take the water's colour, fade with depth and carry the caustics.
// Needs: common.glsl, sky.glsl, shadowSpace.glsl, shadows.glsl, clouds.glsl, air.glsl,
// coloredLight.glsl (Light Fog), blockIds.glsl.

#if VL_QUALITY == 1
    const int VL_STEPS = 8;
#elif VL_QUALITY == 2
    const int VL_STEPS = 12;
#else
    const int VL_STEPS = 18;
#endif

const float VL_MAX_DIST_SKY = 320.0;  // blocks marched in air
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

// Light the water itself scatters towards the camera at a point under water (shadow-map
// path through the water, caustics), before the absorption on the way to the camera.
vec3 UnderwaterScatter(vec3 p, vec3 L) {
    vec3 clip = (shadowProjection * vec4((shadowModelView * vec4(p, 1.0)).xyz, 1.0)).xyz;
    if (length(clip.xy) > 0.98) return vec3(0.0);
    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
    float vis = texture(shadowtex1HW, coord);
    if (vis <= 0.0) return vec3(0.0);
    float surfaceDepth = texture(shadowtex0, coord.xy).r;
    float path = max(ShadowDepthToBlocks(coord.z - surfaceDepth), 0.0);
    return vis * UnderwaterLight(path, (p + cameraPosition).xz + L.xz * path / 1.333, 1.0);
}

// The water's own colour for its scattered light (the default look gives about (0.35, 0.75, 0.85)).
vec3 UnderwaterScatterTint() {
    return vec3(UNDERWATER_COLOR_R, UNDERWATER_COLOR_G, UNDERWATER_COLOR_B) * CameraWaterStyle().fogColor * vec3(35.0, 15.0, 12.0);
}

// The air march (W5, docs/WORLD_MODEL.md system G; plan items F5, F8, Q6, Q19, Q24): the
// light scattered towards the camera along the view ray to a point (player space), by
// everything the air holds:
//   - haze (thicker low down) and mist (air.glsl), lit by the sun where the shadow map and
//     the clouds let it through: light shafts, also through gaps between leaves and, far
//     out over the land, from gaps in the clouds;
//   - glowing haze around light sources, from the light volume (Light Fog);
//   - the air lit up by lightning;
//   - looking into water from above: the shafts under the surface, faintly.
// Mist dims what lies behind it along the way. Steps are packed closer near the camera;
// the march is accumulated over frames (program/lightShafts.glsl), so few steps suffice.
vec3 MarchLightShafts(vec3 endPos, bool sky, vec3 sunDir, vec3 lightDir, float dither) {
    // Marched from the eye (view bobbing moves it off the origin, see EyePlayerPos).
    vec3 eye = EyePlayerPos();
    float endDist = sky ? 1e9 : length(endPos - eye);
    vec3 dir = normalize(endPos - eye);
    float VdotL = dot(dir, lightDir);

    if (isEyeInWater == 1) {
        // Under water: scattering by the water itself, with absorption along the way.
        float dist = min(endDist, VL_MAX_DIST_WATER);
        float stepLen = dist / float(VL_STEPS);
        vec3 L = ShadowLightDir();
        vec3 sum = vec3(0.0);
        for (int i = 0; i < VL_STEPS; i++) {
            float t = (float(i) + dither) * stepLen;
            sum += UnderwaterScatter(eye + dir * t, L) * exp(-t * WaterAbsorption());
        }
        float phase = 0.6 + 1.4 * HG(VdotL, 0.6) * 0.25;
        return sum * stepLen * 0.012 * phase * UnderwaterScatterTint() * SunLightColor(sunDir.y) * VL_STRENGTH;
    }

    // Further than before for the sky and far land: shafts from gaps in the clouds.
    float dist = min(endDist, VL_MAX_DIST_SKY);
    vec3 L = ShadowLightDir();
    vec3 sunColor = SunLightColor(sunDir.y);
    float hazePhase = 0.15 + HG(VdotL, 0.75) * 0.06;
    float mistPhase = 0.35 + 0.5 * HG(VdotL, 0.6);
    float strength = LightShaftStrength(sunDir);

    // Early outs (P2): deep underground the sun's light cannot reach the air around the
    // camera (skip the shadow-map and cloud-shadow lookups of every step); with no mist,
    // no light fog, no lightning and no water either, there is nothing to march at all.
    bool sunActive = caveFactor < 0.98 && strength * Luminance(sunColor) > 1e-4;
    bool glowActive = false;
    #ifdef COLORED_LIGHTING
        glowActive = LIGHT_FOG > 0.0;
    #endif
    bool otherActive = wsMist.x > 0.001 || lightningBoltPosition.w > 0.5 || glowActive;
    #if defined WATER_SHAFTS_FROM_ABOVE && !defined WORLD_NETHER
        otherActive = otherActive || !sky;
    #endif
    if (!sunActive && !otherActive) return vec3(0.0);

    vec3 sum = vec3(0.0);
    float mistDepth = 0.0;   // mist passed so far (optical depth)
    float waterTravel = 0.0; // blocks of water passed so far (looking in from above)
    float tPrev = 0.0;
    for (int i = 0; i < VL_STEPS; i++) {
        // Quadratic spacing: dense near the camera, sparse far out.
        float x = (float(i) + dither) / float(VL_STEPS);
        float t = x * x * dist;
        float stepLen = 2.0 * x * dist / float(VL_STEPS); // dt/di
        vec3 p = eye + dir * t;
        vec3 worldPos = p + cameraPosition;

        #if defined WATER_SHAFTS_FROM_ABOVE && !defined WORLD_NETHER
            if (ColumnHas(waterCellsSampler, worldPos)) {
                // Under the water surface: the water's own shafts, through the water so far.
                waterTravel += t - tPrev;
                tPrev = t;
                sum += UnderwaterScatter(p, L) * exp(-waterTravel * WaterAbsorption()) * stepLen
                     * (0.012 * 0.5 * (0.6 + 0.35 * HG(VdotL, 0.6))) * UnderwaterScatterTint() * sunColor * VL_STRENGTH;
                continue;
            }
        #endif
        tPrev = t;
        vec3 transmit = exp(-mistDepth) * exp(-waterTravel * WaterAbsorption());

        // Haze, thicker low down: densest around sea level, thinning with height.
        float haze = exp(-max(worldPos.y - 63.0, 0.0) / 60.0) * (1.0 + rainStrength);
        float mist = MistDensity(worldPos);
        mistDepth += mist * stepLen;
        vec3 sunVis = sunActive ? ShaftVisibility(p, lightDir) : vec3(0.0);
        // Beyond the shadow map only the clouds shadow the haze: it counts a little less
        // there (the fog's colour already holds most of the light of distant haze).
        float hazeShare = mix(1.0, 0.6, smoothstep(shadowDistance * 0.8, shadowDistance, t));
        sum += sunVis * sunColor * (haze * hazeShare * 0.0035 * hazePhase * strength + mist * mistPhase * VL_STRENGTH) * transmit * stepLen;

        #ifdef COLORED_LIGHTING
            // Glowing air around light sources (Q6): a little haze everywhere, more in caves
            // and mist, lit by the light volume's block light.
            // Only near the camera (within ~48 blocks): further out the steps are long, and
            // the odd step landing right by a distant torch would count a whole step of its
            // glow (sparkling noise). Each step counts at most 3 blocks of it.
            float glowRange = 1.0 - smoothstep(32.0, 48.0, t);
            if (LIGHT_FOG > 0.0 && glowRange > 0.0) {
                vec3 v = worldPos - vec3(VoxelOrigin());
                vec3 block = VoxelLight(v);
                float peak = max(block.r, max(block.g, block.b));
                if (peak > 0.05) {
                    // A glow in the air hugs its source: far steeper than the light's reach
                    // on surfaces (the volume's light drops by 0.86 per block; to the 6th
                    // power that is ~40% one block away, ~7% at three, ~1% at five).
                    // A little air everywhere, more in caves, some in mist.
                    float glowAir = 0.003 + 0.008 * caveFactor + mist * 0.25;
                    float glow = pow(peak, 6.0) * glowAir * 1.2 * LIGHT_FOG * BLOCKLIGHT_I * glowRange;
                    sum += GradeLightColor(block / peak) * glow * transmit * min(stepLen, 3.0);
                }
            }
        #endif
        #ifdef WORLD_OVERWORLD
            // Lightning lights up the (rainy) air.
            sum += LightningFlashColor() * ((haze * 0.004 + mist) * 0.5) * transmit * stepLen;
        #endif
    }
    return sum;
}

#endif
