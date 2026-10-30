// Cloud-shadow map (begin_a.csh, compute, right after the world state; A1): see
// lib/atmosphere/cloudShadowMap.glsl.

#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(32, 32, 1);

#if defined WORLD_OVERWORLD && CLOUD_STYLE == 1 && CLOUD_SHADOWS > 0
    #include "/lib/gbuffer/layout.glsl"
    #include "/lib/util/noise.glsl"
    #include "/lib/atmosphere/sky.glsl"
    #define CLOUD_SHADOW_MAP_WRITER
    #include "/lib/atmosphere/clouds.glsl"

    void main() {
        #ifdef OPT_CLOUD_SHADOW_MAP
            ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
            vec3 L = mat3(gbufferModelViewInverse) * normalize(shadowLightPosition);
            float base = CloudShadowBase() - 0.01;
            vec2 center = floor(cameraPosition.xz / CSM_CELL) * CSM_CELL;
            vec2 xz = center + (vec2(texel) + 0.5 - float(CSM_SIZE / 2)) * CSM_CELL;
            csmValues[texel.y * CSM_SIZE + texel.x] = CloudShadowDirect(vec3(xz.x, base, xz.y), L);
            if (texel == ivec2(0)) {
                csmFrame = frameCounter;
                csmBase = base;
                csmCenter = center;
            }
        #endif
    }
#else
    void main() {}
#endif
