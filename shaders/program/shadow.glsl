// Shadow pass: depth from the sun/moon, plus the tint of translucent casters.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"

#ifdef VERTEX_SHADER

#define WATER_HEIGHT_WRITER
#include "/lib/materials/waterHeight.glsl"

uniform mat4 shadowModelViewInverse;

in vec2 mc_Entity;
in vec4 at_midBlock; // xyz: offset to the block centre in 1/64 blocks

out vec2 texCoord;
out vec4 vertColor;
flat out int blockId;

void main() {
    #ifndef ENTITY_SHADOWS
        // Entity shadows are switched off in shaders.properties (shadowEntities); this
        // check also makes Iris list ENTITY_SHADOWS as a menu option.
    #endif
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertColor = gl_Color;
    blockId = int(mc_Entity.x + 0.5);

    // Record water surfaces for underwater lighting. The shadow pass covers all water
    // around the player every frame, whether or not it is on screen.
    if (IsWater(blockId) && gl_Normal.y > 0.5) {
        vec3 worldPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz + cameraPosition;
        WriteWaterHeight(worldPos, worldPos + at_midBlock.xyz / 64.0);
    }

    vec4 clip = ftransform(); // orthographic: w == 1
    gl_Position = vec4(DistortShadowClip(clip.xyz), 1.0);
}

#endif

#ifdef FRAGMENT_SHADER

uniform sampler2D gtexture;

in vec2 texCoord;
in vec4 vertColor;
flat in int blockId;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outShadowColor; // tint of translucent casters
layout(location = 1) out vec4 outShadowWater; // r = 1 where the nearest caster is water

void main() {
    // Water goes into the translucent shadow depth with no tint, marked in shadowcolor1:
    // lighting uses it for underwater absorption and caustics.
    if (IsWater(blockId)) {
        outShadowColor = vec4(1.0, 1.0, 1.0, 0.0);
        outShadowWater = vec4(1.0, 0.0, 0.0, 1.0);
        return;
    }

    vec4 albedo = texture(gtexture, texCoord);
    if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) albedo.rgb *= vertColor.rgb;
    if (albedo.a < 0.1) discard;

    outShadowColor = albedo;
    outShadowWater = vec4(0.0);
}

#endif
