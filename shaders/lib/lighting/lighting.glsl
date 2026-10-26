// Lighting model (M1): shadow-mapped sun/moon, sky ambient, blocklight, foliage subsurface.
// Colours come from lib/atmosphere/sky.glsl so lighting matches the sky.
// Needs: common.glsl, sky.glsl, and (outside the Nether) shadowSpace.glsl + shadows.glsl.

#ifdef WORLD_OVERWORLD
    #include "/lib/util/noise.glsl"
    #include "/lib/atmosphere/clouds.glsl"
#endif

#include "/lib/lighting/coloredLight.glsl"

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

// Returns the light arriving at the surface; multiply by albedo. sunLight: the sun/moon
// light reaching the surface (shadows and clouds applied, before the angle), for highlights.
vec3 GetLighting(Surface s, vec3 sunDir, vec3 lightDir, out vec3 sunLight) {
    sunLight = vec3(0.0);
    // Block light: the brighter of the world's light level and a held light sets the
    // brightness; the colour is a blend of the two weighted by how strong each is here
    // (colours from coloredLight.glsl).
    float held = HeldLight(length(s.playerPos));
    float worldPart = BlocklightFalloff(s.lm.x), heldPart = BlocklightFalloff(held);
    vec3 light = vec3(0.0);
    if (worldPart + heldPart > 1e-4) {
        vec3 color = WorldBlocklightColor(s.playerPos, s.normal, s.lm.x) * worldPart + HeldLightColor() * heldPart;
        light = color / (worldPart + heldPart) * BlocklightFalloff(max(s.lm.x, held)) * BLOCKLIGHT_I;
    }

    bool hasNormal = dot(s.normal, s.normal) > 0.5;
    float NdotL = hasNormal ? dot(s.normal, lightDir) : 0.45;
    float diffuse = s.foliage ? 0.35 + 0.65 * abs(NdotL) : saturate(NdotL);
    float upFacing = hasNormal ? 0.75 + 0.25 * s.normal.y : 0.9;

    #if defined WORLD_NETHER
        // Biome-tinted ambient (crimson, warped, ...), from the same colours as the Nether fog.
        vec3 biomeTint = NetherSky();
        biomeTint /= max(max(biomeTint.r, max(biomeTint.g, biomeTint.b)), 0.01);
        light += mix(vec3(0.30, 0.13, 0.07), vec3(0.30, 0.13, 0.07) * 0.5 + biomeTint * 0.15, 0.6) * 0.55 * AMBIENT_MULT * LightMultiplier(0.0);
    #else
        #ifdef WORLD_END
            vec3 directColor = vec3(0.42, 0.34, 0.55) * 0.5 * LightMultiplier(0.0);
            vec3 ambientColor = vec3(0.16, 0.12, 0.22) * 0.55 * LightMultiplier(0.0);
            float skyGate = 1.0;
            // The End's sky flash lights everything facing it (E3).
            float endFlash = EndFlash();
            if (endFlash > 0.0) {
                float facing = hasNormal ? saturate(dot(s.normal, EndFlashDir())) * 0.8 + 0.2 : 0.6;
                light += vec3(0.75, 0.55, 1.00) * (endFlash * facing * 0.6);
            }
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

        #ifdef WORLD_OVERWORLD
            // Cloud shadows (only where the sun reaches at all).
            if (skyGate > 0.0 && dot(sunVis, vec3(1.0)) > 0.0) sunVis *= CloudShadow(s.playerPos + cameraPosition, lightDir);
        #endif
        sunLight = directColor * sunVis * skyGate * s.ao;
        light += directColor * diffuse * sunVis * skyGate;
        light += ambientColor * upFacing * AMBIENT_MULT;
        #ifdef WORLD_OVERWORLD
            // Lightning: the bolt's own light, and the flash of the whole sky.
            light += LightningLight(s.playerPos, s.normal, s.lm.y);
            light += LightningFlashColor() * (0.25 * s.lm.y * s.lm.y * upFacing);
        #endif

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

vec3 GetLighting(Surface s, vec3 sunDir, vec3 lightDir) {
    vec3 sunLight;
    return GetLighting(s, sunDir, lightDir, sunLight);
}
