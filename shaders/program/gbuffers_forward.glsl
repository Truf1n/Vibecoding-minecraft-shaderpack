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
#include "/lib/materials/columnMaps.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/noise.glsl"
#include "/lib/materials/waves.glsl"

// True if any block space touching this surface corner is covered by a block (the corner
// is shared by up to four water blocks, so they all agree and the surface has no cracks).
bool CornerUnderBlock(vec3 wp) {
    float level = floor(wp.y - 0.5) + 1.5;
    for (int i = 0; i < 4; i++) {
        vec2 o = vec2(i & 1, i >> 1) - 0.5;
        vec3 p = vec3(wp.x + o.x * 0.98, level, wp.z + o.y * 0.98);
        if (HasCeiling(p) || HasGlassCeiling(p)) return true;
    }
    return false;
}
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
    #ifdef WAVING_WEATHER
    #ifdef PROG_GBUFFERS_WEATHER
        // Rain and snow fall at a slant in the wind (plan item V5): the wind's speed over
        // their falling speed (raindrops ~9 blocks/s, snowflakes ~2.5), from the world state.
        {
            float fallSpeed = mix(9.0, 2.5, inSnowyBiome);
            vec2 wind = WindDir() * min(WindSpeed() / fallSpeed, 1.5) * WAVING_INTENSITY;
            // Higher up, a drop is further upwind (it is carried along as it falls).
            playerPos.xz -= wind * (playerPos.y + cameraPosition.y - floor(cameraPosition.y));
            wavedWater = true;
        }
    #endif
    #endif
    #ifdef WAVING_WATER_VERTEX
    #ifdef PROG_GBUFFERS_WATER
        // Gently raise and lower the water surface (plan item W10). Only downwards, so it
        // never pokes above the shore, and only on top faces of water.
        // Not where the water is pressed right under a block.
        vec3 wp = playerPos + cameraPosition;
        if (IsWater(blockId) && worldNormal.y > 0.9 && !CornerUnderBlock(wp)) {
            // The long waves of the wave field (waves.glsl), calm without wind.
            float shelter = smoothstep(0.35, 0.85, RemapLightmap(lmCoord).y);
            float h = Waves(wp.xz, GetWaveConditions(shelter, 0.6, 0.5), 0.0, true).height;
            playerPos.y += clamp(h - 0.05, -0.1, 0.0);
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
        #if defined PROG_GBUFFERS_HAND_WATER && HAND_SWAY > 0
            // Hand sway (as in gbuffers_deferred.glsl), for translucent held items.
            const float swayAmounts[4] = float[4](0.0, 0.006, 0.012, 0.024);
            float t = frameTimeCounter;
            vec3 sway = vec3(sin(t * 0.83) * 1.0 + sin(t * 1.9) * 0.25, sin(t * 1.21) * 0.7 + sin(t * 2.6) * 0.15, 0.0) * swayAmounts[HAND_SWAY];
            gl_Position = gl_ProjectionMatrix * (gl_ModelViewMatrix * gl_Vertex + vec4(sway, 0.0));
        #endif
    #endif
    gl_Position = ApplyTAAJitter(gl_Position);
}

#endif

#ifdef FRAGMENT_SHADER

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
    #include "/lib/materials/portals.glsl"
    #include "/lib/materials/ice.glsl"
    #include "/lib/materials/caustics.glsl"
    #include "/lib/materials/columnMaps.glsl"
    #ifdef INTERACTIVE_RIPPLES
        #define RIPPLE_READER
        #include "/lib/materials/ripples.glsl"
    #endif
    #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
        #include "/lib/atmosphere/cloudBuffer.glsl"
    #endif
    #include "/lib/materials/water.glsl"
#elif defined PROG_GBUFFERS_ENTITIES_TRANSLUCENT || defined PROG_GBUFFERS_BLOCK_TRANSLUCENT
    // Translucent mobs may be drawn before or after deferred: order-independent layers.
    #define TRANSLUCENT_OIT
    #include "/lib/materials/translucent.glsl"
