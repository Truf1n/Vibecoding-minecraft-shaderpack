// Cloud pass (first deferred pass, into buffers at 1/CLOUD_RES_DIV of the screen size, see
// size.buffer in shaders.properties): ray marches the cloud layer for every reduced-size pixel and blends
// the result with the previous frames, re-projected to where the clouds were. Independent
// of the terrain, so the history stays valid when things move in front of the clouds;
// the lighting pass hides clouds behind terrain per full-size pixel.

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
#include "/lib/util/noise.glsl"
#include "/lib/util/reprojection.glsl"
#include "/lib/atmosphere/sky.glsl"
#include "/lib/atmosphere/clouds.glsl"
#include "/lib/atmosphere/cloudBuffer.glsl"

flat in vec3 sunDir;
flat in vec3 lightDir;

uniform sampler2D depthtex0;

// Marks a cloud pixel that was not marched because terrain hides it (P1): its emptiness
// must not be blended into later frames, and the composite pass must never draw it in
// front of anything (it is farther than any real cloud distance).
const float CLOUD_SKIPPED_DIST = 65000.0;

/* RENDERTARGETS: 9,10 */
layout(location = 0) out vec4 outClouds;
layout(location = 1) out vec4 outCloudDistance;

void main() {
    vec2 bufferSize = vec2(textureSize(colortex9, 0));
    vec2 uv = gl_FragCoord.xy / bufferSize;
    #ifdef NO_CLOUDS_UNDERGROUND
        // Deep underground the sky cannot be seen: skip the march (plan item C4).
        if (caveFactor > 0.95) {
            outClouds = vec4(0.0, 0.0, 0.0, 1.0);
            outCloudDistance = vec4(CLOUD_NONE_DIST, 0.0, 0.0, 1.0);
            return;
        }
    #endif

    vec3 dir = normalize(ViewToPlayerDir(ScreenToView(uv, 1.0)));

    // Clouds only where they can show (P1): if terrain covers all of this pixel's patch of
    // the screen, nearer than where the ray first meets a cloud layer, nothing to march.
    {
        vec2 fullSize = vec2(viewWidth, viewHeight);
        // Every full-size pixel under it (at most 4x4), so a thin gap of sky is never missed.
        ivec2 footprint = ivec2(ceil(fullSize / bufferSize)); // full-size pixels per cloud pixel
        ivec2 corner = ivec2(floor(gl_FragCoord.xy - 0.5) * fullSize / bufferSize);
        float farthest = 0.0;
        for (int y = 0; y < 4 && y < footprint.y; y++) {
            for (int x = 0; x < 4 && x < footprint.x; x++) {
                farthest = max(farthest, texelFetch(depthtex0, min(corner + ivec2(x, y), ivec2(fullSize) - 1), 0).r);
            }
        }
        if (farthest < 1.0) {
            float terrainDist = length(ScreenToView(uv, farthest));
            float cloudNear = 1e9;
            for (int i = 0; i < CLOUD_LAYERS; i++) {
                float tNear, tFar;
                if (LayerSpan(GetCloudLayer(i), cameraPosition.y, dir, tNear, tFar)) cloudNear = min(cloudNear, tNear);
            }
            if (terrainDist < cloudNear) {
                outClouds = vec4(0.0, 0.0, 0.0, 1.0);
                outCloudDistance = vec4(CLOUD_SKIPPED_DIST, 0.0, 0.0, 1.0);
                return;
            }
        }
    }
    float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
    CloudSample c = MarchClouds(dir, sunDir, lightDir, dither);
    c.scatter *= vec3(CLOUD_COLOR_R, CLOUD_COLOR_G, CLOUD_COLOR_B);

    // Blend with the previous frames where the same bit of cloud was then.
    vec3 cloudPos = dir * min(c.distance, 20000.0) + cameraPosition - previousCameraPosition;
    vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(cloudPos, 1.0));
    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    vec4 result = vec4(c.scatter, c.transmittance);
    // Sky effects behind the clouds (P15): the aurora (20 layers), nebulae and rainbow
    // cost a lot per pixel and are soft anyway, so they are drawn here, at the cloud
    // resolution, smoothed by the same history (the lighting pass leaves them out of the
    // sky). Not seen from under water (the surface draws its own view of the sky).
    if (isEyeInWater == 0) result.rgb += (Nebulae(dir, sunDir) + Aurora(dir, sunDir) + Rainbow(dir, sunDir)) * c.transmittance;
    bool prevMarched = texelFetch(colortex10, ivec2(prevUV * bufferSize), 0).r < CLOUD_SKIPPED_DIST - 100.0;
    if (prevMarched && prevClip.w > 0.0 && all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        vec4 history = SampleClouds(prevUV);
        float motion = length((prevUV - uv) * bufferSize);
        float blend = 0.88 * (1.0 - smoothstep(2.0, 12.0, motion) * 0.5);
        result = mix(result, history, blend);
    }

    outClouds = result;
    outCloudDistance = vec4(c.distance, 0.0, 0.0, 1.0);
}

#endif
