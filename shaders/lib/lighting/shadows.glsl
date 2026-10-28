// Sun/moon shadows (plan items L1-L5, L19).
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

    // 3x3 hardware-filtered PCF (each tap is itself bilinear-filtered: 36 effective samples).
    float spacing = SHADOW_SOFTNESS / float(shadowMapResolution);
    #if PLAYER_SHADOW_QUALITY > 0
        // Finer filtering close to the player (crisper shadows of you and around you).
        float nearPlayer = 1.0 - smoothstep(4.0, 20.0, length(playerPos));
        spacing *= mix(1.0, PLAYER_SHADOW_QUALITY == 1 ? 0.55 : 0.35, nearPlayer);
    #endif
    float opaque = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            opaque += texture(shadowtex1HW, coord + vec3(vec2(x, y) * spacing, 0.0));
        }
    }
    opaque /= 9.0;
    r.light = vec3(opaque);

    // Translucent casters nearest to the sun. Water absorbs the light per colour and
    // focuses it into caustics, over the distance the light travelled through it (from
    // the shadow map, as for any caster). Glass or ice: the caustics are worked out as if
    // it were not there - the water under it comes from the column maps, since the shadow
    // map only sees the glass - and its tint goes on top.
    float allVis = texture(shadowtex0HW, coord);
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
