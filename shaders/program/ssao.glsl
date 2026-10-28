// Ground-truth ambient occlusion (deferred1, docs/WORLD_MODEL.md F2, plan item Q1): soft
// contact shadows in corners, where blocks meet, under overhangs and around mobs, plus the
// "bent normal": the direction the surface sees the most sky in, which steers its sky light.
// Half size (size.buffer.colortex15). Horizon-based (GTAO, Jimenez 2016): in a few screen
// directions (slices), the highest horizon on each side of the pixel within ~1 block is
// found, and the cosine-weighted share of the hemisphere above them is integrated exactly.
// The slices turn a little every frame (TAA blends them); the lighting pass upsamples the
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

uniform sampler2D colortex2;
uniform sampler2D depthtex0;

/* RENDERTARGETS: 15 */
layout(location = 0) out vec4 outAO; // rgb: bent normal (world, *0.5+0.5), a: occlusion (1 = open)

#if SSAO == 2
    const int AO_SLICES = 3;
    const int AO_STEPS = 6;
#else
    const int AO_SLICES = 2;
    const int AO_STEPS = 4;
#endif
const float AO_RADIUS = 1.1; // blocks

vec3 ViewToScreenAO(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return clip.xyz / clip.w * 0.5 + 0.5;
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
    outAO = vec4(worldNormal * 0.5 + 0.5, 1.0);
    if (depth >= 1.0 || depth < 0.56) return; // sky, held item

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
    if (distanceFade <= 0.0) return;

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
    outAO = vec4(bentWorld * 0.5 + 0.5, ao);
}

#endif
