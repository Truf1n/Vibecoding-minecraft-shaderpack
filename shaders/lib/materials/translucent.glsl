// Two ways translucent geometry reaches the image:
//
// 1. Sorted surfaces (terrain translucents: water, ice, glass, slime...): Sodium sorts
//    these back to front, so they alpha-blend into colortex0 normally and layer correctly
//    (ice under water is dimmed by the water). Coloured transmittance that alpha blending
//    cannot express (stained glass tint) is multiplied into colortex5 and applied in composite.
//
// 2. Order-independent layers (translucent mobs, which Iris may draw before or after the
//    deferred pass): add light into colortex6 and multiply transmittance into colortex5.
//    Both blends commute, so draw order does not matter.
//
// The composite pass resolves: colortex0 * colortex5 + colortex6.

struct TranslucentSurface {
    vec3 color;  // blended over the background with `alpha`
    float alpha;
    vec3 tint;   // extra per-channel multiplier for everything behind (1 = none)
};

TranslucentSurface PlainSurface(vec3 color, float alpha) {
    TranslucentSurface s;
    s.color = color;
    s.alpha = alpha;
    s.tint = vec3(1.0);
    return s;
}

struct TranslucentOut {
    vec3 light;    // light added in front of the background
    vec3 transmit; // fraction of the background that shows through, per channel
};

TranslucentOut AlphaLayer(vec3 color, float alpha) {
    TranslucentOut o;
    o.light = color * alpha;
    o.transmit = vec3(1.0 - alpha);
    return o;
}

// Fog for an additive layer: the background was already fogged at its own distance,
// so fade this layer's own contribution out instead of adding fog colour again.
TranslucentOut FogLayer(TranslucentOut o, float fogAmount) {
    o.light *= 1.0 - fogAmount;
    o.transmit = mix(o.transmit, vec3(1.0), fogAmount);
    return o;
}
