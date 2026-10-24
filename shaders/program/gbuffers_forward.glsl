// Forward-rendered geometry. One template, selected by the wrapper's FWD_* define:
//   FWD_SKY       vanilla sky disc/stars: discarded (the sky is drawn in deferred)
//   FWD_SKYTEX    sun / moon / custom sky textures            -> colortex0
//   FWD_OVERLAY   vanilla clouds, glint, glowing eyes, beams  -> colortex4 (premultiplied overlay)
//   FWD_UNLIT     leads, debug lines, selection outline       -> colortex0 + shading model "keep"
//   FWD_LIT       particles, weather                         -> colortex0 (forward-lit, blended)
//                 water/translucent terrain                    -> colortex0 (sorted) + colortex5 tint
//                 translucent mobs                             -> colortex5/6 (order-independent layers)
//   FWD_DAMAGE    block-breaking cracks                       -> colortex0 and the G-buffer albedo

#include "/lib/common.glsl"
#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/jitter.glsl"

#ifdef VERTEX_SHADER

#ifdef PROG_GBUFFERS_WATER
in vec2 mc_Entity;
#endif

out vec2 texCoord;
out vec2 lmCoord;
out vec4 vertColor;
out vec3 playerPos;
out vec3 worldNormal;
flat out int blockId;
flat out vec3 sunDir;
flat out vec3 lightDir;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertColor = gl_Color;

    // "Feet" player space: the translation in gbufferModelViewInverse removes view bobbing,
    // so this matches the deferred pass, the shadow map and world coordinates exactly.
    vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    playerPos = mat3(gbufferModelViewInverse) * viewPos + gbufferModelViewInverse[3].xyz;
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);

    vec3 viewNormal = normalize(gl_NormalMatrix * gl_Normal);
    worldNormal = mat3(gbufferModelViewInverse) * viewNormal;

    #ifdef PROG_GBUFFERS_WATER
        blockId = int(mc_Entity.x + 0.5);
    #else
        blockId = 0;
    #endif

    bool wavedWater = false;
    #ifdef WAVING_WATER_VERTEX
    #ifdef PROG_GBUFFERS_WATER
        // Gently raise and lower the water surface (plan item W10). Only downwards, so it
        // never pokes above the shore, and only on top faces of water.
        if (blockId == BLOCK_WATER && worldNormal.y > 0.9) {
            vec3 wp = playerPos + cameraPosition;
            float t = frameTimeCounter * WATER_WAVE_SPEED;
            float wave = sin(wp.x * 0.65 + t * 1.3) * sin(wp.z * 0.55 + t * 1.1) * 0.5 + 0.5;
            playerPos.y -= wave * 0.05;
            wavedWater = true;
        }
    #endif
    #endif

    #ifdef PROG_GBUFFERS_LINE
        // Lines arrive as point pairs with the direction in gl_Normal; expand them into
        // screen-space quads the way vanilla's line shader does.
        vec2 screenSize = vec2(viewWidth, viewHeight);
        float lineWidth = max(2.5, viewHeight / 1080.0 * 2.5);
        mat4 mvp = gl_ProjectionMatrix * gl_ModelViewMatrix;
        vec4 startClip = mvp * gl_Vertex;
        vec4 endClip = mvp * vec4(gl_Vertex.xyz + gl_Normal, 1.0);
        vec3 startNdc = startClip.xyz / startClip.w;
        vec3 endNdc = endClip.xyz / endClip.w;
        vec2 dir = normalize((endNdc.xy - startNdc.xy) * screenSize);
        vec2 offset = vec2(-dir.y, dir.x) * lineWidth / screenSize;
        if (offset.x < 0.0) offset = -offset;
        if (gl_VertexID % 2 != 0) offset = -offset;
        gl_Position = vec4((startNdc + vec3(offset, 0.0)) * startClip.w, startClip.w);
    #else
        gl_Position = wavedWater
            ? gl_ProjectionMatrix * (gbufferModelView * vec4(playerPos, 1.0))
            : ftransform();
    #endif
    gl_Position = ApplyTAAJitter(gl_Position);
}

#endif

#ifdef FRAGMENT_SHADER

#ifdef PROG_GBUFFERS_WATER
    #define WATER_HEIGHT_WRITER // water surfaces record their height (waterHeight.glsl)
