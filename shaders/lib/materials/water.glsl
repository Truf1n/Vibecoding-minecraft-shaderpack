// Water: textureless, biome-tinted, smooth procedural waves, screen-space reflections of
// the scene with a sky fallback, a soft sun/moon glint, and depth-based opacity.
// Needs: sky.glsl, lighting.glsl (+ shadows.glsl outside the Nether), fog.glsl,
// space.glsl, translucent.glsl, ssr.glsl, caustics.glsl.

// Wave height in blocks: a few drifting octaves, large swells first. `detail` fades the
// small ripples out with distance so far water does not alias.
float WaveHeight(vec2 p, float detail) {
    float t = frameTimeCounter * WATER_WAVE_SPEED;
    vec2 q = p / WATER_WAVE_SIZE;
    float h = 0.0;
    h += SmoothNoise(q * 0.35 + vec2( 0.42,  0.15) * t) * 0.55;
    h += SmoothNoise(mat2(0.8, -0.6, 0.6, 0.8) * q * 0.75 + vec2(-0.25,  0.48) * t) * 0.28;
    h += SmoothNoise(mat2(0.6, 0.8, -0.8, 0.6) * q * 1.6  + vec2( 0.62, -0.31) * t) * 0.12 * detail;
    h += SmoothNoise(q * 3.3 + vec2(-0.70, -0.55) * t) * 0.05 * detail;
    return h;
}

vec3 WaveNormal(vec2 p, float strength, float detail) {
    const float e = 0.06;
    float h0 = WaveHeight(p, detail);
    float hx = WaveHeight(p + vec2(e, 0.0), detail);
    float hz = WaveHeight(p + vec2(0.0, e), detail);
    return normalize(vec3((h0 - hx) / e * strength, 1.0, (h0 - hz) / e * strength));
}

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

// Biome-tinted, user-adjustable colour of light scattered inside the water.
vec3 WaterScatterColor(vec3 biomeTint) {
    vec3 c = mix(vec3(0.006, 0.030, 0.055), SrgbToLinear(biomeTint) * 0.07, 0.4);
    return c * vec3(WATER_COLOR_R, WATER_COLOR_G, WATER_COLOR_B);
}

// Screen-space offset that bends the view ray through a wave normal, scaled by how much
// water there is to bend through.
vec2 RefractionOffset(vec3 N, vec3 viewPos, float thickness) {
    vec3 offView = mat3(gbufferModelView) * vec3(N.x, 0.0, N.z);
    float amount = 0.45 * float(WATER_REFRACTION) / 100.0 * saturate(thickness * 0.5);
    return vec2(offView.x * gbufferProjection[0][0], offView.y * gbufferProjection[1][1]) * 0.5 * amount / max(-viewPos.z, 1.0);
}

uniform sampler2D colortex2; // G-buffer normals of the opaque scene
uniform sampler2D colortex3; // G-buffer material: b = dry waterloggable block

// Seen from below: does the view ray through this surface point hit the underside of a
// block flush with the top of the water's block space (the vanilla water surface sits
// 1/9 block lower, leaving a gap)? Rays that leave the gap sideways, or that hit the
// side of a block poking out of the water, see a real water/air surface instead.
// Partial blocks that could be waterlogged but aren't (stairs, slabs, ...) keep the air gap.
bool IsUnderBlock(vec3 worldPos) {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    float depth = texelFetch(depthtex1, pixel, 0).r;
    if (depth >= 1.0) return false;
    vec3 hitPos = ViewToPlayer(ScreenToView(gl_FragCoord.xy / vec2(viewWidth, viewHeight), depth)) + cameraPosition;
    vec3 hitNormal = DecodeNormal(texelFetch(colortex2, pixel, 0).xy);
    float cellTop = floor(worldPos.y - 0.5) + 1.0; // surface is at 8/9 (lowered by waving)
    return hitNormal.y < -0.5 && abs(hitPos.y - cellTop) < 0.03
        && texelFetch(colortex3, pixel, 0).b < 0.5;
}

