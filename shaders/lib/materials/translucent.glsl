// Order-independent translucency: each translucent surface adds light (colortex6, additive
// blend) and multiplies the background by its transmittance (colortex5, multiplicative
// blend). Both blends are commutative, so the result does not depend on draw order
// (Sodium re-sorts translucent faces only after the camera settles).
// The composite pass resolves: scene * transmittance + light.

struct TranslucentOut {
    vec3 light;    // light added in front of the background (reflections, scattering, frames)
    vec3 transmit; // fraction of the background that shows through, per channel
};

// A plain alpha-blended surface expressed in the same form.
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
