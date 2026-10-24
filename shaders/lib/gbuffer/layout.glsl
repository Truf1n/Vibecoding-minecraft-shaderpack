// Buffer layout. Iris reads these declarations from the comment block.
/*
const int colortex0Format = R11F_G11F_B10F; // HDR scene colour (linear)
const int colortex1Format = RGBA8;          // albedo (sRGB) | vanilla AO
const int colortex2Format = RGBA16;         // world normal (octahedral xy) | blocklight | skylight
const int colortex3Format = RGBA8;          // shading model | emission | reserved | reserved
const int colortex4Format = RGBA16F;        // pre-deferred overlay, premultiplied (clouds, glint, glowing eyes, beams)
const int colortex5Format = RGBA8;          // translucent transmittance (multiplicative, order-independent)
const int colortex6Format = RGBA16F;        // translucent emitted/reflected light (additive, order-independent)
*/

const bool colortex1Clear = true;
const bool colortex2Clear = true;
const bool colortex3Clear = true;
const bool colortex4Clear = true;
const bool colortex5Clear = true;
const bool colortex6Clear = true;
const vec4 colortex0ClearColor = vec4(0.0, 0.0, 0.0, 1.0); // sky is added in deferred
const vec4 colortex1ClearColor = vec4(0.0, 0.0, 0.0, 0.0); // Iris default for colortex1 is white
const vec4 colortex4ClearColor = vec4(0.0, 0.0, 0.0, 0.0);
const vec4 colortex5ClearColor = vec4(1.0, 1.0, 1.0, 1.0);
const vec4 colortex6ClearColor = vec4(0.0, 0.0, 0.0, 0.0);

// Vanilla AO is passed through vertex colour alpha (separateAo = true) at full strength;
// the pack scales it with VANILLA_AO_I.
const float ambientOcclusionLevel = 1.0;

// Unbound-style tilted sun path (plan item L18). The End has no sun, so keep it upright there.
#ifdef WORLD_END
    const float sunPathRotation = 0.0;
#else
    const float sunPathRotation = -40.0;
#endif
