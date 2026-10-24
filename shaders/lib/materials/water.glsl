// Water: textureless, biome-tinted, smooth procedural waves, screen-space reflections of
// the scene with a sky fallback, a soft sun/moon glint, and depth-based opacity.
// Needs: sky.glsl, lighting.glsl (+ shadows.glsl outside the Nether), fog.glsl,
// space.glsl, translucent.glsl, ssr.glsl.

uniform sampler2D noisetex;

const int noiseTextureResolution = 256;

// Smooth value noise from the noise texture (cubic interpolation: no faceted ridges).
float SmoothNoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    ivec2 c = ivec2(mod(i, float(noiseTextureResolution)));
    ivec2 c1 = ivec2(mod(i + 1.0, float(noiseTextureResolution)));
    float a = texelFetch(noisetex, c, 0).r;
    float b = texelFetch(noisetex, ivec2(c1.x, c.y), 0).r;
    float d = texelFetch(noisetex, ivec2(c.x, c1.y), 0).r;
    float e = texelFetch(noisetex, c1, 0).r;
    return mix(mix(a, b, u.x), mix(d, e, u.x), u.y);
}

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

TranslucentSurface ShadeWater(vec3 biomeTint, vec3 playerPos, vec3 geoNormal, Surface surf, vec3 sunDir, vec3 lightDir) {
    vec3 worldPos = playerPos + cameraPosition;
    float dist = length(playerPos);
    vec3 V = -playerPos / max(dist, 1e-4);

    // Waves only on upward faces; gentler with distance.
    vec3 N = geoNormal;
    float detail = 1.0 - smoothstep(12.0, 48.0, dist);
    if (geoNormal.y > 0.5) N = WaveNormal(worldPos.xz, WATER_WAVE_STRENGTH * 0.22 / (1.0 + dist * 0.01), detail);

    // Deep water colour: dark, biome-tinted navy; lit like everything else.
    vec3 waterColor = mix(vec3(0.006, 0.030, 0.055), SrgbToLinear(biomeTint) * 0.07, 0.4);
    vec3 scatter = waterColor * GetLighting(surf, sunDir, lightDir);

    // Opacity from the water depth along the view ray (both distances from the depth
    // buffer, so they agree exactly).
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float behindDist = length(ScreenToView(uv, texture(depthtex1, uv).r));
    float surfaceDist = length(ScreenToView(uv, gl_FragCoord.z));
    float thickness = max(behindDist - surfaceDist, 0.0);
    float opacity = 1.0 - exp(-thickness * 0.22 * WATER_FOG_MULT);
    opacity = mix(0.12, 1.0, opacity);

    if (isEyeInWater == 1) {
        // Seen from below: see-through (M3 adds total internal reflection and refraction).
        return PlainSurface(scatter, 0.25);
    }

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
    // How much sky one pixel's reflection covers: stars are spread over it (prefiltered),
    // so calm water shows crisp stars and wavy water a steady shimmer instead of sparkles.
    float starFootprint = max(length(fwidth(R)), PixelAngle());
    vec3 reflection = GetSkyReflection(R, sunDir, starFootprint) * skyVis + scatter * (1.0 - skyVis);

    #if WATER_REFLECTIONS == 1
        if (geoNormal.y > 0.5 && fresnel > 0.03) {
            vec3 viewPos = ScreenToView(uv, gl_FragCoord.z);
            vec3 viewR = normalize(mat3(gbufferModelView) * R);
            vec4 ssr = TraceSSR(viewPos, viewR, SSRDither());
            reflection = mix(reflection, ssr.rgb, ssr.a);
        }
    #endif

    float roughness = 0.08 + dist * 0.0015;
    reflection += SunLightColor(sunDir.y) * GGXSpecular(N, V, lightDir, roughness) / max(fresnel, 0.02)
                * skyVis * skyVis * (1.0 - rainStrength);

    float alpha = mix(opacity, 1.0, fresnel);
    vec3 color = (scatter * opacity * (1.0 - fresnel) + reflection * fresnel) / max(alpha, 1e-4);
    return PlainSurface(color, alpha);
}
