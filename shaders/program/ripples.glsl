// Interactive ripple simulation step (shadowcomp1, compute; see lib/materials/ripples.glsl).
// Wave equation on a 256 x 256 grid of quarter-block cells around the player:
//   h_new = (2 h - h_old + a * laplacian(h)) * damping
// with the previous two steps kept in the r and g channels. Cells where the shadow pass saw
// an entity touch the water are pushed down; cells whose spot just came into range (the
// grid wraps around the world) start flat.

#include "/lib/common.glsl"
#include "/lib/materials/ripples.glsl"
#include "/lib/materials/columnMaps.glsl"

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;
const ivec3 workGroups = ivec3(16, 16, 1);

uniform vec3 previousCameraPosition;

layout(rg16f) uniform image2D rippleImg;
layout(r32ui) uniform readonly uimage2D rippleLowImg;
layout(r32ui) uniform readonly uimage2D rippleHighImg;

// World cell held by a texel, for a window centred on a camera position.
ivec2 WindowCell(ivec2 texel, vec3 camera) {
    ivec2 origin = RippleCellOf(camera.xz) - RIPPLE_SIZE / 2;
    return origin + ivec2(mod(vec2(texel - origin), float(RIPPLE_SIZE)));
}

// The image starts out with whatever was in the memory: never let a bad value in.
float Clean(float x) { return isnan(x) || isinf(x) ? 0.0 : clamp(x, -0.2, 0.2); }

void main() {
    ivec2 texel = ivec2(gl_GlobalInvocationID.xy);
    if (any(greaterThanEqual(texel, ivec2(RIPPLE_SIZE)))) return;
    int readHalf = 1 - RippleCurrentHalf(), writeHalf = RippleCurrentHalf();
    ivec2 readBase = ivec2(0, RIPPLE_SIZE * readHalf), writeBase = ivec2(0, RIPPLE_SIZE * writeHalf);

    // This texel's spot moved into the window since last frame: start flat.
    if (WindowCell(texel, cameraPosition) != WindowCell(texel, previousCameraPosition)) {
        imageStore(rippleImg, texel + writeBase, vec4(0.0));
        return;
    }

    vec2 here = imageLoad(rippleImg, texel + readBase).rg; // r: height now, g: height a step ago
    here = vec2(Clean(here.r), Clean(here.g));
    ivec2 size = ivec2(RIPPLE_SIZE);
    float left = imageLoad(rippleImg, ((texel + ivec2(-1, 0)) + size) % size + readBase).r;
    float right = imageLoad(rippleImg, ((texel + ivec2(1, 0)) + size) % size + readBase).r;
    float down = imageLoad(rippleImg, ((texel + ivec2(0, -1)) + size) % size + readBase).r;
    float up = imageLoad(rippleImg, ((texel + ivec2(0, 1)) + size) % size + readBase).r;

    float dt = clamp(frameTime, 0.0, 0.05);
    const float waveSpeed = 2.5; // blocks per second
    float a = min(pow(waveSpeed * dt * RIPPLE_CELLS_PER_BLOCK, 2.0), 0.45);
    float neighbours = Clean(left) + Clean(right) + Clean(down) + Clean(up);
    float h = (2.0 * here.r - here.g + a * (neighbours - 4.0 * here.r)) * exp(-dt * 1.4);

    // An entity crossing the water surface here this frame: push the surface down.
    uint high = imageLoad(rippleHighImg, texel).r;
    if (high != 0u) {
        float top = UnpackRippleHeight(high);
        float bottom = UnpackRippleHeight(0xFFFFFFFFu - imageLoad(rippleLowImg, texel).r);
        vec2 xz = (vec2(WindowCell(texel, cameraPosition)) + 0.5) / RIPPLE_CELLS_PER_BLOCK;
        float surface = ColumnWaterSurface(vec3(xz.x, bottom - 1.0, xz.y));
        if (surface > -1e5 && bottom < surface + 0.1 && top > surface - 0.3) h = mix(h, -0.06, 0.5);
    }

    imageStore(rippleImg, texel + writeBase, vec4(Clean(h), here.r, 0.0, 0.0));
}
