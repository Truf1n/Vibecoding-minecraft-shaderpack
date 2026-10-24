#ifndef WATER_LAYER_GLSL
#define WATER_LAYER_GLSL

// Water layer: the depth of the nearest water as seen from the sun/moon, stored per
// shadow-map texel. The shadow map itself only keeps the nearest caster, so glass or ice
// lying on water hides the water from it; here every water fragment of the shadow pass
// competes only with other water (atomic max on the inverted depth, so the result does
// not depend on draw order). Lighting compares it with a point's own shadow depth to get
// the length of the light's path through water, exactly as the shadow map does for open
// water. Iris clears it at the start of every frame.

const int WATER_LAYER_SIZE = 4096; // must match image.waterLayerImg in shaders.properties

// 0 = no water; nearer to the light = larger.
uint EncodeWaterDepth(float depth) { return uint((1.0 - clamp(depth, 0.0, 1.0)) * 16777215.0) + 1u; }
float DecodeWaterDepth(uint v) { return 1.0 - float(v - 1u) / 16777215.0; }

#ifdef FRAGMENT_SHADER
#ifdef PROG_SHADOW
    layout(r32ui) uniform uimage2D waterLayerImg;

    // fragCoord: gl_FragCoord.xy of the shadow pass; depth: gl_FragCoord.z.
    void WriteWaterLayer(vec2 fragCoord, float depth) {
        ivec2 texel = ivec2(fragCoord / float(shadowMapResolution) * float(WATER_LAYER_SIZE));
        imageAtomicMax(waterLayerImg, texel, EncodeWaterDepth(depth));
    }
#endif
#endif

#ifndef PROG_SHADOW
    uniform usampler2D waterLayerSampler;

    // Shadow-map depth of the nearest water at this shadow coordinate, or -1 if none.
    float WaterLayerDepth(vec2 shadowCoord) {
        uint v = texelFetch(waterLayerSampler, ivec2(shadowCoord * float(WATER_LAYER_SIZE)), 0).r;
        return v == 0u ? -1.0 : DecodeWaterDepth(v);
    }
#endif

#endif
