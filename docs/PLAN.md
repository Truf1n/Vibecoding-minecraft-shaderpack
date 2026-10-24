# Shaderpack Plan: a Complementary Unbound-style pack that runs faster

*Research and implementation plan, 23 Oct 2026. Reference: Complementary r5.9.2 (14 Sep 2026), the latest release.*

**How to use this document:** every feature has an ID (for example `C3` or `W9`). When you've read it, reply with the IDs you want, the ones you want **changed** (and how), and the ones to **drop**. If you don't want to go through them all, section 7 has my suggested v1 scope.

---

## 0. TL;DR

1. **Platform is the biggest decision, and it changed this year.** Minecraft Java is moving from OpenGL to Vulkan: 26.4 Snapshot 1 (22 Sep 2026) made Vulkan the default. Iris, which runs every current shaderpack including Complementary, **only works on OpenGL**. Players have to set *Graphics API → OpenGL* to use it. Iris's successor, **Aperture**, runs on Vulkan but uses a new, incompatible format (TypeScript pipeline + Slang shaders). It is in private beta for shader developers, and its public docs are marked outdated. **My recommendation:** build on Iris now, because it's the only format you can actually play and test today, and structure the code so a later Aperture port mostly means rewriting the pipeline layer, not the effects.
2. **Complementary Unbound is ~21,600 lines of GLSL built since 2018.** Full parity is a long project. The plan is phased so you get a playable, good-looking pack early (milestones M0–M5) and features are added after that.
3. **Licence:** Complementary's licence does not allow copying or modifying its code into a new pack that looks like it. So this will be an **original codebase**. It aims for the Unbound *style* using standard, published rendering techniques. I used Complementary's source only to list its features and understand its pipeline at a high level.
4. **Running faster than Unbound is realistic.** The source shows several expensive systems run at full resolution or touch huge data volumes every frame: clouds, light shafts, SSAO, floodfill coloured lighting, and lighting done during geometry rendering. Section 4 lists the specific changes. I can't benchmark here (no GPU or Minecraft in this container), so all performance claims need to be measured on your machine.
5. **Testing loop:** I can write the shader code and compile-check it here (`glslangValidator` is installed). You load it in-game, press R to reload, and send screenshots or errors back. Visual tuning will take many rounds of that.

---

## 1. What making a Minecraft shaderpack involves

### 1.1 Loaders and platforms

| Loader | Status (Oct 2026) | Pack format | Notes |
|---|---|---|---|
| **Iris** (Fabric/NeoForge, with Sodium) | Actively maintained (1.11.x on MC 26.3). **OpenGL only.** | "OptiFine format": GLSL files + `.properties` | The de-facto standard. Adds compute shaders, custom 3D images, SSBOs, DH/Voxy hooks. Complementary itself recommends Iris over OptiFine. |
| **OptiFine** | Legacy | Same format, fewer features | Lacks Iris's custom images and SSBOs, so no voxel coloured lighting. Supporting it as well doubles testing. **Recommend: don't target it.** |
| **Aperture** (Iris successor) | Private beta for shader devs, Vulkan + Sodium on 26.2 | `pack.ts` (TypeScript pipeline definition) + **Slang** shaders. No default pipeline; every texture and pass is defined explicitly. | Not compatible with old packs. Public migration guide says it's "extremely outdated". Possibly the long-term future. |
| Vulkan PostFX / Vulcade / iris-vulkan fork | Experimental third-party | Own formats | Not mature; ignore for now. |

Minecraft versions now use year-based numbers (26.1, 26.2, 26.3, 26.4 snapshots). Mojang hasn't announced when (or whether) OpenGL will be removed. Until then, Iris packs work with the OpenGL setting.

### 1.2 Anatomy of a pack (Iris / OptiFine format)

```
MyPack.zip (or a folder in .minecraft/shaderpacks/)
└─ shaders/
   ├─ shaders.properties     # options menu layout, profiles, sliders, custom uniforms,
   │                         # buffer sizes, custom images/SSBOs, per-program toggles, blending
   ├─ block.properties       # maps block names → integer IDs the shader branches on (materials!)
   ├─ item.properties        # held-item IDs (handheld light colour etc.)
   ├─ entity.properties      # entity IDs (glowing eyes, special materials)
   ├─ dimension.properties   # maps (modded) dimensions to folders
   ├─ lang/en_US.lang        # option names + hover descriptions
   ├─ world0/ world-1/ world1/   # overworld / nether / end: thin per-program files that
   │                             # #define the dimension and #include the shared program
   ├─ program/               # shared program sources (one per pass)
   └─ lib/                   # shared GLSL: lighting, atmosphere, materials, noise, utils
```

### 1.3 The frame, pass by pass

Iris runs these programs in order every frame. You implement the ones you need, and missing ones fall back to defaults.

1. **setup** (compute, once at load or resize): precompute lookup tables.
2. **begin** (compute/fullscreen): per-frame bookkeeping.
3. **shadow**: re-renders the world from the sun's point of view into a shadow map. Also used to **voxelize** blocks into 3D images for coloured lighting. This pass is often CPU-bound because it means rendering the geometry a second time.
4. **shadowcomp** (fullscreen/compute): processes shadow-pass data, for example floodfill light propagation.
5. **prepare** (fullscreen): before terrain.
6. **gbuffers_\*** (opaque): terrain, entities, block entities, hand, sky, clouds, particles, weather, beacon beams, lightning, enchant glint, damaged blocks, spider eyes, lines. These write colour, normals and material data into **colortex** buffers.
7. **deferred** (fullscreen, 1–99): lighting and effects that need the opaque scene, such as SSAO, sky and clouds.
8. **gbuffers_water / translucent**: water, glass, ice, slime and honey are drawn over the opaque scene.
9. **composite** (fullscreen, 1–99): reflections, refraction, fog, volumetric light, bloom, TAA, and so on.
10. **final**: writes to the screen.