#endif

#include "/lib/util/space.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/atmosphere/sky.glsl"
#ifndef WORLD_NETHER
    #include "/lib/lighting/shadowSpace.glsl"
    #include "/lib/lighting/shadows.glsl"
#endif
#include "/lib/lighting/lighting.glsl"
#include "/lib/atmosphere/fog.glsl"

uniform sampler2D gtexture;

#if defined PROG_GBUFFERS_WATER || defined PROG_GBUFFERS_HAND_WATER
    // Translucent terrain is sorted back to front by Sodium: plain alpha blending layers it
    // correctly; stained-glass tint goes to colortex5.
    #define TRANSLUCENT_SORTED
    #include "/lib/materials/translucent.glsl"
    #include "/lib/materials/ssr.glsl"
    #include "/lib/materials/glass.glsl"
    #include "/lib/materials/ice.glsl"
    #include "/lib/materials/caustics.glsl"
    #include "/lib/materials/waterHeight.glsl"
    #include "/lib/materials/water.glsl"
#elif defined PROG_GBUFFERS_ENTITIES_TRANSLUCENT || defined PROG_GBUFFERS_BLOCK_TRANSLUCENT
    // Translucent mobs may be drawn before or after deferred: order-independent layers.
    #define TRANSLUCENT_OIT
    #include "/lib/materials/translucent.glsl"
#endif
#if FORWARD_ORDER_SAFE == 1 && defined PROG_GBUFFERS_TEXTURED
    // Also write the "keep" shading model, so this survives if Iris draws it before deferred.
    #define ORDER_SAFE_LAYER
#endif

in vec2 texCoord;
in vec2 lmCoord;
in vec4 vertColor;
in vec3 playerPos;
in vec3 worldNormal;
flat in int blockId;
flat in vec3 sunDir;
flat in vec3 lightDir;

#if defined TRANSLUCENT_SORTED
    /* RENDERTARGETS: 0,5 */
    layout(location = 0) out vec4 outColor;
    layout(location = 1) out vec4 outTint;
#elif defined TRANSLUCENT_OIT
    /* RENDERTARGETS: 5,6 */
    layout(location = 0) out vec4 outTransmit;
    layout(location = 1) out vec4 outLight;
#elif defined FWD_UNLIT || defined ORDER_SAFE_LAYER
    /* RENDERTARGETS: 0,3 */
    layout(location = 0) out vec4 outColor;
    layout(location = 1) out vec4 outMaterial;
#elif defined FWD_OVERLAY
    /* RENDERTARGETS: 4 */
    layout(location = 0) out vec4 outColor;
#elif defined FWD_DAMAGE
    /* RENDERTARGETS: 0,1 */
    layout(location = 0) out vec4 outColor;
    layout(location = 1) out vec4 outAlbedo;
#else
    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 outColor;
#endif

