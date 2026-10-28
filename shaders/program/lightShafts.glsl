// The air march (W5; light shafts, mist light, glowing air):
//   LS_MARCH (composite, into the half-size colortex11, see size.buffer): marches the view ray of
//            each half-size pixel (lib/atmosphere/lightShafts.glsl) with random offsets
//            that change every frame, and blends the result into the previous frames'
//            (re-projected to where the same spot was, rejected where the depth there does
//            not match): smooth shafts from few steps, without a fixed noise pattern.
//            rgb = scattered light, a = linear depth of that pixel.
//   Adding it to the scene happens in the tint pass (composite1, program/composite.glsl),
//            upsampled with weights that follow the depth (lib/atmosphere/airBuffer.glsl).
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

uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
#include "/lib/atmosphere/airBuffer.glsl"

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

#endif
