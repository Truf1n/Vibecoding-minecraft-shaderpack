// Opaque geometry -> G-buffer. Used by terrain, entities, block entities and the hand.
// Lighting happens once per pixel in deferred.glsl, so overdraw only costs the cheap
// material evaluation below.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"

#ifdef VERTEX_SHADER

#ifdef PROG_GBUFFERS_TERRAIN
in vec2 mc_Entity;
#endif

out vec2 texCoord;
out vec2 lmCoord;
out vec4 vertColor;
out vec3 worldNormal;
flat out int blockId;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertColor = gl_Color;
    worldNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);

    #if defined PROG_GBUFFERS_TERRAIN
        blockId = int(mc_Entity.x + 0.5);
    #elif defined PROG_GBUFFERS_BLOCK
        blockId = blockEntityId;
    #else
        blockId = 0;
    #endif

    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/util/encoding.glsl"
#include "/lib/materials/terrainMaterial.glsl"

uniform sampler2D gtexture;

in vec2 texCoord;
in vec2 lmCoord;
in vec4 vertColor;
in vec3 worldNormal;
flat in int blockId;

/* RENDERTARGETS: 1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormalLight;
layout(location = 2) out vec4 outMaterial;

void main() {
    vec4 tex = texture(gtexture, texCoord);

    #ifdef PROG_GBUFFERS_TERRAIN
        // separateAo = true: vertex alpha carries vanilla AO, not transparency.
        vec4 albedo = vec4(tex.rgb * vertColor.rgb, tex.a);
        float ao = mix(1.0, vertColor.a, VANILLA_AO_I);
    #else
        vec4 albedo = tex * vertColor;
        float ao = 1.0;
    #endif

    if (albedo.a < alphaTestRef) discard;

    #ifdef PROG_GBUFFERS_ENTITIES
        albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a); // hurt flash
    #endif

    Material mat;
    #if defined PROG_GBUFFERS_TERRAIN
        mat = GetTerrainMaterial(blockId, albedo.rgb);
    #elif defined PROG_GBUFFERS_BLOCK
        mat.shadingModel = SM_DEFAULT;
        mat.emission = blockId == BLOCK_END_PORTAL ? 0.5 : 0.0;
    #elif defined PROG_GBUFFERS_HAND
        mat.shadingModel = SM_HAND;
        mat.emission = 0.0;
    #else
        mat.shadingModel = SM_ENTITY;
        mat.emission = 0.0;
    #endif

    outAlbedo = vec4(albedo.rgb, saturate(ao));
    outNormalLight = vec4(EncodeNormal(normalize(worldNormal)), RemapLightmap(lmCoord));
    outMaterial = vec4(EncodeId(mat.shadingModel), mat.emission, 0.0, 1.0);
}

#endif
