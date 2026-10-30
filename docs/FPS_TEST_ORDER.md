# FPS test: switching features on one by one

How to find what each feature costs:
1. Start from a baseline with everything that can be off switched off.
2. Switch features on one at a time, from the foundations (shadows, lighting) up to the
   newest effects.
3. Note the FPS after each step: the drop at that step is the feature's cost on top of
   everything before it.

Every option is named exactly as it appears in the menu. Open the menu with **Options >
Video Settings > Shader Packs > Shader Pack Settings**. The top-level pages are:
- Lighting
- Shadows
- Atmosphere (with the sub-page Sky Effects)
- Clouds & Light Shafts
- Water & Glass
- Materials
- Camera
- Colour
- Weather
- Waving
- Debug

A name shown in yellow in the menu marks an option with a large effect on performance.

## Scene and method

**Where to stand:** on a shore, 2–3 blocks above the water, looking out and slightly down at
it, with trees beside you, a torch-lit build in view, and the morning sun in front of you or
to the side.

**Freeze the world:**
- `/time set 2000`
- `/gamerule doDaylightCycle false`
- `/weather clear`
- `/gamerule doWeatherCycle false`

Stand still and don't touch the water.

**After each step:** wait about 10 s, then read the average FPS over the next 10 s.

**Leave alone (on) throughout:**
- every option on the **Debug** page (A1–B7, tested separately);
- **Shadows > Leaf Shadow Optimization**;
- **Clouds & Light Shafts > No Clouds Underground**.

## Step 0: the baseline

| Page | Option (as in the menu) | Set to |
|---|---|---|
| Shadows | Shadow Resolution | 1024 |
| Shadows | Shadow Distance | 4 Chunks |
| Shadows | Sun Size | 0.00 |
| Shadows | Shadow Samples | 8 |
| Shadows | Half-Size Shadows | Off |
| Shadows | Contact Shadows | Off |
| Shadows | Far Shadows | Off |
| Shadows | See-through Mob Shadows | Off |
| Shadows | Lightning Shadows | Off |
| Shadows | Entity Shadows | Off |
| Shadows | Player Shadow | Off |
| Shadows | Player Shadow Quality | Normal |
| Shadows | Coloured Shadows | Off |
| Shadows | Leaf Translucency | 0.00 |
| Lighting | Ambient Occlusion | Off |
| Lighting | Block Light Flickering | Off |
| Lighting | Directional Block Light | Off |
| Lighting | Sun Bounce | 0.00 |
| Lighting | Sky Occlusion | 0.00 |
| Lighting | Coloured Lighting | Off |
| Materials | Block Reflections | Off |
| Materials | Generated Normals | Off |
| Materials | Coated Textures | 0 |
| Materials | Materials on Entities | Off |
| Materials | Glowing Ores | Off |
| Materials | Glowing Amethyst | Off |
| Materials | Glowing Lichen | Off |
| Materials | Glowing Armour Trims | Off |
| Materials | Glowing Lava Particles | Off |
| Materials | Portal Effects | Off |
| Water & Glass | Water Reflections | Sky Only |
| Water & Glass | Water Refraction | Off |
| Water & Glass | Biome Water | Off |
| Water & Glass | Water Foam | Off |
| Water & Glass | Water Caustics | Off |
| Water & Glass | Waving Water Height | Off |
| Water & Glass | Underwater Distortion | Off |
| Water & Glass | Interactive Ripples | Off |
| Clouds & Light Shafts | Cloud Style | Off |
| Clouds & Light Shafts | Light Shafts | Off |
| Atmosphere | Star Amount | Off |
| Atmosphere | Mist | Off |
| Atmosphere | Rain Curtains | Off |
| Atmosphere | Light Fog | 0.00 |
| Atmosphere | Water Shafts From Above | Off |
| Atmosphere > Sky Effects | Nebulae | 0.00 |
| Atmosphere > Sky Effects | Aurora | Off |
| Atmosphere > Sky Effects | Rainbows | Off |
| Weather | Puddles | Off |
| Weather | Wet Surfaces | Off |
| Weather | Rain Ripples | Off |
| Weather | Snowstorms & Sandstorms | Off |
| Waving | Waving Plants | Off |
| Waving | Waving Leaves & Vines | Off |
| Waving | Bobbing Lily Pads | Off |
| Waving | Flowing Lava | Off |
| Waving | Slanted Rain & Snow | Off |
| Waving | Hand Sway | Off |
| Camera | Temporal Anti-Aliasing | Off |
| Camera | Image Sharpening | Off |
| Camera | FXAA | Off |
| Camera | Bloom | Off |
| Camera | Vignette | 0.00 |
| Camera | Chromatic Aberration | Off |
| Colour | Auto Exposure | Off |

