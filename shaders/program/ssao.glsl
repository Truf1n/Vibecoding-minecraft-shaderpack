// Ground-truth ambient occlusion (deferred1, docs/WORLD_MODEL.md F2, plan item Q1), and the
// half-size soft sun shadows (P19/P20, with Half-Size Shadows) in the same pass. AO: soft
// contact shadows in corners, where blocks meet, under overhangs and around mobs, plus the
// "bent normal": the direction the surface sees the most sky in, which steers its sky light.
// Half size (size.buffer.colortex15). Horizon-based (GTAO, Jimenez 2016): in a few screen
// directions (slices), the highest horizon on each side of the pixel within ~1 block is
// found, and the cosine-weighted share of the hemisphere above them is integrated exactly.
// The slices turn every frame and the pass keeps a history of its own; the lighting pass upsamples the
// result with a depth-aware blur and adds the multi-bounce correction (bright surfaces lose
// less light to occlusion and keep their colour). Only ambient, bounce and block light are
// darkened, never sunlight. Positions go through the projection matrices both ways, which
// carry Minecraft's view bobbing, so the occlusion stays put on the blocks while walking.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"
#include "/lib/util/reprojection.glsl"
#include "/lib/materials/blockIds.glsl"
#if defined HALF_RES_SHADOWS && !defined WORLD_NETHER
    #define SUN_SHADOWS_HERE
    #include "/lib/atmosphere/sky.glsl"
    #include "/lib/lighting/shadowSpace.glsl"
    #include "/lib/lighting/shadows.glsl"
    uniform sampler2D colortex3;
#endif

uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D colortex15; // the previous frames' result (this pass reads it and writes the next)

/* RENDERTARGETS: 15 */
// r: height of the bent normal (*0.5+0.5; all the lighting uses of it), g: occlusion
// (1 = open), b: sunlight past opaque casters (soft shadows, Half-Size Shadows), a: depth
// (log, for checking the history)
layout(location = 0) out vec4 outAO;

float EncodeAODepth(float linear) { return log2(1.0 + linear) / log2(1.0 + far); }
float DecodeAODepth(float e) { return exp2(e * log2(1.0 + far)) - 1.0; }

// Few samples per frame (P14): the slices turn every frame and the result is blended with
// the previous frames' (re-projected), so over a few frames many directions add up.
#if SSAO == 2
    const int AO_SLICES = 2;
    const int AO_STEPS = 5;
#else
    const int AO_SLICES = 1;
    const int AO_STEPS = 4;
#endif
const float AO_RADIUS = 1.1; // blocks

// Ground-truth AO at a pixel: xyz bent normal (world), w occlusion.
vec4 GroundTruthAO(vec2 uv, float depth, vec3 worldNormal, vec2 size, vec2 screen) {
    vec3 normal = normalize(mat3(gbufferModelView) * worldNormal);
    // Lifted a hair off the surface (more far away, where depth precision runs out), so a
    // flat surface never shadows itself.
    vec3 viewPos = ScreenToView(uv, depth);
    viewPos += normal * (0.01 + 0.002 * -viewPos.z);
    vec3 V = normalize(-viewPos);

    // Screen radius of the search (in uv), from the world radius at this depth.
    float radiusUV = AO_RADIUS * gbufferProjection[1][1] * 0.5 / max(-viewPos.z, 0.1);
    // Far away the search covers only a few pixels: fade out smoothly (not cut off, which
    // would pop on and off at that distance as you move).
    float distanceFade = smoothstep(2.0, 6.0, radiusUV * size.y);
    if (distanceFade <= 0.0) return vec4(worldNormal, 1.0);

    float noise = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 16) * 0.618034);
    float stepJitter = fract(noise * 7.31 + 0.37);
    float visibility = 0.0;
    vec3 bent = vec3(0.0);
    for (int s = 0; s < AO_SLICES; s++) {
        float phi = (float(s) + noise) * PI / float(AO_SLICES);
        vec2 dir = vec2(cos(phi), sin(phi));
        vec3 dirV = vec3(dir, 0.0);
        vec3 orthoDir = dirV - dot(dirV, V) * V;
        vec3 axis = normalize(cross(dirV, V));
        vec3 projN = normal - axis * dot(normal, axis);
        float projLen = length(projN);
        if (projLen < 1e-4) continue;
        float cosN = clamp(dot(projN, V) / projLen, -1.0, 1.0);
        float n = sign(dot(orthoDir, projN)) * acos(cosN);

        // Highest horizon on each side (as the cosine of its angle from the view direction).
        float horizonCos[2] = float[2](-1.0, -1.0);
        for (int side = 0; side < 2; side++) {
            vec2 sideDir = dir * (side == 0 ? -1.0 : 1.0) * vec2(size.y / size.x, 1.0);
            for (int i = 0; i < AO_STEPS; i++) {
                float t = (float(i) + stepJitter) / float(AO_STEPS);
                // At least one pixel out, so the first step never reads this pixel itself.
                vec2 offset = sideDir * max(radiusUV * t * t, 1.5 / screen.y);
                ivec2 samplePixel = ivec2((uv + offset) * screen);
                if (any(lessThan(samplePixel, ivec2(0))) || any(greaterThanEqual(samplePixel, ivec2(screen)))) break;
                float sampleDepth = texelFetch(depthtex0, samplePixel, 0).r;
                if (sampleDepth < 0.56) continue; // the held item hides nothing
                vec3 d = ScreenToView((vec2(samplePixel) + 0.5) / screen, sampleDepth) - viewPos;
                float len2 = dot(d, d);
                float c = dot(d, V) * inversesqrt(max(len2, 1e-6));
                // Farther than the radius counts less (a separate object behind).
                float falloff = saturate(1.0 - len2 / (AO_RADIUS * AO_RADIUS * 1.5));
                horizonCos[side] = max(horizonCos[side], mix(-1.0, c, falloff));
            }
        }
        float h0 = n + max(-acos(horizonCos[0]) - n, -PI * 0.5);
        float h1 = n + min(acos(horizonCos[1]) - n, PI * 0.5);
        float sinN = sin(n);
        float arc0 = -cos(2.0 * h0 - n) + cosN + 2.0 * h0 * sinN;
        float arc1 = -cos(2.0 * h1 - n) + cosN + 2.0 * h1 * sinN;
        visibility += projLen * 0.25 * (arc0 + arc1);
        // Bent normal: the middle of the open arc in this slice.
        float mid = (h0 + h1) * 0.5;
        bent += projLen * (V * cos(mid) + normalize(orthoDir) * sin(mid));
    }
    float ao = saturate(visibility / float(AO_SLICES));
    // Fade out towards the screen edges, where much of the surroundings is off screen.
    vec2 edge = smoothstep(vec2(0.0), vec2(0.06), uv) * smoothstep(vec2(0.0), vec2(0.06), 1.0 - uv);
    float edgeFade = edge.x * edge.y * distanceFade;
    ao = mix(1.0, ao, edgeFade);
    vec3 bentWorld = dot(bent, bent) > 1e-6 ? normalize(mat3(gbufferModelViewInverse) * normalize(bent)) : worldNormal;
    bentWorld = normalize(mix(worldNormal, bentWorld, edgeFade));
    return vec4(bentWorld, ao);
}

