// Deferred resolve (deferred2, after the cloud and ambient occlusion passes): draws the sky behind everything,
// lights every opaque G-buffer pixel once, adds the volumetric clouds to the sky (so water
// reflects and refracts them), then composites the pre-deferred overlay (vanilla clouds,
// glint, glowing eyes, beacon beams).

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texCoord;
flat out vec3 sunDir;
flat out vec3 lightDir;

void main() {
    gl_Position = ftransform();
    texCoord = gl_MultiTexCoord0.xy;
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
}

#endif

#ifdef FRAGMENT_SHADER

uniform sampler2D depthtex0;
uniform sampler2D colortex3;
// lighting.glsl: contact shadows (traced through the depth buffer, so only here).
#define CONTACT_SHADOW_PASS

#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"
#include "/lib/atmosphere/sky.glsl"
#ifndef WORLD_NETHER
    #include "/lib/lighting/shadowSpace.glsl"
    #include "/lib/lighting/shadows.glsl"
#endif
#include "/lib/lighting/lighting.glsl"
#include "/lib/lighting/specular.glsl"
#include "/lib/atmosphere/fog.glsl"
#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
    #define VOLUMETRIC_CLOUDS
    #include "/lib/atmosphere/cloudBuffer.glsl"
#endif

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex4;
#if SSAO > 0 || (defined HALF_RES_SHADOWS && !defined WORLD_NETHER)
    #define HALF_SIZE_BUFFER
    uniform sampler2D colortex15; // half size (ssao.glsl): bent normal height, occlusion, sunlight, depth

    // Upsamples the half-size buffer. Occlusion and bent normal: a small blur that follows
    // the depth (so it does not bleed across edges and the per-frame slices smooth out).
    // Sunlight: only the four nearest, also matched by normal, so a face turned away from
    // the sun (none there) never darkens the edge of a lit one; -1 where none fits (thin
    // things the half-size buffer missed: the lighting then works it out itself).
    vec2 SampleHalfSize(ivec2 pixel, float depth, vec3 normal, out float sun) {
        vec2 screen = vec2(viewWidth, viewHeight);
        float linear = ScreenToView((vec2(pixel) + 0.5) / screen, depth).z;
        vec2 pos = vec2(pixel) * 0.5; // in half-size texels (texel t holds full-size pixel 2t)
        ivec2 base = ivec2(floor(pos));
        ivec2 maxTexel = textureSize(colortex15, 0) - 1;
        vec2 sum = vec2(0.0);
        float wsum = 0.0, sunSum = 0.0, sunWeight = 0.0;
        for (int y = -1; y <= 2; y++) {
            for (int x = -1; x <= 2; x++) {
                ivec2 t = clamp(base + ivec2(x, y), ivec2(0), maxTexel);
                vec2 d = vec2(t) - pos;
                ivec2 full = min(t * 2, ivec2(screen) - 1); // the pixel the half-size pass read
                vec4 v = texelFetch(colortex15, t, 0);
                #ifdef OPT_HALF_DEPTH_IN_BUFFER
                    // The depth the half-size pass stored with it (B1), instead of reading it
                    // again (16 reads and conversions per pixel); same log encoding as ssao.glsl.
                    float z = -(exp2(v.a * log2(1.0 + far)) - 1.0);
                #else
                    float z = ScreenToView((vec2(full) + 0.5) / screen, texelFetch(depthtex0, full, 0).r).z;
                #endif
                float depthWeight = exp(-abs(z - linear) / (0.05 * abs(linear) + 0.1));
                float w = exp(-dot(d, d) * 0.5) * depthWeight;
                sum += v.rg * w;
                wsum += w;
                if (x >= 0 && x <= 1 && y >= 0 && y <= 1) {
                    vec3 n = DecodeNormal(texelFetch(colortex2, full, 0).xy);
                    float sw = (1.0 - abs(d.x)) * (1.0 - abs(d.y)) * depthWeight * pow(saturate(dot(n, normal)), 8.0) + 1e-5;
                    sunSum += v.b * sw;
                    sunWeight += sw;
                }
            }
        }
        sun = sunWeight > 0.05 ? sunSum / sunWeight : -1.0;
        return sum / max(wsum, 1e-4);
    }

    // Multi-bounce (Jimenez 2016): light bouncing around inside a corner comes back off the
    // surface itself, so bright surfaces lose less to occlusion, and keep their colour.
    vec3 MultiBounceAO(float ao, vec3 albedo) {
        vec3 a = 2.0404 * albedo - 0.3324;
        vec3 b = -4.7951 * albedo + 0.6417;
        vec3 c = 2.7552 * albedo + 0.6903;
        return max(vec3(ao), ((ao * a + b) * ao + c) * ao);
    }
