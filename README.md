# Untitled Shaders (working name)

An original Iris shaderpack in the style of Complementary Unbound, built to run faster.
Plan and feature list: [docs/PLAN.md](docs/PLAN.md).

**Target:** Minecraft 26.3, NeoForge, Iris + Sodium, OpenGL. In *Video Settings → Graphics API*
choose **OpenGL**; Iris does not run on the Vulkan renderer.

## Status

Milestone **M1 (core lighting)**: deferred pipeline with shadow-mapped sun/moon (coloured
shadows through stained glass, leaf translucency), sky-matched ambient light, blocklight,
handheld light, filmic tonemap, a procedural sky for all three dimensions (sunset glow,
stars, End sky), and interim water (waves, sky reflection, sun glint, depth tint).
Not yet: atmospheric fog, clouds, light shafts, materials/PBR, TAA (see docs/PLAN.md).

## Install / test

1. Build the zip: `python3 tools/package.py M0` → `dist/UntitledShaders-M0.zip`
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
  check.py             compile + link every program with glslangValidator, incl. option variants
  package.py           check, then zip into dist/
docs/PLAN.md           research, feature list (IDs), milestones
```

## Rendering pipeline

| Stage | Programs | Writes |
|---|---|---|
| Shadow map | `shadow` (not in the Nether) | shadowtex0/1, shadowcolor0 (glass tint) |
| Sun / moon | `gbuffers_skytextured` (vanilla sky disc and stars are discarded) | colortex0 |
| Opaque geometry | `gbuffers_terrain/entities/block/hand` | G-buffer: colortex1 albedo+AO, colortex2 normal+lightmap, colortex3 shading model+emission |
| Overlays | `gbuffers_clouds/armor_glint/spidereyes/beaconbeam/lightning` | colortex4 (premultiplied) |
| Deferred | `deferred` | procedural sky behind everything; lights the G-buffer once per pixel → colortex0 |
| Translucents, particles, weather | `gbuffers_water/hand_water/textured/weather` | colortex0 (forward-lit, blended) |
| Output | `final` | tonemap, sRGB, dither, debug views |

## Licence

Original code; not derived from Complementary's source (see docs/PLAN.md §3). Licence TBD.
