// Platform layer: every Iris-provided uniform the pack uses is declared here and
// nowhere else, so a future port to another loader only has to replace this file
// (plus the sampler blocks in each program).
// Samplers are NOT declared here on purpose: Iris enables some passes (e.g. the
// shadow pass) when it sees their samplers referenced, so each program declares
// only the samplers it reads.

// Camera and matrices
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec3 cameraPosition;
uniform vec3 cameraPositionFract; // fractional part of cameraPosition (pairs with block indices)
uniform float near;
uniform float far;
uniform float viewWidth;
uniform float viewHeight;

// Celestial
uniform vec3 sunPosition;     // view space
uniform vec3 upPosition;      // view space
uniform vec3 shadowLightPosition; // view space; the sun by day, the moon by night
uniform float sunAngle;       // 0 sunrise, 0.25 noon, 0.5 sunset, 0.75 midnight

// World state
uniform float rainStrength;
// (stormRain, stormThunder, afterRain and wetness come from the world state: worldState.glsl)
uniform float frameTime;      // seconds the last frame took
uniform float temperature;    // biome temperature at the player (vanilla: snow below 0.15)
uniform float rainfall;       // biome downfall at the player
uniform float biomeWindiness; // custom: open, windy biomes > 1, sheltered forests < 1
uniform float thunderStrength;
uniform float watSwamp, watMangrove, watWarm, watLukewarm, watCold, watMeadow, watCherry, watPale; // custom: water biome weights
uniform float watDesert, watBadlands, watJungle, watMushroom;
uniform float inSnowyBiome, inSandyBiome, inDryBiome; // custom, 0..1
uniform vec4 lightningBoltPosition; // camera-relative position of a lightning bolt; w = 1 while one exists
uniform float endFlashIntensity;
uniform vec3 endFlashPosition; // view space
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform int isEyeInWater;     // 0 air, 1 water, 2 lava, 3 powder snow
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform int moonPhase;        // 0 full moon ... 4 new moon ... 7
uniform float caveFactor;     // custom (shaders.properties): 1 when the camera is underground
uniform float inNetherWastes, inCrimsonForest, inWarpedForest, inBasaltDeltas, inSoulValley; // custom, 0..1
uniform int frameCounter;
uniform int worldTime;         // 0..23999 ticks into the day
uniform int worldDay;
uniform ivec2 eyeBrightnessSmooth; // block / sky light around the eye, 0..240
uniform float frameTimeCounter;

// Per-draw
uniform int renderStage;
uniform float alphaTestRef;
uniform vec4 entityColor;     // hurt / creeper flash overlay
uniform int blockEntityId;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