Key concepts you'll see throughout:

- **colortex0–15**: render targets with chosen formats, for example `R11F_G11F_B10F` for HDR colour. Fullscreen passes read the "main" copy and write the "alt" copy, then the copies swap (**buffer flipping**).
- **`/* RENDERTARGETS: 0,3 */`** comments choose which buffers a pass writes.
- **Options are preprocessor `#define`s.** `shaders.properties` builds the menus and profiles from them, and changing an option recompiles the pack. That is why heavy features cost nothing when they're off.
- **Custom uniforms** in `shaders.properties` (smoothed values, biome checks, "is in cave" estimates) avoid per-pixel work.
- **Iris-only:** custom 2D/3D images (`image.*`), SSBOs, compute shaders, `shadow.culling = reversed` for voxelization, `size.buffer` and `scale` for lower-resolution passes.
- **Distorted shadow maps:** one shadow map, warped so it has more resolution near the player. Iris has no cascaded shadow maps.
- **Temporal accumulation (TAA):** effects use a few noisy samples per frame that get averaged over time. Almost every modern pack depends on this.

### 1.4 Development workflow

- Edit files in the `shaderpacks/` folder. In game, **R** reloads shaders, **K** toggles them, and **O** opens the pack menu. Iris's debug mode (Ctrl+D on the shader pack screen) shows full compile errors.
- **What I can do here:** write all code and compile-check every program with `glslangValidator` against a stub header of Iris uniforms, so syntax and type errors are caught before you load it.
- **What only you can do:** run it, look at it, and measure FPS. Any visual tuning needs your screenshots.
- **Profiling (for the "faster" goal):** FPS and 1%-low logging with CapFrameX or PresentMon on Windows, or MangoHud on Linux. Per-pass GPU timings with RenderDoc, NVIDIA Nsight Graphics or AMD Radeon GPU Profiler.

---

## 2. How Complementary Unbound works (what we're matching)

- **"Unbound" is a style preset, not a separate pack.** Reimagined and Unbound share one codebase. The *Visual Style* option switches these defaults:
  - Unbound water style
  - Unbound volumetric clouds
  - Unbound sun/moon
  - sun path tilted −40°
  - Unbound aurora
  - Unbound rainbow
  - glowing ores on

  Everything else is shared.
- **Lighting is forward.** Full lighting (shadows, sky light, block light, coloured light) is computed inside every geometry shader: terrain, entities, water, hand and so on, 12 programs in total. Pixels that are drawn and then covered by other geometry are shaded anyway (overdraw). This is worst with dense foliage.
- **Fullscreen passes:**
  - `deferred1`: SSAO, sky, clouds, outlines, distant-light bokeh
  - `composite`: reflections
  - `composite1`: volumetric light, fog, refraction, Nether storm, coloured light fog
  - `composite3`: bloom fog
  - `composite4`: tiled bloom blur, many taps in one pass
  - `composite5`: bloom apply, lens flare
  - `composite6`: TAA
  - `composite7`: FXAA
  - `final`: sharpening, error text

  That's 9 fullscreen passes, plus a floodfill compute pass.
- **Resolution:** clouds (up to 30 ray-march steps per pixel), volumetric light and SSAO all run at **full resolution** every frame, made smooth with dithering and TAA. Only PBR reflections have a half-resolution option.
- **Advanced Color Tracing (ACT)** is its coloured lighting:
  - Light blocks are written into a 3D voxel image during the shadow pass, with `shadow.culling = reversed`, which turns off shadow-pass culling near the player. That's a hidden CPU cost.
  - A compute shader then spreads light through the **whole** volume every frame (floodfill), alternating between two RGBA16F 3D textures.
  - VRAM for the ACT volumes alone: ~64 MB (6 chunks), ~151 MB (8 chunks), **~1.2 GB (16 chunks, its top profile)**, ~4.8 GB (32 chunks).
  - World-space reflections add a further 200–810 MB buffer. The top profile uses **~2 GB of VRAM** for these systems alone.
- **IntegratedPBR+ ("IPBR+")** is the main reason it looks the way it does. It's a hand-tuned material library: per-block smoothness, metalness, emission and subsurface scattering for vanilla blocks, about 2,850 lines for terrain alone, plus a ~500-line `block.properties`. This is the single biggest *content* effort in the project.
- **Profiles:** Potato, Very Low, Low, Medium, High, Very High, Ultra, "Complementary". They control shadows, reflections, light shafts, SSAO, FXAA, detail quality, clouds, AF, ACT, WSR, entity shadows and puddles.

---

## 3. Licence and the clean-room approach

My reading of the Complementary License Agreement 1.7 (not legal advice):

