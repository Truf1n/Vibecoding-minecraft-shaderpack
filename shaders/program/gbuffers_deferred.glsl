// Opaque geometry -> G-buffer. Used by terrain, entities, block entities and the hand.
// Lighting happens once per pixel in deferred.glsl, so overdraw only costs the cheap
// material evaluation below.

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/jitter.glsl"
#include "/lib/util/encoding.glsl"
#ifdef PROG_GBUFFERS_TERRAIN
    #include "/lib/materials/waving.glsl"
#endif

#ifdef VERTEX_SHADER

#ifdef PROG_GBUFFERS_TERRAIN
in vec2 mc_Entity;
in vec4 mc_midTexCoord; // centre of this face's sprite in the atlas
#endif

out vec2 texCoord;
out vec2 lmCoord;
out vec4 vertColor;
out vec3 worldNormal;
out vec3 playerPos;
flat out int blockId;
flat out vec4 spriteBounds; // atlas rectangle of the sprite: min.xy, max.zw

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertColor = gl_Color;
    worldNormal = mat3(gbufferModelViewInverse) * normalize(gl_NormalMatrix * gl_Normal);
    playerPos = mat3(gbufferModelViewInverse) * (gl_ModelViewMatrix * gl_Vertex).xyz + gbufferModelViewInverse[3].xyz;

    #ifdef PROG_GBUFFERS_TERRAIN
        // Each corner of a block face sits at a corner of its sprite: the distance to the
        // sprite centre gives the sprite's half size.
        vec2 halfSize = abs(texCoord - mc_midTexCoord.xy);
        spriteBounds = vec4(mc_midTexCoord.xy - halfSize, mc_midTexCoord.xy + halfSize);
    #else
        spriteBounds = vec4(0.0, 0.0, 1.0, 1.0);
    #endif

    #if defined PROG_GBUFFERS_TERRAIN
        blockId = int(mc_Entity.x + 0.5);
    #elif defined PROG_GBUFFERS_BLOCK
        blockId = blockEntityId;
    #else
        blockId = 0;
    #endif

    #if defined PROG_GBUFFERS_TERRAIN
        vec3 wave = WavingOffset(blockId, playerPos + cameraPosition, texCoord.y < mc_midTexCoord.y, RemapLightmap(lmCoord).y);
        playerPos += wave;
        gl_Position = ApplyTAAJitter(gl_ProjectionMatrix * (gbufferModelView * vec4(playerPos, 1.0)));
    #elif defined PROG_GBUFFERS_HAND && HAND_SWAY > 0
        // Hand sway: the held item drifts gently, as if breathing.
        const float swayAmounts[4] = float[4](0.0, 0.006, 0.012, 0.024);
        float t = frameTimeCounter;
        vec3 sway = vec3(sin(t * 0.83) * 1.0 + sin(t * 1.9) * 0.25, sin(t * 1.21) * 0.7 + sin(t * 2.6) * 0.15, 0.0) * swayAmounts[HAND_SWAY];
        gl_Position = ApplyTAAJitter(gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex + vec4(sway, 0.0)));
    #else
        gl_Position = ApplyTAAJitter(ftransform());
    #endif
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/materials/terrainMaterial.glsl"

uniform sampler2D gtexture;

#include "/lib/materials/surfaceDetail.glsl"
#include "/lib/materials/portals.glsl"

uniform int currentRenderedItemId; // armour trims (item.properties)

// Generated normals and coated textures: on blocks always, on entities as an option.
#ifdef PROG_GBUFFERS_TERRAIN
    #define SURFACE_DETAIL
#endif
#ifdef ENTITY_MATERIALS
    #if defined PROG_GBUFFERS_ENTITIES || defined PROG_GBUFFERS_BLOCK
        #define SURFACE_DETAIL
    #endif
#endif

in vec2 texCoord;
in vec2 lmCoord;
in vec4 vertColor;
in vec3 worldNormal;
in vec3 playerPos;
flat in int blockId;
flat in vec4 spriteBounds;

