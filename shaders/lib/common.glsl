// Included first by every program (after the wrapper's #defines).

#include "/lib/settings.glsl"
#include "/lib/uniforms.glsl"

#define PI 3.14159265359
#define TAU 6.28318530718
#define saturate(x) clamp(x, 0.0, 1.0)

float Luminance(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

// Albedo is stored sRGB-encoded in RGBA8 (better precision in darks); all lighting is linear.
vec3 SrgbToLinear(vec3 c) { return pow(c, vec3(2.2)); }
vec3 LinearToSrgb(vec3 c) { return pow(max(c, 0.0), vec3(1.0 / 2.2)); }

// Where the eye really is, in player space. Minecraft folds view bobbing into the
// projection matrix, so the image is seen from slightly off the view-space origin, moving
// with every step. Anything that depends on the direction to the camera (reflections,
// highlights, Fresnel, light shafts, parallax) must use this, not the origin, or it swings
// with the bobbing. (If the bobbing is in the model-view matrix instead, this is simply
// its translation.)
vec3 EyePlayerPos() {
    vec4 eye = gbufferProjectionInverse * vec4(0.0, 0.0, 1.0, 0.0);
    return mat3(gbufferModelViewInverse) * (eye.xyz / eye.w) + gbufferModelViewInverse[3].xyz;
}
// Unit direction from the eye to a point (player space).
vec3 EyeDir(vec3 playerPos) { return normalize(playerPos - EyePlayerPos()); }

// Sun elevation in [-1, 1]; positive while the sun is above the horizon.
float SunElevation() { return dot(normalize(sunPosition), normalize(upPosition)); }
