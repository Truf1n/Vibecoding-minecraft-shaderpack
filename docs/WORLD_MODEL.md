# World model: one cause-and-effect system for light, air, water and weather

Plan for the quality items Q1–Q4, Q6–Q31 (Q5 prepared for), rebuilt around a single physical
model instead of separate effects that each invent their own timing and colours. Written after
M9.5; replaces/absorbs parts of M2 (sky/fog), M3 (water), M5 (clouds/shafts), M6 (coloured
light), M9 (weather).

Status: **W1 implemented (M10-W1):**
- the world state buffer: begin pass, weather smoothing, integrated wind with gusts, air,
  wetness, snow depth, swell, sun and sky light once per frame;
- clouds, plants, rain slant, water waves, caustics and storm fog driven by it;
- auto exposure.

**W2 implemented (M10-W2):**
- the analytic wave field: wind sea on fixed headings, ripples from gusts, swell; fetch and
  shelter;
- rain rings added onto the waves;
- Jacobian caustics with dispersion;
- roughness from the unresolved waves;
- interactive ripples.

Still to do from W2: shorelines (Q16). Underwater light shafts stay along the unrefracted
sun direction: the shadow map can only be looked up along it.

W3 onwards: design only.

---

## 1. Principles

1. **One source of truth per physical quantity.** Wind, cloud cover, humidity, temperature,
   wetness, snow depth, sun and sky light, exposure: each is computed **once per frame** in a
   small state block and read by every effect. Nothing re-derives "how rainy is it" on its own.
2. **Causes flow one way.** Sun + season of the day + biome + vanilla weather → air state →
   clouds, wind, precipitation → water, plants, surfaces → light transport → camera. Effects never
   feed back into causes within a frame (except slow, integrated state like wetness and snow,
   which is updated once per frame from the previous frame's values).
3. **Integrate, don't evaluate.** Anything that moves with a speed that can change (wind drift,
   wave phases, cloud advection, gust fields) is stored as an *accumulated offset* that grows by
   `speed × frameTime` each frame. Today, `time × speed` jumps when the speed changes; integrated
   offsets never jump, so the wind can freely strengthen and veer.
4. **Deterministic from world time.** All random choices (wind direction of the day, cloud
   formation, swell direction) are seeded by the world day, so everyone on a server sees the
   same sky (the existing "synced to world time" idea, applied to everything).
5. **Three wavelengths are physics, not a tint.** Light is carried as R/G/B at about 650 / 550 /
   450 nm. Water refraction (n = 1.331 / 1.333 / 1.338), water absorption (red first), air
   scattering (blue first) and caustic dispersion all use per-channel constants, so colour
   shifts come out of the model instead of being painted on.
6. **Near / mid / far split for every kind of occlusion.** Small things are resolved in screen
   space, block-scale things in the voxel volume, big things in maps (shadow map, heightmap,
   vanilla light levels). Each scale is handled by the cheapest tool that can resolve it, and
   they combine instead of overlapping.
7. **Slow things update slowly.** Sky visibility and sun bounce change over seconds, so they
   are updated over several frames (round-robin), not every frame.

---

## 2. The chain at a glance

