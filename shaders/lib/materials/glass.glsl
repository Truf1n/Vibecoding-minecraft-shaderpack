// Continuity-style glass: textureless, tinted by its colour only, with a thin frame on
// edges that do not touch the same kind of glass (neighbours come from the glass voxel
// grid filled in the shadow pass). Outside the grid every edge gets a frame.
// Needs: blockIds.glsl, glassVoxels.glsl, sky.glsl, lighting.glsl.

uniform usampler3D glassVoxelSampler;

#define GLASS_BORDER_WIDTH (1.0 / 16.0)

// Is the block at voxel v (relative to this one) the same glass? Outside the grid: unknown -> no.
bool SameGlass(ivec3 v, uint code) {
    return InGlassGrid(v) && texelFetch(glassVoxelSampler, v, 0).r == code;
}

// 1 on frame pixels, 0 inside the pane.
float GlassFrame(vec3 playerPos, vec3 normal, int blockId) {
    // Step slightly into the block so face pixels resolve to their own block.
    vec3 p = playerPos + cameraPositionFract - normal * 0.01;
    vec3 local = fract(p);
    ivec3 voxel = GlassVoxelIndex(playerPos - normal * 0.01);
    uint code = GlassVoxelCode(blockId);

    vec3 an = abs(normal);
    int axisN = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);

    // Top and bottom faces of a pane are its thin edges: always frame.
    if (IsPane(blockId) && axisN == 1) return 1.0;

    float frame = 0.0;
    for (int axis = 0; axis < 3; axis++) {
        if (axis == axisN) continue;
        ivec3 offset = ivec3(0);
        offset[axis] = 1;
        if (local[axis] < GLASS_BORDER_WIDTH && !SameGlass(voxel - offset, code)) frame = 1.0;
        if (local[axis] > 1.0 - GLASS_BORDER_WIDTH && !SameGlass(voxel + offset, code)) frame = 1.0;
    }
    return frame;
}

// Transmittance colour of the glass from the average of its texture (mip level 4 of a
// 16px sprite is one texel), so resource-pack colours are respected.
vec3 GlassTint(int blockId, vec4 avgTexel) {
    if (blockId == BLOCK_GLASS || blockId == BLOCK_GLASS_PANE) return vec3(0.96, 0.98, 0.98);
    if (blockId == BLOCK_TINTED_GLASS) return vec3(0.16, 0.13, 0.20);
    vec3 c = SrgbToLinear(avgTexel.rgb);
    vec3 hue = c / max(max(c.r, max(c.g, c.b)), 0.6);
    return mix(vec3(1.0), hue, 0.85);
}

TranslucentOut ShadeGlass(int blockId, vec4 avgTexel, vec3 playerPos, vec3 normal, Surface surf, vec3 sunDir, vec3 lightDir) {
    TranslucentOut o;
    vec3 tint = GlassTint(blockId, avgTexel);
    float frame = GlassFrame(playerPos, normal, blockId);

    vec3 V = -normalize(playerPos);
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(abs(dot(normal, V))), 5.0);
    vec3 R = reflect(-V, normal);
    R.y = abs(R.y);
    vec3 reflection = GetSky(R, sunDir, false) * surf.lm.y * surf.lm.y;

    // Frame: a lighter shade of the glass colour, lit like an opaque surface.
    vec3 frameColor = mix(tint, vec3(1.0), 0.45) * 0.75 * GetLighting(surf, sunDir, lightDir);
    const float frameAlpha = 0.9;

    o.light = mix(reflection * fresnel, frameColor * frameAlpha, frame);
    o.transmit = mix(tint * (1.0 - fresnel), vec3(1.0 - frameAlpha), frame);
    return o;
}