void main() {
    #if defined FWD_SKY
        discard; // sky, sunset fan, stars and void are drawn by deferred.glsl

    #elif defined FWD_SKYTEX
        #ifdef WORLD_END
            discard; // replaced by the procedural End sky
        #endif
        #if SUN_MOON_STYLE == 1
            // The sun and moon are drawn procedurally in the sky (sky.glsl).
            if (renderStage == MC_RENDER_STAGE_SUN || renderStage == MC_RENDER_STAGE_MOON) discard;
        #endif
        vec4 albedo = texture(gtexture, texCoord) * vertColor;
        outColor = vec4(SrgbToLinear(albedo.rgb) * 2.0 * (1.0 - rainStrength), albedo.a);

    #elif defined FWD_OVERLAY
        #ifdef OVERLAY_NO_TEXTURE
            vec4 albedo = vertColor;
        #else
            vec4 albedo = texture(gtexture, texCoord) * vertColor;
        #endif
        if (albedo.a < 0.004) discard;
        vec3 color = SrgbToLinear(albedo.rgb);

        #if defined OVERLAY_CLOUDS
            Surface surf;
            surf.playerPos = playerPos;
            surf.normal = vec3(0.0, 1.0, 0.0);
            surf.lm = vec2(0.0, 1.0);
            surf.ao = 1.0;
            surf.foliage = false;
            surf.useShadowMap = false;
            color *= GetLighting(surf, sunDir, lightDir);
            outColor = vec4(color * albedo.a, albedo.a); // alpha-blended layer
        #else
            float strength = 1.0;
            #ifdef OVERLAY_EMISSIVE
                strength = 2.0;
            #endif
            outColor = vec4(color * albedo.a * strength, 0.0); // additive layer
        #endif

    #elif defined FWD_UNLIT
        outColor = vec4(SrgbToLinear(vertColor.rgb), vertColor.a);
        outMaterial = vec4(0.0); // SM_KEEP: deferred leaves this pixel alone

    #elif defined FWD_DAMAGE
        // Iris may draw cracks before or after the deferred pass, so write both the albedo
        // (used if before) and the lit scene (used if after). Blend is dst * 2src, so 0.5 is neutral.
        vec4 crack = texture(gtexture, texCoord) * vertColor;
        if (crack.a < 0.1) discard;
        outColor = vec4(crack.rgb, 1.0);
        outAlbedo = vec4(crack.rgb, 1.0);

    #else // FWD_LIT
        vec4 albedo = texture(gtexture, texCoord) * vertColor;

        #if defined PROG_GBUFFERS_TEXTURED && DEBUG_PARTICLES == 1
            outColor = vec4(1.0, 0.0, 1.0, 1.0);
            #ifdef ORDER_SAFE_LAYER
                outMaterial = vec4(0.0);
            #endif
            return;
        #endif

        vec2 lm = RemapLightmap(lmCoord);
        lm.x = max(lm.x, HeldLight(length(playerPos)));
        Surface surf;
        surf.playerPos = playerPos;
        #if defined PROG_GBUFFERS_TEXTURED || defined PROG_GBUFFERS_WEATHER
            surf.normal = vec3(0.0); // camera-facing sprites
        #else
            surf.normal = normalize(worldNormal);
        #endif
        surf.lm = lm;
        surf.ao = 1.0;
        surf.foliage = false;
        surf.useShadowMap = true;

        #if defined TRANSLUCENT_SORTED
            TranslucentSurface surface;
            if (blockId == BLOCK_WATER) {
                surface = ShadeWater(vertColor.rgb, playerPos, surf.normal, surf, sunDir, lightDir);
            } else if (IsGlass(blockId)) {
                // The texture (vanilla or Continuity's connected one) supplies the frame; the
                // see-through part becomes a clean colour tint instead of a hazy overlay.
                vec4 avgTexel = textureLod(gtexture, texCoord, 4.0) * vertColor;
                surface = ShadeGlass(blockId, albedo, avgTexel, playerPos, surf.normal, surf, sunDir, lightDir);
            } else if (blockId == BLOCK_ICE) {
                if (albedo.a < alphaTestRef) discard;
                surface = ShadeIce(albedo, playerPos, surf.normal, surf, sunDir, lightDir);
            } else if (blockId == BLOCK_NETHER_PORTAL) {
                // Self-lit: never tinted by the (orange) blocklight around it.
                surface = PlainSurface(SrgbToLinear(albedo.rgb) * 2.5, max(albedo.a, 0.6));
            } else {
                if (albedo.a < alphaTestRef) discard;
                surface = PlainSurface(SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir), albedo.a);
            }
            float fogAmount = BorderFogAmount(length(playerPos));
            outColor = vec4(ApplyFog(surface.color, playerPos, sunDir, false), surface.alpha);
            outTint = vec4(mix(surface.tint, vec3(1.0), fogAmount), 1.0);
        #elif defined TRANSLUCENT_OIT
            if (albedo.a < alphaTestRef) discard;
            albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a); // hurt flash
            TranslucentOut layer = AlphaLayer(SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir), albedo.a);
            layer = FogLayer(layer, BorderFogAmount(length(playerPos)));
            outTransmit = vec4(layer.transmit, 1.0);
            outLight = vec4(layer.light, 1.0);
        #else
            if (albedo.a < alphaTestRef) discard;
            vec3 color = SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir);

            #ifdef PROG_GBUFFERS_WEATHER
                albedo.a *= 0.6;
            #endif
            outColor = vec4(ApplyFog(color, playerPos, sunDir, false), albedo.a);
            #ifdef ORDER_SAFE_LAYER
                outMaterial = vec4(0.0);
            #endif
        #endif
    #endif
}

#endif