```
INPUTS (per frame)          sun/moon direction, world time & day, vanilla rain/thunder,
                            biome temperature & rainfall, camera altitude, frame time
   │
   ▼
[A] WORLD STATE  (begin pass, compute, ~0 ms)  ──────────────────────────────────────────┐
    wind (dir, speed, gust strength, integrated offsets: surface / aloft / jet)          │
    air: temperature, humidity, cloud cover & type, precipitation, storm, visibility       │
    integrated: wetness, snow depth, swell direction, exposure                              │
    light: sun & moon irradiance at ground, sky irradiance (up / horizon), sun disc size    │
   │                                                                                       │
   ├──▶ [B] CLOUDS: cover & type from air state, advected by wind aloft (veered), grow and
   │        decay with time of day (convection), dense cores mark rain shafts
   │            │ cloud density along the sun ray ──▶ sun light at ground (shadows, softness)
   │            │ cloud density above ──▶ rain curtains, storm darkness
   │
   ├──▶ [C] WIND FIELD (any point): mean wind + travelling gusts, slowed by shelter
   │        ├─▶ plants (stiffness per type, rain weighs them down)
   │        ├─▶ water waves (wind sea + "cat's paws" where gusts pass)
   │        ├─▶ rain & snow slant (wind / fall speed), windward walls get wet, snow drifts leeward
   │        ├─▶ mist and storm dust drift
   │        └─▶ star twinkle (turbulence)
   │
   ├──▶ [D] WATER: one analytic wave field (swell + wind sea + ripples + rain + interactions)
   │        ├─▶ surface normals, vertex motion, reflection roughness (from the unresolved part)
   │        └─▶ caustics from the wave curvature, per wavelength, depth-dependent; absorbed with depth
   │
   ├──▶ [E] SURFACES: wetness (rain × exposure × wind), puddles (concavity), splashes, snow cover
   │
   ▼
[F] LIGHT TRANSPORT
    direct sun   = sun irradiance × cloud transmittance × shadow (PCSS + contact + far heightmap)
                   × water (absorption + caustics) × canopy
    sky light    = sky irradiance × sky visibility (vanilla light × voxel sky occlusion × GTAO,
                   along the bent normal)
    bounce       = sun bounce from the light volume (coloured by the blocks it bounced off)
    block light  = vanilla level × coloured hue from the light volume, directional
    transients   = lightning (voxel-traced shadows), End flashes
   │
   ▼
[G] AIR MEDIUM (one volumetric march): haze + mist + rain curtains + storm dust/snow,
    lit by sun (shafts), sky, block light (light fog), lightning
   │
   ▼
[H] CAMERA: auto exposure (eye adaptation), TAA (entity-aware), bloom, tonemap (AgX option),
    depth of field, motion blur, lens flare
```

---

## 3. The systems

### A. World state (new; Q22 and the foundation for everything)

A `begin.csh` compute pass (one thread, runs before the shadow pass each frame) updates a
small **shader storage buffer** (Iris `bufferObject`, about 256 bytes) that every program reads
as `readonly`. It keeps its values between frames, which allows integration.

