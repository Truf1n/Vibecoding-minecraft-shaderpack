// Cloud pass (first deferred pass, at 1/CLOUD_RES_DIV resolution, see scale.deferred in
// shaders.properties): ray marches the cloud layer for every reduced-size pixel and blends
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

/* RENDERTARGETS: 9,10 */
layout(location = 0) out vec4 outClouds;
layout(location = 1) out vec4 outCloudDistance;

void main() {
    // This pass covers the lower-left 1/CLOUD_RES_DIV of the screen.
    vec2 uv = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * CLOUD_RENDER_SCALE);
    if (any(greaterThan(uv, vec2(1.0)))) discard;

    vec3 dir = normalize(ViewToPlayerDir(ScreenToView(uv, 1.0)));
    float dither = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))) + float(frameCounter % 64) * 0.618034);
    CloudSample c = MarchClouds(dir, sunDir, lightDir, dither);
    c.scatter *= vec3(CLOUD_COLOR_R, CLOUD_COLOR_G, CLOUD_COLOR_B);

    // Blend with the previous frames where the same bit of cloud was then.
    vec3 cloudPos = dir * min(c.distance, 20000.0) + cameraPosition - previousCameraPosition;
    vec4 prevClip = gbufferPreviousProjection * (gbufferPreviousModelView * vec4(cloudPos, 1.0));
    vec2 prevUV = prevClip.xy / prevClip.w * 0.5 + 0.5;
    vec4 result = vec4(c.scatter, c.transmittance);
    if (prevClip.w > 0.0 && all(greaterThan(prevUV, vec2(0.0))) && all(lessThan(prevUV, vec2(1.0)))) {
        vec4 history = SampleClouds(prevUV);
        float motion = length((prevUV - uv) * vec2(viewWidth, viewHeight) * CLOUD_RENDER_SCALE);
        float blend = 0.88 * (1.0 - smoothstep(2.0, 12.0, motion) * 0.5);
        result = mix(result, history, blend);
    }

    outClouds = result;
    outCloudDistance = vec4(c.distance, 0.0, 0.0, 1.0);
}

#endif
