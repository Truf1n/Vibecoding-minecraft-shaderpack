// Temporal anti-aliasing resolve (plan item T1): blend the current frame with last
// frame's result, re-projected to where each point was, after clamping the history to
// the colours around the pixel now (so moving objects do not leave ghost trails).

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

void main() {
    gl_Position = ftransform();
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/space.glsl"
#include "/lib/util/reprojection.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex8; // TAA history (not cleared between frames)
uniform sampler2D depthtex0;
uniform sampler2D depthtex1; // without translucents

// The result goes only into the history; the final pass reads it from there (saves a
// full-screen write).
/* RENDERTARGETS: 8 */
layout(location = 0) out vec4 outHistory;

// Work in a compressed range so a few very bright pixels do not dominate the blend.
vec3 Compress(vec3 c) { return c / (1.0 + Luminance(c)); }
vec3 Expand(vec3 c) { return c / max(1.0 - Luminance(c), 1e-4); }

vec3 RgbToYCoCg(vec3 c) {
    return vec3(0.25 * c.r + 0.5 * c.g + 0.25 * c.b, 0.5 * c.r - 0.5 * c.b, -0.25 * c.r + 0.5 * c.g - 0.25 * c.b);
}
vec3 YCoCgToRgb(vec3 c) { return vec3(c.x + c.y - c.z, c.x + c.z, c.x - c.y - c.z); }

// How far a history colour lies outside the neighbourhood box (<= 1: inside).
float BoxDistance(vec3 history, vec3 mean, vec3 extent) {
    vec3 d = abs(history - mean) / extent;
    return max(d.x, max(d.y, d.z));
}

// Catmull-Rom history sample from 5 bilinear taps: sharper than bilinear when moving.
vec3 SampleHistory(vec2 uv) {
    vec2 size = vec2(viewWidth, viewHeight);
    vec2 pos = uv * size;
    vec2 center = floor(pos - 0.5) + 0.5;
    vec2 f = pos - center;
    vec2 w0 = f * (-0.5 + f * (1.0 - 0.5 * f));
    vec2 w1 = 1.0 + f * f * (-2.5 + 1.5 * f);
    vec2 w2 = f * (0.5 + f * (2.0 - 1.5 * f));
    vec2 w3 = f * f * (-0.5 + 0.5 * f);
    vec2 w12 = w1 + w2;
    vec2 tc0 = (center - 1.0) / size;
    vec2 tc3 = (center + 2.0) / size;
    vec2 tc12 = (center + w2 / w12) / size;

    vec3 result = textureLod(colortex8, vec2(tc12.x, tc0.y), 0.0).rgb * (w12.x * w0.y)
                + textureLod(colortex8, vec2(tc0.x, tc12.y), 0.0).rgb * (w0.x * w12.y)
                + textureLod(colortex8, tc12, 0.0).rgb * (w12.x * w12.y)
                + textureLod(colortex8, vec2(tc3.x, tc12.y), 0.0).rgb * (w3.x * w12.y)
                + textureLod(colortex8, vec2(tc12.x, tc3.y), 0.0).rgb * (w12.x * w3.y);
    float weight = w12.x * w0.y + w0.x * w12.y + w12.x * w12.y + w3.x * w12.y + w12.x * w3.y;
    return max(result / weight, 0.0);
}

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec2 uv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec3 current = Compress(texelFetch(colortex0, pixel, 0).rgb);

    // Neighbourhood statistics (3x3) in YCoCg for variance clipping.
    vec3 m1 = vec3(0.0), m2 = vec3(0.0);
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            vec3 c = RgbToYCoCg(Compress(texelFetch(colortex0, pixel + ivec2(x, y), 0).rgb));
            m1 += c;
            m2 += c * c;
        }
    }
    vec3 mean = m1 / 9.0;
    vec3 sigma = sqrt(max(m2 / 9.0 - mean * mean, 0.0));
    vec3 boxMax = mean + sigma * 1.25;

    float depth = texelFetch(depthtex0, pixel, 0).r;
    vec2 prevUV = ReprojectToPreviousFrame(uv, depth);
    bool onScreen = all(greaterThanEqual(prevUV, vec2(0.0))) && all(lessThanEqual(prevUV, vec2(1.0)));
    vec3 extent = max(boxMax - mean, vec3(1e-5));
    vec3 history = onScreen ? RgbToYCoCg(Compress(SampleHistory(prevUV))) : vec3(0.0);

    // Through glass (or water) the pixel shows both the pane and what lies behind it, which
    // move differently: also follow what is behind, and keep whichever history matches
    // the pixel now better (otherwise the view behind the glass smears and lags).
    float depthBehind = texelFetch(depthtex1, pixel, 0).r;
    if (depthBehind > depth + 1e-6 && depth >= HAND_DEPTH_LIMIT) {
        vec2 behindUV = ReprojectToPreviousFrame(uv, depthBehind);
        if (all(greaterThanEqual(behindUV, vec2(0.0))) && all(lessThanEqual(behindUV, vec2(1.0)))) {
            vec3 behind = RgbToYCoCg(Compress(SampleHistory(behindUV)));
            if (!onScreen || BoxDistance(behind, mean, extent) < BoxDistance(history, mean, extent)) {
                history = behind;
                prevUV = behindUV;
                onScreen = true;
            }
        }
    }

    vec3 result = current;
    if (onScreen) {
        // Clip the history towards the mean until it fits inside the neighbourhood box.
        vec3 dir = history - mean;
        float t = BoxDistance(history, mean, extent);
        if (t > 1.0) history = mean + dir / t;

        // Trust the history less when the camera moved a lot (fast turns blur otherwise).
        float motion = length((prevUV - uv) * vec2(viewWidth, viewHeight));
        float blend = TAA_SMOOTHING * (1.0 - smoothstep(4.0, 40.0, motion) * 0.3);
        result = mix(current, YCoCgToRgb(history), blend);
    }

    result = Expand(max(result, 0.0));
    outHistory = vec4(result, 1.0);
}

#endif
