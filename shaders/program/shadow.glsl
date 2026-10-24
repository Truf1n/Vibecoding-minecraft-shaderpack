// Shadow pass: depth from the sun/moon, plus the tint of translucent casters.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"
#include "/lib/voxel/glassVoxels.glsl"

#ifdef VERTEX_SHADER

in vec2 mc_Entity;
in vec4 at_midBlock;

uniform mat4 shadowModelViewInverse;
layout(r8ui) uniform writeonly uimage3D glassVoxelImg;

out vec2 texCoord;
out vec4 vertColor;
flat out int blockId;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    vertColor = gl_Color;
    blockId = int(mc_Entity.x + 0.5);

    // Record glass blocks into the voxel grid (every vertex of a block writes the same cell).
    uint glassCode = GlassVoxelCode(blockId);
    if (glassCode != 0u) {
        vec3 playerPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz;
        ivec3 voxel = GlassVoxelIndex(playerPos + at_midBlock.xyz / 64.0);
        if (InGlassGrid(voxel)) imageStore(glassVoxelImg, voxel, uvec4(glassCode));
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

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outShadowColor;

void main() {
    // Water does not cast sun shadows (caustics come with the water pass).
    if (blockId == BLOCK_WATER) discard;

    // Plain glass is clear (textureless look): it casts no shadow.
    if (blockId == BLOCK_GLASS || blockId == BLOCK_GLASS_PANE) discard;

    vec4 albedo = texture(gtexture, texCoord);
    if (IsGlass(blockId)) {
        // Textureless glass: a uniform tint from the texture's average colour.
        albedo = textureLod(gtexture, texCoord, 4.0);
        albedo.a = 0.85;
    }
    if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT) albedo.rgb *= vertColor.rgb;
    if (albedo.a < 0.1) discard;

    outShadowColor = albedo;
}

#endif
