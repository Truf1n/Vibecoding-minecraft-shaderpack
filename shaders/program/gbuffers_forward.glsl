// Forward-rendered geometry. One template, selected by the wrapper's FWD_* define:
//   FWD_SKY       sky disc, sunset fan, stars, void          -> colortex0
//   FWD_SKYTEX    sun / moon / custom sky textures            -> colortex0
//   FWD_OVERLAY   vanilla clouds, glint, glowing eyes, beams  -> colortex4 (premultiplied overlay)
//   FWD_UNLIT     leads, debug lines, selection outline       -> colortex0 + shading model "keep"
//   FWD_LIT       water/translucents, particles, weather      -> colortex0 (drawn after deferred)
//   FWD_DAMAGE    block-breaking cracks                       -> multiplies the G-buffer albedo

#include "/lib/common.glsl"
#include "/lib/materials/blockIds.glsl"

#ifdef VERTEX_SHADER

#ifdef PROG_GBUFFERS_WATER
in vec2 mc_Entity;
#endif

out vec2 texCoord;
out vec2 lmCoord;
out vec4 vertColor;
out vec3 playerPos;
out float NdotL;
flat out int blockId;

void main() {
    texCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmCoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    vertColor = gl_Color;

    vec3 viewPos = (gl_ModelViewMatrix * gl_Vertex).xyz;
    playerPos = mat3(gbufferModelViewInverse) * viewPos;

    #if defined PROG_GBUFFERS_TEXTURED || defined PROG_GBUFFERS_WEATHER
        NdotL = -1.0; // camera-facing sprites: no meaningful normal
    #else
        vec3 viewNormal = normalize(gl_NormalMatrix * gl_Normal);
        NdotL = saturate(dot(viewNormal, normalize(shadowLightPosition)));
    #endif

    #ifdef PROG_GBUFFERS_WATER
        blockId = int(mc_Entity.x + 0.5);
    #else
        blockId = 0;
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
        gl_Position = ftransform();
    #endif
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/util/space.glsl"
#include "/lib/lighting/basicLighting.glsl"
#include "/lib/lighting/basicFog.glsl"

uniform sampler2D gtexture;

in vec2 texCoord;
in vec2 lmCoord;
in vec4 vertColor;
in vec3 playerPos;
in float NdotL;
flat in int blockId;

#if defined FWD_UNLIT
    /* RENDERTARGETS: 0,3 */
    layout(location = 0) out vec4 outColor;
    layout(location = 1) out vec4 outMaterial;
#elif defined FWD_OVERLAY
    /* RENDERTARGETS: 4 */
    layout(location = 0) out vec4 outColor;
#elif defined FWD_DAMAGE
    /* RENDERTARGETS: 1 */
    layout(location = 0) out vec4 outColor;
#else
    /* RENDERTARGETS: 0 */
    layout(location = 0) out vec4 outColor;
#endif

void main() {
    #if defined FWD_SKY
        vec3 viewPos = ScreenToView(gl_FragCoord.xy / vec2(viewWidth, viewHeight), 1.0);
        float upDot = dot(normalize(viewPos), normalize(upPosition));
        vec3 horizon = SrgbToLinear(fogColor);
        vec3 color = mix(horizon, SrgbToLinear(skyColor), smoothstep(-0.05, 0.45, upDot));
        float alpha = 1.0;

        if (renderStage == MC_RENDER_STAGE_STARS) {
            color = SrgbToLinear(vertColor.rgb) * 1.5;
            alpha = vertColor.a;
        } else if (renderStage == MC_RENDER_STAGE_SUNSET) {
            color = SrgbToLinear(vertColor.rgb);
            alpha = vertColor.a;
        } else if (renderStage == MC_RENDER_STAGE_VOID) {
            color = horizon * 0.2;
        }
        outColor = vec4(ApplyFog(color, viewPos, true), alpha); // viewPos is on the far plane

    #elif defined FWD_SKYTEX
        vec4 albedo = texture(gtexture, texCoord) * vertColor;
        outColor = vec4(SrgbToLinear(albedo.rgb) * 2.0, albedo.a);

    #elif defined FWD_OVERLAY
        #ifdef OVERLAY_NO_TEXTURE
            vec4 albedo = vertColor;
        #else
            vec4 albedo = texture(gtexture, texCoord) * vertColor;
        #endif
        if (albedo.a < 0.004) discard;
        vec3 color = SrgbToLinear(albedo.rgb);

        #if defined OVERLAY_CLOUDS
            color *= GetBasicLighting(vec2(0.0, 1.0), -1.0, 1.0, false);
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
        vec4 crack = texture(gtexture, texCoord);
        if (crack.a < 0.1) discard;
        outColor = vec4(crack.rgb, 1.0); // blended as dst * 2src (vanilla), so 0.5 is neutral

    #else // FWD_LIT
        vec4 albedo = texture(gtexture, texCoord) * vertColor;
        if (albedo.a < alphaTestRef) discard;

        vec2 lm = RemapLightmap(lmCoord);
        lm.x = max(lm.x, HeldLight(length(playerPos)));
        vec3 color = SrgbToLinear(albedo.rgb) * GetBasicLighting(lm, NdotL, 1.0, false);

        #ifdef PROG_GBUFFERS_WEATHER
            albedo.a *= 0.6;
        #endif
        outColor = vec4(ApplyFog(color, playerPos, false), albedo.a);
    #endif
}

#endif
