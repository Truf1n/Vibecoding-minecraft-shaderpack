// Final output: exposure, tonemap, encode, dither. Also hosts the debug views.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

out vec2 texCoord;

void main() {
    gl_Position = ftransform();
    texCoord = gl_MultiTexCoord0.xy;
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/encoding.glsl"

uniform sampler2D colortex0;
#if DEBUG_VIEW > 0
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
#endif

in vec2 texCoord;

layout(location = 0) out vec4 outColor;

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

// Interleaved gradient noise (Jimenez 2014): breaks up 8-bit banding in skies.
float Dither(vec2 pixel) { return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715)))); }

vec3 ToDisplay(vec3 hdr) { return Saturation(Tonemap(hdr * TM_EXPOSURE), T_SATURATION); }

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = ToDisplay(texelFetch(colortex0, pixel, 0).rgb);

    #if IMAGE_SHARPENING > 0
        // Contrast-adaptive sharpening (after the tonemap): sharpen less where the local
        // contrast is already high, so edges do not ring.
        vec3 n = ToDisplay(texelFetch(colortex0, pixel + ivec2(0, 1), 0).rgb);
        vec3 s = ToDisplay(texelFetch(colortex0, pixel - ivec2(0, 1), 0).rgb);
        vec3 e = ToDisplay(texelFetch(colortex0, pixel + ivec2(1, 0), 0).rgb);
        vec3 w = ToDisplay(texelFetch(colortex0, pixel - ivec2(1, 0), 0).rgb);
        vec3 lo = min(color, min(min(n, s), min(e, w)));
        vec3 hi = max(color, max(max(n, s), max(e, w)));
        vec3 amount = sqrt(saturate(min(lo, 1.0 - hi) / max(hi, 1e-4)));
        vec3 weight = -amount * float(IMAGE_SHARPENING) * 0.025;
        color = saturate((color + (n + s + e + w) * weight) / (1.0 + 4.0 * weight));
    #endif

    color = LinearToSrgb(color);
    color += (Dither(gl_FragCoord.xy) - 0.5) / 255.0;

    #if DEBUG_VIEW == 1
        color = texelFetch(colortex1, pixel, 0).rgb;
    #elif DEBUG_VIEW == 2
        color = DecodeNormal(texelFetch(colortex2, pixel, 0).xy) * 0.5 + 0.5;
    #elif DEBUG_VIEW == 3
        color = vec3(texelFetch(colortex2, pixel, 0).zw, 0.0);
    #elif DEBUG_VIEW == 4
        int sm = DecodeId(texelFetch(colortex3, pixel, 0).r);
        const vec3 palette[6] = vec3[6](vec3(0.0), vec3(0.6), vec3(0.2, 0.9, 0.2), vec3(0.0, 0.5, 0.1), vec3(0.9, 0.4, 0.1), vec3(0.3, 0.5, 1.0));
        color = palette[clamp(sm, 0, 5)];
    #elif DEBUG_VIEW == 5
        color = vec3(texelFetch(colortex1, pixel, 0).a);
    #elif DEBUG_VIEW == 6
        color = vec3(texelFetch(colortex3, pixel, 0).g);
    #endif

    outColor = vec4(color, 1.0);
}

#endif
