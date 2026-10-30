// Bloom tiles (composite3, plan item K1): each tile is a Gaussian blur of one mip level
// of the finished scene (see lib/post/bloomTiles.glsl). The buffer is half size
// (size.buffer.colortex13), so this pass only shades a quarter of the screen's pixels,
// and most of them belong to the smallest tiles' gaps, which are skipped.

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
    const bool colortex8MipmapEnabled = true;
#else
    uniform sampler2D colortex0;
    #define sceneTex colortex0
    const bool colortex0MipmapEnabled = true;
#endif

/* RENDERTARGETS: 13 */
layout(location = 0) out vec3 outBloom;

void main() {
    vec2 bufferSize = floor(vec2(viewWidth, viewHeight) * 0.5);
    vec2 uv = gl_FragCoord.xy / bufferSize;

    outBloom = vec3(0.0);
    for (int k = 0; k < BLOOM_TILES; k++) {
        float scale = BloomTileScale(k);
        vec2 local = (uv - BloomTileOffset(k)) / scale;
        if (any(lessThan(local, vec2(0.0))) || any(greaterThan(local, vec2(1.0)))) continue;

        // 7x7 binomial (Gaussian-like) blur of mip level k + 2.
        float lod = float(k + 2);
        vec2 texel = exp2(lod) / vec2(viewWidth, viewHeight);
        vec3 sum = vec3(0.0);
        #ifdef OPT_BLOOM_LINEAR_TAPS
            // The same 7-tap weights from 4 filtered reads per axis (B6): each read lands
            // between two taps, where bilinear filtering mixes them in their ratio
            // (1+6 at -2.14, 15+10 at -0.6, the centre's 20 split in two).
            const float o[4] = float[4](-15.0 / 7.0, -0.6, 0.6, 15.0 / 7.0);
            const float w[4] = float[4](7.0, 25.0, 25.0, 7.0);
            for (int y = 0; y < 4; y++) {
                for (int x = 0; x < 4; x++) {
                    vec2 p = clamp(local + vec2(o[x], o[y]) * texel, vec2(0.0), vec2(1.0));
                    // Clamp very bright pixels (the sun) so they do not swamp the whole tile.
                    vec3 c = min(textureLod(sceneTex, p, lod).rgb, vec3(64.0));
                    sum += c * (w[x] * w[y]);
                }
            }
        #else
            const float w[7] = float[7](1.0, 6.0, 15.0, 20.0, 15.0, 6.0, 1.0);
            for (int y = 0; y < 7; y++) {
                for (int x = 0; x < 7; x++) {
                    vec2 p = clamp(local + vec2(x - 3, y - 3) * texel, vec2(0.0), vec2(1.0));
                    // Clamp very bright pixels (the sun) so they do not swamp the whole tile.
                    vec3 c = min(textureLod(sceneTex, p, lod).rgb, vec3(64.0));
                    sum += c * (w[x] * w[y]);
                }
            }
        #endif
        outBloom = sum / 4096.0;
        break;
    }
}

#endif
