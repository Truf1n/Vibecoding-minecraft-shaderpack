// Caustics map (begin_b.csh, compute, after the world state and its wave table; B3): see
// lib/materials/causticsMap.glsl.

#include "/lib/common.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(64, 64, 1);

#if defined WORLD_OVERWORLD && defined WATER_CAUSTICS && VL_QUALITY > 0
    #include "/lib/util/noise.glsl"
    #include "/lib/materials/waves.glsl"
    #define CAUSTICS_MAP_WRITER
    #include "/lib/materials/causticsMap.glsl"
    #include "/lib/world/frameFlags.glsl"

    void main() {
        #ifdef OPT_CAUSTICS_MAP
            // Only while the light shafts read it: last frame's request (this frame's starts
            // clear and is set again by the shafts).
            int f = frameCounter % 8;
            if (gl_GlobalInvocationID.xy == uvec2(0)) causticsUsed[f] = 0u;
            if (causticsUsed[(f + 7) % 8] == 0u && frameCounter > 8) return;

            ivec2 cell = ivec2(gl_GlobalInvocationID.xy);
            vec2 origin = floor(cameraPosition.xz / CAUSTICS_MAP_CELL) * CAUSTICS_MAP_CELL - float(CAUSTICS_MAP_SIZE / 2) * CAUSTICS_MAP_CELL;
            vec2 xz = origin + vec2(cell) * CAUSTICS_MAP_CELL;
            // As UnderwaterLight (caustics.glsl) asks for them: open water, the local gusts.
            WaveConditions conditions = GetWaveConditions(1.0, 0.6, GustAt(xz));
            vec3 h = Waves(xz, conditions, CAUSTICS_MAP_FOOTPRINT, false).hessian;
            cmCells[cell.y * CAUSTICS_MAP_SIZE + cell.x] = uvec2(packHalf2x16(h.xy), packHalf2x16(vec2(h.z, 0.0)));
            if (cell == ivec2(0)) {
                cmFrame = frameCounter;
                cmOrigin = origin;
            }
        #endif
    }
#else
    void main() {}
#endif
