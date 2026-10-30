# The rendering pipeline, pass by pass

Everything the pack does in one frame, in the order Iris runs it, with how much work each
pass does. Numbers use the defaults at 4K (3840 x 2160):
- **full size** = 8.3 M pixels;
- **half size** = 2.1 M pixels;
- shadow map 4096², shadow distance 160 blocks;
- light volume 256 x 128 x 256 (Colored Light Range 2);
- cloud quality 2, cloud resolution 1/2, light-shaft quality 2;
- SSAO 1, 12 shadow samples, TAA on, bloom on.

How to read the cost columns:
- "reads" means texture or image reads per pixel, or per thread for compute passes. A
  hardware-filtered read (bilinear, shadow compare) counts as one.
- "x" inside a loop means per step.
- Passes marked *compute* are not drawn over the screen: they run a fixed grid of threads.

```
 begin ─ begin_a ─ shadow ─ shadowcomp ─ shadowcomp1 ─ shadowcomp2
   │                  (sun's view)     (light volume, ripples)
   ▼
 gbuffers (opaque) ─ deferred ─ deferred1 ─ deferred2 ─ [deferred3/4]
   (fill G-buffer)    (clouds)    (AO+sun)   (lighting)   (block refl.)
   ▼
 gbuffers (translucent: water, glass, particles, weather)
   ▼
 composite ─ composite1 ─ composite2 ─ composite3 ─ composite4 ─ final
 (air march)  (tints, air)  (TAA)       (bloom)      (post)       (dither)
```

---

## 1. Start of frame

| Pass | Size | Work | Skipped when |
|---|---|---|---|
| **begin** *compute* (worldState) | 1 thread | Weather, wind, mist, wave clock, water look of the camera's biome, auto-exposure smoothing: once, written to a small buffer every other pass reads | never (it is tiny) |
| **begin_a** *compute* (cloudShadowMap, A1) | 512 x 512 = 262 k threads | Cloud shadow straight down the sun's path for a 1024 x 1024-block area. Per thread: 2 layers x (1 coverage + 2 density) noise evaluations | Nether, End; Cloud Shadows 0; A1 off |

## 2. Shadow pass (the world from the sun)

**shadow** draws every block, mob and the player within 160 blocks into a 4096² depth map,
whether or not it is on screen. It is the costliest pass in geometry (all chunks around
you, from a second viewpoint), but its pixel work is light.

The vertex shader does far more than the shadow map. It is the pack's only look at the
whole world around you. Once per block face (one vertex in four):
- **Voxel volume** (for coloured light): 1 atomic write.
- **Block colour** (for sun bounce, Overworld only): 1 mip-4 texture read + 1 atomic write.
- **Column maps:** water cells, water surfaces, glass, block undersides. 1–2 atomic writes,
  only for water, glass and undersides.
- **Ripple sources:** 2 atomic writes per mob or player vertex within 31 blocks.
- **Culling:**
  - Leaves without sky light are dropped (Leaf Shadow Optimization).
  - Blocks whose shadow can't reach the screen are dropped (A5): 5 plane tests.
- **Waving plants** are moved, so their shadows move with them.

Pixel work:
- **Blocks:** 1 texture read.
- **Glass:** 1 mip read.
- **Water:** no texture work.
- **Nether:** the shadow map is discarded outright, so the pass only fills the voxel volume.

## 3. World simulation (compute, after the shadow pass)

| Pass | Size | Per thread | Skipped when |
|---|---|---|---|
| **shadowcomp** (floodfill) | 256 x 128 x 256 = 8.4 M threads, as 16 k groups of 8³ ("bricks") | **Idle brick** (no blocks, nothing lit nearby): only stores two zero values per cell. **Active brick, half the cells per frame** (checkerboard): 1 voxel read + 6 block-light reads; in the Overworld also 6 sky reads, 6 bounce reads, the 6 neighbours' voxel and colour reads where sky reaches, 4 shadow-map taps (sunlit spots only), 1 history read. **Other half:** 2 reads (carried over) | Coloured Lighting off |
| **shadowcomp1** (rippleSources) | 512² = 262 k | Compares the ripple-source heights with the water: 2 reads + column lookups; raises the "something touched water" flag (A3) | Ripples off; Nether, End |
| **shadowcomp2** (ripples) | 1024² = 1 M | Wave equation step: 4x4 neighbourhood = 16 reads, plus source reads. **Returns at once when the water has been flat for 4 frames (A3)** | Ripples off; Nether, End |

## 4. Opaque geometry (G-buffer)

**gbuffers_terrain / entities / block / hand** draw what you see. They write three
buffers:
- colour + vanilla AO;
- normal + light levels;
- material (shading model, emission, smoothness, metalness).

No lighting happens here.

