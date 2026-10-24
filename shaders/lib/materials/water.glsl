// Interim water (pulled forward from M3): textureless, biome-coloured, procedural waves,
// Fresnel sky reflection with a soft sun/moon glint, and per-channel absorption by depth.
// Screen-space reflections and refraction come with the full water pass in M3.
// Output is order-independent (additive light + multiplicative transmittance).
// Needs: sky.glsl, lighting.glsl (+ shadows.glsl outside the Nether), basicFog.glsl, space.glsl.

uniform sampler2D noisetex;
uniform sampler2D depthtex1; // opaque depth (without translucents)

const int noiseTextureResolution = 256;

float WaveNoise(vec2 p) { return texture(noisetex, p / float(noiseTextureResolution)).r; }

// Sum of drifting value-noise octaves, in blocks. `detail` fades the small octaves out
// with distance, so distant water does not alias into sparkles.
float WaveHeight(vec2 p, float detail) {
    float t = frameTimeCounter;
    float h = 0.0;
    h += WaveNoise(p * 0.45 + vec2( 0.50,  0.18) * t) * 0.50;
    h += WaveNoise(p * 0.95 + vec2(-0.32,  0.55) * t) * 0.28;
    h += WaveNoise(p * 2.10 + vec2( 0.75, -0.40) * t) * 0.12 * detail;
    h += WaveNoise(p * 4.30 + vec2(-0.85, -0.65) * t) * 0.05 * detail;
    return h;
}

vec3 WaveNormal(vec2 p, float strength, float detail) {
    const float e = 0.05;
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

TranslucentOut ShadeWater(vec3 biomeTint, vec3 playerPos, vec3 geoNormal, Surface surf, vec3 sunDir, vec3 lightDir) {
    TranslucentOut o;
    vec3 worldPos = playerPos + cameraPosition;
    float dist = length(playerPos);
    vec3 V = -playerPos / max(dist, 1e-4);

    // Waves only on upward faces; weaker and smoother with distance.
    vec3 N = geoNormal;
    float detail = 1.0 - smoothstep(16.0, 64.0, dist);
    if (geoNormal.y > 0.5) N = WaveNormal(worldPos.xz, 0.30 / (1.0 + dist * 0.015), detail);

    // Water colour: biome tint pulled towards Unbound-style teal; lit like everything else.
    vec3 waterColor = mix(vec3(0.020, 0.110, 0.140), SrgbToLinear(biomeTint) * 0.18, 0.45);
    vec3 scatter = waterColor * GetLighting(surf, sunDir, lightDir);

    // Per-channel absorption through the water between this surface and what is behind it.
    // Both distances come from the depth buffer, so they agree exactly (view bobbing included).
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float behindDist = length(ScreenToView(uv, texture(depthtex1, uv).r));
    float surfaceDist = length(ScreenToView(uv, gl_FragCoord.z));
    float thickness = isEyeInWater == 1 ? 0.0 : max(behindDist - surfaceDist, 0.0);
    vec3 transmit = exp(-thickness * vec3(0.32, 0.10, 0.075));
    float opacity = 1.0 - dot(transmit, vec3(0.333));

    if (isEyeInWater == 1) {
        // Seen from below: mostly see-through, no sky reflection (M3 adds total internal reflection).
        o.light = scatter * 0.3;
        o.transmit = vec3(0.75);
        return o;
    }

    float fresnel = 0.02 + 0.98 * pow(1.0 - saturate(dot(N, V)), 5.0);

    // Something translucent (ice, glass) directly above: no sky reflection or glint.
    float open = 1.0;
    #ifndef WORLD_NETHER
        open = 1.0 - TranslucentCoverAbove(playerPos);
    #endif

    vec3 R = reflect(-V, N);
    R.y = max(R.y, 0.02); // never reflect the ground below the horizon
    float skyVis = surf.lm.y * surf.lm.y * open;
    vec3 reflection = GetSky(normalize(R), sunDir, true) * skyVis + scatter * (1.0 - skyVis);

    float roughness = 0.07 + dist * 0.0015;
    reflection += SunLightColor(sunDir.y) * GGXSpecular(N, V, lightDir, roughness) / max(fresnel, 0.02)
                * skyVis * skyVis * (1.0 - rainStrength);

    o.light = scatter * opacity * (1.0 - fresnel) + reflection * fresnel;
    o.transmit = transmit * (1.0 - fresnel);
    return o;
}
