// Sun/moon shadows (plan items L1-L5, L19; soft shadows and far shadows: W4).
// Needs common.glsl and shadowSpace.glsl. Not available in the Nether (no shadow pass).

#include "/lib/materials/caustics.glsl"
#include "/lib/materials/columnMaps.glsl"

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2DShadow shadowtex0HW; // all geometry, hardware depth compare
uniform sampler2DShadow shadowtex1HW; // opaque only, hardware depth compare
uniform sampler2D shadowtex0;         // all geometry, raw depth
uniform sampler2D shadowtex1;         // opaque only, raw depth (for foliage thickness)
uniform sampler2D shadowcolor0;       // tint of translucent casters (glass, ice)
uniform sampler2D shadowcolor1;       // r: nearest caster is water; g: opacity of a see-through caster

// Direction towards the sun/moon in world space (+z of shadow view space).
vec3 ShadowLightDir() { return vec3(shadowModelView[0][2], shadowModelView[1][2], shadowModelView[2][2]); }

// Blocks between two shadow-map depths.
float ShadowDepthToBlocks(float deltaDepth) { return deltaDepth * 2.0 / SHADOW_Z_SCALE / abs(shadowProjection[2][2]); }

// Per-pixel turn of the filter spiral, changing every frame (TAA averages the frames).
float ShadowNoise() {
    #ifdef FRAGMENT_SHADER
        return fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
    #else
        return 0.5;
    #endif
}

// Point i of n on a disc of radius 1, evenly spread (golden-angle spiral), turned by phi.
vec2 VogelDisk(int i, int n, float phi) {
    float r = sqrt((float(i) + 0.5) / float(n));
    float a = float(i) * 2.39996323 + phi;
    return r * vec2(cos(a), sin(a));
}

// How wide shadows blur per block between the caster and the receiver: the apparent size of
// the light. In overcast weather the light comes from a wide bright patch of cloud instead
// of the sun's disc, so shadows go very soft.
float SunPenumbra() {
    float size = 0.014 * SHADOW_PENUMBRA;
    #ifdef WORLD_OVERWORLD
        size *= 1.0 + 4.0 * stormRain;
    #endif
    return size;
}

struct ShadowResult {
    vec3 light;        // 0 = fully shadowed, 1 = lit; tinted by coloured glass
    float coverage;    // 1 inside the shadow map, fading to 0 at its edge
    float thickness;   // blocks of opaque geometry between the light and this point
};

