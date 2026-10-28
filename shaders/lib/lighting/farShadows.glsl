#ifndef FAR_SHADOWS_GLSL
#define FAR_SHADOWS_GLSL

// Far shadows (W4, plan item Q10; Distant Horizons style): beyond the shadow map, terrain
// still shadows terrain. The shadow pass (which draws the world out to FAR_SHADOW_RANGE
// times the shadow distance for this) records the highest top face in every 2x2-block
// column (farHeightImg, 512x512 columns = 1024 blocks, wrapping around the world like the
// column maps, cleared every frame). Far pixels march over it towards the sun with growing
// steps, softly: so distant mountains shade each other, valleys go dark at sunset and the
// far side of a ridge falls into shadow.

const float FAR_CELL = 2.0;      // blocks per height-map column
const int FAR_SIZE = 512;        // columns per side
const float FAR_REACH = 500.0;   // blocks from the camera the map is trusted

ivec2 FarCell(vec2 worldXZ) { return ivec2(mod(floor(worldXZ / FAR_CELL), float(FAR_SIZE))); }
uint PackFarHeight(float y) { return uint(clamp((y + 128.0) * 8.0, 1.0, 65535.0)); }
float UnpackFarHeight(uint v) { return v == 0u ? -1e6 : float(v) / 8.0 - 128.0; }

#ifdef FAR_HEIGHT_WRITER
    layout(r32ui) uniform uimage2D farHeightImg;
    void WriteFarHeight(vec3 worldPos) {
        if (any(greaterThan(abs(worldPos.xz - cameraPosition.xz), vec2(FAR_REACH)))) return;
        imageAtomicMax(farHeightImg, FarCell(worldPos.xz), PackFarHeight(worldPos.y));
    }
#else
    uniform usampler2D farHeightSampler;

    // Sunlight reaching a far point, 0..1. worldPos: absolute; L: towards the sun/moon.
    float FarShadow(vec3 worldPos, vec3 L) {
        if (L.y < 0.01) return 0.0;
        float vis = 1.0;
        float t = 3.0;
        // Shadows blur with distance from their caster (the sun is a disc), and there is
        // no point being sharper than the 2-block columns.
        float softness = 0.03 * (1.0 + 4.0 * stormRain) * SHADOW_PENUMBRA + 0.02;
        vec3 start = worldPos + vec3(0.0, 0.6, 0.0); // its own column's top is (about) here
        for (int i = 0; i < 24; i++) {
            vec3 p = start + L * t;
            if (any(greaterThan(abs(p.xz - cameraPosition.xz), vec2(FAR_REACH))) || p.y > 320.0) break;
            float h = UnpackFarHeight(texelFetch(farHeightSampler, FarCell(p.xz), 0).r);
            vis = min(vis, saturate((p.y - h) / (t * softness) + 0.5));
            if (vis <= 0.0) break;
            t = t * 1.2 + 1.0;
        }
        return vis;
    }
#endif

#endif
