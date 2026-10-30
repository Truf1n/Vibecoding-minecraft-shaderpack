#ifndef CAUSTICS_MAP_GLSL
#define CAUSTICS_MAP_GLSL

// Caustics map (B3; written by program/causticsMap.glsl, begin_b.csh): the curvature of the
// wave field (what the caustics are made from, waves.glsl) on a 1024x1024 grid of
// 1/8-block cells around the camera (128 blocks across), worked out once per frame instead
// of summing every wave at every step of the light shafts under water. Only made while the
// light shafts read it (frameFlags.glsl), and only read by them (causticsFootprint > 0,
// caustics.glsl): the map holds the waves the shafts keep (none shorter than about a
// quarter of a block), not the finest ripples sunlit surfaces show.
// Needs: common.glsl.

const int CAUSTICS_MAP_SIZE = 1024;
const float CAUSTICS_MAP_CELL = 0.125; // blocks
const float CAUSTICS_MAP_FOOTPRINT = 0.12; // waves left out, as in the shafts (caustics.glsl)

#ifdef CAUSTICS_MAP_WRITER
    layout(std430, binding = 5) writeonly buffer CausticsMapBuffer {
#else
    layout(std430, binding = 5) readonly buffer CausticsMapBuffer {
#endif
    int cmFrame;      // frameCounter of the frame it was made for
    float cmPad;
    vec2 cmOrigin;    // world xz of cell (0, 0)
    uvec2 cmCells[];  // curvature (d2h/dx2, d2h/dz2 | d2h/dxdz), as half floats
};

#ifndef CAUSTICS_MAP_WRITER
    #include "/lib/world/frameFlags.glsl"

    // The waves' curvature at a world xz from the map (bilinear); false where there is no
    // fresh map there (the caller then sums the waves itself).
    bool CausticsMapHessian(vec2 xz, out vec3 hessian) {
        hessian = vec3(0.0);
        #ifdef FRAGMENT_SHADER
            // Ask for the map next frame (one pixel in 256 is enough).
            if (((int(gl_FragCoord.x) | int(gl_FragCoord.y)) & 15) == 0) causticsUsed[frameCounter % 8] = 1u;
        #endif
        if (cmFrame != frameCounter) return false;
        vec2 pos = (xz - cmOrigin) / CAUSTICS_MAP_CELL;
        ivec2 base = ivec2(floor(pos));
        if (any(lessThan(base, ivec2(0))) || any(greaterThanEqual(base, ivec2(CAUSTICS_MAP_SIZE - 1)))) return false;
        vec2 f = pos - vec2(base);
        for (int i = 0; i < 4; i++) {
            ivec2 c = base + ivec2(i & 1, i >> 1);
            uvec2 packed = cmCells[c.y * CAUSTICS_MAP_SIZE + c.x];
            vec3 h = vec3(unpackHalf2x16(packed.x), unpackHalf2x16(packed.y).x);
            hessian += h * ((i & 1) == 1 ? f.x : 1.0 - f.x) * ((i >> 1) == 1 ? f.y : 1.0 - f.y);
        }
        return true;
    }
#endif

#endif
