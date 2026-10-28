// Post-processing (composite5, plan items K1, K3, K4, K9, H3): chromatic aberration,
// bloom, exposure, tonemap, colour balance and grading, vignette. Writes the display image
// (sRGB) for the final pass, which adds FXAA, sharpening and dithering.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/post/bloomTiles.glsl"

#ifdef TAA
    uniform sampler2D colortex8; // the TAA pass leaves the finished image in its history
    #define sceneTex colortex8
#else
    uniform sampler2D colortex0;
    #define sceneTex colortex0
#endif
#ifdef BLOOM
    uniform sampler2D colortex13;
    uniform sampler2D depthtex0;
#endif

/* RENDERTARGETS: 14 */
layout(location = 0) out vec4 outDisplay;

// Filmic curve (Lottes 2016): x^a / (x^(a*d) * b + c), solved so mid grey 0.18 -> 0.22
// and TM_WHITE_PATH -> 1. Per channel, so very bright colours drift towards white.
vec3 Tonemap(vec3 x) {
    const float a = TM_CONTRAST;
    const float d = 0.95;
    const float hdrMax = TM_WHITE_PATH;
    const float midIn = 0.18;
    const float midOut = 0.22;
    float hA = pow(hdrMax, a), hAD = pow(hdrMax, a * d), mA = pow(midIn, a), mAD = pow(midIn, a * d);
    float b = (-mA + hA * midOut) / ((hAD - mAD) * midOut);
    float c = (hAD * mA - hA * mAD * midOut) / ((hAD - mAD) * midOut);
    x = max(x, 0.0);
    return saturate(pow(x, vec3(a)) / (pow(x, vec3(a * d)) * b + c));
}

vec3 Saturation(vec3 c, float s) { return max(mix(vec3(Luminance(c)), c, s), 0.0); }

#ifdef BLOOM
    // One bloom tile at a screen position: smooth (cubic B-spline from four bilinear taps),
    // and kept inside the tile.
    vec3 BloomTile(int k, vec2 uv) {
        vec2 size = vec2(textureSize(colortex13, 0));
        float scale = BloomTileScale(k);
        vec2 margin = 1.5 / (size * scale);
        vec2 pos = (BloomTileOffset(k) + clamp(uv, margin, 1.0 - margin) * scale) * size;

        vec2 center = floor(pos - 0.5) + 0.5;
        vec2 f = pos - center;
        vec2 f2 = f * f, f3 = f2 * f;
        vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
        vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
        vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
        vec2 w3 = f3 / 6.0;
        vec2 g0 = w0 + w1, g1 = w2 + w3;
        vec2 p0 = (center - 1.0 + w1 / g0) / size;
        vec2 p1 = (center + 1.0 + w3 / g1) / size;
        return g0.y * (g0.x * textureLod(colortex13, p0, 0.0).rgb + g1.x * textureLod(colortex13, vec2(p1.x, p0.y), 0.0).rgb)
             + g1.y * (g0.x * textureLod(colortex13, vec2(p0.x, p1.y), 0.0).rgb + g1.x * textureLod(colortex13, p1, 0.0).rgb);
    }

    vec3 Bloom(vec2 uv) {
        vec3 sum = vec3(0.0);
        for (int k = 0; k < BLOOM_TILES; k++) sum += BloomTile(k, uv);
        return sum / float(BLOOM_TILES);
    }

    // How much of the image is replaced by its blurred copy: more in damp air (rain,
    // caves, under water) and in the Nether's haze.
    float BloomAmount() {
        float fog = rainStrength * 0.6 + caveFactor * 0.6 + (isEyeInWater == 1 ? 1.0 : 0.0);
        #ifdef WORLD_NETHER
            fog += 0.5;
        #endif
        return saturate(0.06 * BLOOM_STRENGTH * (1.0 + BLOOM_FOG * fog));
    }

    // Distant light bloom (plan item K8): far away, at night and in caves, lights spread a
    // little wider, as if scattered by the air in between.
    float DistantBloom(vec2 uv) {
        if (DISTANT_LIGHT_BLOOM <= 0.0) return 1.0;
        float depth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;
        if (depth >= 1.0 || depth < 0.56) return 1.0;
        vec4 view = gbufferProjectionInverse * vec4(vec3(uv, depth) * 2.0 - 1.0, 1.0);
        float dist = length(view.xyz / view.w);
        float dark = max(1.0 - smoothstep(-0.1, 0.1, SunElevation()), caveFactor);
        return 1.0 + 2.5 * DISTANT_LIGHT_BLOOM * smoothstep(40.0, 160.0, dist) * dark;
    }
#endif

void main() {
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);

    vec3 color;
    #if CHROMATIC_ABERRATION > 0
        // Red and blue land slightly apart towards the edges of the screen, as in a lens.
        vec2 fromCenter = uv - 0.5;
        vec2 shift = fromCenter * dot(fromCenter, fromCenter) * (float(CHROMATIC_ABERRATION) * 0.012);
        color.r = textureLod(sceneTex, uv - shift, 0.0).r;
        color.g = textureLod(sceneTex, uv, 0.0).g;
        color.b = textureLod(sceneTex, uv + shift, 0.0).b;
    #else
        color = texelFetch(sceneTex, ivec2(gl_FragCoord.xy), 0).rgb;
    #endif

    #ifdef BLOOM
        color = mix(color, Bloom(uv), saturate(BloomAmount() * DistantBloom(uv)));
    #endif

    color *= TM_EXPOSURE;
    // Dark desaturation: little colour is seen in the darkest parts of the image.
    float lum = Luminance(color);
    color = mix(color, vec3(lum), CB_DARK_DESATURATION * exp(-lum * 60.0));

    color = Tonemap(color);
    color = Saturation(color, T_SATURATION);
    // Vibrance: dull colours gain (or lose) more saturation than vivid ones.
    float chroma = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
    color = Saturation(color, 1.0 + (CB_VIBRANCE - 1.0) * (1.0 - chroma));

    // Grading: channel mixing matrix (rows: output R, G, B) and per-channel curves.
    const mat3 grade = mat3(GRADE_RR, GRADE_GR, GRADE_BR,
                            GRADE_RG, GRADE_GG, GRADE_BG,
                            GRADE_RB, GRADE_GB, GRADE_BB);
    color = saturate(grade * color);
    color = pow(color, 1.0 / vec3(GRADE_CURVE_R, GRADE_CURVE_G, GRADE_CURVE_B));

    float edge = length((uv - 0.5) * vec2(viewWidth / viewHeight, 1.0)) / length(vec2(viewWidth / viewHeight, 1.0) * 0.5);
    color *= 1.0 - VIGNETTE * 0.6 * smoothstep(0.35, 1.1, edge);

    outDisplay = vec4(LinearToSrgb(color), 1.0);
}

#endif