- Modifying its code, or redistributing parts of it, is only allowed as a "Modified Pack" that meets all of these: credit and link, no "Complementary" in the name, **must look noticeably different from the original in daytime overworld scenes**, must keep *their* licence and no other, and must contain significant **human-written** code.
- A pack that deliberately looks like Unbound can't meet the "look different" rule. Code written by me may not count as human-written either.
- **So:** we write everything from scratch, using techniques that are public knowledge (papers, articles, textbook graphics). The visual style is matched by eye from screenshots and gameplay. That's fine: a style isn't owned, but their code and tuned constants are. I won't copy code or constants from their source.
- You can choose any licence for the new pack (for example MIT, or something more restrictive).

---

## 4. Plan to beat Unbound's performance

These are the main levers, compared against what Complementary does (from its source). The impact figures are **estimates to be confirmed by measurement**.

| System | Complementary r5.9.2 | Our approach | Expected effect |
|---|---|---|---|
| Volumetric clouds | Full-res ray march, up to 30 steps/pixel, every frame | Half- or quarter-res march + temporal reprojection (checkerboard over 2–4 frames) + depth-aware upsample; skip pixels covered by terrain using a min/max depth pyramid | Cloud cost ↓ ~60–85% |
| Light shafts (VL) | Full-res, dithered + TAA | Half-res + bilateral upsample; skipped entirely when the sun is behind you, below the horizon or you're indoors (cheap uniforms) | VL cost ↓ ~50–75% |
| SSAO | Full-res | Half-res ground-truth AO (GTAO) + bilateral upsample, with temporal accumulation | AO cost ↓ ~50–70% |
| Opaque lighting | Forward: shading runs for every drawn fragment in 12 programs, including overdrawn ones | **Deferred**: geometry passes only write a compact G-buffer, and lighting runs once per pixel. Translucents stay forward. | Biggest win in foliage-heavy scenes. Costs extra G-buffer bandwidth, so it **must be measured**. |
| Coloured light (floodfill) | Whole volume every frame; RGBA16F ×2; full vertical range | Two-tier update (near region every frame, far region spread over several frames); `R11G11B10F` storage (half the bytes); smaller vertical range; propagate several steps per dispatch using shared memory | VRAM ↓ ~3.5× at the same range (16 chunks: ~1.2 GB → ~340 MB); compute ↓ ~2–4× |
| Bloom | Tiled blur with large sampling loops in one pass, then an apply pass | Compute mip-chain downsample + small upsample (far fewer taps per pixel) | Modest win |
| Shadow pass (CPU) | Up to 4096² map, 16 chunks at top profile; entity shadows can cost "more than 50% FPS" (their words) | Profile-tuned distances; entity shadows near-only by default; optional "no shadows from tiny foliage"; leaf-shadow LOD | Fewer draw calls; varies a lot by scene |
| Pass count / bandwidth | 9 fullscreen passes | Merge fog + VL + refraction where possible; tight formats (`R11G11B10F`, octahedral normals in 16 bits, 8-bit material) | Small but universal win, more noticeable at 1440p/4K |
| Profiles | 8 tiers | ~6 tiers tuned by **measured** cost per feature, with costly options labelled in the menu | Better defaults |

**Reality check.** Complementary is known for a good visuals-to-performance ratio and already has some optimizations (half-res reflections, leaf-shadow optimization). The evidence on how heavy it is relative to other packs is thin:

- One un-benchmarked YouTube comparison had Unbound as the slowest of BSL, Photon, Bliss and Unbound.
- The author of BCU, a derivative pack, claims ~150 vs ~110 FPS on an RTX 3070. That's unverified, but it suggests there's headroom.

Our gains come mainly from **resolution, amortization and deferred shading**, not micro-tweaks.

**Benchmark method** (proposed; run on your machine):

- 5 fixed scenes on a fixed seed: forest at noon, ocean at sunset, cave with torches, Nether, rainy village.
- Fixed `/time`, `/weather` and FOV, at 1080p and 1440p.
- Complementary Unbound at the closest matching profile.
- Record average FPS and 1% lows over 30 s.
- Goal: **≥25–40% higher FPS at matched visual tier**. That's a target, not a promise.

---

## 5. Complete Complementary Unbound feature list with notes

**Legend**

- **Effort:** S = small and self-contained; M = a subsystem with a few tuning rounds; L = major subsystem, multi-session; XL = flagship system, many sessions.
- **Cost (GPU/CPU):** Free / Low / Med / High / V.High.
- **Rec (my recommendation):** Core = needed for the Unbound look; Yes = recommended; Maybe = optional; Later = after v1; Skip.
- `[ ]` = Complementary's option values.

### B. Foundations (not menu options, but required)

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| B1 | HDR pipeline + filmic tonemapper (exposure, contrast, "white path") | M | Low | Core | Write our own curve tuned to the Unbound look by eye. |
| B2 | G-buffer layout + material ID system (`block/item/entity.properties`) | M | — | Core | Deferred layout from section 4. ID table is large but mechanical. |
| B3 | Lighting model: sun/moon light, sky ambient, block light, minimum light, time-of-day colour palettes (sunrise, noon, night, rain, Nether, End) | L | Med | Core | Most of the "feel" lives here. |
| B4 | Sky rendering: gradient sky, horizon glow, sunset scattering (artistic, not physical) | M | Low | Core | Alternative: physically-based sky LUTs. More realistic but less "Unbound". |
| B5 | Distorted shadow map + filtering + bias | M | High | Core | See L1. |
| B6 | Basic distance fog + underwater, lava and powder-snow fog | S | Low | Core | |
| B7 | Translucents: water, stained glass tint, ice, slime, honey; multi-layer handling | L | Med | Core | Water seen behind glass is a classic pain point. |
| B8 | All gbuffers programs: hand, entities, block entities, particles, weather, beacon beam, lightning, glint, damaged block, spider eyes, lines | M | — | Core | Mostly plumbing. |
| B9 | Settings menu: screens, sliders, profiles, `en_US.lang` descriptions | M | — | Core | Built up as features land. |
| B10 | Overworld / Nether / End variants | S | — | Core | |

