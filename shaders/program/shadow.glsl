// Shadow pass: depth from the sun/moon, the tint of translucent casters, and the column maps.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/lighting/shadowSpace.glsl"

#ifdef VERTEX_SHADER

#define COLUMN_MAP_WRITER
#include "/lib/materials/columnMaps.glsl"
#ifdef INTERACTIVE_RIPPLES
    #include "/lib/materials/ripples.glsl"
    layout(r32ui) uniform uimage2D rippleLowImg;
    layout(r32ui) uniform uimage2D rippleHighImg;
#endif
#include "/lib/util/encoding.glsl"
#include "/lib/materials/waving.glsl"
#ifdef COLORED_LIGHTING
    #include "/lib/lighting/voxels.glsl"
    layout(r32ui) uniform uimage3D voxelImg;
    layout(r32ui) uniform uimage3D albedoImg; // average colour of each block (sun bounce), packed (voxels.glsl)
    uniform sampler2D gtexture;

    // Records what fills this block space for the coloured-light floodfill (voxels.glsl).
    void WriteVoxel(vec3 blockCenter, int id, int emission, vec2 midTexCoord) {
        uint priority;
        if (emission > 0) priority = VOXEL_PRIORITY_SOURCE;
        else if (IsWater(id)) priority = VOXEL_PRIORITY_WATER;
        else if (renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT || id == BLOCK_LEAVES) priority = VOXEL_PRIORITY_TINT;
        else if (id == BLOCK_DRY_WATERLOGGABLE || id == BLOCK_THIN_SOLID) return; // slabs, stairs, carpets, snow layers...: light gets past
        else if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID) priority = VOXEL_PRIORITY_SOLID;
        else return; // plants, rails, doors...: light passes freely
        ivec3 coord = ivec3(floor(blockCenter)) - VoxelOrigin();
        if (any(lessThan(coord, ivec3(0))) || any(greaterThanEqual(coord, VOXEL_SIZE))) return;
        imageAtomicMax(voxelImg, coord, EncodeVoxel(priority, id, emission));
        // The block's average colour (mip level 4 of its sprite, with the biome tint), for
        // the sunlight it bounces (light volume, floodfill.glsl). Faces of one block may
        // differ (grass top and sides): the top face's wins, then the sides', always the
        // same one (an atomic max on the face rank in the top bits; a plain store would let
        // a different face win every frame, and the bounce colour flicker).
        if (priority == VOXEL_PRIORITY_SOLID || priority == VOXEL_PRIORITY_TINT) {
            vec3 albedo = textureLod(gtexture, midTexCoord, 4.0).rgb * gl_Color.rgb;
            uint rank = gl_Normal.y > 0.5 ? 3u : (gl_Normal.y < -0.5 ? 1u : 2u);
            imageAtomicMax(albedoImg, coord, PackVoxelAlbedo(albedo, rank));
        }
    }
#endif

uniform mat4 shadowModelViewInverse;
#if defined FAR_SHADOWS && defined WORLD_OVERWORLD
    #define FAR_HEIGHT_WRITER
    #include "/lib/lighting/farShadows.glsl"
#endif

