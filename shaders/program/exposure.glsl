// Auto exposure (composite4 compute, runs before the post pass; plan item Q28): measures how
// bright the finished scene is and adapts the exposure like an eye - quicker to bright
// light than to darkness. Only part of the way (Auto Exposure Strength), so caves and nights
// still look dark, just less murky. Result in the world state (wsExposure.x), used by post.

#include "/lib/common.glsl"
#include "/lib/gbuffer/layout.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(1, 1, 1);

#ifdef TAA
    uniform sampler2D colortex8; // finished scene (TAA history)
    #define sceneTex colortex8
#else
    uniform sampler2D colortex0;
    #define sceneTex colortex0
#endif

shared float logSums[256];
shared float weights[256];

// Average brightness of the scene that looks "right" without adapting (a typical outdoor
// daytime view, which the tonemap and colours were tuned for).
const float AE_REFERENCE = 0.3;

void main() {
    // A 48 x 27 grid of samples (3 x 3 per thread), weighted towards the centre of the view.
    int id = int(gl_LocalInvocationIndex);
    float logSum = 0.0, weightSum = 0.0;
    for (int j = 0; j < 9; j++) {
        int index = id * 9 + j;
        vec2 cell = vec2(index % 48, index / 48);
        if (cell.y >= 27.0) continue;
        vec2 uv = (cell + 0.5) / vec2(48.0, 27.0);
        float lum = Luminance(textureLod(sceneTex, uv, 0.0).rgb);
        float w = 1.0 - 0.7 * saturate(length((uv - 0.5) * vec2(1.6, 1.0)) * 1.4);
        logSum += log(max(lum, 1e-4)) * w;
        weightSum += w;
    }
    logSums[id] = logSum;
    weights[id] = weightSum;
    barrier();
    for (int stride = 128; stride > 0; stride >>= 1) {
        if (id < stride) {
            logSums[id] += logSums[id + stride];
            weights[id] += weights[id + stride];
        }
        barrier();
    }
    if (id != 0) return;

    float average = exp(logSums[0] / max(weights[0], 1e-4));
    float target = 1.0;
    #ifdef AUTO_EXPOSURE
        target = clamp(pow(AE_REFERENCE / max(average, 1e-4), 0.5 * AUTO_EXPOSURE_STRENGTH), AUTO_EXPOSURE_MIN, AUTO_EXPOSURE_MAX);
    #endif
    float current = wsExposure.x > 0.0 ? wsExposure.x : target;
    // Opening up in the dark takes a few seconds; closing down in bright light under one.
    float tau = target > current ? 2.5 : 0.7;
    float dt = clamp(frameTime, 0.0, 0.25);
    wsExposure = vec4(mix(current, target, 1.0 - exp(-dt / tau)), target, average, 0.0);
}