#endif

in vec2 texCoord;
flat in vec3 sunDir;
flat in vec3 lightDir;

#define EMISSION_BRIGHTNESS 2.5

/* RENDERTARGETS: 0,7 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSceneCopy; // read by screen-space reflections

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    float depth = texelFetch(depthtex0, pixel, 0).r;
    int shadingModel = DecodeId(texelFetch(colortex3, pixel, 0).r);
    vec3 playerPos = ViewToPlayer(ScreenToView(texCoord, depth));

    if (depth == 1.0) {
        // Sky: colortex0 holds only what vanilla drew on top (sun, moon), cleared to black.
        vec3 dir = EyeDir(playerPos);
        #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
            // The aurora, nebulae and rainbow come with the clouds here (drawn at the cloud
            // pass's resolution, P15): only the plain sky, stars and discs per pixel.
            color += isEyeInWater == 1 ? GetSkyFromUnderwater(dir, sunDir) : OverworldSky(dir, sunDir, PixelAngle(), true, false);
        #else
            color += isEyeInWater == 1 ? GetSkyFromUnderwater(dir, sunDir) : GetSky(dir, sunDir, PixelAngle());
        #endif
        #ifdef VOLUMETRIC_CLOUDS
            vec4 clouds = SampleClouds(texCoord);
            color = color * clouds.a + clouds.rgb;
        #endif
        color = ApplyFog(color, playerPos, sunDir, true);
    } else if (shadingModel != SM_KEEP) {
        vec4 albedoAo = texelFetch(colortex1, pixel, 0);
        vec4 normalLight = texelFetch(colortex2, pixel, 0);
        vec4 material = texelFetch(colortex3, pixel, 0);

        vec3 albedo = SrgbToLinear(albedoAo.rgb);
        vec3 normal = DecodeNormal(normalLight.xy);

        vec2 lm = normalLight.zw;

        // Rain (plan items R5, +5): exposed surfaces darken as they get wet, and water
        // collects in puddles on flat ground, with ripples from the raindrops.
        float puddle = 0.0, wet = 0.0;
        vec3 puddleNormal = normal;
        #ifdef WORLD_OVERWORLD
            if (shadingModel == SM_DEFAULT || shadingModel == SM_FOLIAGE || shadingModel == SM_LEAVES) {
                vec3 worldPos = playerPos + cameraPosition;
                #ifdef WET_SURFACES
                    wet = wetness * RainExposure(lm.y);
                #endif
                if (shadingModel == SM_DEFAULT) puddle = PuddleAmount(worldPos, normal.y, lm.y);
                if (puddle > 0.0) {
                    puddleNormal = vec3(0.0, 1.0, 0.0);
                    #ifdef RAIN_RIPPLES
                        vec2 ripple = RainRipples(worldPos.xz) * VisibleRain() * (1.0 - inDryBiome) * (1.0 - smoothstep(16.0, 48.0, length(playerPos)));
                        puddleNormal = normalize(vec3(-ripple.x, 1.0, -ripple.y));
                    #endif
                    puddleNormal = normalize(mix(normal, puddleNormal, puddle));
                }
                albedo *= 1.0 - 0.35 * max(wet, puddle);
                albedo = pow(albedo, vec3(1.0 + 0.25 * max(wet, puddle))); // wet colours look deeper
            }
        #endif

        Surface surf;
        surf.playerPos = playerPos;
        surf.normal = normal;
        surf.lm = lm;
        surf.ao = albedoAo.a;
        surf.foliage = shadingModel == SM_FOLIAGE || shadingModel == SM_LEAVES;
        surf.useShadowMap = shadingModel != SM_HAND; // hand depth uses its own projection

        #ifdef HALF_SIZE_BUFFER
            if (shadingModel != SM_HAND) {
                float sun;
                vec2 half_ = SampleHalfSize(pixel, depth, normal, sun);
                #if SSAO > 0
                    lightingAO = MultiBounceAO(pow(half_.g, SSAO_STRENGTH), albedo);
                    lightingBentUp = half_.r * 2.0 - 1.0;
                #endif
                #ifdef HALF_RES_SHADOWS
                #ifndef WORLD_NETHER
                    shadowOpaqueOverride = sun;
                #endif
                #endif
            }
        #endif
        vec3 sunLight;
        vec3 light = GetLighting(surf, sunDir, lightDir, sunLight);

        // Specular (X1): metals give most of their light back as reflection, so they keep
        // only a little diffuse light; what the surface reflects is added by the reflection
        // passes (deferred3/4), the sun/moon highlight here.
        float smoothness = material.b, metalness = material.a;
        vec3 V = -EyeDir(playerPos);
        float roughness = RoughnessFromSmoothness(smoothness);
        vec3 f0 = SpecularF0(albedo, metalness);
        vec3 F = FresnelRoughness(dot(normal, V), f0, roughness);
        // (Without the reflection passes nothing would give metals their light back, so
        // they stay fully diffuse.)
        float diffuseScale = 1.0;
        #if BLOCK_REFLECTIONS == 2
            diffuseScale = (1.0 - metalness * 0.8) * (1.0 - Luminance(F) * smoothness);
        #endif
        color = albedo * light * diffuseScale;
        #if BLOCK_REFLECTIONS >= 1
            if (smoothness > 0.05) {
                // Specular anti-aliasing: where the normal changes quickly between pixels
                // (bumpy texels, far away), widen the highlight so it cannot collapse into
                // single flickering white pixels.
                vec3 nRight = DecodeNormal(texelFetch(colortex2, pixel + ivec2(1, 0), 0).xy);
                vec3 nUp = DecodeNormal(texelFetch(colortex2, pixel + ivec2(0, 1), 0).xy);
                float variance = (2.0 - dot(normal, nRight) - dot(normal, nUp)) * 0.5;
                float distanceBlur = length(playerPos) * 0.0015;
                float aaRoughness = sqrt(roughness * roughness + min(2.0 * variance, 0.18)) + distanceBlur;
                color += sunLight * SpecularHighlight(normal, V, lightDir, max(aaRoughness, 0.05), f0) * smoothness;
            }
        #endif
        color += albedo * material.g * EMISSION_BRIGHTNESS;

        #ifdef WORLD_OVERWORLD
            // Puddles and wet surfaces mirror the sky (and the clouds); smooth for puddles,
            // a faint sheen at grazing angles for merely wet surfaces.
            float gloss = max(puddle, wet * 0.3);
            if (gloss > 0.01) {
                vec3 R = reflect(-V, puddleNormal);
                R.y = abs(R.y);
                vec3 refl = GetBlockSkyReflection(R, sunDir, PixelAngle());
                #ifdef VOLUMETRIC_CLOUDS
                    vec4 cloudsR = CloudsInDirection(R);
                    refl = refl * cloudsR.a + cloudsR.rgb;
                #endif
                refl *= lm.y * lm.y;
                float fresnel = (0.02 + 0.98 * pow(1.0 - saturate(dot(puddleNormal, V)), 5.0)) * gloss;
                color = mix(color, refl, fresnel);
                color += sunLight * SpecularHighlight(puddleNormal, V, lightDir, mix(0.5, 0.06, puddle), vec3(0.02)) * gloss;
                #ifdef COLORED_LIGHTING
                    // Block-light glints on puddles (Q7).
                    if (lm.x > 0.05) {
                        #ifdef OPT_VOLUME_GRADIENT
                            vec3 blockColor;
                            vec4 from;
                            WorldBlocklight(playerPos, vec3(0.0, 1.0, 0.0), lm.x, blockColor, from);
                        #else
                            vec4 from = BlocklightDirection(playerPos, vec3(0.0, 1.0, 0.0));
                            vec3 blockColor = WorldBlocklightColor(playerPos, vec3(0.0, 1.0, 0.0), lm.x);
                        #endif
                        blockColor *= BlocklightFalloff(lm.x) * BLOCKLIGHT_I;
                        color += blockColor * SpecularHighlight(puddleNormal, V, from.xyz, mix(0.5, 0.1, puddle), vec3(0.02)) * gloss * from.w;
                    }
                #endif
            }
        #endif
        color = ApplyFog(color, playerPos, sunDir, false);
    }

    // (Clouds in front of terrain, water and everything else are added in composite, after
    // the translucent pass.)

    vec4 overlay = texelFetch(colortex4, pixel, 0);
    color = color * (1.0 - overlay.a) + overlay.rgb;

    outColor = vec4(color, 1.0);
    outSceneCopy = vec4(color, 1.0);
}

#endif
