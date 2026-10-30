#ifndef DEPTH_TILES_GLSL
#define DEPTH_TILES_GLSL

// Nearest opaque depth per 8x8-pixel tile (program/depthTiles.glsl, P18). Sized for up to
// 8K (960 x 540 tiles).
const int DEPTH_TILE = 8;

#ifdef DEPTH_TILES_WRITER
    layout(std430, binding = 2) writeonly buffer DepthTiles { float depthTileNearest[]; };
#else
    layout(std430, binding = 2) readonly buffer DepthTiles { float depthTileNearest[]; };
#endif

ivec2 DepthTileCount() { return (ivec2(viewWidth, viewHeight) + DEPTH_TILE - 1) / DEPTH_TILE; }

#ifndef DEPTH_TILES_WRITER
    // Nearest depth (raw depth-buffer value) in the tile under a screen position (0..1).
    float DepthTileAt(vec2 uv) {
        ivec2 tiles = DepthTileCount();
        ivec2 t = clamp(ivec2(uv * vec2(viewWidth, viewHeight)) / DEPTH_TILE, ivec2(0), tiles - 1);
        return depthTileNearest[t.y * tiles.x + t.x];
    }
#endif

#endif
