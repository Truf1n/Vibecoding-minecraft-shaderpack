// Interim water (pulled forward from M3): procedural wave normals, Fresnel sky
// reflection with a sun/moon glint, and depth-based absorption. Screen-space
// reflections and refraction come with the full water pass in M3.
// Runs in gbuffers_water; needs sky.glsl, basicLighting.glsl, basicFog.glsl, space.glsl.

uniform sampler2D noisetex;
uniform sampler2D depthtex1; // opaque depth (without translucents)

const int noiseTextureResolution = 256;

float WaveNoise(vec2 p) { return texture(noisetex, p / float(noiseTextureResolution)).r; }

// Sum of drifting value-noise octaves, in blocks.
float WaveHeight(vec2 p) {
    float t = frameTimeCounter;
    float h = 0.0;
    h += WaveNoise(p * 0.55 + vec2( 0.55,  0.20) * t) * 0.45;
    h += WaveNoise(p * 1.10 + vec2(-0.35,  0.60) * t) * 0.25;
    h += WaveNoise(p * 2.30 + vec2( 0.80, -0.45) * t) * 0.12;
    h += WaveNoise(p * 4.70 + vec2(-0.90, -0.70) * t) * 0.06;
    return h;
}

vec3 WaveNormal(vec2 p, float strength) {
    const float e = 0.04;
    float h0 = WaveHeight(p);
    float hx = WaveHeight(p + vec2(e, 0.0));
    float hz = WaveHeight(p + vec2(0.0, e));
    return normalize(vec3((h0 - hx) / e * strength, 1.0, (h0 - hz) / e * strength));
}

vec4 ShadeWater(vec4 albedo, vec3 playerPos, vec3 geoNormal, vec2 lm, vec3 sunDir, vec3 lightDir) {
    vec3 worldPos = playerPos + cameraPosition;
    float dist = length(playerPos);
    vec3 V = -playerPos / max(dist, 1e-4);

    // Waves only on upward faces; fade with distance to avoid shimmering.
    vec3 N = geoNormal;
    if (geoNormal.y > 0.5) N = WaveNormal(worldPos.xz, 0.35 / (1.0 + dist * 0.02));

    // Water colour from the (biome-tinted) texture, darkened; lit like everything else.
    vec3 tint = SrgbToLinear(albedo.rgb);
    vec3 bodyLight = GetBasicLighting(lm, 0.5, 1.0, false, sunDir);
    vec3 body = tint * vec3(0.15, 0.30, 0.32) * bodyLight;

    // Thickness of water between this surface and the opaque geometry behind it.
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    float behindDist = length(ScreenToView(uv, texture(depthtex1, uv).r));
    float thickness = max(behindDist - dist, 0.0);
    float bodyAlpha = 1.0 - exp(-thickness * 0.35);
    bodyAlpha = mix(0.25, 1.0, bodyAlpha);

    if (isEyeInWater == 1) {
        // Seen from below: no sky reflection, mostly see-through.
        return vec4(ApplyFog(body, playerPos, sunDir, false), 0.35);
    }

    float NdotV = saturate(dot(N, V));
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

    vec3 R = reflect(-V, N);
    R.y = max(R.y, 0.02); // never reflect the ground below the horizon
    float skyVis = lm.y * lm.y;
    vec3 reflection = GetSky(normalize(R), sunDir, true) * skyVis + body * (1.0 - skyVis);

    // Sun/moon glint (normalized Blinn-Phong), only where the sky is visible.
    vec3 H = normalize(lightDir + V);
    float spec = pow(saturate(dot(N, H)), 900.0) * 120.0;
    reflection += SunLightColor(sunDir.y) * spec * skyVis * skyVis * (1.0 - rainStrength);

    float alpha = mix(bodyAlpha, 1.0, fresnel);
    vec3 color = (body * bodyAlpha * (1.0 - fresnel) + reflection * fresnel) / max(alpha, 1e-4);
    return vec4(ApplyFog(color, playerPos, sunDir, false), alpha);
}
