// Light shafts, two passes:
//   LS_MARCH (composite1, half resolution via scale.composite1): marches the view ray of
//            each half-size pixel; rgb = scattered light, a = linear depth of that pixel.
//   LS_APPLY (composite2, full resolution): adds it to the scene, upsampled with weights
//            that follow the depth, so shafts don't bleed across object edges.

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

const float LS_SCALE = 0.5; // must match scale.composite1 in shaders.properties

uniform sampler2D depthtex0;
uniform sampler2D colortex11; // shafts at half resolution: rgb light, a linear depth

float LinearDepth(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - ndc * (far - near));
}

#ifdef LS_MARCH

#include "/lib/util/noise.glsl"
#include "/lib/atmosphere/sky.glsl"
#include "/lib/lighting/shadowSpace.glsl"
#include "/lib/lighting/shadows.glsl"
#include "/lib/atmosphere/clouds.glsl"
#include "/lib/atmosphere/lightShafts.glsl"

flat in vec3 sunDir;
flat in vec3 lightDir;

/* RENDERTARGETS: 11 */
layout(location = 0) out vec4 outShafts;

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * LS_SCALE);
    if (any(greaterThan(uv, vec2(1.0)))) discard;

    // Farthest depth of the four full-size pixels under this one, so shafts reach past
    // thin things (the upsample picks the matching samples back out).
    ivec2 full = ivec2(gl_FragCoord.xy) * 2;
    float depth = texelFetch(depthtex0, full, 0).r;
    depth = max(depth, texelFetch(depthtex0, full + ivec2(1, 0), 0).r);
    depth = max(depth, texelFetch(depthtex0, full + ivec2(0, 1), 0).r);
    depth = max(depth, texelFetch(depthtex0, full + ivec2(1, 1), 0).r);

    vec3 endPos = ViewToPlayer(ScreenToView(uv, depth)) - gbufferModelViewInverse[3].xyz;
    float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
    vec3 shafts = MarchLightShafts(endPos, depth >= 1.0, sunDir, lightDir, dither);
    outShafts = vec4(shafts, LinearDepth(depth));
}

#endif

#ifdef LS_APPLY

uniform sampler2D colortex0;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 outColor;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    float depth = LinearDepth(texelFetch(depthtex0, pixel, 0).r);

    // Bilinear upsample of the four nearest half-size samples, each also weighted by how
    // close its depth is to this pixel's.
    vec2 halfPos = gl_FragCoord.xy * LS_SCALE - 0.5;
    ivec2 base = ivec2(floor(halfPos));
    vec2 f = halfPos - vec2(base);
    ivec2 maxTexel = ivec2(vec2(viewWidth, viewHeight) * LS_SCALE) - 1;
    vec3 sum = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 4; i++) {
        ivec2 o = ivec2(i & 1, i >> 1);
        vec4 s = texelFetch(colortex11, clamp(base + o, ivec2(0), maxTexel), 0);
        float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
        w *= exp(-abs(s.a - depth) / (0.05 * depth + 0.1)) + 1e-4;
        sum += s.rgb * w;
        wsum += w;
    }
    color += sum / max(wsum, 1e-5);
    outColor = vec4(color, 1.0);
}

#endif

#endif