void main() {
    vec2 size = floor(vec2(viewWidth, viewHeight) * 0.5);
    vec2 screen = vec2(viewWidth, viewHeight);
    // Every position is rebuilt at the centre of the full-size pixel whose depth it reads:
    // anywhere else, on ground seen at a low angle (where the depth changes fast from pixel
    // to pixel), the point lands off the surface and makes false occlusion, in blotches.
    ivec2 pixel = ivec2(gl_FragCoord.xy) * 2;
    vec2 uv = (vec2(pixel) + 0.5) / screen;
    float depth = texelFetch(depthtex0, pixel, 0).r;
    vec3 worldNormal = DecodeNormal(texelFetch(colortex2, pixel, 0).xy);
    outAO = vec4(worldNormal.y * 0.5 + 0.5, 1.0, 1.0, 1.0);
    if (depth >= 1.0 || depth < 0.56) return; // sky, held item

    #if SSAO > 0
        vec4 aoResult = GroundTruthAO(uv, depth, worldNormal, size, screen);
    #else
        vec4 aoResult = vec4(worldNormal, 1.0); // (the pass runs for the shadows alone)
    #endif
    float sunVis = 1.0;
    #ifdef SUN_SHADOWS_HERE
        // Soft sun shadows at half size (P19), with half the filter taps per frame and
        // added up over frames below (P20); the lighting pass upsamples them. Faces turned
        // away from the sun get none (the upsample keeps them apart by their normals).
        vec3 playerPos = ViewToPlayer(ScreenToView(uv, depth));
        int model = DecodeId(texelFetch(colortex3, pixel, 0).r);
        bool foliage = model == SM_FOLIAGE || model == SM_LEAVES;
        vec3 L = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
        // (Where no sky light reaches, the lighting never asks for the sun: caves.)
        float skylight = texelFetch(colortex2, pixel, 0).w;
        if (skylight > 0.05 && (foliage || dot(worldNormal, L) > 0.0)) {
            shadowFilterQuality = 3;
            GetShadow(playerPos, worldNormal, foliage);
            sunVis = shadowLastOpaque;
        } else {
            sunVis = 0.0;
        }
    #endif

    float linear = -ScreenToView(uv, depth).z;
    vec4 result = vec4(aoResult.y * 0.5 + 0.5, aoResult.w, sunVis, EncodeAODepth(linear));

    // Blend with the previous frames where this spot was then. A history at another depth
    // than this spot had then belonged to another surface (it moved in or out): not used.
    // Shadows take a shorter history than the occlusion (they move with mobs and the sun).
    vec2 prevUV = ReprojectToPreviousFrame(uv, depth);
    if (all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        vec4 history = texture(colortex15, prevUV);
        vec3 worldPos = ViewToPlayer(ScreenToView(uv, depth)) + cameraPosition;
        float expected = -(gbufferPreviousModelView * vec4(worldPos - previousCameraPosition, 1.0)).z;
        float match = 1.0 - smoothstep(0.04, 0.08, abs(DecodeAODepth(history.a) - expected) / max(expected, 0.1));
        float motion = length((prevUV - uv) * size);
        float trust = match * (1.0 - 0.4 * smoothstep(2.0, 10.0, motion));
        result.rg = mix(result.rg, history.rg, 0.8 * trust);
        result.b = mix(result.b, history.b, 0.5 * trust);
    }
    outAO = result;
}

#endif
