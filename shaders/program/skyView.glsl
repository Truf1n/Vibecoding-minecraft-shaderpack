// Cloud panorama (deferred.csh, compute, alongside the cloud pass): the clouds in every
// direction above the horizon around the camera, so reflections (water, puddles, polished
// blocks, ice) and the view up out of the water show clouds in world space, also where
// they are not on screen. 1024 x 256 directions: azimuth across, elevation up, packed
// closer together near the horizon (where reflections look most of the time). A quarter
// of them (every other one each way, in turn) is re-marched each frame with new random
// offsets and blended into what was there.
// Read with CloudsInDirection (lib/atmosphere/cloudBuffer.glsl).

#include "/lib/common.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 16, 1); // half the panorama each way: a quarter of it per frame

#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1
    #include "/lib/gbuffer/layout.glsl"
    #include "/lib/util/noise.glsl"
    #include "/lib/atmosphere/sky.glsl"
    #include "/lib/atmosphere/clouds.glsl"
    #include "/lib/atmosphere/skyView.glsl"

    layout(rgba16f) uniform image2D skyViewImg;

    void main() {
        ivec2 phase = ivec2(frameCounter & 1, (frameCounter >> 1) & 1);
        ivec2 texel = ivec2(gl_GlobalInvocationID.xy) * 2 + phase;
        #ifdef NO_CLOUDS_UNDERGROUND
            if (caveFactor > 0.95) return; // the sky cannot be seen: keep what was there
        #endif
        vec3 dir = SkyViewDirection((vec2(texel) + 0.5) / vec2(SKY_VIEW_SIZE));
        vec3 sunDir = mat3(gbufferModelViewInverse) * normalize(sunPosition);
        vec3 lightDir = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
        float dither = Hash13(vec3(vec2(texel), float(frameCounter % 4096)));
        CloudSample c = MarchClouds(dir, sunDir, lightDir, dither);
        vec4 result = vec4(c.scatter * vec3(CLOUD_COLOR_R, CLOUD_COLOR_G, CLOUD_COLOR_B), c.transmittance);
        vec4 history = imageLoad(skyViewImg, texel);
        bool valid = all(equal(history, history)) && history.a >= 0.0 && history.a <= 1.0 && frameCounter > 2;
        if (valid) result = mix(result, history, 0.6);
        imageStore(skyViewImg, texel, result);
    }
#else
    void main() {}
#endif
