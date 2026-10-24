// Lighting model (M1): shadow-mapped sun/moon, sky ambient, blocklight, foliage subsurface.
// Colours come from lib/atmosphere/sky.glsl so lighting matches the sky.
// Needs: common.glsl, sky.glsl, and (outside the Nether) shadowSpace.glsl + shadows.glsl.

vec3 BlocklightColor() { return vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B) * BLOCKLIGHT_I; }

// Dynamic handheld light (plan item L14): vanilla light level minus distance, like vanilla falloff.
float HeldLight(float distToCamera) {
    float level = float(max(heldBlockLightValue, heldBlockLightValue2));
    return saturate((level - distToCamera) / 15.0);
}

// Blocklight falloff: steep near the source, long soft tail (vanilla levels are linear-ish).
float BlocklightFalloff(float lmBlock) {
    float l = lmBlock * lmBlock;
    return l * (0.25 + 0.75 * l) * 1.6;
}

struct Surface {
    vec3 playerPos; // camera-relative world position
    vec3 normal;    // world normal; vec3(0) for camera-facing sprites
    vec2 lm;        // (block, sky) light in [0,1]
    float ao;
    bool foliage;   // two-sided, light passes through
    bool useShadowMap;
};

// Returns the light arriving at the surface; multiply by albedo.
vec3 GetLighting(Surface s, vec3 sunDir, vec3 lightDir) {
    vec3 light = BlocklightColor() * BlocklightFalloff(s.lm.x);

    bool hasNormal = dot(s.normal, s.normal) > 0.5;
    float NdotL = hasNormal ? dot(s.normal, lightDir) : 0.45;
    float diffuse = s.foliage ? 0.35 + 0.65 * abs(NdotL) : saturate(NdotL);
    float upFacing = hasNormal ? 0.75 + 0.25 * s.normal.y : 0.9;

    #if defined WORLD_NETHER
        // Biome-tinted ambient (crimson, warped, ...), from the same colours as the Nether fog.
        vec3 biomeTint = NetherSky();
        biomeTint /= max(max(biomeTint.r, max(biomeTint.g, biomeTint.b)), 0.01);
        light += mix(vec3(0.30, 0.13, 0.07), vec3(0.30, 0.13, 0.07) * 0.5 + biomeTint * 0.15, 0.6) * 0.55 * AMBIENT_MULT;
    #else
        #ifdef WORLD_END
            vec3 directColor = vec3(0.42, 0.34, 0.55) * 0.5;
            vec3 ambientColor = vec3(0.16, 0.12, 0.22) * 0.55;
            float skyGate = 1.0;
        #else
            vec3 directColor = SunLightColor(sunDir.y);
            vec3 ambientColor = SkyAmbientColor(sunDir.y) * 0.85 * s.lm.y * s.lm.y;
            // Sky light gates the sun so it cannot leak into caves the shadow map misses.
            float skyGate = smoothstep(0.05, 0.35, s.lm.y);
        #endif

        // Fallback outside the shadow map (or for the hand): approximate from sky light.
        vec3 sunVis = vec3(pow(s.lm.y, 4.0));
        float thickness = 4.0;
        if (s.useShadowMap && skyGate > 0.0 && (diffuse > 0.0 || s.foliage)) {
            ShadowResult sh = GetShadow(s.playerPos, hasNormal ? s.normal : vec3(0.0), s.foliage);
            sunVis = mix(sunVis, sh.light, sh.coverage);
            thickness = mix(thickness, sh.thickness, sh.coverage);
        }

        light += directColor * diffuse * sunVis * skyGate;
        light += ambientColor * upFacing * AMBIENT_MULT;

        if (s.foliage) {
            // Light scattered through thin leaves/grass, strongest looking towards the sun.
            vec3 viewDir = normalize(s.playerPos);
            float phase = 0.25 + 1.75 * pow(saturate(dot(viewDir, lightDir)), 6.0);
            float transmit = exp(-thickness * 1.5);
            light += directColor * transmit * phase * 0.6 * FOLIAGE_SSS * skyGate;
        }
    #endif

    light += vec3(0.0035 * CAVE_LIGHTING) + vec3(0.25 * nightVision);
    return light * s.ao;
}
