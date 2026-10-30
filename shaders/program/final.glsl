// Final output: FXAA, sharpening and dithering of the display image from the post pass
// (composite4). Also hosts the debug views.

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

uniform sampler2D colortex14; // display image (sRGB) from the post pass
#if DEBUG_VIEW > 0
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D colortex3;
#endif

in vec2 texCoord;

layout(location = 0) out vec4 outColor;

vec3 Display(ivec2 p) { return texelFetch(colortex14, p, 0).rgb; }
vec3 DisplayAt(vec2 uv) { return textureLod(colortex14, uv, 0.0).rgb; }
float Luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

#ifdef FXAA
    // FXAA 3.11 (Lottes), quality version: find the edge through the pixel, walk along it
    // to both ends, and blend across it by how far the pixel is from the nearer end.
    vec3 Fxaa(ivec2 pixel, vec2 uv) {
        vec2 rcp = 1.0 / vec2(viewWidth, viewHeight);
        vec3 rgbM = Display(pixel);
        float lumaM = Luma(rgbM);
        float lumaN = Luma(Display(pixel + ivec2(0, 1)));
        float lumaS = Luma(Display(pixel - ivec2(0, 1)));
        float lumaE = Luma(Display(pixel + ivec2(1, 0)));
        float lumaW = Luma(Display(pixel - ivec2(1, 0)));
        float lumaMax = max(lumaM, max(max(lumaN, lumaS), max(lumaE, lumaW)));
        float lumaMin = min(lumaM, min(min(lumaN, lumaS), min(lumaE, lumaW)));
        float range = lumaMax - lumaMin;
        if (range < max(0.0312, lumaMax * 0.125)) return rgbM;

        float lumaNW = Luma(Display(pixel + ivec2(-1, 1)));
        float lumaNE = Luma(Display(pixel + ivec2(1, 1)));
        float lumaSW = Luma(Display(pixel + ivec2(-1, -1)));
        float lumaSE = Luma(Display(pixel + ivec2(1, -1)));

        // Sub-pixel aliasing (single bright or dark pixels).
        float lumaL = ((lumaN + lumaS + lumaE + lumaW) * 2.0 + (lumaNW + lumaNE + lumaSW + lumaSE)) / 12.0;
        float subpix = smoothstep(0.0, 1.0, saturate(abs(lumaL - lumaM) / range));
        subpix = subpix * subpix * FXAA_SUBPIXEL;

        float edgeHorz = abs(lumaNW - 2.0 * lumaN + lumaNE) + 2.0 * abs(lumaW - 2.0 * lumaM + lumaE) + abs(lumaSW - 2.0 * lumaS + lumaSE);
        float edgeVert = abs(lumaNW - 2.0 * lumaW + lumaSW) + 2.0 * abs(lumaN - 2.0 * lumaM + lumaS) + abs(lumaNE - 2.0 * lumaE + lumaSE);
        bool horzSpan = edgeHorz >= edgeVert;

        // Which side of the pixel the edge lies on.
        float luma1 = horzSpan ? lumaS : lumaW;
        float luma2 = horzSpan ? lumaN : lumaE;
        float grad1 = abs(luma1 - lumaM), grad2 = abs(luma2 - lumaM);
        float lengthSign = horzSpan ? rcp.y : rcp.x;
        float lumaSide = luma2;
        if (grad1 >= grad2) { lengthSign = -lengthSign; lumaSide = luma1; }
        float gradientScaled = 0.25 * max(grad1, grad2);
        float lumaLocalAvg = 0.5 * (lumaSide + lumaM);

        // Walk along the edge in both directions until its contrast ends.
        vec2 posB = uv;
        if (horzSpan) posB.y += lengthSign * 0.5; else posB.x += lengthSign * 0.5;
        vec2 offNP = horzSpan ? vec2(rcp.x, 0.0) : vec2(0.0, rcp.y);
        vec2 posN = posB - offNP, posP = posB + offNP;
        float lumaEndN = Luma(DisplayAt(posN)) - lumaLocalAvg;
        float lumaEndP = Luma(DisplayAt(posP)) - lumaLocalAvg;
        bool doneN = abs(lumaEndN) >= gradientScaled, doneP = abs(lumaEndP) >= gradientScaled;
        const float stepSizes[10] = float[10](1.5, 2.0, 2.0, 2.0, 2.0, 4.0, 4.0, 8.0, 8.0, 12.0);
        for (int i = 0; i < 10 && !(doneN && doneP); i++) {
            if (!doneN) { posN -= offNP * stepSizes[i]; lumaEndN = Luma(DisplayAt(posN)) - lumaLocalAvg; doneN = abs(lumaEndN) >= gradientScaled; }
            if (!doneP) { posP += offNP * stepSizes[i]; lumaEndP = Luma(DisplayAt(posP)) - lumaLocalAvg; doneP = abs(lumaEndP) >= gradientScaled; }
        }

        float dstN = horzSpan ? uv.x - posN.x : uv.y - posN.y;
        float dstP = horzSpan ? posP.x - uv.x : posP.y - uv.y;
        bool directionN = dstN < dstP;
        bool lumaMLTZero = lumaM - lumaLocalAvg < 0.0;
        bool goodSpan = directionN ? (lumaEndN < 0.0) != lumaMLTZero : (lumaEndP < 0.0) != lumaMLTZero;
        float pixelOffset = goodSpan ? 0.5 - min(dstN, dstP) / (dstN + dstP) : 0.0;
        float offset = max(pixelOffset, subpix);

        vec2 finalUV = uv;
        if (horzSpan) finalUV.y += offset * lengthSign; else finalUV.x += offset * lengthSign;
        return DisplayAt(finalUV);
    }
#endif

// Interleaved gradient noise (Jimenez 2014): breaks up 8-bit banding in skies.
float Dither(vec2 pixel) { return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715)))); }

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    #ifdef FXAA
        vec3 color = Fxaa(pixel, uv);
    #else
        vec3 color = Display(pixel);
    #endif

    #if IMAGE_SHARPENING > 0 && !(defined OPT_SHARPEN_IN_POST && CHROMATIC_ABERRATION == 0)
        // Contrast-adaptive sharpening (unless the post pass did it, A6): sharpen less where the local contrast is already
        // high, so edges do not ring.
        vec3 n = Display(pixel + ivec2(0, 1));
        vec3 s = Display(pixel - ivec2(0, 1));
        vec3 e = Display(pixel + ivec2(1, 0));
        vec3 w = Display(pixel - ivec2(1, 0));
        vec3 lo = min(color, min(min(n, s), min(e, w)));
        vec3 hi = max(color, max(max(n, s), max(e, w)));
        vec3 amount = sqrt(saturate(min(lo, 1.0 - hi) / max(hi, 1e-4)));
        vec3 weight = -amount * float(IMAGE_SHARPENING) * 0.025;
        color = saturate((color + (n + s + e + w) * weight) / (1.0 + 4.0 * weight));
    #endif

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
    #elif DEBUG_VIEW == 7
        color = vec3(texelFetch(colortex3, pixel, 0).b);
    #elif DEBUG_VIEW == 8
        color = vec3(texelFetch(colortex3, pixel, 0).a);
    #endif

    outColor = vec4(color, 1.0);
}

#endif
