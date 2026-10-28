// User-facing options. Iris builds the shader menu from the "//[...]" lists below;
// shaders.properties arranges them into screens and profiles.
// Keep every option in this file so the menu has one source of truth.
// Include it exactly once per program (common.glsl does this); no include guard,
// so Iris's option scanner sees every define unconditionally.

// ---- Camera / colour balance -------------------------------------------------
#define TAA
#define TAA_SMOOTHING 0.90  //[0.75 0.80 0.85 0.88 0.90 0.92 0.94 0.96]
#define TAA_JITTER 1.00     //[0.00 0.25 0.50 0.75 1.00]
#define IMAGE_SHARPENING 3  //[0 1 2 3 4 5 6 7 8 9 10]
// Auto exposure: the image adapts to how bright the view is, like eyes (part of the way).
#define AUTO_EXPOSURE
#define AUTO_EXPOSURE_STRENGTH 0.60 //[0.20 0.40 0.60 0.80 1.00]
#define AUTO_EXPOSURE_MIN 0.50      //[0.25 0.35 0.50 0.70 1.00]
#define AUTO_EXPOSURE_MAX 3.00      //[1.00 1.50 2.00 3.00 4.00 6.00]
#define TM_EXPOSURE 1.00 //[0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
#define TM_CONTRAST 1.25 //[1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.50]
#define TM_WHITE_PATH 10.0 //[4.0 6.0 8.0 10.0 12.0 16.0 24.0]
#define T_SATURATION 1.10 //[0.00 0.50 0.70 0.80 0.90 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]
// Vibrance: saturates dull colours more than already vivid ones.
#define CB_VIBRANCE 1.00 //[0.00 0.25 0.50 0.75 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
// Takes the colour out of the darkest parts of the image, like eyes in low light.
#define CB_DARK_DESATURATION 0.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.90 1.00]
// Colour grading matrix (output R/G/B from input R/G/B) and per-channel curves (gamma).
#define GRADE_RR 1.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_RG 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_RB 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_GR 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_GG 1.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_GB 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_BR 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_BG 0.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_BB 1.00 //[0.00 0.05 0.10 0.15 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.50]
#define GRADE_CURVE_R 1.00 //[0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30]
#define GRADE_CURVE_G 1.00 //[0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30]
#define GRADE_CURVE_B 1.00 //[0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30]
// Light and atmosphere colour multipliers per condition (R, G, B and intensity).
#define LIGHT_SUNSET_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_SUNSET_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_SUNSET_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_SUNSET_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define LIGHT_NOON_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NOON_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NOON_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NOON_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define LIGHT_NIGHT_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NIGHT_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NIGHT_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NIGHT_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define LIGHT_RAIN_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_RAIN_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_RAIN_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_RAIN_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define LIGHT_NETHER_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NETHER_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NETHER_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_NETHER_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define LIGHT_END_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_END_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_END_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define LIGHT_END_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_SUNSET_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_SUNSET_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_SUNSET_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_SUNSET_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_NOON_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NOON_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NOON_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NOON_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_NIGHT_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NIGHT_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NIGHT_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NIGHT_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_RAIN_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_RAIN_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_RAIN_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_RAIN_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_NETHER_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NETHER_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NETHER_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_NETHER_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]
#define ATMO_END_R 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_END_G 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_END_B 1.00 //[0.00 0.10 0.20 0.30 0.40 0.50 0.60 0.70 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50 1.60 1.70 1.80 1.90 2.00]
#define ATMO_END_I 1.00 //[0.00 0.25 0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00 2.50 3.00]

// ---- Post-processing ---------------------------------------------------------
#define BLOOM
#define BLOOM_STRENGTH 1.00 //[0.25 0.50 0.75 1.00 1.25 1.50 2.00 2.50 3.00]
// Extra bloom in rain, caves and under water (damp air scatters light).
#define BLOOM_FOG 1.00      //[0.00 0.50 1.00 1.50 2.00 3.00]
// Far-away lights glow a little wider at night and in caves, as if seen through air.
#define DISTANT_LIGHT_BLOOM 1.00 //[0.00 0.50 1.00 1.50 2.00 3.00]
#define VIGNETTE 0.25       //[0.00 0.10 0.20 0.25 0.30 0.40 0.50 0.70 1.00]
#define CHROMATIC_ABERRATION 0 //[0 1 2 3 4 5]
//#define FXAA
#define FXAA_SUBPIXEL 0.50  //[0.00 0.25 0.50 0.75 1.00]

