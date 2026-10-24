// Sub-pixel camera jitter for temporal anti-aliasing (plan item T1): each frame the whole
// image is shifted by a different point of an 8-sample Halton(2,3) pattern, so the TAA
// pass can accumulate the in-between samples.

vec2 HaltonJitter(int i) {
    const vec2 halton[8] = vec2[8](
        vec2(0.500, 0.333), vec2(0.250, 0.667), vec2(0.750, 0.111), vec2(0.125, 0.444),
        vec2(0.625, 0.778), vec2(0.375, 0.222), vec2(0.875, 0.556), vec2(0.0625, 0.889));
    return halton[i % 8] - 0.5;
}

// Offset to add to a clip-space position (call after the projection).
vec4 ApplyTAAJitter(vec4 clipPos) {
    #ifdef TAA
        vec2 offsetNdc = HaltonJitter(frameCounter) * 2.0 / vec2(viewWidth, viewHeight) * TAA_JITTER;
        clipPos.xy += offsetNdc * clipPos.w;
    #endif
    return clipPos;
}