Per pixel:
- 1 texture read.
- Material from the block ID: a few branches, no reads.
- **Generated normals** (within 64 blocks): 3 more texture reads.
- **Coated textures:** a hash.

Solid terrain uses early depth testing, so pixels hidden behind others are never shaded.

## 5. Deferred passes (lighting the opaque scene)

| Pass | Size | Per pixel | Skipped when |
|---|---|---|---|
| **deferred** (clouds) | Half size, 2.1 M | **Hidden-sky check:** up to 4 depth reads; if terrain covers the patch, it stops there. **Otherwise the cloud march**, layers nearest first, for the 2 layers. Volumetric layer: up to 22 steps (empty sky at double steps), each with 1 coverage read and 1 density read (3D noise). Where cloud is found, 4 more density reads along the sun (2 for thin wisps). Sheet layer (cirrus): 1 sample. **Sky effects** (aurora 20 slices, nebulae, rainbow) if present; **history:** 4–5 reads | Not Overworld; Volumetric Clouds off; deep underground |
| **deferred** *compute* (skyView, the cloud panorama) | 512 x 128 = 65 k marches (a quarter of 1024 x 256 per frame) | A full cloud march in one direction, like above + 1 history read | Nothing on screen reflects clouds (A4); underground |
| **deferred1** (SSAO + half-size shadows) | Half size, 2.1 M | **AO:** 1 slice x 2 sides x 4 steps = 8 depth reads. **Sun shadow** (only where sky light > 0.05 and the surface faces the sun): 6-tap blocker search + 6 filter taps x 2 maps = 18 reads, + 2 for glass and water. **History:** 1 read | SSAO 0 and Half-Res Shadows off |
| **deferred2** (lighting, sky, puddles) | Full size, 8.3 M | See the breakdown below | never |
| **deferred2** *compute* (depthTiles) | One thread per 8x8 tile, 130 k | 64 depth reads: nearest depth per tile, which lets water SSR skip empty space | no reflection traces anything |
| **deferred3/4** (block reflections) | Half or full size | Trace + apply | off unless Block Reflections = 2 |

### deferred2 per pixel, the busiest pass

**Sky pixels:**
- the sky model + 1 cloud read + fog.
- Under water: the underwater sky.

**Terrain pixels:**
1. **G-buffer:** 4 reads (colour, normal, material, depth).
2. **Half-size upsample** (AO and sun shadow), 36 reads:
   - 16 AO-buffer reads;
   - **16 depth reads, each turned back into a distance;**
   - 4 normal reads.
3. **Sun shadow:**
   - If the half-size result is usable: 2 reads (a check for glass or water above).
   - Otherwise the full filter: 18–30 reads.
4. **Cloud shadow:** 4 reads from the map (A1), or about 6 noise evaluations without it.
5. **Block light:**
   - With A2: 8 light-volume reads (colour and direction together).
   - Without A2: about 40.
6. **Sun bounce + sky occlusion:** 8 light-volume reads, only where sky light > 0.02.
7. **Wet and puddle surfaces** (rain, Overworld):
   - puddle noise;
   - rain ripples (procedural);
   - sky reflection + 1 panorama read;
   - block-light glint: 8 reads.
8. **Specular highlight:** 2 normal reads (Block Reflections ≥ 1, smooth surfaces only).
9. **Fog:** analytic, no reads.
10. **Overlay** (particles drawn earlier): 1 read.

## 6. Translucent geometry (forward shading: water, glass, particles, rain)

Translucents are lit as they are drawn: everything is worked out per pixel of each
surface, and surfaces that overlap (glass in front of water) pay for each layer.

### Water, per pixel

- **Waves:** 2 swell waves + up to 24 wind-sea waves (12 headings x 2; those across the wind
  are skipped, typically 8–12 left) + 6 ripples + chop.
  - Each wave is a sin/cos plus its curvature.
  - **Each wave also recomputes its random direction and length (hash + pow) every time,
    although they are the same for every pixel.**
- **Rain rings:** procedural. **Ripples:** 16 reads, or 0 when idle (A3).
- **Lighting:** the full `GetLighting`, same as terrain but with the cheap shadow filter
  (4 taps x 2 maps). Glass/water-above check: 4 reads. Cloud shadow: 4 reads. Light
  volume: 16 reads.
- **Translucent cover above:** 3 shadow-map reads.
- **Refraction:**
  - 3 depth reads + 1 scene read;
  - where the bed is shallow, a foam pattern of 2 noise evaluations.
- **Sky reflection:**
  - Sky model + stars + 1 panorama read.
  - Water within 32 blocks uses a 4-read smoothed panorama lookup.
- **Screen-space reflection** (Water Reflections 1, top faces only):
  - Up to 24 steps (fewer far away), each 1 depth read, jumping over empty tiles.
  - On a hit, 5 refine steps + 1 scene read.
- **Block-light glint:** 8 reads.