### G. Global settings

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| G1 | Visual Style switch [Reimagined / Unbound] | L | — | Skip | We build Unbound only. A second style doubles the art work. Could come later. |
| G2 | RP Support [Basic / IntegratedPBR+ / seuspbr / labPBR] | M | Low | Core | Basic + IPBR-style in v1; labPBR in P1. |
| G3 | Profiles [Potato … Ultra, "Complementary"] | S | — | Core | ~6 tiers, tuned by measurement. |
| G4 | Detail Quality [Potato/Med/High/Ultra]: bundles water material, TAA quality, nebula, Nether storm, sky reflections, puddle accuracy, waving, motion blur, reflection fixes, translucent filtering | S | varies | Core | Same idea, our own grouping. |
| G5 | In-menu "Information" help buttons | S | Free | Maybe | |
| G6 | Yellow/red names for costly settings | S | Free | Yes | Very useful for users. |

### L. Shadows and lighting

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| L1 | Real-time sun/moon shadows [Off, Very Low → Ultra; 1024–4096 maps, better filtering per tier] | M | High | Core | Blue-noise rotated PCF + TAA. Alternative: PCSS (see +3). |
| L2 | Shadow distance [4 → 64 chunks] | S | High | Core | Main CPU lever. |
| L3 | Coloured shadows through stained glass | S | Low | Core | Uses a second shadow colour buffer. |
| L4 | Shadow smoothing [Very sharp → Very smooth] | S | Low–Med | Yes | Sharp needs a bigger map. |
| L5 | Entity shadows [Off / mobs / mobs + block entities] | S | High | Yes | Default: mobs, near-only. |
| L6 | Player shadow toggle | S | Low | Yes | |
| L7 | Leaf shadow optimization (drops leaf/vine shadows in dark areas) | S | saves | Yes | |
| L8 | SSAO "edge shadow" [Off/Med/High] + intensity | M | Med | Yes | We use half-res GTAO. |
| L9 | Vanilla AO intensity | S | Free | Core | |
| L10 | Shadow-light (ambient) multiplier | S | Free | Core | |
| L11 | Cave lighting multiplier (minimum light without skylight) | S | Free | Core | |
| L12 | Blocklight intensity, RGB, contrast curve | S | Free | Core | |
| L13 | Blocklight flickering | S | Free | Yes | |
| L14 | Dynamic handheld lighting [Off / Subtle / Normal] | S | Low | Core | |
| L15 | Directional blocklight (labPBR only) [Subtle/Normal/Intense] | M | Med | Maybe | |
| L16 | Pixelated shadows / blocklight / AO + pixel scale [0.25×–16×] | M | Low | Maybe | Popular "pixel-locked" lighting look. |
| L17 | Moon-phase influence on night light, atmosphere and moon reflection [full / partial / new intensities] | S | Free | Yes | |
| L18 | Sun/moon path angle (Unbound = −40°) | S | Free | Core | |
| L19 | Leaf/foliage subsurface scattering (part of IPBR+) | M | Low | Core | Big part of the sunlit-forest look. |

### A. Advanced Color Tracing (voxel coloured lighting) and its extras

Needs compute shaders, so it won't work on macOS.

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| A1 | Coloured blocklight via voxelization + floodfill [Off, 4 → 32 chunks] | XL | High (VRAM!) | Yes (v2) | Our amortized version from section 4. Alternatives: (a) cheap fake colour from a per-light-ID tint near the light (no propagation); (b) Photonics mod (D5). |
| A2 | Coloured light saturation | S | Free | Yes | |
| A3 | Torch/fire colour warmth | S | Free | Yes | |
| A4 | Coloured light fog (volumetric blocklight fog) + intensity | M | High | Maybe | They mark it "can severely impact performance". Ours would be half-res. |
| A5 | Coloured candle light (matches candle colour) | S | Free | Yes | |
| A6 | Connected glass (all glass connects; auto-off with the Continuity mod) | M | Low | Maybe | |
| A7 | Glowing portal edges | S | Low | Maybe | |
| A8 | No rain puddles under glass roofs (voxel check) | S | Low | Maybe | |
| A9 | World-Space Reflections [WSR only / WSR + SSR], max 16 chunks | XL | V.High | Later | Reflects things that are off-screen. Adds a ~200–810 MB buffer. |
| A10 | Player model in WSR | L | High | Skip | |

### S. Sky, sun, moon and night sky

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| S1 | Unbound sky colours across the day (incl. rain) | M | Low | Core | |
| S2 | Sun/moon style [Reimagined / Unbound / Unbound-smaller] | S | Free | Core | Unbound style. |
| S3 | Hide sun/moon below horizon | S | Free | Yes | |
| S4 | Sun/moon visible during rain (also rebalances rain lighting) | S | Free | Yes | |
| S5 | Star amount [Off → Very high] | S | Free | Core | |
| S6 | Night nebulae (procedural, different every night) + brightness | M | Med | Yes | |
| S7 | Aurora [Off / Reimagined / Unbound] + condition [every night / full moon / snowy biome / combos] | M | Low–Med | Yes | |
| S8 | Rainbows [Off / after rain / always], Unbound style | S | Low | Yes | |
| S9 | Sky effects in reflections [Off / water / water + blocks] | S | Low–Med | Yes | |

