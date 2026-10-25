// Special portal effects (plan item M11): a deep, drifting starfield inside End portals and
// gateways, and a slow swirl of light over Nether portals.
// Needs: common.glsl.

float PortalHash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Stars on several layers seen through the portal surface, deeper layers shifting less
// as the view moves (parallax). playerPos: camera-relative position on the portal.
vec3 EndPortalColor(vec3 playerPos) {
    vec3 dir = normalize(playerPos);
    vec3 worldPos = playerPos + cameraPosition;
    vec3 color = vec3(0.006, 0.012, 0.020);
    for (int i = 0; i < 6; i++) {
        float layer = float(i);
        float depth = 1.0 + layer * 1.6;
        vec2 p = (worldPos.xz + dir.xz / max(abs(dir.y), 0.25) * depth) * (2.2 + layer * 0.7) + layer * 13.7;
        p += frameTimeCounter * vec2(0.06, 0.035) * (1.0 + layer * 0.3);
        vec2 cell = floor(p);
        float h = PortalHash(cell + layer * 7.1);
        vec2 offset = vec2(PortalHash(cell + 3.3), PortalHash(cell + 9.1)) - 0.5;
        float star = smoothstep(0.12, 0.0, length(fract(p) - 0.5 - offset * 0.6)) * step(0.72, h);
        vec3 tint = mix(vec3(0.20, 0.90, 0.80), vec3(0.55, 0.30, 1.00), fract(h * 7.3));
        color += star * tint * (1.2 - layer * 0.15);
    }
    return color;
}

// Brightness of a Nether portal's light at a point: slow waves of light drifting over it.
float NetherPortalSwirl(vec3 worldPos) {
    float t = frameTimeCounter * 0.6;
    vec2 p = vec2(worldPos.x + worldPos.z, worldPos.y);
    float a = sin(p.x * 1.7 + sin(p.y * 1.3 + t) * 1.5 + t * 0.8);
    float b = sin(p.y * 2.1 - sin(p.x * 0.9 - t * 1.1) * 1.2 - t);
    return 0.8 + 0.25 * (a * b);
}
