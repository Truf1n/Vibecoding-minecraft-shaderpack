#!/usr/bin/env python3
"""Generate the per-dimension program wrappers (shaders/world*/ and the root fallbacks).

Each wrapper is a few lines: #version, the dimension and program defines, the stage
define, and an #include of the shared template in shaders/program/. Edit PROGRAMS
below and re-run; never edit generated files by hand.

    python3 tools/gen_wrappers.py
"""
from pathlib import Path

SHADERS = Path(__file__).resolve().parent.parent / "shaders"
VERSION = "#version 430 compatibility"

# Folder -> dimension define. shaders/dimension.properties routes modded dimensions
# to world0 (overworld behaviour).
WORLDS = {
    "world0": "WORLD_OVERWORLD",
    "world-1": "WORLD_NETHER",
    "world1": "WORLD_END",
}

# program name -> (template, extra defines)
PROGRAMS = {
    # Opaque geometry -> G-buffer
    "gbuffers_terrain":     ("gbuffers_deferred", []),
    # Solid terrain on its own (P11): no alpha test, so the depth test runs before the
    # shader and hidden pixels never run the material code.
    "gbuffers_terrain_solid": ("gbuffers_deferred", ["PROG_GBUFFERS_TERRAIN", "TERRAIN_SOLID"]),
    "gbuffers_entities":    ("gbuffers_deferred", []),
    "gbuffers_block":       ("gbuffers_deferred", []),
    "gbuffers_hand":        ("gbuffers_deferred", []),
    # Forward
    "gbuffers_skybasic":    ("gbuffers_forward", ["FWD_SKY"]),
    "gbuffers_skytextured": ("gbuffers_forward", ["FWD_SKYTEX"]),
    "gbuffers_clouds":      ("gbuffers_forward", ["FWD_OVERLAY", "OVERLAY_CLOUDS"]),
    "gbuffers_armor_glint": ("gbuffers_forward", ["FWD_OVERLAY"]),
    "gbuffers_spidereyes":  ("gbuffers_forward", ["FWD_OVERLAY", "OVERLAY_EMISSIVE"]),
    "gbuffers_beaconbeam":  ("gbuffers_forward", ["FWD_OVERLAY", "OVERLAY_EMISSIVE"]),
    "gbuffers_lightning":   ("gbuffers_forward", ["FWD_OVERLAY", "OVERLAY_EMISSIVE", "OVERLAY_NO_TEXTURE"]),
    "gbuffers_basic":       ("gbuffers_forward", ["FWD_UNLIT"]),
    "gbuffers_line":        ("gbuffers_forward", ["FWD_UNLIT"]),
    "gbuffers_damagedblock": ("gbuffers_forward", ["FWD_DAMAGE"]),
    "gbuffers_textured":    ("gbuffers_forward", ["FWD_LIT"]),
    "gbuffers_weather":     ("gbuffers_forward", ["FWD_LIT"]),
    "gbuffers_water":       ("gbuffers_forward", ["FWD_LIT"]),
    "gbuffers_hand_water":  ("gbuffers_forward", ["FWD_LIT"]),
    # Translucent mobs (slime outer layer, allay, piglins in 26.x, ...) are drawn after
    # deferred, so they must be forward-lit rather than written to the G-buffer.
    "gbuffers_entities_translucent": ("gbuffers_forward", ["FWD_LIT"]),
    "gbuffers_block_translucent":    ("gbuffers_forward", ["FWD_LIT"]),
    # Shadow map (in the Nether only to fill the coloured-light voxels)
    "shadow":               ("shadow", []),
    # Coloured-light floodfill (compute)
    "shadowcomp":           ("floodfill", []),
    "shadowcomp1":          ("rippleSources", []),     # interactive ripples: where entities cross water
    "shadowcomp2":          ("ripples", []),           # interactive ripples: simulation step
    # Fullscreen
    "deferred":             ("clouds", []),            # reduced size (scale.deferred)
    "deferred1":            ("ssao", []),              # half size (size.buffer.colortex15)
    "deferred2":            ("deferred", []),          # lighting, sky, clouds composite
    "deferred3":            ("reflections", ["REFL_TRACE"]),  # full or half size (size.buffer)
    "deferred4":            ("reflections", ["REFL_APPLY"]),
    "composite":            ("lightShafts", ["LS_MARCH"]),  # air march, half size (size.buffer.colortex11)
    "composite1":           ("composite", []),         # tints, clouds in front, air light
    "composite2":           ("taa", []),
    "composite3":           ("bloom", []),             # half size (size.buffer.colortex13)
    "composite4":           ("post", []),              # tonemap, grading -> colortex14
    "final":                ("final", []),
}

# Compute shaders that run at the start of a pass that also has a fragment program
# (pass name -> template, defines). They write <pass>.csh next to <pass>.vsh/.fsh.
EXTRA_COMPUTE = {
    "begin":                ("worldState", ["WORLD_STATE_WRITER"]),   # world state (once per frame)
    "composite4":           ("exposure", ["WORLD_STATE_WRITER"]),     # auto exposure, before post
    "deferred":             ("skyView", []),                          # cloud panorama for reflections
}

# Programs left out of a dimension entirely (Iris skips missing passes).
# (Passes switched off by options - TAA, clouds, light shafts - are disabled from
# shaders.properties.)
# Clouds and light shafts are Overworld-only (no sun in the Nether, End beams come later).
SKIP = {
    "world-1": {"deferred", "composite", "shadowcomp1", "shadowcomp2"},
    "world1": {"deferred", "composite"},
}

STAGES = {".vsh": "VERTEX_SHADER", ".fsh": "FRAGMENT_SHADER"}
COMPUTE_STAGES = {".csh": "COMPUTE_SHADER"}
COMPUTE_TEMPLATES = {"floodfill", "rippleSources", "ripples"}
HEADER = "// Generated by tools/gen_wrappers.py. Edit the table there, not this file."


def main() -> None:
    count = 0
    for folder, world in WORLDS.items():
        out_dir = SHADERS / folder
        out_dir.mkdir(parents=True, exist_ok=True)
        for program, (template, defines) in PROGRAMS.items():
            if program in SKIP.get(folder, ()):
                continue
            stages = COMPUTE_STAGES if template in COMPUTE_TEMPLATES else STAGES
            for ext, stage in stages.items():
                lines = [VERSION, HEADER, "", f"#define {world}", f"#define PROG_{program.upper()}"]
                lines += [f"#define {d}" for d in defines]
                lines += [f"#define {stage}", "", f'#include "/program/{template}.glsl"', ""]
                (out_dir / f"{program}{ext}").write_text("\n".join(lines))
                count += 1
        for program, (template, defines) in EXTRA_COMPUTE.items():
            if program in SKIP.get(folder, ()):
                continue
            lines = [VERSION, HEADER, "", f"#define {world}", f"#define PROG_{program.upper()}_COMPUTE"]
            lines += [f"#define {d}" for d in defines]
            lines += ["#define COMPUTE_SHADER", "", f'#include "/program/{template}.glsl"', ""]
            (out_dir / f"{program}.csh").write_text("\n".join(lines))
            count += 1
    print(f"wrote {count} wrapper files")


if __name__ == "__main__":
    main()