/* RENDERTARGETS: 1,2,3 */
layout(location = 0) out vec4 outAlbedo;
layout(location = 1) out vec4 outNormalLight;
layout(location = 2) out vec4 outMaterial;

void main() {
    #ifdef WAVING_LAVA
    #ifdef PROG_GBUFFERS_TERRAIN
        #define LAVA_FLOW
    #endif
    #endif
    vec4 tex = texture(gtexture, texCoord);
    #ifdef LAVA_FLOW
        // Lava's surface slowly churns (plan item V3): brighter and darker patches drift
        // over it. (Only the brightness changes: bending the texture tears it apart where
        // the flowing-lava sprite is rotated and stretched.)
        if (blockId == BLOCK_LIGHT_LAVA) {
            vec3 wp = playerPos + cameraPosition;
            float t = frameTimeCounter * 0.3 * WAVING_SPEED;
            vec2 q = wp.xz * 0.45 + vec2(wp.y * 0.3, -wp.y * 0.2);
            float churn = sin(q.x * 1.7 + t + sin(q.y * 1.3 - t * 0.7) * 1.5) * sin(q.y * 1.9 - t * 0.8 + sin(q.x * 1.1 + t * 0.5) * 1.5);
            tex.rgb *= 0.88 + 0.22 * churn;
        }
    #endif

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
        #if GLOW_LICHEN == 1
            // Glow lichen glows only where the sky does not reach.
            if (blockId == BLOCK_LIGHT_LICHEN) mat.emission *= 1.0 - smoothstep(0.2, 0.6, RemapLightmap(lmCoord).y);
        #endif
    #elif defined PROG_GBUFFERS_BLOCK
        mat = DefaultMaterial(SM_DEFAULT);
        if (blockId == BLOCK_END_PORTAL) {
            #ifdef PORTAL_EFFECTS
                albedo.rgb = EndPortalColor(playerPos);
                mat.emission = 1.0;
            #else
                mat.emission = 0.5;
            #endif
        }
    #elif defined PROG_GBUFFERS_HAND
        mat = DefaultMaterial(SM_HAND);
    #else
        mat = DefaultMaterial(SM_ENTITY);
        #ifdef GLOWING_TRIMS
            // Armour trims (item.properties maps trim materials to 6001).
            if (currentRenderedItemId == 6001) mat.emission = 0.45 * smoothstep(0.35, 0.75, Luminance(albedo.rgb));
        #endif
    #endif

    // Surface detail from the texture (blocks; entities with Materials on Entities).
    vec3 normal = normalize(worldNormal);
    #ifdef SURFACE_DETAIL
        float detailFade = 1.0 - smoothstep(24.0, 64.0, length(playerPos));
        #ifdef GENERATED_NORMALS
            vec3 geoNormal = normal;
            normal = GeneratedNormal(texCoord, spriteBounds, normal, playerPos, NORMAL_STRENGTH * 1.5 * detailFade);
            // A face turned away from the sun must stay out of its light: bumps may not tilt
            // towards the sun more than the face itself does (otherwise single texels light
            // up on the shaded side).
            vec3 L = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
            float faceNdotL = dot(geoNormal, L);
            float limit = max(faceNdotL, 0.0) + 0.35 * smoothstep(0.0, 0.3, faceNdotL);
            float over = dot(normal, L) - limit;
            if (over > 0.0) normal = normalize(normal - L * over);
        #endif
        #if COATED_TEXTURES > 0
            albedo.rgb = CoatTexture(albedo.rgb, texCoord, floor(playerPos + cameraPosition - worldNormal * 0.01),
                                     float(COATED_TEXTURES) * 0.01 * detailFade * (1.0 - mat.smoothness * 0.6));
        #endif
    #endif

    outAlbedo = vec4(saturate(albedo.rgb), saturate(ao));
    outNormalLight = vec4(EncodeNormal(normal), RemapLightmap(lmCoord));
    outMaterial = vec4(EncodeId(mat.shadingModel), mat.emission, mat.smoothness, mat.metalness);
}

#endif
