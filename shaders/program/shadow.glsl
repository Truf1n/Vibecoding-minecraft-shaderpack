// Shadow pass: depth from the sun/moon, the tint of translucent casters, and the column maps.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"

#ifdef VERTEX_SHADER

#define COLUMN_MAP_WRITER
#include "/lib/materials/columnMaps.glsl"

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

    // Column maps (columnMaps.glsl): water, water surfaces, glass, and
    // block undersides flush with the bottom of their block space. The shadow pass covers
    // everything around the player every frame, whether or not it is on screen. Partial
    // blocks that could hold water but don't (stairs, slabs, ...) and leaves are not
    // undersides: they keep the air gap above the water.
    bool terrain = renderStage == MC_RENDER_STAGE_TERRAIN_SOLID || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
                || renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED || renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT;
    bool seeThrough = renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT && !IsWater(blockId);
    if (terrain && (seeThrough || IsWater(blockId) || gl_Normal.y < -0.5)) {
        vec3 worldPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz + cameraPosition;
        vec3 blockCenter = worldPos + at_midBlock.xyz / 64.0;
        bool underside = gl_Normal.y < -0.5 && abs(worldPos.y - (blockCenter.y - 0.5)) < 0.01;
        if (IsWater(blockId)) {
            MarkColumn(MAP_WATER_CELLS, blockCenter);
            if (gl_Normal.y > 0.5) MarkColumn(MAP_WATER_SURFACE, blockCenter);
        } else {
            if (seeThrough) MarkColumn(MAP_GLASS_CELLS, blockCenter);
            if (underside && blockId != BLOCK_DRY_WATERLOGGABLE && blockId != BLOCK_LEAVES && !IsPlant(blockId)) {
                MarkColumn(seeThrough ? MAP_GLASS_CEILING : MAP_CEILING, blockCenter);
            }
        }
    }

    vec4 clip = ftransform(); // orthographic: w == 1
    gl_Position = vec4(DistortShadowClip(clip.xyz), 1.0);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/materials/glassTint.glsl"

uniform sampler2D gtexture;

in vec2 texCoord;
in vec4 vertColor;
flat in int blockId;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outShadowColor; // tint of translucent casters
layout(location = 1) out vec4 outShadowCaster; // r: water, g: opacity of a see-through block

// Blending is off for the shadow pass (shaders.properties): whichever caster is nearest
// to the sun decides these values, whatever order things are drawn in.
void main() {
    if (IsWater(blockId)) {
        // Water: no tint, marked in shadowcolor1.
        outShadowColor = vec4(1.0, 1.0, 1.0, 0.0);
        outShadowCaster = vec4(1.0, 0.0, 0.0, 1.0);
        return;
    }

    if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) {
        // Translucent blocks cast one even tint per block (mip level 4 of a 16px sprite is
        // its average), so the frame pixels of glass leave no seams in the light.
        vec4 avgTexel = textureLod(gtexture, texCoord, 4.0) * vec4(vertColor.rgb, 1.0);
        if (IsGlass(blockId)) {
            outShadowColor = vec4(LinearToSrgb(GlassTint(blockId, avgTexel)), 1.0);
        } else {
            if (avgTexel.a < 0.02) discard;
            outShadowColor = avgTexel;
        }
        outShadowCaster = vec4(0.0, avgTexel.a, 0.0, 1.0);
        return;
    }

    vec4 albedo = texture(gtexture, texCoord);
    if (albedo.a < 0.1) discard;
    outShadowColor = albedo;
    outShadowCaster = vec4(0.0);
}

#endif