### C. Clouds

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| C1 | Cloud style [Off / Reimagined layer / **Unbound volumetric** / Vanilla] | L | High | Core | Unbound volumetric at reduced resolution (section 4). Vanilla pass-through is free. A "Reimagined"-style layer could be Maybe. |
| C2 | Cloud quality [Low / Med / High]: samples, lighting, detail | S | — | Core | |
| C3 | Cloud shadows on terrain | S | Low | Yes | |
| C4 | Prevent clouds in interiors | S | Free | Yes | |
| C5 | Altitude; speed incl. "synced to world time" (same clouds for everyone on a server) | S | Free | Yes | |
| C6 | Cloud RGB colour | S | Free | Yes | |
| C7 | Unbound clouds: amount, size, extra clouds in rain | S | Free | Yes | |
| C8 | Reimagined clouds: second layer + its altitude | S | Low | Skip | Only relevant with a Reimagined style. |

### F. Fog and volumetric light

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| F1 | Border fog (hides chunk edges) | S | Free | Core | |
| F2 | Atmospheric (height) fog: intensity, start distance, altitude | S | Low | Core | |
| F3 | Cave fog | S | Low | Yes | |
| F4 | Less fog inside lava / powder snow | S | Free | Yes | |
| F5 | Light shafts [quality Off → Very high; mode Scene-aware / Regular / Extreme] | M | High | Core | Half-res plus early-outs (section 4). |
| F6 | Light-shaft "smoke" (noisy volumetric density) | M | V.High | Maybe | Cheaper at half-res; still pricey. |
| F7 | Special Pale Garden light shafts | S | Low | Maybe | |
| F8 | Light-shaft multipliers per time (noon / sunset / night / rain) + sunset colour | S | Free | Yes | |

### R. Weather

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| R1 | Rain style [Light & warmer / Heavy & colder] | S | Free | Yes | |
| R2 | Special cold/dry weather (snowstorm / sandstorm atmosphere by biome) | S | Low | Yes | |
| R3 | Weather texture opacity | S | Free | Yes | |
| R4 | Improved weather rendering (better colours; fixes rain invisible behind glass) | M | Low | Yes | |
| R5 | Rain puddles [Off / puddles in rain / full coverage in rain / always variants] | M | Low–Med | Yes | Needs block reflections (X1). |

### N. Nether

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| N1 | Nether storm (volumetric smoke) + opacity, base altitude, height | M | Med | Maybe | Would be half-res. |
| N2 | Nether view limit [6 chunks → limitless] | S | varies | Yes | |
| N3 | Nether colour mode [constant / per-biome / per-biome rebalanced] | S | Free | Yes | |

### E. End

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| E1 | End beams (volumetric) + intensity, centre altitude, height | M | Med | Yes | |
| E2 | End stars + intensity | S | Free | Yes | |
| E3 | End flashes (sky-flash event added in MC 1.21.9) | S | Free | Yes | |

### W. Water

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| W1 | Water style [Reimagined / Reimagined + waves / **Unbound**] | L | Med | Core | Unbound style. |
| W2 | Caustics (light patterns under water) [same as water / Reimagined / Unbound] | M | Low | Yes | |
| W3 | Refraction intensity + underwater screen distortion | M | Low–Med | Core | |
| W4 | Foam at water edges | S | Low | Yes | |
| W5 | Water opacity factor, water fog factor | S | Free | Core | |
| W6 | Surface colour RGB + mode [constant / biome / biome-clamped] | S | Free | Yes | |
| W7 | Brighter shallow / cave water | S | Free | Yes | |
| W8 | Underwater colour RGB | S | Free | Yes | |
| W9 | Wave normals: strength; small / medium / large wave strength; speed; size | M | Low | Core | |
| W10 | Waving water height (vertex movement) | S | Low | Yes | |
| W11 | Water reflections [Off / sky only / "Potato" fast / Medium screen-space ray traced (SSR)] | M | Med–High | Core | SSR with hierarchical depth for speed. |

### X. Reflections and glass

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| X1 | Block reflections [Off / sun-moon highlights only / full specular reflections] | M | Med | Core | |
| X2 | Reflection resolution [Full / Half] | S | saves | Core | Half by default. |
| X3 | Improved glass (adds a translucent layer) | S | Low | Yes | |
| X4 | More reflective distant glass | S | Free | Yes | |
| X5 | Mirror-like tinted glass [35 / 70 / 100%] | S | Low | Maybe | |