in vec2 mc_Entity;
in vec4 mc_midTexCoord;
in vec4 at_midBlock; // xyz: offset to the block centre in 1/64 blocks; w: light emission 0-15

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
    bool columnInfo = seeThrough || IsWater(blockId) || gl_Normal.y < -0.5;
    // Voxels need one vertex per face: Sodium stores each quad as four consecutive vertices,
    // so exactly one of them has an index divisible by four.
    #ifdef COLORED_LIGHTING
        bool voxel = (gl_VertexID & 3) == 0;
    #else
        bool voxel = false;
    #endif
    #if defined FAR_SHADOWS && defined WORLD_OVERWORLD
        // Far-shadow height map: one corner of every face looking up (not water).
        if (terrain && gl_Normal.y > 0.5 && (gl_VertexID & 3) == 0 && !IsWater(blockId)) {
            WriteFarHeight((shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz + cameraPosition);
        }
    #endif
    if (terrain && (columnInfo || voxel)) {
        vec3 worldPos = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz + cameraPosition;
        vec3 blockCenter = worldPos + at_midBlock.xyz / 64.0;
        #ifdef COLORED_LIGHTING
            if (voxel) WriteVoxel(blockCenter, blockId, int(at_midBlock.w + 0.5), mc_midTexCoord.xy);
        #endif
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

    #ifdef INTERACTIVE_RIPPLES
        // Entities (the player too): record how low and how high they reach above each
        // quarter-block cell, for the ripple simulation to check against the water.
        if (renderStage == MC_RENDER_STAGE_ENTITIES) {
            vec3 wp = (shadowModelViewInverse * (gl_ModelViewMatrix * gl_Vertex)).xyz + cameraPosition;
            if (all(lessThan(abs(wp.xz - cameraPosition.xz), vec2(31.0)))) {
                ivec2 texel = RippleWrap(RippleCellOf(wp.xz, RIPPLE_MASK_CELLS), RIPPLE_MASK_SIZE);
                uint q = PackRippleHeight(wp.y);
                imageAtomicMax(rippleHighImg, texel, q);
                imageAtomicMax(rippleLowImg, texel, 0xFFFFFFFFu - q);
            }
        }
    #endif
    vec4 clip = ftransform(); // orthographic: w == 1
    #ifdef LEAF_SHADOW_OPTIMIZATION
        // Leaves and vines with (almost) no sky light: in caves and interiors, where their
        // shadows hardly ever show. Moved out of the shadow map.
        if (terrain && (blockId == BLOCK_LEAVES || blockId == BLOCK_PLANT_HANGING)
            && RemapLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy).y < 0.15) {
            gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
            return;
        }
    #endif
    if (terrain && IsPlant(blockId)) {
        // Waving plants (waving.glsl), so their shadows move with them.
        vec3 shadowViewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
        vec3 wp = (shadowModelViewInverse * vec4(shadowViewPos, 1.0)).xyz + cameraPosition;
        vec2 lm = RemapLightmap((gl_TextureMatrix[1] * gl_MultiTexCoord1).xy);
        vec3 wave = WavingOffset(blockId, wp, texCoord.y < mc_midTexCoord.y, lm.y);
        clip = gl_ProjectionMatrix * vec4(shadowViewPos + mat3(gl_ModelViewMatrix) * wave, 1.0);
    }
    gl_Position = vec4(DistortShadowClip(clip.xyz), 1.0);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/materials/glassTint.glsl"

uniform sampler2D gtexture;
uniform int entityId; // entity.properties

in vec2 texCoord;
in vec4 vertColor;
flat in int blockId;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 outShadowColor; // tint of translucent casters
layout(location = 1) out vec4 outShadowCaster; // r: water, g: opacity of a see-through block

// Blending is off for the shadow pass (shaders.properties): whichever caster is nearest
// to the sun decides these values, whatever order things are drawn in.
void main() {
    #ifdef WORLD_NETHER
        discard; // the Nether has no sun: this pass only fills the coloured-light voxels
    #endif
    #ifndef PLAYER_SHADOW
        if (entityId == ENTITY_PLAYER) discard;
    #endif
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
    #ifdef TRANSLUCENT_ENTITY_SHADOWS
        // See-through parts of mobs (slimes' outer layer, ...): a share of their texels,
        // as many as they are opaque, cast shadow; the soft-shadow filter averages them
        // into a partial shadow.
        if (renderStage == MC_RENDER_STAGE_ENTITIES && albedo.a < 0.95) {
            float pattern = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));
            if (albedo.a * vertColor.a < pattern) discard;
        }
    #endif
    outShadowColor = albedo;
    outShadowCaster = vec4(0.0);
}

#endif
