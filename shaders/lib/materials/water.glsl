// Water: textureless, biome-tinted, smooth procedural waves, screen-space reflections of
// the scene with a sky fallback, a soft sun/moon glint, and depth-based opacity.
// Needs: sky.glsl, lighting.glsl (+ shadows.glsl outside the Nether), fog.glsl,
// space.glsl, translucent.glsl, ssr.glsl, caustics.glsl (which brings waves.glsl).

// How open the water is at this pixel ("fetch", columnMaps.glsl): from the vertex shader
// (it changes only from block to block), or worked out here where that has none (-1).
float vertexWaterFetch = -1.0;

// GGX specular (normalized). Roughness grows with distance so the glint stays a few
// pixels wide instead of single flickering pixels.
float GGXSpecular(vec3 N, vec3 V, vec3 L, float roughness) {
    vec3 H = normalize(L + V);
    float NdotH = saturate(dot(N, H));
    float a2 = roughness * roughness * roughness * roughness;
    float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
    float D = a2 / (PI * d * d);
    float F = 0.02 + 0.98 * pow(1.0 - saturate(dot(H, V)), 5.0);
    return min(D * F * 0.25, 40.0) * saturate(dot(N, L));
}

// Biome-styled (waterStyles.glsl), user-adjustable colour of light scattered inside the
// water, still nudged by the biome tint itself (modded colours carry through).
vec3 WaterScatterColor(WaterStyle style, vec3 biomeTint) {
    vec3 c = mix(style.scatter, SrgbToLinear(biomeTint) * 0.07, 0.3);
    return c * vec3(WATER_COLOR_R, WATER_COLOR_G, WATER_COLOR_B);
}

// Screen-space offset that bends the view ray through a wave normal, scaled by how much
// water there is to bend through.
vec2 RefractionOffset(vec3 N, vec3 viewPos, float thickness) {
    vec3 offView = mat3(gbufferModelView) * vec3(N.x, 0.0, N.z);
    float amount = 0.45 * float(WATER_REFRACTION) / 100.0 * saturate(thickness * 0.5);
    return vec2(offView.x * gbufferProjection[0][0], offView.y * gbufferProjection[1][1]) * 0.5 * amount / max(-viewPos.z, 1.0);
}

// Underwater view of a source block's surface sitting in the thin gap right under a block
// (the vanilla surface is 1/9 block below the top of its block space):
#define SURFACE_OPEN        0 // open water: the normal surface
#define SURFACE_FILLED      1 // drawn as if the water filled its block up to the top
#define SURFACE_FLAT        2 // a calm surface, otherwise like open water
int UnderBlockState(vec3 worldPos) {
    float cellTop = floor(worldPos.y - 0.5) + 1.0; // surface is at 8/9 (lowered by waving)
    vec3 above = vec3(worldPos.x, cellTop + 0.5, worldPos.z);
    if (HasCeiling(above)) {
        // Solid block on top: filled if the view ray ends in the gap (on the block's
        // underside or a wall poking into the gap), flat where it slips out sideways.
        float depth = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;
        if (depth >= 1.0) return SURFACE_FLAT;
        float hitY = ViewToPlayer(ScreenToView(gl_FragCoord.xy / vec2(viewWidth, viewHeight), depth)).y + cameraPosition.y;
        return hitY < cellTop + 0.03 ? SURFACE_FILLED : SURFACE_FLAT;
    }
    if (HasGlassCeiling(above)) {
        // Glass sunk in water: the water goes on around and above it, so there is no
        // surface here. Glass at the top of the water: this is the real surface, calm
        // under the glass (the glass itself shows as a tint, see gbuffers_forward.glsl).
        return WaterAboveGlassStack(above) ? SURFACE_FILLED : SURFACE_FLAT;
    }
    return SURFACE_OPEN;
}