### M. Materials: IntegratedPBR+ equivalent (no resource pack needed)

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| M1 | **Built-in material library**: per-block smoothness, metalness, emission and SSS for vanilla blocks, block entities and entities | XL | Low–Med | Core | Biggest content job. Start by category (metals, gems, ores, stone, wood, foliage, emissives), then refine per block. |
| M2 | Generated normals (auto bump from textures) + strength + resolution | M | Low–Med | Yes | |
| M3 | Coated textures (auto "dusty" detail) + strength | S | Low | Yes | |
| M4 | Allow M2/M3 on entities | S | Low | Yes | |
| M5 | Glowing ores: master switch, strength, and each of iron, gold, copper, redstone, lapis, emerald, diamond, nether quartz, nether gold, gilded blackstone, ancient debris, modded ores | M | Low | Core | On by default in Unbound. |
| M6 | Glowing amethyst [crystal / + block], glow lichen [off / closed areas / always], emissive redstone block, emissive lapis block | S | Free | Yes | |
| M7 | Glowing armour trims | S | Free | Yes | |
| M8 | Emissive mode: let labPBR/seuspbr packs override built-in emission | S | Free | Later | With P1. |
| M9 | Compatibility mode (gentler on mods / resource packs) | S | Free | Maybe | |
| M10 | Particle features (glowing lava particles, better water particles) | S | Free | Yes | |
| M11 | Special portal effects (animated Nether / End portals and gateways) | M | Low | Yes | |
| M12 | Green-screen lime blocks (for video editing) | S | Free | Maybe | |
| M13 | Hide armour [main player / all entities; elytra only while flying] | S | Free | Maybe | |
| M14 | Snowy world (everything snow-covered) | S | Low | Maybe | |
| M15 | Shader-side anisotropic filtering [Off / 4× / 8× / 16×] | M | Med | Maybe | |

### P. Resource-pack PBR

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| P1 | labPBR support (normal, specular, emission, porosity, SSS, AO maps) | M | Low–Med | Yes | Modern standard. |
| P2 | seuspbr support | S | Low | Skip | Legacy format. |
| P3 | Normal-map strength, custom emission intensity | S | Free | Yes | |
| P4 | Parallax occlusion mapping: depth, quality [16–512], distance, lighting [smooth / sharp], on cutout blocks | L | High | Maybe | |

### V. Waving and animation

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| V1 | Waving grass / foliage | S | Low | Core | |
| V2 | Waving leaves | S | Low | Core | |
| V3 | Waving lava texture | S | Free | Yes | |
| V4 | Waving lily pads (bobbing on waves) | S | Free | Maybe | |
| V5 | Waving rain / snow textures | S | Free | Yes | |
| V6 | Waving speed, intensity, no waving indoors, rain multiplier | S | Free | Yes | |
| V7 | Hand sway ("breathing") [Off / Subtle / Normal / Intense] | S | Free | Yes | |

### K. Camera and post-processing

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| K1 | Bloom + strength (including rain / cave humidity "bloom fog") | M | Med | Core | Compute mip-chain bloom. |
| K2 | Lens flare [sun only / sun + moon; circle / square] + intensity | M | Med | Maybe | They mark it "can severely impact"; ours can be cheaper. |
| K3 | Vignette | S | Free | Yes | |
| K4 | Chromatic aberration | S | Low | Yes | |
| K5 | Image sharpening [Off → 10×] | S | Low | Yes | Contrast-adaptive sharpening (CAS) combined with TAA. |
| K6 | Motion blur + strength | M | Med | Maybe | |
| K7 | World blur: distance blur (per condition: day, night / interior, rain, underwater, Nether, End) **or** depth of field (strength; focus auto or on the brightness slider); FOV-scaled, chromatic, anamorphic options | M | High | Maybe | |
| K8 | Distant light bokeh (distant lights look scattered) | S | Low | Yes | |
| K9 | Colour balance: brightness, contrast, saturation, vibrance, dark desaturation, white reachability | S | Free | Core | |

### T. Anti-aliasing

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| T1 | TAA [on / off]: smoothing, jitter [off / low / medium / full], Catmull-Rom sampling | M | Low–Med | Core | Required for the reduced-resolution effects. |
| T2 | FXAA [on / off]: strength, reduce while moving | S | Low | Yes | |

### H. Colour customization

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| H1 | Lighting colour multipliers (RGB + intensity) for sunrise / sunset, noon, night, rain, Nether, End | S | Free | Yes | |
| H2 | Atmosphere colour multipliers for the same 6 conditions | S | Free | Yes | |
| H3 | Colour grading matrix (R/G/B → R/G/B) + per-channel curves | S | Free | Yes | |

### U. Utility and misc

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| U1 | Selection outline [Off / default / rainbow / custom colour / "versatile"] + auto-hide when empty-handed + brightness / RGB | S | Free | Yes | |
| U2 | World outline (bright edges): thickness, brightness, on entities, distance-scaled | S | Low–Med | Maybe | |
| U3 | Dark outline + thickness | S | Low–Med | Maybe | |
| U4 | Show light levels (mob-spawn overlay) [hold spider eye / hold light / always] | S | Free | Yes | |
| U5 | Reduce close-up particles | S | Free | Yes | |
| U6 | Force all coloured particles to glow | S | Free | Skip | |
| U7 | Colour-coded programs (debug view of which program drew what) | S | Free | Yes | Helps *us* debug. |
| U8 | On-screen error text (unsupported combinations: OptiFine / macOS + ACT, multiple LOD mods, extreme coordinates, etc.) | S | Free | Maybe | |

### D. Mod support

