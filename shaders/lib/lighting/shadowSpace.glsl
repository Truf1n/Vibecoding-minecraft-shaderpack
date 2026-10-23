// Shadow map projection shared by the shadow pass and every reader.
// Radial distortion concentrates resolution near the player (one map, no cascades);
// depth is compressed so the whole shadow range fits with good precision.

const float SHADOW_DISTORT = 0.85;  // 0 = none, closer to 1 = sharper near the player
const float SHADOW_Z_SCALE = 0.2;

float ShadowDistortFactor(vec2 clipXY) { return length(clipXY) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT); }

vec3 DistortShadowClip(vec3 clip) {
    return vec3(clip.xy / ShadowDistortFactor(clip.xy), clip.z * SHADOW_Z_SCALE);
}

// Iris pass configuration.
const bool shadowHardwareFiltering = true;  // enables the shadowtex*HW compare samplers
const float shadowDistanceRenderMul = 1.0;  // don't render shadow casters beyond shadowDistance (CPU saver)
const float entityShadowDistanceMul = 0.25; // entities only cast shadows within 1/4 of shadowDistance