Everything else (colours, grading, strengths, sizes) costs nothing; leave it as it is.

## The order

### Shadows
| # | Page | Option | Set to |
|---|---|---|---|
| 1 | Shadows | Shadow Resolution | 4096 |
| 2 | Shadows | Shadow Distance | 10 Chunks |
| 3 | Shadows | Shadow Samples | 12 |
| 4 | Shadows | Sun Size | 1.00 |
| 5 | Shadows | Half-Size Shadows | On |
| 6 | Shadows | Coloured Shadows | On |
| 7 | Shadows | Entity Shadows, Player Shadow, See-through Mob Shadows; Player Shadow Quality | On, On, On; High |
| 8 | Shadows | Leaf Translucency | 1.00 |

### Lighting
| # | Page | Option | Set to |
|---|---|---|---|
| 9 | Lighting | Ambient Occlusion | Medium |
| 10 | Lighting | Coloured Lighting (check Coloured Light Range is 256 blocks) | On |
| 11 | Lighting | Directional Block Light | On |
| 12 | Lighting | Sky Occlusion | 0.80 |
| 13 | Lighting | Sun Bounce | 1.00 |
| 14 | Lighting | Block Light Flickering | 2 |

### Surfaces
| # | Page | Option | Set to |
|---|---|---|---|
| 15 | Materials | Generated Normals | On |
| 16 | Materials | Coated Textures | 50 |
| 17 | Materials | Materials on Entities, Glowing Ores, Glowing Amethyst, Glowing Lichen, Glowing Armour Trims, Glowing Lava Particles, Portal Effects (one step: they cost almost nothing) | On, On, Crystals, Closed Areas, On, On, On |

### Water
| # | Page | Option | Set to |
|---|---|---|---|
| 18 | Water & Glass | Biome Water + Water Refraction | On + 100 |
| 19 | Water & Glass | Water Caustics | On |
| 20 | Water & Glass | Water Reflections | Screen-Space |
| 21 | Water & Glass | Waving Water Height | On |
| 22 | Water & Glass | Water Foam | Normal |
| 23 | Water & Glass | Interactive Ripples (almost nothing while the water is untouched) | On |

### Waving
| # | Page | Option | Set to |
|---|---|---|---|
| 24 | Waving | Waving Plants, Waving Leaves & Vines, Bobbing Lily Pads, Flowing Lava, Hand Sway | On, On, On, On, Subtle |

### Sky and air
| # | Page | Option | Set to |
|---|---|---|---|
| 25 | Clouds & Light Shafts | Cloud Style (check Cloud Quality = Medium and Cloud Resolution = Half) | Unbound |
| 26 | Clouds & Light Shafts | Cloud Shadows | 70 |
| 27 | Clouds & Light Shafts | Light Shafts | Medium |
| 28 | Atmosphere | Mist (only shows on misty mornings; may cost little in a clear scene) | 100% |
| 29 | Atmosphere | Light Fog | 1.00 |
| 30 | Atmosphere | Water Shafts From Above | On |

### Camera and colour
| # | Page | Option | Set to |
|---|---|---|---|
| 31 | Camera | Temporal Anti-Aliasing | On |
| 32 | Camera | Image Sharpening | 3 |
| 33 | Camera | Bloom (+ Distant Light Bloom 1.00) | On |
| 34 | Colour | Auto Exposure | On |
| 35 | Camera | Vignette | 0.25 |

At step 35 everything is back at the defaults.

### Separate conditions (stay at step 35, change only the world)
| # | Do this | Then switch on, one at a time |
|---|---|---|
| 36 | `/weather rain` | Weather > Puddles = In Rain; Weather > Wet Surfaces; Weather > Rain Ripples; Weather > Slanted Rain & Snow; Atmosphere > Rain Curtains |
| 37 | `/weather thunder` | Shadows > Lightning Shadows |
| 38 | `/time set 18000` (night) | Atmosphere > Star Amount = Medium; Sky Effects > Nebulae = 0.60; Sky Effects > Aurora = Curtains, with Aurora Shows = Every Night (otherwise it may not appear) |
| 39 | `/weather clear` straight after rain, by day | Sky Effects > Rainbows = After Rain |
| 40 | In a snowy or desert biome, in rain | Weather > Snowstorms & Sandstorms |

### Off by default (only if you want their cost)
- **Materials > Block Reflections** = Full
- **Camera > FXAA**
- **Shadows > Contact Shadows**
- **Shadows > Far Shadows** (still parked)
