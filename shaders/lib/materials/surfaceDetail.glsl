// Surface detail made from the texture itself (plan items M2-M4): generated normals (a bump
// from each texel's brightness: lighter texels stand out) and coated textures (a faint
// per-texel dusting that breaks up flat colours).
// Needs: common.glsl, and `uniform sampler2D gtexture` declared by the program.

// Texel-snapped texture lookup kept inside this block's sprite in the atlas (bounds =
// min.xy, max.zw), wrapping around so neighbouring sprites never bleed in.
vec4 SpriteTexel(vec2 uv, vec4 bounds, vec2 texelSize) {
    vec2 size = bounds.zw - bounds.xy;
    vec2 c = bounds.xy + mod(uv - bounds.xy, size);
    return textureLod(gtexture, c, 0.0);
}

float TexelHeight(vec4 t) { return Luminance(t.rgb) * t.a; }

// Surface normal with the generated bump. N: geometry normal; playerPos: camera-relative
// position (for the tangent frame, from screen-space derivatives); strength 0..
vec3 GeneratedNormal(vec2 uv, vec4 bounds, vec3 N, vec3 playerPos, float strength) {
    if (strength <= 0.0) return N;
    vec2 texSize = vec2(textureSize(gtexture, 0));
    vec2 texelSize = 1.0 / texSize;
    vec2 center = (floor(uv * texSize) + 0.5) * texelSize;

    float h0 = TexelHeight(SpriteTexel(center, bounds, texelSize));
    float hx = TexelHeight(SpriteTexel(center + vec2(texelSize.x, 0.0), bounds, texelSize));
    float hy = TexelHeight(SpriteTexel(center + vec2(0.0, texelSize.y), bounds, texelSize));
    vec2 slope = vec2(h0 - hx, h0 - hy) * strength;

    // Tangent frame from how position and texture coordinates change across the pixel.
    vec3 dp1 = dFdx(playerPos), dp2 = dFdy(playerPos);
    vec2 duv1 = dFdx(uv), duv2 = dFdy(uv);
    vec3 dp2perp = cross(dp2, N), dp1perp = cross(N, dp1);
    vec3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    vec3 B = dp2perp * duv1.y + dp1perp * duv2.y;
    float scale = max(dot(T, T), dot(B, B));
    if (scale < 1e-20) return N;
    scale = inversesqrt(scale);
    vec3 n = normalize(N + (T * slope.x + B * slope.y) * scale);
    // Never tilt so far that the surface faces away from where it is seen.
    return dot(n, N) < 0.3 ? N : n;
}

float TexelHash(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

// Per-texel dusting: a small random brightness change per texel, different on every block.
vec3 CoatTexture(vec3 albedo, vec2 uv, vec3 blockPos, float strength) {
    vec2 texel = floor(uv * vec2(textureSize(gtexture, 0)));
    float n = TexelHash(vec3(texel, dot(blockPos, vec3(1.0, 57.0, 113.0))));
    return albedo * (1.0 + (n - 0.5) * 0.16 * strength);
}