// ---- Shadows ----------------------------------------------------------------
// Iris reads these two constants directly; they are also menu options.
const int shadowMapResolution = 4096; //[1024 2048 3072 4096 6144 8192]
const float shadowDistance = 160.0;   //[64.0 96.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0]
// Smallest shadow blur (shadow-map texels): edges right where an object touches the ground.
#define SHADOW_SOFTNESS 1.5 //[0.5 1.0 1.5 2.0 3.0 4.0]
// Size of the sun's disc for shadows: shadows are sharp where an object meets the ground and
// soften the further they fall from it (more in overcast weather). 0 = always sharp.
#define SHADOW_PENUMBRA 1.00 //[0.00 0.50 0.75 1.00 1.50 2.00 3.00]
// Shadow filter samples (fewer far away).
#define SHADOW_SAMPLES 12 //[8 12 16 24]
// Tiny shadows the shadow map is too coarse for (grass, small items, where things meet the
// ground), traced on screen within ~24 blocks.
#define CONTACT_SHADOWS
// Shadows beyond the shadow distance, from a coarse height map of the terrain (mountains,
// valleys at sunset). Draws more of the world in the shadow pass (some CPU/GPU cost).
#define FAR_SHADOWS
// How far far shadows reach, in multiples of the shadow distance (limited by render distance).
#define FAR_SHADOW_RANGE 3.0 //[2.0 3.0 4.0 6.0]
// See-through mobs and their see-through parts (slimes, ...) cast partial shadows.
#define TRANSLUCENT_ENTITY_SHADOWS
// Lightning casts shadows from hills, trees and buildings (needs Coloured Lighting).
#define LIGHTNING_SHADOWS
// How fast shadow resolution drops with distance: low = even detail everywhere,
// high = very sharp under you and blocky far away.
#define SHADOW_FALLOFF 0.75 //[0.40 0.50 0.60 0.70 0.75 0.80 0.85 0.90]
#define ENTITY_SHADOWS
// Your own shadow (with Entity Shadows off, only yours is drawn).
#define PLAYER_SHADOW
// Sharper shadows close to you (your own shadow especially): 0 normal, 1 high, 2 very high.
// Finer filtering near the player and a little more shadow-map detail around you.
#define PLAYER_SHADOW_QUALITY 1 //[0 1 2]
// Leaves and vines deep in the dark (caves, interiors) cast no shadows: a little faster.
#define LEAF_SHADOW_OPTIMIZATION
#define COLORED_SHADOWS
#define FOLIAGE_SSS 1.00 //[0.00 0.50 0.75 1.00 1.25 1.50 2.00]

// ---- Lighting -------------------------------------------------------------------
// Screen-space ambient occlusion: 0 off, 1 medium, 2 high
#define SSAO 1                  //[0 1 2]
#define SSAO_STRENGTH 1.00      //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
// Light volume (needs Coloured Lighting): sunlight bounced off sunlit blocks, in their
// colour; how much the sky light is shut out by blocks around (caves, overhangs, trees).
#define SUN_BOUNCE 1.00         //[0.00 0.25 0.50 0.75 1.00 1.50 2.00]
#define VOXEL_SKY_OCCLUSION 0.80 //[0.00 0.25 0.50 0.65 0.80 1.00]
// Faces turned away from a light get less of it (needs Coloured Lighting).
#define DIRECTIONAL_BLOCKLIGHT
// Block light flickering, in steps of 2% brightness.
#define BLOCKLIGHT_FLICKER 2    //[0 1 2 3 4 5]
#define AMBIENT_MULT 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define CAVE_LIGHTING 1.00  //[0.00 0.25 0.50 0.75 1.00 1.50 2.00 3.00]
#define BLOCKLIGHT_I 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define BLOCKLIGHT_R 1.00   //[0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20]
#define BLOCKLIGHT_G 0.62   //[0.40 0.50 0.56 0.62 0.70 0.80 0.90 1.00]
#define BLOCKLIGHT_B 0.32   //[0.10 0.20 0.26 0.32 0.40 0.50 0.70 1.00]
#define VANILLA_AO_I 1.00   //[0.00 0.25 0.50 0.75 1.00 1.25 1.50]