| ID | Feature | Effort | Cost | Rec | Notes / alternatives |
|---|---|---|---|---|---|
| D1 | Distant Horizons (`dh_terrain` / `dh_water` / `dh_shadow`, seamless blend, fog) | L | varies | Maybe | Every material and fog path needs a DH version. |
| D2 | Voxy (LOD mod) | M | varies | Maybe | |
| D3 | Colorwheel (Create / Flywheel instanced rendering) | M | — | Maybe | Only if you play with Create. |
| D4 | Modded ores / lights / blocks via `block.properties` sections; `dimension.properties` for modded dimensions | S | — | Yes | |
| D5 | Photonics (alpha mod: voxel ray-traced blocklight shadows + GI; not in Complementary, but the Euphoria Patches add-on supports it) | L | High | Later | |

### + Ideas beyond Complementary

| ID | Feature | Effort | Cost | Rec | Notes |
|---|---|---|---|---|---|
| +1 | Reduced-resolution volumetrics with temporal reprojection (clouds, VL, light fog, Nether storm) | L | saves | Core | The heart of the performance plan. |
| +2 | Auto-exposure (eye adaptation, histogram in compute) | S | Low | Maybe | Changes the Unbound look; would be an option. |
| +3 | Contact-hardening soft shadows (PCSS: sharp near the caster, soft far away) | M | Med | Maybe | |
| +4 | Screen-space contact shadows (small details the shadow map misses) | M | Low–Med | Maybe | |
| +5 | Wet surfaces in rain (darker, glossier) + rain ripples in puddles | M | Low | Yes | |
| +6 | Lightning flashes that light up clouds and terrain | S | Free | Maybe | |
| +7 | Shooting stars, moon detail | S | Free | Maybe | |
| +8 | Heat haze in the Nether / above lava | S | Low | Maybe | |
| +9 | Temporal upscaling (render expensive passes at lower internal res, FSR-style) | XL | saves | Later | Big 4K win. Hard in Iris because geometry can't easily be rendered at lower res. |
| +10 | Aperture / Vulkan port | XL | — | Later | When Aperture is public and stable. |
| +11 | Built-in debug views (show G-buffer, AO, shadow map, etc.) | S | Free | Yes | Speeds up our tuning. |

---

## 6. Architecture

- **Target:** Iris (current versions for MC 1.21.11 and 26.x), OpenGL. GLSL with compute shaders (OpenGL 4.3+) for the advanced features. Effects degrade gracefully when compute isn't available; macOS gets a compute-free path.
- **Code layout:**
  - `lib/` holds pure functions (atmosphere, lighting, materials, noise, utils).
  - `program/` files are thin pass wrappers.
  - One `settings.glsl` holds every option `#define`.
  - A thin **platform layer** wraps all Iris-specific uniforms, samplers and buffer names. This is what makes a future Aperture/Slang port practical.
- **Proposed pass layout:**
  - `shadow`: shadow map + coloured shadows (+ light voxelization when A1 is on)
  - `shadowcomp`: amortized floodfill
  - `gbuffers` opaque: compact G-buffer
  - `deferred`: half-res AO → full lighting → sky + reduced-res clouds, reprojected and upsampled
  - `gbuffers_water`: forward-lit translucents
  - `composite`: reflections + refraction + fog + half-res VL
  - `composite`: volumetric upsample / temporal accumulation
  - compute bloom
  - `composite`: TAA + sharpening
  - `final`: tonemap, grading, vignette, chromatic aberration (+ FXAA option)
- **Tooling:**
  - a compile-check script (glslangValidator + Iris stub header) that I run before every hand-off
  - a fixed in-game test-scene checklist for screenshots
  - the benchmark method from section 4

---

## 7. Phased implementation

Each milestone ends with a playable pack you test.

| Milestone | Contents | Result |
|---|---|---|
| **M0 Skeleton** | Pack loads, all programs pass through, settings menu, block IDs, compile-check script | Vanilla-looking but ours |
| **M1 Core lighting** | G-buffer, deferred lighting, shadows (L1–L4), sky ambient, blocklight, AO, tonemap (B1–B6, B8–B10) | A solid basic shader |
| **M2 Sky and atmosphere** | Unbound sky, sun/moon, stars, fog (F1–F4), Nether / End basics | Day/night cycle feels right |
| **M3 Water** | Unbound water normals, SSR, refraction, water fog, caustics, foam (W1–W11) | |
| **M4 Temporal base** | TAA + jitter, reduced-res + reprojection infrastructure (T1, +1) | Needed for M5 |
| **M5 Clouds and light shafts** | Unbound volumetric clouds + shadows, VL (C1–C7, F5, F8) | **"Looks like Unbound" checkpoint, first benchmark against Complementary** |
| **M6 Coloured lighting** | Voxel floodfill coloured blocklight with amortized updates and compact storage (section 4), coloured light saturation, fire warmth, candle colours (A1–A3, A5); light fog (A4) optional | Moved up from v2 at the user's request |
| **M7 Materials** | Built-in material library pass 1, glowing ores, generated normals, coated textures, foliage SSS, glass (M1–M7, M10, M11, L19, X1–X4) | |
| **M8 Post** | Bloom, colour balance / grading, sharpening, FXAA, etc. (K1, K3–K5, K8, K9, T2, H1–H3) | |
| **M9 Night and weather extras** | Aurora, nebulae, rainbows, puddles, weather styles, End beams, waving (S6–S9, R1–R5, E1–E3, V1–V7, +5) | Feature-complete v1 |
| **M10 Tuning** | Profiles, performance pass, utilities (U1, U4, U5, U7), docs | **v1 release** |
| v2 | ACT extras (A6–A8), Nether storm, lens flare, DOF / motion blur, outlines, DH / Voxy, labPBR, POM, … | |
| Later | WSR, temporal upscaling, Photonics, Aperture port | |

