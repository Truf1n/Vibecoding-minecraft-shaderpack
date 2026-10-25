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
#define TM_EXPOSURE 1.00 //[0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]
#define TM_CONTRAST 1.25 //[1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.50]
#define TM_WHITE_PATH 10.0 //[4.0 6.0 8.0 10.0 12.0 16.0 24.0]
#define T_SATURATION 1.10 //[0.00 0.50 0.70 0.80 0.90 1.00 1.05 1.10 1.15 1.20 1.30 1.40 1.50]

// ---- Shadows ----------------------------------------------------------------
// Iris reads these two constants directly; they are also menu options.
const int shadowMapResolution = 4096; //[1024 2048 3072 4096 6144 8192]
const float shadowDistance = 160.0;   //[64.0 96.0 128.0 160.0 192.0 224.0 256.0 320.0 384.0 512.0]
#define SHADOW_SOFTNESS 1.5 //[0.5 1.0 1.5 2.0 3.0 4.0]
// How fast shadow resolution drops with distance: low = even detail everywhere,
// high = very sharp under you and blocky far away.
#define SHADOW_FALLOFF 0.60 //[0.40 0.50 0.60 0.70 0.80 0.85 0.90]
#define ENTITY_SHADOWS
#define COLORED_SHADOWS
#define FOLIAGE_SSS 1.00 //[0.00 0.50 0.75 1.00 1.25 1.50 2.00]

// ---- Lighting -------------------------------------------------------------------
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

// ---- Glass / ice --------------------------------------------------------------
#define GLASS_TINT 0.45        //[0.15 0.25 0.35 0.45 0.55 0.65 0.75 0.85 1.00]
#define ICE_OPACITY 0.60       //[0.30 0.40 0.50 0.60 0.70 0.80 1.00]
#define ICE_REFLECTIVITY 1.00  //[0.00 0.50 0.75 1.00 1.25 1.50 2.00]

// ---- Water ------------------------------------------------------------------
#define WATER_REFLECTIONS 1   //[0 1]
#define WATER_WAVE_STRENGTH 1.00 //[0.00 0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_WAVE_SPEED 1.00    //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_WAVE_SIZE 1.00     //[0.50 0.75 1.00 1.25 1.50 2.00]
#define WATER_FOG_MULT 1.00      //[0.25 0.50 0.75 1.00 1.50 2.00 3.00]
#define WATER_REFRACTION 100     //[0 25 50 75 100 150 200]
#define WATER_FOAM 2             //[0 1 2 3]
#define WATER_CAUSTICS
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
// 0 off, 1 albedo, 2 world normal, 3 lightmap, 4 shading model, 5 vanilla AO, 6 emission
#define DEBUG_VIEW 0 //[0 1 2 3 4 5 6]
// Draws every particle flat magenta, to tell "not drawn" apart from "drawn but hidden".
#define DEBUG_PARTICLES 0 //[0 1]

// ---- Internal (not menu options) --------------------------------------------
// Particles also write the "keep" shading model, so they survive if Iris draws them
// before the deferred pass instead of after it.
#define FORWARD_ORDER_SAFE 1