// ---- Coloured lighting --------------------------------------------------------
// Block light takes the colour of its source (floodfill through a voxel volume).
#define COLORED_LIGHTING
// Volume around the player: 1 = 128x64x128 blocks, 2 = 256x128x256 blocks
#define COLORED_LIGHT_RANGE 2           //[1 2]
#define COLORED_LIGHT_SATURATION 1.35   //[0.00 0.25 0.50 0.75 1.00 1.15 1.35 1.50 1.75 2.00]
// Torch and fire colour, from warm white (0) to deep orange (1).
#define FIRE_WARMTH 0.70                //[0.00 0.25 0.50 0.70 0.85 1.00]
#define COLORED_CANDLES

// ---- Materials ------------------------------------------------------------------
// 0 off, 1 sun/moon highlights only, 2 full reflections of the surroundings
#define BLOCK_REFLECTIONS 0             //[0 1 2]
// Reflections are traced at 1/N of the screen size.
#define REFLECTION_RES 2                //[1 2]
#define GENERATED_NORMALS
#define NORMAL_STRENGTH 1.00            //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
// Coated textures: per-texel dusting, percent
#define COATED_TEXTURES 50              //[0 25 50 75 100]
// Generated normals and coated textures on mobs and block entities too.
#define ENTITY_MATERIALS
#define GLOWING_ORES
#define GLOWING_ORES_STRENGTH 1.00      //[0.25 0.50 0.75 1.00 1.50 2.00]
#define GLOW_ORE_IRON
#define GLOW_ORE_GOLD
#define GLOW_ORE_COPPER
#define GLOW_ORE_REDSTONE
#define GLOW_ORE_LAPIS
#define GLOW_ORE_EMERALD
#define GLOW_ORE_DIAMOND
#define GLOW_ORE_NETHER_QUARTZ
#define GLOW_ORE_NETHER_GOLD
#define GLOW_ORE_ANCIENT_DEBRIS
// 0 off, 1 amethyst crystals, 2 crystals and amethyst blocks
#define GLOWING_AMETHYST 1              //[0 1 2]
// 0 off, 1 only where the sky doesn't reach, 2 always
#define GLOW_LICHEN 1                   //[0 1 2]
//#define EMISSIVE_REDSTONE_BLOCK
//#define EMISSIVE_LAPIS_BLOCK
#define GLOWING_TRIMS
#define GLOWING_LAVA_PARTICLES
#define PORTAL_EFFECTS

// ---- Glass / ice --------------------------------------------------------------
// Glass reflects more far away, where you see it at a glancing angle.
#define DISTANT_GLASS_REFLECTIONS
#define GLASS_TINT 0.45        //[0.15 0.25 0.35 0.45 0.55 0.65 0.75 0.85 1.00]
#define ICE_OPACITY 0.60       //[0.30 0.40 0.50 0.60 0.70 0.80 1.00]
#define ICE_REFLECTIVITY 1.00  //[0.00 0.50 0.75 1.00 1.25 1.50 2.00]