// Water is drawn opaque: it samples the opaque scene behind it (colortex7) itself, so it
// can refract it and absorb light per colour channel.
TranslucentSurface ShadeWater(vec3 biomeTint, bool sourceBlock, vec3 playerPos, vec3 geoNormal, Surface surf, vec3 sunDir, vec3 lightDir) {
    vec3 worldPos = playerPos + cameraPosition;
    float dist = length(playerPos);
    vec3 V = -playerPos / max(dist, 1e-4);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 viewPos = ScreenToView(uv, gl_FragCoord.z);
    float surfaceDist = length(viewPos);

    // Normal of the face towards the camera (the surface can be seen from either side),
    // with waves on horizontal faces; gentler with distance.
    vec3 faceN = dot(geoNormal, V) >= 0.0 ? geoNormal : -geoNormal;
    vec3 N = faceN;
    float detail = 1.0 - smoothstep(12.0, 48.0, dist);
    if (abs(geoNormal.y) > 0.5) {
        N = WaveNormal(worldPos.xz, WATER_WAVE_STRENGTH * 0.22 / (1.0 + dist * 0.01), detail);
        if (faceN.y < 0.0) N = -N;
    }

    vec3 scatterLight = WaterScatterColor(biomeTint) * GetLighting(surf, sunDir, lightDir);

    // ---- Seen from below -------------------------------------------------------------
    if (isEyeInWater == 1) {
        // From inside the water only the real water/air surface is drawn: vertical faces
        // (water against glass and the like) are skipped, and so is a source block's
        // surface sitting in the thin gap right under a block, which is treated as if the
        // water filled the block up to the top.
        if (abs(geoNormal.y) < 0.5) discard;
        if (sourceBlock && IsUnderBlock(worldPos)) discard;

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
        if (texture(depthtex1, refrUV).r >= 1.0) above = GetSky(normalize(T), sunDir, -1.0);
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

    vec3 transmittance = exp(-refrThickness * WaterAbsorption());
    vec3 behind = texture(colortex7, refrUV).rgb;
    float inScatter = 1.0 - dot(transmittance, vec3(0.2126, 0.7152, 0.0722));
    vec3 body = behind * transmittance + scatterLight * inScatter;

    // Foam where the water is very shallow (shorelines, around blocks).
    #if WATER_FOAM > 0
        float verticalDepth = thickness * abs(V.y);
        float foamMask = 1.0 - smoothstep(0.05, 0.45, verticalDepth);
        if (foamMask > 0.0) {
            float t = frameTimeCounter * WATER_WAVE_SPEED;
            float foamNoise = SmoothNoise(worldPos.xz * 3.0 + vec2(t * 0.6, -t * 0.4));
            foamNoise *= SmoothNoise(worldPos.xz * 5.5 - vec2(t * 0.3, t * 0.5) + 31.0);
            float foam = smoothstep(0.15, 0.45, foamNoise * foamMask * 1.6) * float(WATER_FOAM) * 0.5;
            body = mix(body, vec3(0.85, 0.92, 0.95) * GetLighting(surf, sunDir, lightDir) * 0.55, saturate(foam));
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
    vec3 reflection = GetSkyReflection(R, sunDir, starFootprint) * skyVis + scatterLight * (1.0 - skyVis);

    #if WATER_REFLECTIONS == 1
        if (geoNormal.y > 0.5 && fresnel > 0.03) {
            vec3 viewR = normalize(mat3(gbufferModelView) * R);
            vec4 ssr = TraceSSR(viewPos, viewR, normalize(mat3(gbufferModelView) * geoNormal), SSRDither());
            reflection = mix(reflection, ssr.rgb, ssr.a);
        }
    #endif

    float roughness = 0.08 + dist * 0.0015;
    vec3 glint = SunLightColor(sunDir.y) * GGXSpecular(N, V, lightDir, roughness) * skyVis * skyVis * (1.0 - rainStrength);

    return PlainSurface(mix(body, reflection, fresnel) + glint, 1.0);
}