#endif
#ifdef PROG_GBUFFERS_WEATHER
    uniform sampler2D depthtex1; // opaque depth (copied before the translucent pass)
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
    /* RENDERTARGETS: 5,6,0,3,7 */
    layout(location = 0) out vec4 outTransmit;
    layout(location = 1) out vec4 outLight;
    layout(location = 2) out vec4 outOpaque;   // solid texels: blended in by their alpha (0 or 1)
    layout(location = 3) out vec4 outKeep;     // and marked "keep" for deferred (alpha 0 or 1)
    layout(location = 4) out vec4 outSceneCopy; // solid texels also into the opaque scene copy the water looks through
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
    #ifdef PROG_GBUFFERS_WEATHER
        // Rain and snow behind glass: Minecraft draws the weather after the translucent
        // blocks, so the depth test against the glass would hide it. Test against the
        // opaque scene by hand instead, and pass the hardware test by claiming to be in
        // front of everything (the weather is drawn last and does not write depth).
        if (gl_FragCoord.z >= texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r) discard;
        gl_FragDepth = 0.0;
    #endif
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
            #if CLOUD_STYLE != 2
                discard; // vanilla clouds only with the Vanilla cloud style
            #endif
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
            #ifdef PROG_GBUFFERS_LIGHTNING
                // A blinding blue-white core: bright enough for the bloom to give it a halo.
                color = vec3(0.68, 0.76, 1.00) * (1.0 + 2.0 * Luminance(color));
                strength = 14.0;
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
            if (IsWater(blockId)) {
                surface = ShadeWater(vertColor.rgb, blockId == BLOCK_WATER, playerPos, surf.normal, surf, sunDir, lightDir);
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
                float portalLight = 2.5;
                #ifdef PORTAL_EFFECTS
                    portalLight *= NetherPortalSwirl(playerPos + cameraPosition);
                #endif
                surface = PlainSurface(SrgbToLinear(albedo.rgb) * portalLight, max(albedo.a, 0.6));
            } else {
                if (albedo.a < alphaTestRef) discard;
                surface = PlainSurface(SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir), albedo.a);
            }
            #ifndef WORLD_NETHER
            if (!IsWater(blockId)) {
                // Seen through the water surface - glass sunk in water from above it, or glass
                // above the water from below: the water draws itself over this as an opaque
                // surface (it refracts the scene behind it, which cannot include translucent
                // blocks), so only the tint reaches the image, faded by the water in between.
                vec3 inside = playerPos + cameraPosition - surf.normal * 0.05;
                float surfaceY = ColumnWaterSurface(inside);
                bool underWater = surfaceY > inside.y;
                if ((isEyeInWater == 1) != underWater) {
                    vec3 transmit;
                    if (isEyeInWater == 1) {
                        // As the underwater fog, and only inside Snell's window: outside it the
                        // surface mirrors the water below instead (critical angle ~48.6 degrees).
                        float upward = EyeDir(playerPos).y;
                        transmit = vec3(exp(-length(playerPos) * 0.06) * smoothstep(0.60, 0.72, upward));
                    } else {
                        // Fades as fast as the water hides the ground behind it (the water's
                        // brightness transmittance, see ShadeWater).
                        float viewDown = max(-EyeDir(playerPos).y, 0.05);
                        vec3 waterT = exp(-(surfaceY - inside.y) / viewDown * WaterAbsorption());
                        transmit = vec3(Luminance(waterT));
                    }
                    surface.color = vec3(0.0);
                    surface.alpha = 0.0;
                    surface.tint = mix(vec3(1.0), surface.tint, transmit);
                }
            }
            #endif
            float fogAmount = BorderFogAmount(length(playerPos));
            outColor = vec4(ApplyFog(surface.color, playerPos, sunDir, false), surface.alpha);
            // Alpha 0 marks "translucent terrain in front" for TAA (taa.glsl): only there does
            // it also follow what is behind (not behind translucent mobs or players).
            outTint = vec4(mix(surface.tint, vec3(1.0), fogAmount), 0.0);
        #elif defined TRANSLUCENT_OIT
            if (albedo.a < alphaTestRef) discard;
            albedo.rgb = mix(albedo.rgb, entityColor.rgb, entityColor.a); // hurt flash
            vec3 lit = SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir);
            if (albedo.a > 0.99) {
                // Solid texels (player skins, most of any mob): drawn like an opaque surface,
                // replacing what is behind. As order-independent layers they would add up
                // with the body parts behind them and look see-through. Written to the scene
                // directly and marked "keep", so it survives whether Iris draws this before
                // or after the deferred pass.
                outOpaque = vec4(ApplyFog(lit, playerPos, sunDir, false), 1.0);
                // Also into the scene copy water refracts (colortex7, made by the deferred
                // pass, which Iris may run before this): else water drawn over a player or
                // mob in it would hide them.
                outSceneCopy = outOpaque;
                outKeep = vec4(0.0, 0.0, 0.0, 1.0);
                outTransmit = vec4(1.0);
                outLight = vec4(0.0, 0.0, 0.0, 1.0);
            } else {
                // Really see-through texels (slime, ghosts, invisible players): layers.
                TranslucentOut layer = AlphaLayer(lit, albedo.a);
                layer = FogLayer(layer, BorderFogAmount(length(playerPos)));
                outTransmit = vec4(layer.transmit, 1.0);
                outLight = vec4(layer.light, 1.0);
                outOpaque = vec4(0.0);
                outSceneCopy = vec4(0.0);
                outKeep = vec4(0.0);
            }
        #else
            if (albedo.a < alphaTestRef) discard;
            vec3 color = SrgbToLinear(albedo.rgb) * GetLighting(surf, sunDir, lightDir);

            #ifdef PROG_GBUFFERS_WEATHER
                // Rain and snow: see-through streaks, lit like the air around them (cooler
                // and heavier or warmer and lighter by Rain Style); snow stays bright.
                bool snow = albedo.b > 0.0 && abs(albedo.r - albedo.b) < 0.08 && Luminance(albedo.rgb) > 0.6;
                #if RAIN_STYLE == 1
                    if (!snow) color *= vec3(0.80, 0.92, 1.10);
                    albedo.a *= WEATHER_OPACITY * 1.25;
                #else
                    if (!snow) color *= vec3(1.00, 0.98, 0.94);
                    albedo.a *= WEATHER_OPACITY;
                #endif
                albedo.a = saturate(albedo.a);
            #endif
            #ifdef GLOWING_LAVA_PARTICLES
            #ifdef PROG_GBUFFERS_TEXTURED
                // Lava pops, embers and flames glow (M10): bright orange particles.
                if (albedo.r > 0.6 && albedo.g < albedo.r * 0.8 && albedo.b < 0.35) color += SrgbToLinear(albedo.rgb) * 3.0;
            #endif
            #endif
            outColor = vec4(ApplyFog(color, playerPos, sunDir, false), albedo.a);
            #ifdef ORDER_SAFE_LAYER
                outMaterial = vec4(0.0);
            #endif
        #endif
    #endif
}

#endif
