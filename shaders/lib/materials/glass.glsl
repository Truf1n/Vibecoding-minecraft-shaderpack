// Stained/tinted glass: the texture's frame pixels (vanilla or Continuity's connected
// textures) are drawn as-is, while the see-through part becomes a clean colour tint
// of the background instead of a hazy alpha blend.
// Needs: blockIds.glsl, translucent.glsl, sky.glsl, lighting.glsl.
// The tint is multiplied into colortex5 and applied to everything behind in composite.

// Transmittance colour from the average of the glass texture (mip level 4 of a 16px
// sprite is one texel), so resource-pack colours are respected.
vec3 GlassTint(int blockId, vec4 avgTexel) {
    if (blockId == BLOCK_TINTED_GLASS) return vec3(0.16, 0.13, 0.20);
    if (blockId == BLOCK_GLASS || blockId == BLOCK_GLASS_PANE) return vec3(0.96, 0.98, 0.98);
    vec3 c = SrgbToLinear(avgTexel.rgb);
    vec3 hue = c / max(max(c.r, max(c.g, c.b)), 0.6);
    return mix(vec3(1.0), hue, GLASS_TINT);
}

TranslucentSurface ShadeGlass(int blockId, vec4 texel, vec4 avgTexel, vec3 playerPos, vec3 normal, Surface surf, vec3 sunDir, vec3 lightDir) {
    // Frame/streak pixels are noticeably more opaque than the glass on average.
    float frame = smoothstep(avgTexel.a + 0.04, avgTexel.a + 0.15, texel.a);

    vec3 V = -normalize(playerPos);
    float fresnel = 0.04 + 0.96 * pow(1.0 - saturate(abs(dot(normal, V))), 5.0);
    vec3 R = reflect(-V, normal);
    R.y = abs(R.y);
    vec3 reflection = GetSky(R, sunDir, -1.0) * surf.lm.y * surf.lm.y;

    TranslucentSurface s;
    // See-through part: only a faint reflection is blended, the colour is a pure tint.
    s.color = mix(reflection, SrgbToLinear(texel.rgb) * GetLighting(surf, sunDir, lightDir), frame);
    s.alpha = mix(fresnel, texel.a, frame);
    s.tint = mix(GlassTint(blockId, avgTexel), vec3(1.0), frame);
    return s;
}
