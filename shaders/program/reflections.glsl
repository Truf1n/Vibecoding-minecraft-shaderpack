// Reflections on smooth opaque blocks (plan items X1, X2), two deferred passes after the
// lighting pass and before translucents:
//   REFL_TRACE (deferred2, into colortex12 at full or half size, see size.buffer): traces
//              a reflected ray per pixel through the screen (the lit scene in colortex7),
//              falling back to the sky (and the clouds) or, out of the sky's reach, to the
//              block light around. Rough surfaces jitter the ray per frame; TAA smooths it.
//              rgb = reflected light, a = linear depth (for the upsample).
//   REFL_APPLY (deferred3, full size): upsamples it following the depth and adds it,
//              weighted by Fresnel, to colortex0 and the scene copy (colortex7).

#include "/lib/common.glsl"

#ifdef VERTEX_SHADER

flat out vec3 sunDir;

void main() {
    gl_Position = ftransform();
    sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
}

#endif

#ifdef FRAGMENT_SHADER

#include "/lib/gbuffer/layout.glsl"
#include "/lib/materials/blockIds.glsl"
#include "/lib/util/encoding.glsl"
#include "/lib/util/space.glsl"
#include "/lib/lighting/specular.glsl"

#if REFLECTION_RES == 2
    const float REFL_SCALE = 0.5; // must match size.buffer.colortex12 in shaders.properties
#else
    const float REFL_SCALE = 1.0;
#endif
const float REFL_MIN_SMOOTHNESS = 0.15;

uniform sampler2D colortex2;
uniform sampler2D colortex3;
uniform sampler2D colortex12;
uniform sampler2D depthtex0;

flat in vec3 sunDir;

float LinearDepthOf(float depth) {
    float ndc = depth * 2.0 - 1.0;
    return 2.0 * near * far / (far + near - ndc * (far - near));
}

#ifdef REFL_TRACE

#include "/lib/atmosphere/sky.glsl"
#include "/lib/materials/ssr.glsl"
#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
    #include "/lib/atmosphere/cloudBuffer.glsl"
#endif

/* RENDERTARGETS: 12 */
layout(location = 0) out vec4 outReflection;

// Microfacet normal drawn from the GGX distribution (u: two random numbers in 0..1).
vec3 SampleGGXNormal(vec3 N, float roughness, vec2 u) {
    float a = roughness * roughness;
    float phi = TAU * u.x;
    float cosTheta = sqrt((1.0 - u.y) / (1.0 + (a * a - 1.0) * u.y));
    float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
    vec3 up = abs(N.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 T = normalize(cross(up, N));
    vec3 B = cross(N, T);
    return normalize(T * (sinTheta * cos(phi)) + B * (sinTheta * sin(phi)) + N * cosTheta);
}

void main() {
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * REFL_SCALE);
    ivec2 pixel = ivec2(uv * vec2(viewWidth, viewHeight));
    float depth = texelFetch(depthtex0, pixel, 0).r;
    vec4 material = texelFetch(colortex3, pixel, 0);
    int shadingModel = DecodeId(material.r);
    if (depth >= 1.0 || shadingModel == SM_KEEP || shadingModel == SM_HAND || material.b < REFL_MIN_SMOOTHNESS) {
        outReflection = vec4(0.0, 0.0, 0.0, LinearDepthOf(depth));
        return;
    }

    vec4 normalLight = texelFetch(colortex2, pixel, 0);
    vec3 normal = DecodeNormal(normalLight.xy);
    vec3 viewPos = ScreenToView(uv, depth);
    vec3 playerPos = ViewToPlayer(viewPos);
    vec3 V = -normalize(playerPos);

    // Rough surfaces: a different microfacet every frame (blurry reflections after TAA).
    float roughness = RoughnessFromSmoothness(material.b);
    float n1 = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
    float n2 = fract(n1 * 7.31 + float(frameCounter % 64) * 0.381966);
    vec3 H = roughness > 0.05 ? SampleGGXNormal(normal, roughness, vec2(n1, n2 * 0.8)) : normal;
    vec3 R = reflect(-V, H);
    if (dot(R, normal) < 0.0) R = reflect(R, normal);

    // Where the screen has nothing: the sky (as much as reaches this spot), else the block
    // light around.
    float skyLight = normalLight.w;
    vec3 fallback = GetBlockSkyReflection(normalize(R), sunDir, -1.0);
    #if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
        vec4 clouds = CloudsInDirection(normalize(R));
        fallback = fallback * clouds.a + clouds.rgb;
    #endif
    fallback *= skyLight * skyLight;
    fallback += vec3(BLOCKLIGHT_R, BLOCKLIGHT_G, BLOCKLIGHT_B) * BLOCKLIGHT_I * normalLight.z * normalLight.z * 0.3;

    vec3 viewR = normalize(mat3(gbufferModelView) * R);
    vec3 viewN = normalize(mat3(gbufferModelView) * normal);
    vec4 hit = TraceSSR(viewPos, viewR, viewN, n1);
    outReflection = vec4(mix(fallback, hit.rgb, hit.a), LinearDepthOf(depth));
}

#endif

#ifdef REFL_APPLY

uniform sampler2D colortex0;
uniform sampler2D colortex1;

/* RENDERTARGETS: 0,7 */
layout(location = 0) out vec4 outColor;
layout(location = 1) out vec4 outSceneCopy;

void main() {
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 color = texelFetch(colortex0, pixel, 0).rgb;
    vec4 material = texelFetch(colortex3, pixel, 0);
    float depth = texelFetch(depthtex0, pixel, 0).r;
    int shadingModel = DecodeId(material.r);

    if (depth < 1.0 && shadingModel != SM_KEEP && shadingModel != SM_HAND && material.b >= REFL_MIN_SMOOTHNESS) {
        // Upsample: the four nearest reflection samples, weighted by distance and by how
        // close their depth is to this pixel's.
        float linear = LinearDepthOf(depth);
        vec2 pos = gl_FragCoord.xy * REFL_SCALE - 0.5;
        ivec2 base = ivec2(floor(pos));
        vec2 f = pos - vec2(base);
        ivec2 maxTexel = textureSize(colortex12, 0) - 1;
        vec3 sum = vec3(0.0);
        float wsum = 0.0;
        for (int i = 0; i < 4; i++) {
            ivec2 o = ivec2(i & 1, i >> 1);
            vec4 s = texelFetch(colortex12, clamp(base + o, ivec2(0), maxTexel), 0);
            float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
            w *= exp(-abs(s.a - linear) / (0.03 * linear + 0.05)) + 1e-4;
            sum += s.rgb * w;
            wsum += w;
        }
        vec3 reflection = sum / max(wsum, 1e-5);

        vec3 albedo = SrgbToLinear(texelFetch(colortex1, pixel, 0).rgb);
        vec3 normal = DecodeNormal(texelFetch(colortex2, pixel, 0).xy);
        vec3 V = -normalize(ViewToPlayer(ScreenToView(gl_FragCoord.xy / vec2(viewWidth, viewHeight), depth)));
        float roughness = RoughnessFromSmoothness(material.b);
        vec3 F = FresnelRoughness(dot(normal, V), SpecularF0(albedo, material.a), roughness);
        color += reflection * F * smoothstep(REFL_MIN_SMOOTHNESS, REFL_MIN_SMOOTHNESS + 0.2, material.b);
    }

    outColor = vec4(color, 1.0);
    outSceneCopy = vec4(color, 1.0);
}

#endif

#endif