| Quantity | How it is driven | Feeds |
|---|---|---|
| **Wind direction** | Prevailing direction of the day (seeded by world day), slowly veering ±40° over hours; storms swing it faster | Everything that moves |
| **Wind speed** (blocks/s) | Calm 1–3 by default; × biome (plains/ocean/peaks windier, jungle/forest calmer, caves 0); rises with rain (5–8) and thunder (10–16); altitude boost | Waves, plants, rain slant, cloud speed |
| **Gust strength** | Grows with speed and storms; low at dawn (stable air) | Gust field |
| **Integrated offsets** | `offset += wind × frameTime` for surface wind, wind aloft (×2.5, veered 25° clockwise: Ekman turning) and jet stream (×6) | Gust field, clouds, cirrus, mist, waves |
| **Temperature** | Biome temperature − altitude lapse (vanilla's own snow line) + day/night swing | Rain vs snow, mist, snow melt, aurora condition |
| **Humidity** | Biome rainfall + recent rain + water nearby; peaks at dawn | Haze, mist, puddle drying, star twinkle |
| **Cloud cover / type** | Base cover of the day (seeded, so days differ) + fair-weather convection peaking mid-afternoon over land + rain (→ stratus) + thunder (→ towering cumulonimbus) | Clouds, sun irradiance, shadow softness, rain curtains |
| **Precipitation** | Vanilla rain, but only as fast as the cover builds (what M9.1 does with `stormRain`) | Wetness, ripples, splashes, puddles, snow |
| **Wetness** (integrated) | `+ precipitation × rate`, `− evaporation(sun, wind, temperature, humidity)` | Wet surfaces, puddle level, rainbow chance |
| **Snow depth** (integrated) | `+ precipitation` when below freezing, melts above freezing (faster in sun and rain) | Snow cover on surfaces |
| **Swell direction** | Slowly follows the average wind of the past hours | Ocean swell |
| **Sun & sky light** | Sun/moon colour through the atmosphere (air mass at the sun's elevation, Rayleigh + Mie per channel) × cloud cover; sky irradiance up and at the horizon | All lighting: no per-pixel sky maths for ambient light |
| **Exposure** | From last frame's luminance histogram, adapting faster to bright than to dark | Camera |

Performance: removes the per-pixel recomputation of sky colours, water styles, storm values
and sun colour (P4), and the wind/wave functions become cheaper because their time-varying
parts are precomputed.

### B. Clouds (upgrade of C1–C7; Q26)

- **Driven, not hand-picked:** cover and type come from the world state. Fair days have
  cumulus that form over land through the morning, peak in the afternoon and thin out in the
  evening; rain turns them into stratus (as now, but driven); thunder grows cumulonimbus
  towers with dark bases. The existing presets become *climate* presets (how cloudy the
  world tends to be), not fixed looks.
- **Evolving, not just sliding:** the coverage noise has a time axis, so clouds grow and
  dissolve while drifting with the wind aloft; cirrus ride the jet stream.
- **Lighting (Q26):** multiple-scattering octaves (several weaker, wider phase lobes: bright
  silver edges, glowing interiors), powder term, ambient from the sky above and from the
  ground below (tinted by average terrain colour and snow cover).
- **Rain shafts:** dense cores are marked as rain sources; the air medium (G) draws rain
  curtains under them.
- **Optimisation (P1):** march only where a cloud can be seen (sky pixels, or terrain farther
  than the cloud layer), with adaptive steps (P13); the reduced-resolution buffer and
  history stay.

### C. Wind field (any point in the world)

`Wind(p) = mean wind × shelter(p) × (1 + gust(p))`

- **Gusts:** a 2D noise field advected by the integrated surface-wind offset and evolving
  slowly: a gust is a patch of stronger wind that travels across the land. One gust visibly
  sweeps over grass, darkens the water with ripples ("cat's paws") and tilts the rain, all at
  the same place and time.
- **Shelter:** wind slows where the voxel sky visibility (system F) is low and near the
  ground: plants in hollows, interiors and caves stay still for a physical reason, which
  replaces "No Waving Indoors".
- **Plants:** the sway is a damped spring driven by the local wind: stiffness and mass per
  type (grass flexible, crops medium, leaves small and fast, tall plants slow), rain
  weighing them down (more bend, slower response). The same function is used in the shadow
  pass.

### D. Water (rebuild of W1–W11; Q13–Q17)

**One analytic wave field** for heights, normals, curvature and vertex motion. It's a sum of
about 12 directional wave components with exact derivatives, so no finite differences: 3× fewer
evaluations than now.

| Layer | Wavelength | Direction | Amplitude driven by |
|---|---|---|---|
| Swell | 20–60 blocks | Swell direction (world state) | Water body size ("fetch") and storms; none in ponds |
| Wind sea | 2–10 blocks | Wind direction ± spread | Wind speed² (capped by fetch) |
| Ripples | 0.2–1 block | Around the wind | Local wind incl. gusts (cat's paws) |
| Rain | rings | — | Precipitation (existing rain ripples) |
| Interaction (Q15) | sim | — | Player, mobs, boats (below) |

- **Fetch:** how big the body of water is, estimated from the water-surface column map
  (count of water columns in a ring around the point) and the biome (ocean/river): ponds
  stay calm, oceans swell.
- **Normals and roughness (Q17):** the components smaller than a pixel aren't drawn as
  normals; their slope variance becomes the surface roughness. Distant and stormy water gets a
  wider sun glitter and blurrier reflections, and calm ponds stay mirror-like (reflection rays
  jittered by that roughness, with the history blend from the block-reflection fix).
- **Interactive ripples (Q15):** a 2D wave-equation simulation, about 128×128 cells at 0.5 block
  around the player (64 blocks), in a ping-pong image. Disturbances are written in the shadow pass
  (entity and player vertices at the water surface level, from the column map), then a compute
  step propagates and damps them. Swimming and boating leave wakes. Cost: about 0.1 ms.
- **Shorelines (Q16):** a distance-to-shore field over the column-map area (jump flooding,
  updated a few rows per frame). Waves run up the shore along its gradient, steepen as the
  water gets shallower, and break into foam.
- **Caustics (Q13, Q14), from the waves themselves:**
  - Light entering the surface bends towards the normal: a crest acts like a converging lens,
    a trough like a diverging one.
  - For a receiver at depth `d` (along the refracted sun ray), the light that reaches it entered
    at the surface point above it along that ray. There the wave field's curvature (Hessian
    `H`) gives the focusing: `I = 1 / |det(I + d·c·H)|`, with `c = 1 − 1/n`.
  - **Per channel:** `n` = 1.331 / 1.333 / 1.338 gives a slightly different focus per
    colour. Separation grows with depth: rainbow-fringed caustic lines in deep water,
    white ones in shallow water. A "Dispersion strength" option can exaggerate it.
  - **Sun disc blur:** the sun isn't a point (0.53°), so caustics soften with depth
    (`det` is blended with `d × sunAngle`). Past the focal depth they fade into even light.
  - **Absorption:** `exp(−σ·path)` per channel with the biome water's coefficients, so caustics
    dim with depth and turn blue-green as red goes first. Cloud cover reduces their contrast
    (diffuse light makes no caustics).
  - **Underwater light shafts** run along the refracted sun direction (steeper than the sun in
    air), carrying the same caustic field.
  - **Cost:** about 12 analytic Hessian evaluations per lookup. This replaces the two noise layers
    in caustics today, which roughly evens out.

### E. Surfaces (Q18, Q20, Q21; replaces the M9 puddles and wet surfaces)

- **Wetness per surface:** global wetness × rain exposure. Exposure covers sky visibility
  (open sky, not just the vanilla light level), the face pointing up, and **the face pointing
  into the wind**: with slanted rain, windward walls get wet and leeward walls stay dry.
  Drying is global (from the world state).
- **Puddles (Q21):** water collects where it would flow to.
  - Flat up-facing spots that are concave: from the GTAO occlusion and the voxel volume
    (cells with higher solid neighbours).
  - Spots on lower ground: from the column map, against the average height around.
  - They fill and dry with the global wetness: small puddles first, then they spread.
- **Splashes (Q18):** tiny short-lived impact rings and droplets on every wet up-facing
  surface, at a rate from precipitation. They use the same event hashing as the ripples, in
  world space, so there's no flicker.
- **Snow cover (Q20):** coverage = global snow depth vs a threshold per spot, shaped by:
  - sky exposure;
  - faces pointing up (and leaves, at reduced strength);
  - drifts: more on the leeward side of blocks, from the wind direction and the voxel volume;
  - noise.

  Snowy surfaces get snow albedo, roughness and light scattering. It melts in sunlight and rain.

### F. Light transport (Q1–Q4, Q6–Q12, Q23; Q5 prepared)

#### F1. The light volume (rebuild of the M6 floodfill: one compute pass, three quantities)

The voxel volume around the player is propagated **once** per update into:

| Channel | What | Update | Format |
|---|---|---|---|
| **Block light hue** | as today (M6 behaviour, stained glass colours it) | every frame | R11G11B10 × 2 (existing) |
| **Sun bounce** (Q2) | Sunlit block faces become light sources. Their colour is the face's average texture colour (written by the shadow pass), × N·L × sun visibility (one shadow-map lookup per face cell in the compute). It spreads into open space with a 1/distance-like falloff. | ¼ of the volume per frame | RGBA8 × 2 |
| **Sky visibility** (Q3) | Open-sky cells = 1, spreading down and sideways with direction-dependent loss: it falls freely downward, fades sideways and around corners. Caves, overhangs and dense forests darken correctly; vanilla's 15-step skylight is only used as a far fallback. | ¼ per frame | alpha of the bounce volume |

- **Directional sampling (Q4):** at a surface, sampling the volume's gradient gives the
  direction most light comes from, for block light, bounce and sky alike. Block light then gets
  N·L shading (faces turned from the torch are dimmer), and sky light uses that direction as its
  bent normal.
- **Block light glints (Q7):** the strongest block-light direction drives a GGX highlight on
  water, puddles and smooth blocks, in the light's colour.
- **Shared with other systems:** the same volume gives the air medium its light fog (Q6:
  block light inside the haze, see G) and gives lightning its shadows (below).
- **Future block-light shadows (Q5):** the M7.2 light-cluster lists slot back in as a fourth
  channel, with short voxel traces to the nearest lights. The design keeps a spare image slot
  and the cluster pass, so it can be added later.
- **Performance (P9, P17):**
  - One compute pass reads each voxel once for all three channels.
  - Bounce and sky visibility update round-robin (¼ per frame); they change slowly.
  - Bricks (8×8×8) with no light and no sky contact are skipped.
  - Net cost is expected to be about the same as today's floodfill alone.

#### F2. Occlusion at three scales (Q1, Q3)

| Scale | Tool | Gives |
|---|---|---|
| Near (≤ 1–2 blocks on screen) | **GTAO** (horizon-based), half res + temporal (replaces M9.5's SSAO) | Contact darkening + bent normal |
| Mid (2–16 blocks) | Light volume sky visibility | Caves, overhangs, under trees |
| Far | Vanilla sky light | Fallback outside the volume |

Combined multiplicatively along the bent normal, with **multi-bounce colour correction**
(Jimenez): occlusion on bright surfaces is lighter and keeps their colour. Applies to sky light,
bounce light and block light, never to direct sun (which has real shadows).

#### F3. Sun shadows (Q8–Q12, Q23)

- **Contact-hardening penumbra (Q8):**
  - Penumbra width = sun angular size × distance from blocker to receiver, found by a 4–6 tap
    blocker search and accounting for the distorted shadow map.
  - Cloud cover widens the effective sun: overcast skies give very soft shadows, and direct sun
    fades in favour of sky light (cause and effect: clouds → shadow softness).
- **Rotated blue-noise sampling + temporal smoothing (Q11, P3, P20):**
  - The filter samples rotate per pixel and per frame, and TAA blends them.
  - Fewer taps for the same smoothness; distant shadows drop to 4 taps.
- **Contact shadows (Q9, as you specified):**
  - A short screen-space trace toward the sun, only within ~24 blocks of the camera.
  - The trace length is about 2 shadow-map texels at that spot, so it only adds detail the
    shadow map can't resolve: small items, grass, entity contact, block-edge gaps.
- **Far shadows (Q10, Distant-Horizons style):**
  - A coarse 2.5D **heightmap**: the max height per 2×2 or 4×4 block cell, written in the
    shadow pass.
  - Beyond the shadow distance, a soft ray march over it toward the sun (wide blur, low
    resolution, no jaggies), so distant mountains shadow each other and valleys go into
    shade at sunset.
  - Range is limited by how far the shadow pass renders chunks. An option can extend the
    shadow chunk range (CPU cost) or keep it within the existing range.
- **Translucent entity shadows (Q12):** translucent mobs and particles write their tint to the
  shadow colour buffer like glass.
- **Lightning (Q23):**
  - During a flash, the bolt is a light source traced through the voxel volume: a short voxel
    trace from each lit pixel to the bolt, about 32 steps, only during the few flash frames.
  - Hills, trees and buildings throw hard, dramatic shadows for an instant. Combined with the
    whole-sky flash from M9, which is softer.

### G. Air medium (Q6, Q19, Q24, Q27; replaces separate light shafts, haze, storm fog)

**One** half-resolution ray march of the air from the camera to the scene (or to a far
distance for the sky), accumulated over frames like the clouds. Beyond the march range, the
same medium is integrated analytically (exponential height fog with the same parameters), so
far terrain blends seamlessly.

| Ingredient | Density from | Notes |
|---|---|---|
| Haze | Humidity, altitude (exponential), biome | Blue-scattering (Rayleigh) + white (Mie) per channel |
| Mist (Q24) | Humidity, temperature inversion (dawn, calm wind), low ground (valleys from the column map/heightmap), water nearby, swamps; drifts with the wind | Pools in valleys and over rivers at dawn; burns off with sun and wind |
| Rain curtains (Q19) | Precipitation × cloud density above (rain shafts under dense cores), wind-slanted | Grey moving sheets in the distance |
| Snow / sand storms | Precipitation × cold / dry × wind speed | Replaces the M9.2 storm fog, now with shape |
| Cave haze | Dark, humid air underground | Gives light fog something to show in |

Lit by:
- **sun:** shadow map + cloud shadows, giving the light shafts;
- **sky:** sky visibility from the light volume, so mist inside caves isn't sky-lit;
- **block light (Q6, light fog):** hue × magnitude from the light volume, giving glowing haze
  around lava, torches and portals;
- **lightning.**

Performance: merges the light-shaft march with the fog and storm evaluations; about 10 steps
with temporal accumulation instead of separate passes. Expected cost: about today's light
shafts.

**Sky (Q25, Q27):**
- **Physically based sky option:** transmittance and multiple-scattering lookup tables
  (Hillaire), built once (setup pass) and a small sky-view table per frame. Sun and sky light
  in the world state come from the **same** tables, so sunsets light the world in their
  colours automatically.
- **Unbound look kept:** the current artistic sky stays the default. The physical sky is an
  option, and the colour multipliers work on both.
- **Q27, as consequences:**
  - star twinkle strength from turbulence (wind, humidity, near the horizon);
  - a 22° moon halo when thin cirrus is present (ice crystals);
  - aurora reflected in water (already partly done).

### H. Camera (Q28–Q31)

- **Auto exposure (Q28):** a luminance histogram from the bloom mips (compute, about 0.05 ms) goes
  into the world state.
  - It adapts like an eye: quicker to bright than to dark.
  - It's limited by min/max exposure options.
  - Night stays readable through a night floor and the existing artistic scaling.
- **Mob motion for TAA (Q29):** *Iris 1.11.7 doesn't provide per-entity motion vectors* (no
  `at_velocity`; checked in the Iris source). Two parts:
  - **Now:** entity pixels are marked (G-buffer shading model and translucent-mob flag) and
    get tighter history clamping, less history weight and a neighbourhood motion estimate,
    which cuts most of the ghosting.
  - **Later:** if a future Iris adds `at_velocity`, it plugs straight into the reprojection.
- **AgX tonemap option (Q30).**
- **Depth of field, motion blur, lens flare (Q31):**
  - DOF uses autofocus on the centre depth, with a physical aperture/focal model.
  - Motion blur comes from the camera reprojection (plus the entity estimate).
  - Lens flare uses the sun's screen position with depth occlusion and ghosts from the bloom
    tiles.

---

## 4. How the pieces interact (examples of the chain)

| Cause | Effects |
|---|---|
| Thunderstorm builds | Cover → cumulonimbus with dark bases. Wind speed and gusts up → plants thrash, wind sea and cat's paws on water, rain slants → windward walls wet. Sun irradiance down + shadows soften to nothing. Rain curtains under the dark cores. Exposure rises (eye adapts). Lightning: voxel shadows + sky and cloud flash |
| Clear calm dawn after rain | High humidity + low wind + cold → mist pools in valleys and over the river, lit gold by low sun shafts. Wetness high → puddles reflect the sunrise; they dry as the sun climbs and wind picks up. The rainbow condition comes from wetness + low sun |
| Afternoon over plains | Convection → cumulus build up; their shadows drift with the wind aloft (veered from the surface wind the plants show) |
| Swimming in a warm ocean | Swell from the day's prevailing wind; caustics sharp in the shallows, colour-fringed and softer deeper, fading blue-green; your wake ripples; shafts along the refracted sun |
| Snowfall in the taiga | Below freezing → snow depth grows → tops and leeward sides whiten over minutes. Snowstorm air with shape. Wind-driven drifts. When it stops and the sun comes out, it melts slowly from sunlit faces |
| Walking into a cave | Sky visibility drops (voxel volume) → sky light fades smoothly, no hard vanilla steps. Sun bounce from the sunlit entrance lights the first blocks in the entrance's colour. Exposure adapts. Cave haze shows torch light fog. Wind falls still |

---

## 5. Implementation phases

Each phase ends with a playable pack, as before. Order is chosen so later phases build on the
data earlier ones provide.

| Phase | Contents | Replaces | Expected cost at 4K* |
|---|---|---|---|
| **W1 Foundation** | World state SSBO (begin pass): integrated wind, weather, wetness, snow, sun/sky light; all existing effects switched to read it (clouds, waving, rain slant, waves, storm fog, puddles). Auto exposure (Q28) | Scattered per-effect timers, per-pixel sky colour maths | **Faster** (P4) |
| **W2 Water** | Analytic wave field (swell / wind sea / ripples / rain, fetch); Jacobian caustics with dispersion and absorption (Q13, Q14); roughness from the spectrum (Q17); refracted underwater shafts; interactive ripples (Q15); then shorelines (Q16) | Noise waves, noise caustics | ≈ same; +0.1 ms for the ripple sim |
| **W3 Light volume + occlusion** | Merged propagation (block hue, sun bounce, sky visibility), directional sampling, block-light glints (Q2–Q4, Q7); GTAO with bent normals and multi-bounce (Q1) | M6 floodfill, M9.5 SSAO, vanilla-skylight ambient | ≈ same (merged and round-robin; P9, P17, P14) |
| **W4 Shadows** | PCSS + blue noise + temporal (Q8, Q11, P3, P20); cloud-softened sun; contact shadows (Q9); translucent entity shadows (Q12); lightning voxel shadows (Q23); far heightmap shadows (Q10) | Fixed 3×3 PCF | +0.3–0.6 ms (far shadows are the biggest part) |
| **W5 Air** | Unified volumetric medium: haze, mist (Q24), rain curtains (Q19), storms, light fog (Q6); cloud upgrade (Q26, formation, P1, P13); physical sky option (Q25); Q27 touches | Light shafts, separate fog/storm fog | ≈ same as today's shafts; clouds faster (P1) |
| **W6 Surfaces** | Wind-driven wetness, concavity puddles (Q21), splashes (Q18), snow cover and drifts (Q20); plant spring model | M9 puddles/wetness | +0.1–0.2 ms |
| **W7 Camera** | Entity-aware TAA (Q29 fallback), AgX (Q30), DOF / motion blur / lens flare (Q31) | — | Options, off by default except TAA changes |
| **M10** | Per-biome and cave mood, presets, performance pass (P10, P11, P12, P16, P18 if needed), release | | |

\*Rough estimates, not measured. Each phase ends with you checking fps in game.

**Performance items that fall out of the design:** P1 and P13 (clouds), P3 and P20 (shadows),
P4 (world state), P9 and P17 (light volume), P14 (AO history), P15 (sky effects into the cloud
pass when the physical sky's per-frame table lands) and P10 (the air medium merges passes).
P11, P12, P16 and P18 stay independent and go into M10.

---

## 6. Resources and limits

- **Iris images (16 max):**
  - Column maps merged into **one** taller image (5 → 1, plus a new "solid tops" map for
    water depth/shores).
  - Voxels (1), block hue A/B (2), bounce + sky A/B (2), ripple sim (1, two halves), shore
    distance (1), far heightmap (1).
  - About 10 in use, leaving spare room for Q5.
- **Memory:** the new volumes add about 64 MB (RGBA8 bounce + sky visibility at 256×128×256 ×2).
  The total stays far below the 14–15 GB limit (the pack is around 1.5 GB now).
- **Buffers:** world state (~256 B), exposure histogram (~1 KB), both SSBOs (the Iris `SSBO`
  feature, supported).
- **Iris checks done:** `begin` compute passes, SSBOs and compute passes in shadowcomp and
  composite are supported in 1.11.7. Per-entity motion vectors aren't.

## 7. Risks

- **Look drift:** a physical model changes the Unbound look. Mitigation: the artistic sky
  stays default, all new quantities get artist multipliers, and each phase is tuned against
  the current version.
- **Far shadows** depend on how far the shadow pass renders chunks (CPU cost). They start
  inside the existing range and get an opt-in extension.
- **Simulated state** (wetness, snow) is per client and resets on reload. Acceptable (vanilla
  weather does the same).
- **Volumetric merge (W5)** is the most invasive rebuild. It's done last among the air
  systems, so its inputs (world state, light volume) already exist.