Seen **from under water**, the surface instead does: column-map checks, SSR, refraction
with 2 reads, and the sky through the surface + 1 panorama read.

The water's vertex shader also does work:
- **Wave height:** the full wave sum again.
- **Openness ("fetch"):** 16 column-map lookups per vertex.

### Glass, ice, translucent mobs
- **Lighting:** `GetLighting` (cheap shadow filter).
- **Water check:** a column-map lookup, for glass seen through water.

### Particles and rain
Lighting from the light levels plus a 4-tap shadow, in the order-safe layer.

## 7. Composite passes (after everything is drawn)

| Pass | Size | Per pixel | Skipped when |
|---|---|---|---|
| **composite** (air march: light shafts, mist, light fog, water shafts) | Half size, 2.1 M | **Setup:** 4 depth reads (+4 for the water surface, looking in from above). **In air:** 12 steps, each with a haze/mist function, 1–3 shadow-map reads (3 under glass), 4 cloud-shadow reads (A1), 1 light-volume read (light fog, within 48 blocks; 8 more near lights). **Into water:** 6 steps; **under water:** 12 steps. Each underwater step: 2 shadow reads + **the full wave sum for the caustics**. **History:** 4 reads | Light-shaft quality 0 |
| **composite1** (tints, clouds in front, air light) | Full size, 8.3 M | Tint: 2 reads; clouds in front: 1 depth + 2 cloud reads; **air light upsample: 16 reads** (+1 depth) | never |
| **composite2** (TAA) | Full size | 3x3 neighbourhood: 9 reads; history: 5 bilinear reads (5 more behind glass and water); 2 depth reads | TAA off |
| **composite3** (bloom tiles) | Half size, only the 6 tiles' area (about a third of it) | **7x7 = 49 mipmap reads** per tile pixel | Bloom off |
| **composite4** (post) | Full size | 1 scene read + sharpening 4 (A6) + **bloom: 6 tiles x 4 = 24 reads** + 1 depth read + tonemap and grading | never |
| **composite4** *compute* (exposure) | 256 threads | 9 reads each, then a reduction | Auto Exposure off |
| **final** | Full size | 1 read + dither (FXAA: 9 + edge walk up to 20) | never |

---

## Where the frame goes (estimate, daytime by water)

The biggest consumers, in order:
1. **Shadow pass geometry:** every chunk within 160 blocks drawn a second time.
2. **deferred2 lighting:** 8.3 M pixels x ~70–100 reads.
3. **Water forward shading:** per water pixel, ~40 waves + ~60 reads + SSR (up to 30 depth
   reads).
4. **Air march:** 2.1 M pixels x 12 steps. Under water or looking into it, each step
   evaluates the waves.
5. **Clouds:** 2.1 M pixels x up to 22 steps x 2 layers, only where sky shows, and the
   panorama (65 k marches).
6. **Floodfill:** 8.4 M cells, half of them updated in active bricks, the rest zeroed.

Smaller:
- composite1: 21 reads per 4K pixel.
- TAA: about 16 reads.
- post: about 30 reads.
- bloom tiles: 49 reads, over a sixth of the screen.
- Everything else: under 0.2 ms each.

## Candidates spotted while writing this up (not done yet)

| # | Where | What | Expected gain |
|---|---|---|---|
| B1 | deferred2, half-size upsample | Its 16 depth reads (and conversions back to distance) are not needed: the half-size buffer already stores each texel's depth (its alpha). | Medium: 16 reads + 16 matrix ops x 8.3 M pixels |
| B2 | Waves (water pixels, vertices, caustics in every shadow under water, every underwater air-march step) | The 26–32 wave directions and lengths are worked out from hashes per pixel, although they change only once a day (swell) or with the wind. Work them out once a frame into the world-state buffer. | Medium to large where water is on screen ("FPS bad with water") |
| B3 | Caustics in the air march | Each underwater step sums every wave again. A small caustics texture made once per frame (around the camera) would replace it with 1 read. | Large under water and looking into water |
| B4 | Floodfill, idle bricks | Idle bricks still write zeros to both volumes every frame: about 100 MB of writes per frame when most of the volume is empty air. They could skip the write when they were also idle the last time that volume was written. | Medium (memory bandwidth) |
| B5 | Floodfill, sky/bounce | The 6 neighbours' bounce values are read twice (once for the sky, once for the bounce colour): 6 reads could go. | Small–medium |
| B6 | Bloom tiles | 49 reads per pixel: the same blur from 16 bilinear reads (linear-sampling trick). | Small |
| B7 | Water vertex shader | "Fetch" (16 lookups) per vertex, every frame, though it only changes when blocks change. | Small |
| B8 | composite1 air-light upsample | 16 reads at 4K: a 3x3 or 2x2 depth-aware upsample may do. | Small–medium (risk: shafts less smooth) |
