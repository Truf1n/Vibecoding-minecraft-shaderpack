// Nearest depth per 8x8-pixel tile (deferred2.csh, compute, before the lighting pass; P18): the
// opaque scene's depth buffer reduced to one value per tile, in a storage buffer
// (bufferObject.2). Reflection rays (lib/materials/ssr.glsl) read it to skip ahead quickly
// where they pass in front of everything in a tile, which is most of their way over open
// water.

#include "/lib/common.glsl"
#include "/lib/materials/depthTiles.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
const vec2 workGroupsRender = vec2(1.0 / 64.0, 1.0 / 64.0); // one thread per 8x8 tile

uniform sampler2D depthtex0;

void main() {
    ivec2 tile = ivec2(gl_GlobalInvocationID.xy);
    ivec2 tiles = DepthTileCount();
    if (any(greaterThanEqual(tile, tiles))) return;
    ivec2 screen = ivec2(viewWidth, viewHeight);
    float nearest = 1.0;
    for (int y = 0; y < DEPTH_TILE; y++) {
        for (int x = 0; x < DEPTH_TILE; x++) {
            ivec2 p = min(tile * DEPTH_TILE + ivec2(x, y), screen - 1);
            nearest = min(nearest, texelFetch(depthtex0, p, 0).r);
        }
    }
    depthTileNearest[tile.y * tiles.x + tile.x] = nearest;
}
