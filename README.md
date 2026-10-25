# Untitled Shaders (working name)

An original Iris shaderpack in the style of Complementary Unbound, built to run faster.
Plan and feature list: [docs/PLAN.md](docs/PLAN.md).

**Target:** Minecraft 26.3, NeoForge, Iris + Sodium, OpenGL. In *Video Settings → Graphics API*
choose **OpenGL**; Iris does not run on the Vulkan renderer.

## Status

Milestone **M6 (coloured lighting)** on top of M5 (clouds and light shafts), M4
(temporal), M3 (water), M2 (atmosphere) and M1 (core lighting):

- Deferred pipeline; shadow-mapped sun/moon with coloured shadows and leaf translucency;
  sky-matched ambient, blocklight, handheld light; filmic tonemap.
- Procedural sky for all three dimensions with an Unbound-style sun, a moon with real
  phases (moonlight follows the phase), adjustable stars.
- Fog: altitude-based atmospheric haze coloured by the sky, border fog, cave fog,
  biome-tinted Nether haze with a view limit, End haze.
- Water: refraction and per-channel absorption of the scene behind, screen-space
  reflections, caustics and absorbed sunlight under water (via the shadow map), shoreline
  foam, waving surface, Snell's window and total internal reflection from below.
- Translucents: sorted blending for terrain, clean stained-glass tint (frames from the
  texture, e.g. Continuity), order-independent layers for translucent mobs.

- Temporal anti-aliasing (Halton jitter, reprojection, variance clipping, Catmull-Rom
  history) and contrast-adaptive sharpening.
- Volumetric clouds at half or quarter resolution, blended over frames, with cloud
  shadows, reflections in water, and visibility from under water. Light shafts at half
  resolution (shadow map, coloured glass, clouds; under water with caustics).

- Coloured block light: the shadow pass voxelizes the blocks around the player, a
  compute pass floodfills light colours through them (tinted by stained glass), and
  lighting takes the hue from it while the brightness follows vanilla light levels.
  Per-source colours, coloured candles, coloured held lights.

Not yet: materials/PBR (M7), bloom (M8) (see docs/PLAN.md).

## Install / test

1. Build the zip: `python3 tools/package.py <label>` → `dist/UntitledShaders-<label>.zip`
   (or copy the whole repo folder; Iris loads any folder that contains `shaders/`).
2. Put it in `.minecraft/shaderpacks/` and select it in *Options → Video → Shader Packs*.
3. In game: **R** reloads shaders, **K** toggles them, **O** opens the pack menu.
   On the shader pack screen, **Ctrl+D** enables Iris debug mode (full compile errors).
4. Report problems with a screenshot plus `logs/latest.log` if anything fails to compile.

## Repository layout

```
shaders/
  shaders.properties   menu layout, pipeline flags, blend modes
  block.properties     block -> id table (mirrored in lib/materials/blockIds.glsl)
  dimension.properties dimension -> program folder
  lang/en_US.lang      option names and descriptions
  lib/                 shared GLSL (settings, platform uniforms, lighting, materials, utils)
  program/             one template per pass; world*/ files just include these
  world0/ world-1/ world1/   GENERATED wrappers (tools/gen_wrappers.py)
tools/
  gen_wrappers.py      regenerate world*/ wrappers after editing its program table
  check.py             compile + link every program with glslangValidator, incl. option variants;
                       also checks every on/off option is detectable by Iris
  package.py           check, then zip into dist/
docs/PLAN.md           research, feature list (IDs), milestones
```

## Rendering pipeline

| Stage | Programs | Writes |
|---|---|---|
| Shadow map | `shadow` (in the Nether only for the voxels) | shadowtex0/1, shadowcolor0 (glass tint), shadowcolor1 (water mask), column bit maps (water, glass, block undersides near the player) |
| Coloured light | `shadowcomp` (compute) | floodfill of the voxel volume → floodImgA/B (alternating) |
| Sun / moon | `gbuffers_skytextured` (vanilla sky disc and stars are discarded) | colortex0 |
| Opaque geometry | `gbuffers_terrain/entities/block/hand` | G-buffer: colortex1 albedo+AO, colortex2 normal+lightmap, colortex3 shading model+emission+dry-waterloggable flag |
| Overlays | `gbuffers_clouds/armor_glint/spidereyes/beaconbeam/lightning` | colortex4 (premultiplied) |
| Clouds | `deferred` (half/quarter size, Overworld) | ray-marched clouds blended with the previous frames → colortex9 (light, transmittance), colortex10 (distance) |
| Deferred | `deferred1` | procedural sky + clouds behind everything; lights the G-buffer once per pixel → colortex0, copy in colortex7 |
| Translucent terrain | `gbuffers_water/hand_water` | colortex0 (sorted alpha blend; water opaque, refracting colortex7) + colortex5 tint |
| Translucent mobs | `gbuffers_entities_translucent/block_translucent` | colortex5/6 (order-independent) |
| Particles, weather | `gbuffers_textured/weather` | colortex0 (forward-lit, blended) |
| Composite | `composite` | colortex0 × colortex5 + colortex6, underwater distortion |
| Light shafts | `composite1` (half size), `composite2` (Overworld) | march → colortex11; depth-aware upsample added to colortex0 |
| TAA | `composite3` | history colortex8 (final reads it from there) |
| Output | `final` | reads colortex8 (TAA on) or colortex0; tonemap, sharpening, sRGB, dither, debug views |

## Licence

Original code; not derived from Complementary's source (see docs/PLAN.md §3). Licence TBD.