// Water is drawn opaque: it samples the opaque scene behind it (colortex7) itself, so it
// can refract it and absorb light per colour channel.
TranslucentSurface ShadeWater(vec3 biomeTint, bool sourceBlock, vec3 playerPos, vec3 geoNormal, Surface surf, vec3 sunDir, vec3 lightDir) {
    vec3 worldPos = playerPos + cameraPosition;
    float dist = length(playerPos);
    vec3 V = -EyeDir(playerPos);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 viewPos = ScreenToView(uv, gl_FragCoord.z);
    float surfaceDist = length(viewPos);

    // Normal of the face towards the camera (the surface can be seen from either side),
    // with waves on horizontal faces; gentler with distance.
    vec3 faceN = dot(geoNormal, V) >= 0.0 ? geoNormal : -geoNormal;
    vec3 N = faceN;
    float detail = 1.0 - smoothstep(12.0, 48.0, dist);
    float waveRoughness = 0.0;
    if (abs(geoNormal.y) > 0.5) {
        // The wave field (waves.glsl): wind sea, ripples and swell from the world state,
        // calm where no wind reaches (sky light low: caves, under roofs) and on small ponds.
        float shelter = smoothstep(0.35, 0.85, surf.lm.y);
        float fetch = vertexWaterFetch >= 0.0 ? vertexWaterFetch : WaterFetch(worldPos);
        WaveConditions conditions = GetWaveConditions(shelter, fetch, GustAt(worldPos.xz));
        float footprint = dist * PixelAngle();
        WaveSample waves = Waves(worldPos.xz, conditions, footprint, false);
        vec2 slope = waves.slope;
        waveRoughness = sqrt(waves.unresolvedSlope2);
        #if defined RAIN_RIPPLES && defined WORLD_OVERWORLD
            // Raindrops hitting the surface: their rings add onto the waves.
            float rain = VisibleRain() * smoothstep(0.86, 0.96, surf.lm.y) * (1.0 - inSnowyBiome) * (1.0 - inDryBiome) * detail;
            if (rain > 0.0) slope += RainRipples(worldPos.xz) * rain;
        #endif
        #ifdef INTERACTIVE_RIPPLES
            slope += RippleSlope(worldPos.xz); // wakes and rings from swimmers, mobs, boats
        #endif
        N = WaveSurfaceNormal(slope);
        if (faceN.y < 0.0) N = -N;
    }

    WaterStyle style = SurfaceWaterStyle(biomeTint);
    vec3 waterLight = GetLighting(surf, sunDir, lightDir); // (once: the foam below reuses it)
    vec3 scatterLight = WaterScatterColor(style, biomeTint) * waterLight;

    // ---- Seen from below -------------------------------------------------------------
    if (isEyeInWater == 1) {
        // From inside the water only the real water/air surface is drawn: vertical faces and
        // undersides (water against glass and the like) are skipped, and so is a source
        // block's surface sitting in the thin gap right under a solid block, which is
        // treated as if the water filled the block up to the top.
        if (abs(geoNormal.y) < 0.5) discard;
        // The underside of water resting on glass or the like (a downward face on a block
        // boundary) is not a water/air surface either. The surface itself seen from below
        // sits partway up its block.
        float yInBlock = fract(worldPos.y + 0.005);
        if (geoNormal.y < -0.5 && yInBlock < 0.02) discard;
        int state = sourceBlock ? UnderBlockState(worldPos) : SURFACE_OPEN;
        if (state == SURFACE_FILLED) discard;
        if (state != SURFACE_OPEN) N = faceN;

        // Total internal reflection: the surface mirrors the underwater scene.
        vec3 R = reflect(-V, N);
        vec3 mirrored = WaterFogColor(sunDir);
        #if WATER_REFLECTIONS == 1
            vec4 ssr = TraceSSR(viewPos, normalize(mat3(gbufferModelView) * R), normalize(mat3(gbufferModelView) * faceN), SSRDither());
            mirrored = mix(mirrored, ssr.rgb, ssr.a);
        #endif

        // Snell's window: inside the critical angle the world above is visible (bent).
        vec3 T = refract(-V, N, 1.333);
        if (dot(T, T) < 0.01) return PlainSurface(mirrored, 1.0);
        vec2 refrUV = clamp(uv + RefractionOffset(N, viewPos, 2.0), vec2(0.001), vec2(0.999));
        vec3 above = texture(colortex7, refrUV).rgb;
        if (texture(depthtex1, refrUV).r >= 1.0) {
            above = GetSkyFromUnderwater(normalize(T), sunDir);
            #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
                vec4 clouds = CloudsInDirection(normalize(T));
                above = above * clouds.a + clouds.rgb;
            #endif
        }
        float transmit = 1.0 - pow(1.0 - saturate(dot(N, V)), 5.0);
        return PlainSurface(mix(mirrored, above, transmit), 1.0);
    }

    // ---- Refraction and absorption ---------------------------------------------------
    float behindDist = length(ScreenToView(uv, texture(depthtex1, uv).r));
    float thickness = max(behindDist - surfaceDist, 0.0);

    vec2 refrUV = uv;
    #if WATER_REFRACTION > 0
        refrUV = clamp(uv + RefractionOffset(N, viewPos, thickness), vec2(0.001), vec2(0.999));
        // Don't pull in things that are in front of the water (shore above the surface).
        float refrDepth = texture(depthtex1, refrUV).r;
        if (length(ScreenToView(refrUV, refrDepth)) < surfaceDist) refrUV = uv;
    #endif
    float refrDist = length(ScreenToView(refrUV, texture(depthtex1, refrUV).r));
    float refrThickness = max(refrDist - surfaceDist, 0.0);

    vec3 transmittance = exp(-refrThickness * style.absorption * WATER_FOG_MULT);
    vec3 behind = texture(colortex7, refrUV).rgb;
    float inScatter = 1.0 - dot(transmittance, vec3(0.2126, 0.7152, 0.0722));
    vec3 body = behind * transmittance + scatterLight * inScatter;

    // Foam where the water is very shallow (shorelines, around blocks).
    #if WATER_FOAM > 0
        float verticalDepth = thickness * abs(V.y);
        float foamMask = 1.0 - smoothstep(0.05, 0.45, verticalDepth);
        if (foamMask > 0.0) {
            float t = wsJet.z * WATER_WAVE_SPEED * 0.3;
            float foamNoise = SmoothNoise(worldPos.xz * 3.0 + vec2(t * 0.6, -t * 0.4));
            foamNoise *= SmoothNoise(worldPos.xz * 5.5 - vec2(t * 0.3, t * 0.5) + 31.0);
            float foam = smoothstep(0.15, 0.45, foamNoise * foamMask * 1.6) * float(WATER_FOAM) * 0.5;
            body = mix(body, vec3(0.85, 0.92, 0.95) * waterLight * 0.55, saturate(foam));
        }
    #endif

    // ---- Reflection ----------------------------------------------------------------
    float fresnel = 0.02 + 0.98 * pow(1.0 - saturate(dot(N, V)), 5.0);

    // Something translucent (ice, glass) directly above: no sky reflection or glint.
    float open = 1.0;
    #ifndef WORLD_NETHER
        open = 1.0 - TranslucentCoverAbove(playerPos);
    #endif
    float skyVis = surf.lm.y * surf.lm.y * open;

    vec3 R = reflect(-V, N);
    R.y = max(R.y, 0.02); // never reflect the ground below the horizon
    R = normalize(R);
    // How much sky one pixel's reflection covers: stars are spread over it (prefiltered).
    float starFootprint = max(length(fwidth(R)), PixelAngle());
    vec3 skyReflection = GetSkyReflection(R, sunDir, starFootprint);
    #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
        // Clouds, looked up where the reflected direction is on screen.
        // (Bicubic up close; bilinear on distant water, where the waves blur it anyway.)
        vec4 clouds = dist < 32.0 ? CloudsInDirection(R) : CloudsInDirectionFast(R);
        skyReflection = skyReflection * clouds.a + clouds.rgb;
    #endif
    // Rough water blurs what it mirrors: lean a little towards the average sky (only a
    // little: at a distance the reflection is still mostly the sky and clouds themselves,
    // smeared, not a flat colour).
    skyReflection = mix(skyReflection, SkyAmbientColor(sunDir.y) * 1.3, saturate(waveRoughness * 1.5) * 0.3);
    vec3 reflection = skyReflection * skyVis + scatterLight * (1.0 - skyVis);

    #if WATER_REFLECTIONS == 1
        if (geoNormal.y > 0.5 && fresnel > 0.03) {
            vec3 viewR = normalize(mat3(gbufferModelView) * R);
            vec4 ssr = TraceSSR(viewPos, viewR, normalize(mat3(gbufferModelView) * geoNormal), SSRDither());
            reflection = mix(reflection, ssr.rgb, ssr.a);
        }
    #endif

    // The glint widens with distance and with the waves too small to draw (Q17): calm ponds
    // give a sharp sun, a choppy sea a wide glitter.
    float roughness = 0.08 + dist * 0.0015 + waveRoughness * 2.0;
    vec3 glint = SunLightColor(sunDir.y) * GGXSpecular(N, V, lightDir, roughness) * skyVis * skyVis * (1.0 - rainStrength);
    #ifdef COLORED_LIGHTING
        // Block-light glints (Q7): torches, lanterns and lava shine on the water, in their
        // colour, from the direction their light comes from (light volume).
        if (surf.lm.x > 0.05) {
            vec4 from = BlocklightDirection(playerPos, vec3(0.0, 1.0, 0.0));
            vec3 blockColor = WorldBlocklightColor(playerPos, vec3(0.0, 1.0, 0.0), surf.lm.x) * BlocklightFalloff(surf.lm.x) * BLOCKLIGHT_I;
            glint += blockColor * GGXSpecular(N, V, from.xyz, roughness + 0.08) * from.w * 0.25;
        }
    #endif

    return PlainSurface(mix(body, reflection, fresnel) + glint, 1.0);
}
