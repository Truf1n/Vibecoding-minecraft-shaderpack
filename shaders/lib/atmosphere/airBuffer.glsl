#ifndef AIR_BUFFER_GLSL
#define AIR_BUFFER_GLSL

// The air march's half-size buffer (colortex11: rgb scattered light, a linear depth) and
// what both its passes share: the march (program/lightShafts.glsl, composite) and adding it
// to the scene (AirLight, in the tint pass, program/composite.glsl - merged into it to save
// a full-screen pass, P10).
// Needs: common.glsl; depthtex0 and depthtex1 declared.

const float LS_SCALE = 0.5; // must match size.buffer.colortex11 in shaders.properties

uniform sampler2D colortex11;

// Depth the air is marched to: through the water surface (and glass) when looking in from
// above, for the shafts under water; from inside the water, up to its surface.
float AirDepth(ivec2 pixel) {
    #ifdef WATER_SHAFTS_FROM_ABOVE
    #ifndef WORLD_NETHER
        if (isEyeInWater != 1) return texelFetch(depthtex1, pixel, 0).r;
    #endif
    #endif
    return texelFetch(depthtex0, pixel, 0).r;
}

float LinearDepth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - ndc * (far - near));
}

// The air's light at a full-size pixel, upsampled with a small blur: the 4x4 nearest
// half-size samples, weighted by distance (Gaussian) and by how close their depth is to
// this pixel's, so it smooths what noise is left without bleeding across object edges.
vec3 AirLight(ivec2 pixel) {
    float depth = LinearDepth(AirDepth(pixel));
    vec2 halfPos = (vec2(pixel) + 0.5) * LS_SCALE - 0.5;
    ivec2 base = ivec2(floor(halfPos));
    ivec2 maxTexel = textureSize(colortex11, 0) - 1;
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int y = -1; y <= 2; y++) {
        for (int x = -1; x <= 2; x++) {
            ivec2 t = base + ivec2(x, y);
            vec4 s = texelFetch(colortex11, clamp(t, ivec2(0), maxTexel), 0);
            vec2 d = vec2(t) - halfPos;
            float w = exp(-dot(d, d) * 0.7) * (exp(-abs(s.a - depth) / (0.05 * depth + 0.1)) + 1e-4);
            sum += s.rgb * w;
            wsum += w;
        }
    }
    return sum / max(wsum, 1e-5);
}

#endif
