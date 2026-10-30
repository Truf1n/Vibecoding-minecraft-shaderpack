# Code and rendering audit (after Perf2)

A pass over the whole pack: unused code, work that runs without being used, passes that could
merge, and what is rendered that is not on screen.

## 1. Fixed in this pass (safe, no visual change)

| What | Waste | Fix |
|---|---|---|
| Vanilla sky dome (`gbuffers_skybasic`), End sky and sun/moon textures | Discarded per fragment: a full screen of fragments every frame (≈8 M at 4K) | Dropped in the vertex shader, never rasterised |
| Light volume in the Nether and End | The floodfill worked out sun bounce and sky visibility, which only Overworld lighting reads | Only in the Overworld, and only with Sun Bounce or Sky Occlusion above 0 |
| Block colours (`albedoImg`) in the Nether and End | Written by the shadow pass for every block face, read by nothing | Overworld only |
| Half-size sun shadows in caves | Worked out where no sky light reaches, though the lighting never asks there | Skipped where sky light is under 0.05 |
| Light-volume reads in caves | 8 reads of bounce and sky per pixel where they cannot matter | Skipped where sky light is 0 |
| Depth tiles (P18) | Built every frame even with all reflections off | Skipped when nothing traces reflections |
| Cloud panorama image | 2 MB allocated with volumetric clouds off | Only with volumetric clouds |
| World state: jet-stream drift, swell direction | Integrated every frame, read by nothing | Removed (single thread: no measurable gain, just tidiness) |
| Dead code | `IsPane`, `ViewToScreenAO`; uniforms `cameraPositionFract`, `skyColor`, `sunAngle` declared, never read | Removed |

Checked and clean:
- every function is called;
- every option is read;
- every custom uniform is used;
- passes that options switch off are disabled in `shaders.properties`: TAA, bloom, the air
  march, block reflections, AO with half-size shadows, ripples, coloured lighting.

Kept on purpose:
- `wsSurface.y` (snow depth, for W6);
- `wsExposure.z` (average scene luminance, for debugging).

## 2. Larger savings: implemented (Opt1), each switchable on the Debug screen

All six are on by default; each `OPT_*` option turns one off for comparison. Notes from
implementing them:
- **A1:** the map is made in `begin_a.csh` and stamped with the frame number. Readers fall back
  to the direct evaluation for a stale map, for points above the lowest cloud base, or outside
  the ±512-block grid.
- **A2:** the direction comes from the exact slope of the trilinear blend. It changes slope at
  block boundaries, which may show as faint per-block steps on walls lit from the side.
- **A3:** a 4-frame ring of flags; both halves of the ping-pong must be flat before it idles.
- **A4:** an 8-frame ring of "used" flags. One pixel in 256 marks use, and a direction's history
  is replaced instead of blended when it was not refreshed 4 frames earlier.
- **A5:** decided per block (all faces of a block agree), after every image write in the shadow
  pass.
- **A6:** `final` cannot be removed altogether: Iris only shows colortex0, which is
  R11G11B10F, and a finished image stored there would band. So `final` stays as dither (and
  FXAA, debug views), and the gain is the sharpening's neighbourhood reads moving to post.

Original proposals:

| # | Proposal | Expected gain | Risk |
|---|---|---|---|
| A1 | **Cloud-shadow map.** Cloud shadows are evaluated per pixel at full 4K in the lighting pass (≈20–25 cloud-noise reads each) and at every step of the light-shaft march (12 steps × the same, per half-size pixel). Instead, one small compute pass would write a cloud-shadow map once per frame: 512×512 in a storage buffer, projected along the sun onto the cloud base. Lighting, shafts, half-size shadows, the water and the light volume would then read it with 4 loads. | Large: likely the biggest single item left (in daylight with clouds) | Low. Higher cloud layers get a small parallax error in their (faint) shadows |
| A2 | **Light-volume reads.** Directional block light and the block-light colour read the volume 5 times (40 texels per lit pixel). Value and direction can both come from the same 8 texels (the slope of the trilinear blend). | Medium where block light is in view (caves, villages at night) | Low. The direction is taken over one block instead of half a block |
| A3 | **Ripple simulation idle.** The 1024×1024 ripple grid steps every frame, and every water pixel reads 16 ripple texels, even when nothing has touched water for a while. An "any ripples left" flag would skip both. | Small–medium (water on screen) | None |
| A4 | **Cloud panorama only when needed.** A quarter of it (65 k cloud marches) is re-marched every frame even with no water, puddle or ice on screen. A flag set by those surfaces would pause it, refreshing it once they appear. | Medium on land, none on water | A frame or two of stale clouds in reflections when water first comes into view |
| A5 | **View-based shadow caster culling.** The shadow pass rasterises every caster around you, including those behind you whose shadows cannot fall anywhere you can see. Their blocks still have to go through the shadow pass (coloured light, column maps), but their triangles could skip rasterisation. | Medium in dense forests (leaf shadows are the costly part) | Sun bounce behind you would treat those blocks as unshadowed; when you turn, it settles over ~0.2 s |
| A6 | **Merge sharpening into post.** `final` exists only for FXAA, sharpening and dithering. Sharpening could run in the post pass on the HDR image (5 extra reads), and `final` would only dither. | One 4K pass (≈0.2 ms) | Sharpening in HDR before tonemapping looks a little different (stronger on highlights) |

## 3. Passes and why the rest cannot merge

| Pass | Job | Merge? |
|---|---|---|
| begin (compute) | world state | Already the smallest possible (one thread) |
| shadow | shadow map, voxels, column maps, block colours, ripple sources, far heights | Must see everything around the player (see section 4) |
| shadowcomp / 1 / 2 (compute) | light volume; ripple sources; ripple step | 1 and 2 cannot merge: each ripple cell would repeat 16 water-surface lookups |
| deferred (+ compute) | clouds (reduced size) + cloud panorama | Already together |
| deferred1 | AO + half-size shadows (half size) | Already merged (P19) |
| deferred2 (+ compute) | lighting, sky, puddles; depth tiles | — |
| deferred3/4 | block reflections (off by default) | The apply needs the trace's neighbours |
| composite | air march (half size) | — |
| composite1 | tints, clouds in front, air light | Already merged (P10) |
| composite2 | TAA | Needs a 3×3 neighbourhood of the finished tint pass |
| composite3 | bloom tiles (half size) | Needs the mip chain |
| composite4 (+ compute) | post; exposure | Exposure could move into begin (reads last frame's image), saving only a dispatch |
| final | FXAA, sharpening, dither | See A6 |

## 4. Off-screen rendering

- **The world itself:** Sodium culls chunks outside the view (and hidden behind others). Nothing
  off screen is drawn into the image.
- **The shadow pass draws everything around you on purpose:**
  - trees behind you cast shadows in front of you;
  - the shadow pass is also how the pack sees the world for coloured light, sky occlusion and
    sun bounce (the voxel volume), for water caustics, rain behind glass and ripples (the column
    maps), and for where mobs touch water;
  - culling it to the view would make torchlight, cave darkness and ripples pop when you turn.
  - What can still be saved is rasterising casters whose shadows can't reach the view (A5).
  - Entity shadows are already limited to a quarter of the shadow distance; block entities
    cast none.
- **Volumes that cover the area around you, not the screen:**
  - the light volume (sparse since P17, half per frame since P9);
  - the ripple grid (A3);
  - the cloud panorama (A4).

  They must exist off screen to be correct the moment you turn.
- **Far shadows** (now off by default) were the one feature that drew extra off-screen terrain;
  their remaining cost is Iris sending that terrain through the shadow pass.
