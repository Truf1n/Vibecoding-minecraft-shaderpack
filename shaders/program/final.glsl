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

// Placeholder tonemap (Narkowicz ACES fit); the Unbound-style curve arrives in M1.
vec3 Tonemap(vec3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

// Interleaved gradient noise (Jimenez 2014): breaks up 8-bit banding in skies.
float Dither(vec2 pixel) { return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715)))); }

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    color = LinearToSrgb(Tonemap(color * TM_EXPOSURE));
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
