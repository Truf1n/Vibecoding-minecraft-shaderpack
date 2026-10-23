// User-facing options. Iris builds the shader menu from the "//[...]" lists below;
// shaders.properties arranges them into screens and profiles.
// Keep every option in this file so the menu has one source of truth.
// Include it exactly once per program (common.glsl does this); no include guard,
// so Iris's option scanner sees every define unconditionally.

// ---- Camera / colour balance -------------------------------------------------
#define TM_EXPOSURE 1.00 //[0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20 1.30 1.40 1.50 1.75 2.00]

// ---- Lighting (placeholder model until M1) ----------------------------------
#define AMBIENT_MULT 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define CAVE_LIGHTING 1.00  //[0.00 0.25 0.50 0.75 1.00 1.50 2.00 3.00]
#define BLOCKLIGHT_I 1.00   //[0.25 0.50 0.75 1.00 1.25 1.50 2.00]
#define BLOCKLIGHT_R 1.00   //[0.50 0.60 0.70 0.80 0.90 1.00 1.10 1.20]
#define BLOCKLIGHT_G 0.62   //[0.40 0.50 0.56 0.62 0.70 0.80 0.90 1.00]
#define BLOCKLIGHT_B 0.32   //[0.10 0.20 0.26 0.32 0.40 0.50 0.70 1.00]
#define VANILLA_AO_I 1.00   //[0.00 0.25 0.50 0.75 1.00 1.25 1.50]

// ---- Fog (placeholder until M2) ---------------------------------------------
#define BORDER_FOG

// ---- Debug ------------------------------------------------------------------
// 0 off, 1 albedo, 2 world normal, 3 lightmap, 4 shading model, 5 vanilla AO, 6 emission
#define DEBUG_VIEW 0 //[0 1 2 3 4 5 6]

