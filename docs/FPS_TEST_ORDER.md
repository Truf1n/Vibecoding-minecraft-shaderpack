# FPS test: switching features on one by one

How to find what each feature costs. Start from a baseline with everything that can be off
switched off. Switch features on one at a time, from the foundations (shadows, lighting) up
to the newest effects. Note the FPS after each step: the drop at each step is that
feature's cost on top of everything before it.

## Scene and method

**Where to stand:** on a shore, 2–3 blocks above the water, looking out and slightly down at
it, with:
- trees beside you;
- a torch-lit build in view;
- the morning sun in front of you or to the side, so light shafts show.

**Freeze the world:**
- `/time set 2000`
- `/gamerule doDaylightCycle false`
- `/weather clear`
- `/gamerule doWeatherCycle false`

Don't touch the water, and stand completely still.

**After each step:** wait about 10 s for the reload and for everything that builds up over
time to settle. Then read the average FPS over about 10 s, from F3 or a frametime overlay.

**The A1–B7 optimisations** (Debug screen) stay on throughout; they are tested separately.
So do Leaf Shadow Optimization and No Clouds Underground.

## Baseline (step 0)

| Screen | Set to |
|---|---|
| Shadows | Resolution 1024, Distance 64, Penumbra 0, Samples 8, Half-Res Shadows off, Contact/Far Shadows off, Translucent Entity Shadows off, Lightning Shadows off, Entity Shadows off, Player Shadow off, Player Shadow Quality 0, Colored Shadows off, Foliage SSS 0 |
| Lighting | SSAO 0, Sun Bounce 0, Voxel Sky Occlusion 0, Directional Blocklight off, Colored Lighting off, Blocklight Flicker 0 |
| Materials | Block Reflections 0, Generated Normals off, Coated Textures 0, Entity Materials off, Glowing Ores off, Glowing Amethyst 0, Glow Lichen 0, Glowing Trims off, Glowing Lava Particles off, Portal Effects off |
| Water | Water Reflections 0, Refraction 0, Biome Water off, Foam 0, Caustics off, Interactive Ripples off, Waving Water Vertex off, Underwater Distortion off |
| Clouds | Cloud Style Off, Light-Shaft Quality (VL_QUALITY) Off |
| Atmosphere | Mist 0, Rain Curtains off, Light Fog 0, Water Shafts From Above off, Stars 0, Nebulae 0, Aurora 0, Rainbows 0 |
| Weather | Puddles 0, Wet Surfaces off, Rain Ripples off, Storms off |
| Waving | Plants, Leaves, Lily Pads, Lava, Weather off; Hand Sway 0 |
| Camera | TAA off, Sharpening 0, FXAA off, Bloom off, Vignette 0, Chromatic Aberration 0 |
| Color | Auto Exposure off |

Colour, grading, intensity and size sliders cost nothing, so leave them as they are.

## Order

### Shadows
1. Shadow Resolution 4096
2. Shadow Distance 160
3. Shadow Samples 12
4. Shadow Penumbra 1.00 (soft shadows with the blocker search)
5. Half-Res Shadows
6. Colored Shadows
7. Entity Shadows + Player Shadow + Player Shadow Quality 1 + Translucent Entity Shadows
8. Foliage SSS 1.00

### Lighting
9. SSAO 1
10. Colored Lighting (Range 2): the light volume and its floodfill
11. Directional Blocklight
12. Voxel Sky Occlusion 0.80
13. Sun Bounce 1.00
14. Blocklight Flicker 2

### Surfaces
15. Generated Normals
16. Coated Textures 50
17. Entity Materials + Glowing Ores, Amethyst 1, Glow Lichen 1, Trims, Lava Particles, Portal Effects (one step: they cost almost nothing)

### Water
18. Biome Water + Water Refraction 100
19. Water Caustics
20. Water Reflections 1 (screen-space reflections)
21. Waving Water Vertex
22. Water Foam 2
23. Interactive Ripples (expect almost nothing while nothing touches the water)

### Waving
24. Waving Plants + Leaves + Lily Pads + Lava + Hand Sway 1

### Sky and air
25. Cloud Style Unbound (volumetric clouds and their reflection panorama)
26. Cloud Shadows 70
27. Light-Shaft Quality Medium (the air march)
28. Mist 100 (shows only on misty mornings; may cost little in a clear scene)
29. Light Fog 1.00
30. Water Shafts From Above

### Camera
31. TAA
32. Image Sharpening 3
33. Bloom (+ Distant Light Bloom 1.00)
34. Auto Exposure
35. Vignette 0.25

At step 35 everything is back at the defaults.

### Separate conditions (stay at step 35, change only the world)
36. **Rain:** `/weather rain`, then switch on Puddles 1, Wet Surfaces, Rain Ripples, Rain Curtains one at a time.
37. **Thunder:** `/weather thunder` + Storms.
38. **Night:** `/time set 18000`, then Stars 2, Nebulae 0.60, Aurora 1 (Aurora Shows: Every Night, for the test).
39. **Rainbow:** `/weather clear` straight after rain, with Rainbows 1.

### Off by default (only if you want their cost)
- Block Reflections 2.
- FXAA.
- Contact Shadows.
- Far Shadows (still parked).
