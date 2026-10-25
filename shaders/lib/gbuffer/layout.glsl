// Buffer layout. Iris reads these declarations from the comment block.
/*
const int colortex0Format = R11F_G11F_B10F; // HDR scene colour (linear)
const int colortex1Format = RGBA8;          // albedo (sRGB) | vanilla AO
const int colortex2Format = RGBA16;         // world normal (octahedral xy) | blocklight | skylight
const int colortex3Format = RGBA8;          // shading model | emission | reserved | reserved
const int colortex4Format = RGBA16F;        // pre-deferred overlay, premultiplied (clouds, glint, glowing eyes, beams)
const int colortex5Format = RGBA8;          // translucent tint (multiplicative: stained glass, translucent mobs)
const int colortex6Format = R11F_G11F_B10F; // translucent mobs: added light (additive, order-independent)
const int colortex7Format = R11F_G11F_B10F; // lit opaque scene copy from deferred (read by water reflections)
const int colortex8Format = RGBA16F;        // TAA history (kept between frames)
const int colortex9Format = RGBA16F;        // clouds (buffer at the cloud resolution): scattered light | transmittance (kept: history)
const int colortex10Format = R16F;          // clouds (buffer at the cloud resolution): distance along the view ray
const int colortex11Format = RGBA16F;       // light shafts (half-size buffer): light | linear depth
*/

const bool colortex1Clear = true;
const bool colortex2Clear = true;
const bool colortex3Clear = true;
const bool colortex4Clear = true;
const bool colortex5Clear = true;
const bool colortex6Clear = true;
const bool colortex8Clear = false;
const bool colortex9Clear = false;
const bool colortex10Clear = false;
const bool colortex11Clear = false;
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
