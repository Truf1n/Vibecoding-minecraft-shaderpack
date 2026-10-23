// Shadow pass: depth from the sun/moon, plus the tint of translucent casters.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"

#ifdef VERTEX_SHADER

in vec2 mc_Entity;

out vec2 texCoord;
out vec4 vertColor;
flat out int blockId;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertColor = gl_Color;
    blockId = int(mc_Entity.x + 0.5);

    vec4 clip = ftransform(); // orthographic: w == 1
    gl_Position = vec4(DistortShadowClip(clip.xyz), 1.0);
}

#endif

#ifdef FRAGMENT_SHADER

uniform sampler2D gtexture;

in vec2 texCoord;
in vec4 vertColor;
flat in int blockId;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor;

void main() {
    // Water does not cast sun shadows (caustics come with the water pass).
    if (blockId == BLOCK_WATER) discard;

    vec4 albedo = texture(gtexture, texCoord);
    if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) albedo.rgb *= vertColor.rgb;
    if (albedo.a < 0.1) discard;

    outShadowColor = albedo;
}

#endif
