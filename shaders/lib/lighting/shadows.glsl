// Sun/moon shadows (plan items L1-L5, L19).
// Needs common.glsl and shadowSpace.glsl. Not available in the Nether (no shadow pass).

uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2DShadow shadowtex0HW; // all geometry, hardware depth compare
uniform sampler2DShadow shadowtex1HW; // opaque only, hardware depth compare
uniform sampler2D shadowtex1;         // opaque only, raw depth (for foliage thickness)
uniform sampler2D shadowcolor0;       // tint of translucent casters (stained glass)

struct ShadowResult {
    vec3 light;        // 0 = fully shadowed, 1 = lit; tinted by coloured glass
    float coverage;    // 1 inside the shadow map, fading to 0 at its edge
    float thickness;   // blocks of opaque geometry between the light and this point
};

// playerPos: camera-relative world position. normal: world normal (zero for sprites).
ShadowResult GetShadow(vec3 playerPos, vec3 normal) {
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
    vec3 offsetView = mat3(shadowModelView) * normal * localTexel * 1.2;
    clip = (shadowProjection * vec4(shadowView + offsetView, 1.0)).xyz;

    vec3 coord = DistortShadowClip(clip) * 0.5 + 0.5;
    coord.z -= 0.00002;

    // 3x3 hardware-filtered PCF (each tap is itself bilinear-filtered: 36 effective samples).
    float spacing = SHADOW_SOFTNESS / float(shadowMapResolution);
    float opaque = 0.0;
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            opaque += texture(shadowtex1HW, coord + vec3(vec2(x, y) * spacing, 0.0));
        }
    }
    opaque /= 9.0;
    r.light = vec3(opaque);

    #ifdef COLORED_SHADOWS
        // Light blocked by translucent casters only gets tinted, not removed.
        float allVis = texture(shadowtex0HW, coord);
        if (allVis < opaque - 0.01) {
            vec4 glass = texture(shadowcolor0, coord.xy);
            vec3 tint = mix(vec3(1.0), SrgbToLinear(glass.rgb), glass.a);
            r.light = vec3(allVis) + (opaque - allVis) * tint;
        }
    #endif

    // Depth of opaque material in front of this point (light travelling through leaves).
    float occluderDepth = texture(shadowtex1, coord.xy).r;
    float deltaNdc = (coord.z - occluderDepth) * 2.0 / SHADOW_Z_SCALE;
    r.thickness = max(deltaNdc / abs(shadowProjection[2][2]), 0.0);

    return r;
}