// playerPos: camera-relative world position. normal: world normal (zero for sprites).
// foliage: two-sided thin geometry, which needs a stronger bias against self-shadow acne.
ShadowResult GetShadow(vec3 playerPos, vec3 normal, bool foliage) {
    ShadowResult r;
    r.light = vec3(1.0);
    r.thickness = 0.0;

    vec3 shadowView = (shadowModelView * vec4(playerPos, 1.0)).xyz;
    vec3 clip = (shadowProjection * vec4(shadowView, 1.0)).xyz;
    float distortFactor = ShadowDistortFactor(clip.xy);
    r.coverage = 1.0 - smoothstep(0.85, 0.98, length(clip.xy));
    if (r.coverage <= 0.0) return r;

    // Normal offset scaled by the local (distorted) texel size in blocks, to avoid acne.
    float texelWorld = 2.0 * shadowDistance / float(shadowMapResolution);
    float localTexel = texelWorld * distortFactor * distortFactor / (1.0 - SHADOW_DISTORT);
    vec3 offsetView = mat3(shadowModelView) * normal;
    if (foliage) {
        // Thin two-sided blades: offset along whichever side faces the light (+z in shadow
        // view space points at the sun/moon) and step towards the light as well, so a
        // blade does not shadow itself while still shadowing its neighbours.
        offsetView *= offsetView.z < 0.0 ? -1.0 : 1.0;
        offsetView = offsetView * localTexel * 1.5 + vec3(0.0, 0.0, localTexel * 3.0);
    } else {
        offsetView *= localTexel * 1.2;
    }
    clip = (shadowProjection * vec4(shadowView + offsetView, 1.0)).xyz;

    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
    coord.z -= 0.00002;

    // Soft shadows (W4, plan items Q8, Q11): percentage-closer soft shadows. A few taps
    // around the point find how far above it the things casting the shadow are; the
    // further, the wider the blur (the sun is a disc, not a point): sharp where a post
    // meets the ground, soft at the tip of a tree's shadow. Overcast skies widen the "sun"
    // a lot. The taps lie on a spiral turned per pixel and per frame (TAA blends them).
    float noise = ShadowNoise();
    float texelsPerBlock = 1.0 / localTexel;
    float uvPerTexel = 1.0 / float(shadowMapResolution);
    float sunSize = SunPenumbra(); // blocks of blur per block between caster and receiver
    float minRadius = SHADOW_SOFTNESS * 0.5; // texels
    #if PLAYER_SHADOW_QUALITY > 0
        // Finer filtering close to the player (crisper shadows of you and around you).
        float nearPlayer = 1.0 - smoothstep(4.0, 20.0, length(playerPos));
        minRadius *= mix(1.0, PLAYER_SHADOW_QUALITY == 1 ? 0.55 : 0.35, nearPlayer);
    #endif
    float radius = minRadius;
    if (sunSize > 0.0) {
        // Blocker search: up to 8 blocks above (beyond that the blur is wide anyway).
        float searchTexels = clamp(sunSize * 8.0 * texelsPerBlock, minRadius, 24.0);
        float blockerSum = 0.0, blockers = 0.0;
        // Only casters at least a tenth of a block above count (not the surface itself
        // where it slopes away from the light).
        float blockerBias = 0.1 / ShadowDepthToBlocks(1.0);
        for (int i = 0; i < 6; i++) {
            vec2 o = VogelDisk(i, 6, noise * TAU) * searchTexels * uvPerTexel;
            float d = textureLod(shadowtex1, coord.xy + o, 0.0).r;
            if (d < coord.z - blockerBias) { blockerSum += d; blockers += 1.0; }
        }
        if (blockers > 0.0) {
            float gap = ShadowDepthToBlocks(coord.z - blockerSum / blockers);
            radius = clamp(gap * sunSize * texelsPerBlock, minRadius, 24.0);
        }
    }
    // Fewer taps far away, where a pixel covers more than the blur anyway.
    int taps = length(playerPos) > 64.0 ? SHADOW_SAMPLES / 2 : SHADOW_SAMPLES;
    float opaque = 0.0, allVis = 0.0;
    for (int i = 0; i < taps; i++) {
        vec3 o = vec3(VogelDisk(i, taps, noise * TAU + 1.3) * radius * uvPerTexel, 0.0);
        opaque += texture(shadowtex1HW, coord + o);
        allVis += texture(shadowtex0HW, coord + o);
    }
    opaque /= float(taps);
    allVis /= float(taps);
    r.light = vec3(opaque);

    // Translucent casters nearest to the sun. Water absorbs the light per colour and
    // focuses it into caustics, over the distance the light travelled through it (from
    // the shadow map, as for any caster). Glass or ice: the caustics are worked out as if
    // it were not there - the water under it comes from the column maps, since the shadow
    // map only sees the glass - and its tint goes on top.
    if (allVis < opaque - 0.01) {
        vec3 worldPos = playerPos + cameraPosition;
        vec3 L = ShadowLightDir();
        vec4 caster = texelFetch(shadowcolor1, ivec2(coord.xy * float(shadowMapResolution)), 0);
        if (caster.r > 0.5) {
            float path = max(ShadowDepthToBlocks(coord.z - texture(shadowtex0, coord.xy).r), 0.0);
            r.light = vec3(opaque) * UnderwaterLight(path, worldPos.xz + L.xz * path / 1.333, 1.0);
        } else {
            #ifdef COLORED_SHADOWS
                vec4 glass = texelFetch(shadowcolor0, ivec2(coord.xy * float(shadowMapResolution)), 0);
                vec3 tint = mix(vec3(1.0), SrgbToLinear(glass.rgb), glass.a);
            #else
                vec3 tint = vec3(0.0);
            #endif
            r.light = vec3(allVis) + (opaque - allVis) * tint;

            // Looked up a little off the surface, so a block's side face reads the water
            // column next to it rather than flipping between the two from pixel to pixel.
            vec3 lookup = worldPos + normal * 0.05;
            float surface = ColumnWaterSurface(lookup);
            if (surface > lookup.y) {
                float path = (surface - lookup.y) / max(L.y, 0.15);
                float causticStrength = 1.0;
                #ifdef OPAQUE_BLOCKS_CAUSTICS
                    // Fairly opaque blocks (tinted glass, ...) let no focused light through.
                    if (caster.g > CAUSTICS_OPACITY_LIMIT) causticStrength = 0.0;
                #endif
                r.light *= UnderwaterLight(path, worldPos.xz + L.xz * path / 1.333, causticStrength);
            }
        }
    }

    // Depth of opaque material in front of this point (light travelling through leaves).
    float occluderDepth = texture(shadowtex1, coord.xy).r;
    r.thickness = max(ShadowDepthToBlocks(coord.z - occluderDepth), 0.0);

    return r;
}

// 1 if a translucent caster (ice, stained glass) sits just above this point towards the
// sun/moon, with nothing opaque in between. Used to stop water under ice reflecting the sky.
float TranslucentCoverAbove(vec3 playerPos) {
    vec3 clip = (shadowProjection * vec4((shadowModelView * vec4(playerPos, 1.0)).xyz, 1.0)).xyz;
    if (length(clip.xy) > 0.95) return 0.0;
    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;

    ivec2 texel = ivec2(coord.xy * float(shadowMapResolution));
    float allDepth = texelFetch(shadowtex0, texel, 0).r;
    float opaqueDepth = texelFetch(shadowtex1, texel, 0).r;
    if (allDepth >= opaqueDepth - 1e-6) return 0.0; // nearest caster is opaque (or none)
    if (texelFetch(shadowcolor1, ivec2(coord.xy * float(shadowMapResolution)), 0).r > 0.5) return 0.0; // that's water, not ice/glass

    float gapBlocks = ShadowDepthToBlocks(coord.z - allDepth);
    return gapBlocks > 0.02 && gapBlocks < 3.0 ? 1.0 : 0.0;
}