// ---- Water ------------------------------------------------------------------
#define WATER_REFLECTIONS 1   //[0 1]
#define WATER_WAVE_STRENGTH 1.00 //[0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_WAVE_SPEED 1.00    //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_WAVE_SIZE 1.00     //[0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_FOG_MULT 1.00      //[0.25 0.50 0.75 1.00 1.50 2.00 3.00]
// Water looks different per biome: murky swamps, clear tropical seas, deep blue cold water...
#define BIOME_WATER
#define WATER_REFRACTION 100     //[0 25 50 75 100 150 200]
#define WATER_FOAM 2             //[0 1 2 3]
#define WATER_CAUSTICS
// You, mobs and boats leave ripples and wakes on the water.
#define INTERACTIVE_RIPPLES
// Colour fringes on caustics (different colours focus at slightly different depths):
// 1 = physically correct (subtle), higher exaggerates.
#define CAUSTIC_DISPERSION 4.0 //[0.0 1.0 2.0 4.0 6.0 8.0]
// Translucent blocks more opaque than the limit cast no caustics on the water under them.
//#define OPAQUE_BLOCKS_CAUSTICS
#define CAUSTICS_OPACITY_LIMIT 0.50 //[0.30 0.40 0.50 0.60 0.70 0.80 0.90]
#define WAVING_WATER_VERTEX
//#define UNDERWATER_DISTORTION
#define WATER_COLOR_R 1.00       //[0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_COLOR_G 1.00       //[0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_COLOR_B 1.00       //[0.50 0.75 1.00 1.25 1.50 2.00]
#define UNDERWATER_COLOR_R 1.00  //[0.50 0.75 1.00 1.25 1.50 2.00]
#define UNDERWATER_COLOR_G 1.00  //[0.50 0.75 1.00 1.25 1.50 2.00]
#define UNDERWATER_COLOR_B 1.00  //[0.50 0.75 1.00 1.25 1.50 2.00]

// ---- Sky ----------------------------------------------------------------------
#define SUN_MOON_STYLE 1        //[1 2]
#define SUN_MOON_HORIZON
//#define SUN_MOON_DURING_RAIN
#define STAR_AMOUNT 2           //[0 1 2 3 4]
#define MOON_PHASE_LIGHTING
#define END_STAR_INTENSITY 1.00 //[0.00 0.25 0.50 0.75 1.00 1.50 2.00]
// Night sky extras: procedural nebulae (0 = off), aurora (0 off, 1 curtains, 2 bands) and
// when it shows (0 every night, 1 full moon, 2 snowy biomes, 3 full moon or snowy biomes).
#define NEBULAE 0.60            //[0.00 0.20 0.40 0.60 0.80 1.00 1.50 2.00]
#define AURORA 1                //[0 1 2]
#define AURORA_CONDITION 3      //[0 1 2 3]
// 0 off, 1 after rain, 2 always (with the sun low behind you)
#define RAINBOWS 1              //[0 1 2]
// Aurora, nebulae and rainbows in reflections: 0 off, 1 water, 2 water and blocks
#define SKY_EFFECT_REFLECTIONS 1 //[0 1 2]
// End: volumetric beams rising from the void, and the End's sky flashes.
#define END_BEAMS
#define END_BEAM_INTENSITY 1.00 //[0.25 0.50 0.75 1.00 1.50 2.00]
#define END_FLASHES

// ---- Weather ------------------------------------------------------------------
// Rain turns the clouds into an overcast deck; thunderstorms darken the sky further.
#define RAIN_OVERCAST
#define STORM_DARKNESS 1.00     //[0.00 0.25 0.50 0.75 1.00 1.25 1.50]
// Lightning lights up its surroundings and the clouds for a moment.
#define LIGHTNING_FLASH 1.00    //[0.00 0.25 0.50 1.00 1.50 2.00 3.00]
// 0 light & warmer, 1 heavy & colder
#define RAIN_STYLE 0            //[0 1]
#define WEATHER_OPACITY 0.60    //[0.20 0.30 0.40 0.50 0.60 0.70 0.80 1.00]
// Snowstorms in snowy biomes and sandstorms in deserts and badlands while it rains.
#define WEATHER_STORMS
// 0 off, 1 puddles in rain, 2 full coverage in rain, 3 puddles always
#define PUDDLES 1               //[0 1 2 3]
// Exposed surfaces darken and get glossier in rain.
#define WET_SURFACES
// Raindrop ripples on puddles and water.
#define RAIN_RIPPLES

