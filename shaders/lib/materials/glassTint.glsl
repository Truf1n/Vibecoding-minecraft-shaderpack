#ifndef GLASS_TINT_GLSL
#define GLASS_TINT_GLSL

// Light passing through glass: shared by the glass surface (glass.glsl) and the shadow
// pass, so coloured shadows match what you see through the glass.
// Needs: common.glsl, blockIds.glsl.

// Transmittance colour from the average of the glass texture (mip level 4 of a 16px
// sprite is one texel), so resource-pack colours are respected.
vec3 GlassTint(int blockId, vec4 avgTexel) {
    if (blockId == BLOCK_TINTED_GLASS) return vec3(0.16, 0.13, 0.20);
    if (blockId == BLOCK_GLASS || blockId == BLOCK_GLASS_PANE) return vec3(0.96, 0.98, 0.98);
    vec3 c = SrgbToLinear(avgTexel.rgb);
    vec3 hue = c / max(max(c.r, max(c.g, c.b)), 0.6);
    return mix(vec3(1.0), hue, GLASS_TINT);
}

#endif
