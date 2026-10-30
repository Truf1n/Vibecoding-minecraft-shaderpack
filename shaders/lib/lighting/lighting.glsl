// Lighting model (M1): shadow-mapped sun/moon, sky ambient, blocklight, foliage subsurface.
// Colours come from lib/atmosphere/sky.glsl so lighting matches the sky.
// Needs: common.glsl, sky.glsl, and (outside the Nether) shadowSpace.glsl + shadows.glsl.

#ifdef WORLD_OVERWORLD
    #include "/lib/util/noise.glsl"
    #include "/lib/atmosphere/clouds.glsl"
#endif

#include "/lib/lighting/coloredLight.glsl"
#ifdef FAR_SHADOWS
    #ifdef WORLD_OVERWORLD
        #include "/lib/lighting/farShadows.glsl"
    #endif
#endif

#ifdef CONTACT_SHADOWS
#if defined CONTACT_SHADOW_PASS && !defined WORLD_NETHER
    // Contact shadows (W4, plan item Q9): a short trace towards the sun through the depth
    // buffer, for shadows smaller than a shadow-map texel - grass on the ground, small
    // items, the gap where a mob stands on a block. Within ~24 blocks only. Only mobs,
    // items and plants count as casters: blocks already cast exact-enough shadows into the
    // shadow map, and a second, sharper copy of their edge beside it looks wrong. Every
    // position is taken at the centre of the pixel whose depth is read (as for the AO), so
    // flat ground never shadows itself.
    float ContactShadow(vec3 playerPos, vec3 normal, vec3 L) {
        float dist = length(playerPos);
        float fade = 1.0 - smoothstep(16.0, 24.0, dist);
        if (fade <= 0.0) return 1.0;
        vec2 screen = vec2(viewWidth, viewHeight);
        float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
        const int STEPS = 10;
        const float LENGTH = 0.35; // blocks
        vec3 start = mat3(gbufferModelView) * (playerPos + normal * (0.02 + dist * 0.002)) + gbufferModelView[3].xyz;
        vec3 dirV = mat3(gbufferModelView) * L;
        for (int i = 0; i < STEPS; i++) {
            float t = (float(i) + noise) / float(STEPS) * LENGTH;
            vec3 p = start + dirV * t;
            vec4 clip = gbufferProjection * vec4(p, 1.0);
            ivec2 pixel = ivec2((clip.xy / clip.w * 0.5 + 0.5) * screen);
            if (any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, ivec2(screen)))) break;
            float depth = texelFetch(depthtex0, pixel, 0).r;
            if (depth < 0.56) continue; // the hand casts nothing
            int caster = DecodeId(texelFetch(colortex3, pixel, 0).r);
            if (caster != SM_ENTITY && caster != SM_FOLIAGE) continue;
            float sceneZ = ScreenToView((vec2(pixel) + 0.5) / screen, depth).z;
            float inFront = sceneZ - p.z; // > 0: the scene is nearer the camera than the ray
            // In front of the ray but not by much (thin things block; a wall far in front
            // of it says nothing about what is behind).
            if (inFront > 0.02 + 0.003 * -p.z && inFront < 0.35) return 1.0 - fade;
        }
        return 1.0;
    }
#endif
#endif

// Dynamic handheld light (plan item L14): vanilla light level minus distance, like vanilla falloff.
float HeldLight(float distToCamera) {
    float level = float(max(heldBlockLightValue, heldBlockLightValue2));
    return saturate((level - distToCamera) / 15.0);
}

// Blocklight flickering (plan item L13): fire and torch light breathes a little, slowly
// drifting across the world so neighbouring lights do not pulse in step.
float BlocklightFlicker(vec3 playerPos) {
    #if BLOCKLIGHT_FLICKER > 0
        vec3 p = playerPos + cameraPosition;
        float t = frameTimeCounter;
        float f = sin(t * 7.3 + p.x * 0.31 + p.z * 0.27) * 0.5 + sin(t * 13.1 + p.y * 0.43 - p.x * 0.19) * 0.3 + sin(t * 23.7 + p.z * 0.51) * 0.2;
        return 1.0 - float(BLOCKLIGHT_FLICKER) * 0.02 * (f * 0.5 + 0.5);
    #else
        return 1.0;
    #endif
}

// Blocklight falloff: steep near the source, long soft tail (vanilla levels are linear-ish).
float BlocklightFalloff(float lmBlock) {
    float l = lmBlock * lmBlock;
    return l * (0.25 + 0.75 * l) * 1.6;
}

