// Shadow map projection shared by the shadow pass and every reader.
// Radial distortion concentrates resolution near the player (one map, no cascades);
// depth is compressed so the whole shadow range fits with good precision.

// Radial distortion: shadow density near the player vs at the edge of the shadow range is
// 1 / (1 - SHADOW_DISTORT)^2 : 1 (0.6 -> 6x, 0.85 -> 44x). Must match in all programs.
// Player Shadow Quality adds a little more concentration around the player.
const float SHADOW_DISTORT = min(SHADOW_FALLOFF + 0.04 * float(PLAYER_SHADOW_QUALITY), 0.92);
const float SHADOW_Z_SCALE = 0.2;

float ShadowDistortFactor(vec2 clipXY) { return length(clipXY) * SHADOW_DISTORT + (1.0 - SHADOW_DISTORT); }

vec3 DistortShadowClip(vec3 clip) {
    return vec3(clip.xy / ShadowDistortFactor(clip.xy), clip.z * SHADOW_Z_SCALE);
}

// Iris pass configuration.
const bool shadowHardwareFiltering = true;  // enables the shadowtex*HW compare samplers
const float shadowDistanceRenderMul = 1.0;  // don't render shadow casters beyond shadowDistance (CPU saver)
const float entityShadowDistanceMul = 0.25; // entities only cast shadows within 1/4 of shadowDistance

/*
const int shadowcolor0Format = RGBA8;
const int shadowcolor1Format = RG8; // r: water, g: opacity of a see-through caster
*/
const vec4 shadowcolor1ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // no water
