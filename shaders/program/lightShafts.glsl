// The air march (W5; light shafts, mist light, glowing air), two passes:
//   LS_MARCH (composite1, into the half-size colortex11, see size.buffer): marches the view ray of
//            each half-size pixel (lib/atmosphere/lightShafts.glsl) with random offsets
//            that change every frame, and blends the result into the previous frames'
//            (re-projected to where the same spot was, rejected where the depth there does
//            not match): smooth shafts from few steps, without a fixed noise pattern.
//            rgb = scattered light, a = linear depth of that pixel.
//   LS_APPLY (composite2, full resolution): adds it to the scene, upsampled with weights
//            that follow the depth, so shafts don't bleed across object edges.
// Looking into water from above, the march goes on below the surface (depth without
// translucents) for the water's own shafts.

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

flat out vec3 sunDir;
flat out vec3 lightDir;

void main() {
    gl_Position = ftransform();
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
    lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/util/space.glsl"

const float LS_SCALE = 0.5; // must match size.buffer.colortex11 in shaders.properties

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D colortex11; // shafts at half resolution: rgb light, a linear depth

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

#ifdef LS_MARCH

#include "/lib/util/noise.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/atmosphere/sky.glsl"
#include "/lib/lighting/shadowSpace.glsl"
#include "/lib/lighting/shadows.glsl"
#include "/lib/atmosphere/clouds.glsl"
#include "/lib/atmosphere/air.glsl"
#include "/lib/lighting/coloredLight.glsl"
#include "/lib/atmosphere/lightShafts.glsl"

uniform vec3 previousCameraPosition;
uniform mat4 gbufferPreviousModelView;
uniform mat4 gbufferPreviousProjection;

flat in vec3 sunDir;
flat in vec3 lightDir;

/* RENDERTARGETS: 11 */
layout(location = 0) out vec4 outShafts;

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * LS_SCALE);

    // Farthest depth of the four full-size pixels under this one, so shafts reach past
    // thin things (the upsample picks the matching samples back out).
    ivec2 full = ivec2(gl_FragCoord.xy) * 2;
    float depth = AirDepth(full);
    depth = max(depth, AirDepth(full + ivec2(1, 0)));
    depth = max(depth, AirDepth(full + ivec2(0, 1)));
    depth = max(depth, AirDepth(full + ivec2(1, 1)));
    bool sky = depth >= 1.0;

    vec3 endPos = ViewToPlayer(ScreenToView(uv, depth)) - gbufferModelViewInverse[3].xyz;
    // A random offset per pixel (no spatial pattern: structured noise leaves its pattern,
    // diagonal lines, in what the frames add up to), stepping on by the golden ratio every
    // frame, so a few frames already cover the ray evenly and the history settles fast.
    float dither = fract(Hash13(vec3(gl_FragCoord.xy, 7.31)) + float(frameCounter % 4096) * 0.618034);
    vec3 shafts = MarchLightShafts(endPos, sky, sunDir, lightDir, dither);
    float linear = LinearDepth(depth);

    // Previous frames: where this spot was on screen then (the sky: the same direction).
    vec3 spot = sky ? normalize(endPos) * 4096.0 : endPos + gbufferModelViewInverse[3].xyz;
    vec3 prevView = (gbufferPreviousModelView * vec4(spot + (sky ? vec3(0.0) : cameraPosition - previousCameraPosition), 1.0)).xyz;
    vec4 prevClip = gbufferPreviousProjection * vec4(prevView, 1.0);
    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    if (prevClip.w > 0.0 && all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        // Bilinear from the four nearest previous texels, each only if it held the same
        // spot (its depth matches): at the edge of an object the matching ones still count.
        vec2 bufferSize = vec2(textureSize(colortex11, 0));
        vec2 pos = prevUV * bufferSize - 0.5;
        ivec2 base = ivec2(floor(pos));
        vec2 f = pos - vec2(base);
        float expected = sky ? far : -prevView.z;
        vec3 prevSum = vec3(0.0);
        float prevWeight = 0.0;
        for (int i = 0; i < 4; i++) {
            ivec2 o = ivec2(i & 1, i >> 1);
            vec4 prev = texelFetch(colortex11, clamp(base + o, ivec2(0), ivec2(bufferSize) - 1), 0);
            bool match = sky ? prev.a > far * 0.99 : abs(prev.a - expected) < 0.05 * expected + 0.25;
            if (!match || any(isnan(prev)) || any(isinf(prev))) continue;
            float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y) + 1e-3;
            prevSum += prev.rgb * w;
            prevWeight += w;
        }
        if (prevWeight > 0.05) {
            // Moving fast: lean on the new frame more.
            float motion = length((prevUV - uv) * bufferSize);
            float history = (0.94 - 0.3 * smoothstep(1.0, 8.0, motion)) * saturate(prevWeight * 1.5);
            shafts = mix(shafts, prevSum / prevWeight, history);
        }
    }
    outShafts = vec4(shafts, linear);
}

#endif

#ifdef LS_APPLY

uniform sampler2D colortex0;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    float depth = LinearDepth(AirDepth(pixel));

    // Upsample with a small blur: the 4x4 nearest half-size samples, weighted by distance
    // (Gaussian) and by how close their depth is to this pixel's, so it smooths what noise
    // is left without bleeding across object edges.
    vec2 halfPos = gl_FragCoord.xy * LS_SCALE - 0.5;
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
    color += sum / max(wsum, 1e-5);
    outColor = vec4(color, 1.0);
}

#endif

#endif