// ---- Waving -------------------------------------------------------------------
#define WAVING_PLANTS
#define WAVING_LEAVES
#define WAVING_LAVA
#define WAVING_LILY_PADS
#define WAVING_WEATHER
#define WAVING_SPEED 1.00       //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WAVING_INTENSITY 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
// Rain makes plants wave this much more.
#define WAVING_RAIN 1.50        //[1.00 1.25 1.50 2.00 2.50 3.00]
// Plants under a roof (no sky light) stay still.
#define NO_WAVING_INDOORS
// Hand sway: 0 off, 1 subtle, 2 normal, 3 intense
#define HAND_SWAY 1             //[0 1 2 3]

// ---- Clouds -----------------------------------------------------------------
// 0 off, 1 Unbound-style volumetric, 2 vanilla
#define CLOUD_STYLE 1           //[0 1 2]
// Cloud look: 1 stratocumulus with cirrus streaks above, 3 overcast, 0 cumulus (M5)
#define CLOUD_PRESET 1          //[1 3 0]
// How much of the sky the high cirrus streaks cover (Stratocumulus look).
#define CIRRUS_AMOUNT 0.55      //[0.00 0.30 0.40 0.50 0.55 0.60 0.70 0.80]
// Samples per pixel: 1 low, 2 medium, 3 high
#define CLOUD_QUALITY 2         //[1 2 3]
// Clouds are rendered at 1/N of the screen size and smoothed over time.
#define CLOUD_RES_DIV 2         //[1 2 4]
#define CLOUD_ALTITUDE 192      //[128 160 192 224 256 320]
#define CLOUD_THICKNESS 48.0    //[24.0 32.0 48.0 64.0 96.0]
#define CLOUD_AMOUNT 0.45       //[0.20 0.30 0.40 0.45 0.50 0.60 0.70 0.85]
#define CLOUD_SIZE 1.00         //[0.50 0.75 1.00 1.25 1.50 2.00]
#define CLOUD_DENSITY 1.00      //[0.50 0.75 1.00 1.50 2.00]
#define CLOUD_SPEED 1.00        //[0.00 0.25 0.50 1.00 2.00 4.00]
// Skip the volumetric clouds while deep underground, where the sky cannot be seen.
#define NO_CLOUDS_UNDERGROUND
// Drift follows the world clock instead of real time (same clouds for everyone).
//#define CLOUD_WORLD_TIME
// Strength of cloud shadows on the ground, percent.
#define CLOUD_SHADOWS 70        //[0 25 50 70 85 100]
#define CLOUD_COLOR_R 1.00      //[0.50 0.60 0.70 0.80 0.90 1.00]
#define CLOUD_COLOR_G 1.00      //[0.50 0.60 0.70 0.80 0.90 1.00]
#define CLOUD_COLOR_B 1.00      //[0.50 0.60 0.70 0.80 0.90 1.00]

// ---- Light shafts --------------------------------------------------------------
// 0 off, 1 low, 2 medium (with cloud shadows), 3 high
#define VL_QUALITY 2            //[0 1 2 3]
#define VL_STRENGTH 1.00        //[0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]

// ---- Fog --------------------------------------------------------------------
#define BORDER_FOG
#define ATM_FOG_MULT 0.80       //[0.00 0.25 0.50 0.65 0.80 0.95 1.20 1.50 2.00]
#define ATM_FOG_DISTANCE 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00 3.00]
#define ATM_FOG_ALTITUDE 63     //[0 32 48 56 63 70 80 96 128]
#define CAVE_FOG
//#define LESS_LAVA_FOG
#define NETHER_VIEW_LIMIT 256.0 //[96.0 128.0 160.0 192.0 256.0 320.0 384.0 512.0 99999.0]

// ---- Debug ------------------------------------------------------------------
// 0 off, 1 albedo, 2 world normal, 3 lightmap, 4 shading model, 5 vanilla AO, 6 emission,
// 7 smoothness, 8 metalness
#define DEBUG_VIEW 0 //[0 1 2 3 4 5 6 7 8]
// Draws every particle flat magenta, to tell "not drawn" apart from "drawn but hidden".
#define DEBUG_PARTICLES 0 //[0 1]

// ---- Internal (not menu options) --------------------------------------------
// Particles also write the "keep" shading model, so they survive if Iris draws them
// before the deferred pass instead of after it.
#define FORWARD_ORDER_SAFE 1

