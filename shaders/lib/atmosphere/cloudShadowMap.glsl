#ifndef CLOUD_SHADOW_MAP_GLSL
#define CLOUD_SHADOW_MAP_GLSL

// Cloud-shadow map (A1; written by program/cloudShadowMap.glsl, begin_a.csh): the sunlight
// the clouds let through, worked out once per frame on a 512x512 grid instead of per pixel
// and per light-shaft step. The grid lies where the sun's rays cross the lowest cloud base:
// every point along one ray of sunlight below the clouds shares the same clouds above it,
// so the map is exact for all of them (up to its 2-block cells). Points above the cloud
// base, far outside the grid, or a frame without a fresh map: worked out directly.
// Needs: clouds.glsl (CloudShadowDirect, GetCloudLayer).

const int CSM_SIZE = 512;
const float CSM_CELL = 2.0; // blocks

#ifdef CLOUD_SHADOW_MAP_WRITER
    layout(std430, binding = 3) writeonly buffer CloudShadowMapBuffer {
#else
    layout(std430, binding = 3) readonly buffer CloudShadowMapBuffer {
#endif
    int csmFrame;    // frameCounter of the frame it was made for
    float csmBase;   // height of the grid (the lowest cloud base)
    vec2 csmCenter;  // world xz of the grid's centre
    float csmValues[];
};

float CloudShadowBase() {
    float base = 1e6;
    for (int i = 0; i < CLOUD_LAYERS; i++) base = min(base, GetCloudLayer(i).bottom);
    return base;
}

#endif