**My suggested v1 scope** (everything marked Core/Yes outside v2/Later):

- B1–B10
- G2–G4, G6
- L1–L14, L17–L19
- S1–S9
- C1–C7
- F1–F5, F8
- R1–R5
- N2, N3
- E1–E3
- W1–W11
- X1–X4
- M1–M7, M10, M11
- P1, P3
- V1–V7
- K1, K3–K5, K8, K9
- T1, T2
- H1–H3
- U1, U4, U5, U7
- D4
- +1, +5, +11

**Reasoning:** this delivers the Unbound look without the systems that make Complementary's top tiers heavy. Coloured lighting (A1) is held to v2 because it's the most complex system and the biggest VRAM user. It's worth doing well, but not first.

---

## 8. Main challenges and risks

1. **Platform shelf life.** Vulkan becomes the default in 26.4, and Iris packs need the OpenGL setting. If Mojang eventually removes OpenGL, Iris packs stop working and Aperture becomes the only route. *Mitigation:* the platform layer (section 6); revisit once Aperture is public.
2. **I can't see the game.** All visual tuning goes through your screenshots and feedback, so expect many short iterations. *Mitigation:* debug views (+11), a fixed scene list, and describing changes precisely so you know what to look at.
3. **Matching "the look" without their constants.** Expect "clearly Unbound-style", not pixel-identical. The licence means it shouldn't be identical anyway.
4. **Temporal artifacts.** Reduced-res effects with reprojection can cause ghosting and smearing on fast camera turns and disocclusions. *Mitigation:* depth/velocity-aware rejection, and per-effect fallback to higher resolution in the menu.
5. **Deferred-vs-forward trade-off.** Must be validated early (end of M1) with a quick A/B in a dense forest.
6. **Translucency.** Water behind glass, particles in water, rain behind glass: the classic layering bugs.
7. **Shadow artifacts.** Acne, peter-panning, and light leaking into caves.
8. **Driver differences.** NVIDIA, AMD, Intel and Mesa GLSL strictness differs. macOS lacks compute. The compile-check script helps with the first, not the second.
9. **VRAM budgets** for voxel volumes on 4–6 GB GPUs.
10. **Mod content.** Modded blocks have no IDs by default, so they get generic materials.
11. **Scope.** The full feature list is years of work for Complementary's author. Phasing keeps it shippable.

---

## 9. Questions for you

1. **Your hardware:** GPU, CPU, OS, monitor resolution? This sets the performance target, and macOS changes the design.
2. **Minecraft version and loader** (Fabric or NeoForge)? Do you use **Distant Horizons**, **Voxy** or **Create**?
3. **Personal use or public release** (Modrinth / CurseForge)? This affects polish, compatibility work and licence choice.
4. **Name** for the pack?
5. **Iris-only, no OptiFine**: OK?
6. **Repository:** this cloud workspace is temporary. To keep the code across sessions, it should live in a GitHub repo. Want me to set one up when we start?
7. **Features:** reply with IDs to include, change or drop, or accept the suggested v1 scope.

---

## Sources

- Complementary source r5.9.2: [github.com/ComplementaryDevelopment/ComplementaryReimagined](https://github.com/ComplementaryDevelopment/ComplementaryReimagined) (`shaders.properties`, `lang/en_US.lang`, `lib/`, `License.txt`)
- Iris documentation (source of shaders.properties): [github.com/IrisShaders/docs](https://github.com/IrisShaders/docs): programs, custom images, SSBOs, feature flags, `voxelDistance`, rendering directives, DH, macOS limits
- Aperture: [Aperture example pack](https://github.com/IrisShaders/Aperture-Example-Pack) (pack.ts + Slang, Jan 2026); [migration guide](https://shaders.properties/aperture/migration/); Iris announcements on X ([Feb 2026](https://x.com/IrisShaders/status/2024298162564059576), [May 2026](https://x.com/IrisShaders/status/2054389223231500347)); [Sportskeeda report](https://www.sportskeeda.com/minecraft/news-iris-shaders-successor-announced-ahead-minecraft-java-transition-opengl-vulkan)
- Vulkan in Java Edition: [26.2 Snapshot 1](https://feedback.minecraft.net/hc/en-us/articles/44898619266317-Minecraft-Java-Edition-26-2-Snapshot-1), [26.2 Snapshot 8](https://www.minecraft.net/en-us/article/minecraft-26-2-snapshot-8), [26.4 Snapshot 1](https://www.minecraft.net/article/minecraft-26-4-snapshot-1), [Vulkan Optimization modpack note on Iris](https://modrinth.com/modpack/vulkan-optimization/version/26.2-4.1)
- OptiFine shader docs: [optifine.readthedocs.io/shaders_dev.html](https://optifine.readthedocs.io/shaders_dev.html)
- Performance signals (weak evidence): [vortexgaming.io comparison](https://vortexgaming.io/en/postdetail/1295859), [BCU shades](https://www.curseforge.com/minecraft/shaders/bcu-shades)
- Euphoria Patches (add-on feature ideas): [Modrinth](https://modrinth.com/mod/euphoria-patches); Photonics: [Modrinth](https://modrinth.com/mod/photonics)
