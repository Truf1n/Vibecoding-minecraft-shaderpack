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
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform int isEyeInWater;     // 0 air, 1 water, 2 lava, 3 powder snow
uniform float nightVision;
uniform float blindness;
uniform float darknessFactor;
uniform int frameCounter;
uniform float frameTimeCounter;

// Per-draw
uniform int renderStage;
uniform float alphaTestRef;
uniform vec4 entityColor;     // hurt / creeper flash overlay
uniform int blockEntityId;
uniform int heldBlockLightValue;
uniform int heldBlockLightValue2;