// Screen-space ambient occlusion at the pixel being lit (set by the deferred pass; 1 in
// the forward passes), already coloured by the multi-bounce correction, and the bent normal
// (the direction that sees the most sky; zero = use the surface normal). They darken and
// steer the ambient, bounce and block light, never the sun.
vec3 lightingAO = vec3(1.0);
float lightingBentUp = -2.0; // height of the bent normal (the AO's most open direction); -2 = none

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
        light = color / (worldPart + heldPart) * BlocklightFalloff(max(s.lm.x, held)) * BLOCKLIGHT_I * lightingAO * BlocklightFlicker(s.playerPos);
        #ifdef DIRECTIONAL_BLOCKLIGHT
        #ifdef COLORED_LIGHTING
            // Directional block light (Q4): faces turned away from where the light comes
            // from get less of it (the world's light only; a held light comes from you).
            if (worldPart > heldPart * 0.5 && dot(s.normal, s.normal) > 0.5) {
                vec4 from = BlocklightDirection(s.playerPos, s.normal);
                float facing = 0.55 + 0.45 * saturate(dot(s.normal, from.xyz) * 0.5 + 0.5);
                light *= mix(1.0, facing / 0.775, from.w * worldPart / (worldPart + heldPart));
            }
        #endif
        #endif
    }

    bool hasNormal = dot(s.normal, s.normal) > 0.5;
    float NdotL = hasNormal ? dot(s.normal, lightDir) : 0.45;
    float diffuse = s.foliage ? 0.35 + 0.65 * abs(NdotL) : saturate(NdotL);
    float skyUp = lightingBentUp > -1.5 ? lightingBentUp : s.normal.y;
    float upFacing = hasNormal ? 0.75 + 0.25 * skyUp : 0.9;

    #if defined WORLD_NETHER
        // Biome-tinted ambient (crimson, warped, ...), from the same colours as the Nether fog.
        vec3 biomeTint = NetherSky();
        biomeTint /= max(max(biomeTint.r, max(biomeTint.g, biomeTint.b)), 0.01);
        light += mix(vec3(0.30, 0.13, 0.07), vec3(0.30, 0.13, 0.07) * 0.5 + biomeTint * 0.15, 0.6) * 0.55 * AMBIENT_MULT * LightMultiplier(0.0) * lightingAO;
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
            #if defined FAR_SHADOWS && defined WORLD_OVERWORLD
                // Beyond the shadow map: the terrain height map (still gated by sky light,
                // for caves).
                if (sh.coverage < 1.0) sunVis *= FarShadow(s.playerPos + cameraPosition, lightDir);
            #endif
            sunVis = mix(sunVis, sh.light, sh.coverage);
            thickness = mix(thickness, sh.thickness, sh.coverage);
            #if defined CONTACT_SHADOW_PASS && defined CONTACT_SHADOWS
                if (hasNormal && !s.foliage && diffuse > 0.0 && dot(sunVis, vec3(1.0)) > 0.0) sunVis *= ContactShadow(s.playerPos, s.normal, lightDir);
            #endif
        }

        #ifdef WORLD_OVERWORLD
            // Cloud shadows (only where the sun reaches at all).
            if (skyGate > 0.0 && dot(sunVis, vec3(1.0)) > 0.0) sunVis *= CloudShadow(s.playerPos + cameraPosition, lightDir);
        #endif
        sunLight = directColor * sunVis * skyGate * s.ao;
        light += directColor * diffuse * sunVis * skyGate;
        #if defined WORLD_OVERWORLD && defined COLORED_LIGHTING
            // Light volume (F1): how much sky this spot can really see (caves, overhangs,
            // under trees, beyond what Minecraft's sky light level says), and sunlight bounced
            // off sunlit blocks nearby, in their colour (Q2, Q3).
            vec4 bounceSky = SurfaceBounceSky(s.playerPos, hasNormal ? s.normal : vec3(0.0, 1.0, 0.0));
            ambientColor *= mix(1.0, bounceSky.a, VOXEL_SKY_OCCLUSION);
            // Bounced light comes mostly from sunlit ground, which faces up: floors get
            // little of it (and never their own: the volume holds it just above them),
            // walls more, undersides of leaves and overhangs the most.
            float receive = hasNormal ? 0.2 + 0.8 * saturate(0.5 - 0.5 * s.normal.y) : 0.5;
            light += directColor * bounceSky.rgb * (SUN_BOUNCE * receive) * lightingAO;
        #endif
        light += ambientColor * upFacing * AMBIENT_MULT * lightingAO;
        #ifdef WORLD_OVERWORLD
            // Lightning: the bolt's own light, and the flash of the whole sky.
            vec3 boltLight = LightningLight(s.playerPos, s.normal, s.lm.y);
            #if defined COLORED_LIGHTING && defined LIGHTNING_SHADOWS
                if (dot(boltLight, vec3(1.0)) > 0.0) boltLight *= LightningVoxelShadow(s.playerPos, hasNormal ? s.normal : vec3(0.0));
            #endif
            light += boltLight;
            light += LightningFlashColor() * (0.25 * s.lm.y * s.lm.y * upFacing);
        #endif

        if (s.foliage) {
            // Light scattered through thin leaves/grass, strongest looking towards the sun.
            vec3 viewDir = EyeDir(s.playerPos);
            float phase = 0.25 + 1.75 * pow(saturate(dot(viewDir, lightDir)), 6.0);
            float transmit = exp(-thickness * 1.5);
            light += directColor * transmit * phase * 0.6 * FOLIAGE_SSS * skyGate;
        }
    #endif

    light += (vec3(0.0035 * CAVE_LIGHTING) + vec3(0.25 * nightVision)) * lightingAO;
    return light * s.ao;
}

vec3 GetLighting(Surface s, vec3 sunDir, vec3 lightDir) {
    vec3 sunLight;
    return GetLighting(s, sunDir, lightDir, sunLight);
}
