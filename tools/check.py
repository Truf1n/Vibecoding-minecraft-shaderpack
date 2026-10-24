#!/usr/bin/env python3
"""Compile-check every program the way Iris would see it, using glslangValidator.

What it does:
  1. Expands #include "/..." relative to shaders/ (like Iris).
  2. Injects the macros Iris predefines (IS_IRIS, MC_VERSION, MC_RENDER_STAGE_*...).
  3. Compiles and links each vertex/fragment pair of every dimension folder.
  4. Repeats with each switch-like option (booleans and small integer lists from
     lib/settings.glsl) flipped to every listed value, so #if branches get compiled too.

It cannot catch driver-specific quirks or visual bugs, only GLSL errors.

    python3 tools/check.py            # baseline + option variants
    python3 tools/check.py --quick    # baseline only
"""
import re
import subprocess
import sys
import tempfile
from pathlib import Path

SHADERS = Path(__file__).resolve().parent.parent / "shaders"
WORLDS = ["world0", "world-1", "world1"]
STAGES = {".vsh": "vert", ".fsh": "frag", ".csh": "comp"}

IRIS_MACROS = {
    "IS_IRIS": "",
    "MC_VERSION": "260300",
    "MC_GL_VERSION": "460",
    "MC_GLSL_VERSION": "460",
    "MC_GL_VENDOR_AMD": "",
    "MC_GL_RENDERER_RADEON": "",
    "MC_OS_WINDOWS": "",
    "IRIS_TAG_SUPPORT": "2",
}
RENDER_STAGES = [
    "NONE", "SKY", "SUNSET", "CUSTOM_SKY", "SUN", "MOON", "STARS", "VOID", "TERRAIN_SOLID",
    "TERRAIN_CUTOUT_MIPPED", "TERRAIN_CUTOUT", "ENTITIES", "BLOCK_ENTITIES", "DESTROY", "OUTLINE",
    "DEBUG", "HAND_SOLID", "TERRAIN_TRANSLUCENT", "TRIPWIRE", "PARTICLES", "CLOUDS", "RAIN_SNOW",
    "WORLD_BORDER", "HAND_TRANSLUCENT",
]
for i, name in enumerate(RENDER_STAGES):
    IRIS_MACROS[f"MC_RENDER_STAGE_{name}"] = str(i)

INCLUDE_RE = re.compile(r'^\s*#include\s+"([^"]+)"', re.M)
# [ \t] rather than \s: a value must be on the same line as its #define.
OPTION_RE = re.compile(r"^[ \t]*(//)?[ \t]*#define[ \t]+(\w+)(?:[ \t]+(\S+))?[ \t]*(?://[ \t]*\[([^\]]*)\])?", re.M)


def expand(path: Path, stack=()) -> str:
    if path in stack:
        raise RuntimeError(f"include cycle: {' -> '.join(map(str, stack + (path,)))}")
    text = path.read_text()

    def repl(m):
        target = SHADERS / m.group(1).lstrip("/")
        if not target.exists():
            raise RuntimeError(f"{path}: missing include {m.group(1)}")
        return expand(target, stack + (path,))

    return INCLUDE_RE.sub(repl, text)


def option_variants():
    """Yield (label, overrides) for each switch-like option value."""
    text = (SHADERS / "lib" / "settings.glsl").read_text()
    for m in OPTION_RE.finditer(text):
        commented, name, value, choices = m.groups()
        if value is None:  # boolean toggle
            yield f"{name}={'on' if commented else 'off'}", {name: None if commented else False}
        elif choices:
            values = choices.split()
            if all(re.fullmatch(r"-?\d+", v) for v in values) and len(values) <= 12:
                for v in values:
                    if v != value:
                        yield f"{name}={v}", {name: v}


def apply_overrides(src: str, overrides: dict) -> str:
    for name, value in overrides.items():
        if value is False:  # disable boolean
            src = re.sub(rf"^(\s*)#define\s+{name}\b.*$", rf"\1// #define {name}", src, flags=re.M)
        elif value is None:  # enable commented-out boolean
            src = re.sub(rf"^(\s*)//\s*#define\s+{name}\b.*$", rf"\1#define {name}", src, flags=re.M)
        else:
            src = re.sub(rf"^(\s*)#define\s+{name}\s+\S+", rf"\1#define {name} {value}", src, flags=re.M)
    return src


def prepare(path: Path, overrides: dict) -> str:
    src = apply_overrides(expand(path), overrides)
    lines = src.split("\n")
    assert lines[0].startswith("#version"), f"{path}: #version must be the first line"
    prelude = [f"#define {k} {v}".rstrip() for k, v in IRIS_MACROS.items()]
    return "\n".join([lines[0]] + prelude + ["#line 2"] + lines[1:])


def check_program(world: str, program: str, files: list, overrides: dict, tmp: Path) -> str | None:
    staged = []
    for f in files:
        out = tmp / f"{world}_{program}.{STAGES[f.suffix]}"
        out.write_text(prepare(f, overrides))
        staged.append(str(out))
    link = ["-l"] if len(staged) > 1 else []
    res = subprocess.run(["glslangValidator", *link, *staged], capture_output=True, text=True)
    if res.returncode != 0:
        return annotate(res.stdout + res.stderr)
    return None


def annotate(log: str) -> str:
    """Append the offending source line to each error (line numbers refer to the
    include-expanded file, which is otherwise hard to map back)."""
    out = []
    for line in log.splitlines():
        out.append(line)
        m = re.match(r"ERROR: (\S+):(\d+):", line)
        if m and Path(m.group(1)).exists():
            src = Path(m.group(1)).read_text().split("\n")
            n = int(m.group(2)) + 1 + len(IRIS_MACROS)  # account for the injected prelude
            if 0 < n <= len(src):
                out.append(f"    > {src[n - 1].strip()}")
    return "\n".join(out)


def run(overrides: dict, label: str, tmp: Path) -> int:
    failures = 0
    for world in WORLDS:
        folder = SHADERS / world
        programs = {}
        for f in sorted(folder.iterdir()):
            if f.suffix in STAGES:
                programs.setdefault(f.stem, []).append(f)
        for program, files in programs.items():
            err = check_program(world, program, files, overrides, tmp)
            if err:
                failures += 1
                print(f"FAIL [{label}] {world}/{program}\n{err}")
    return failures


def check_option_detection() -> int:
    """Iris only lists a boolean option in the menu if some shader file tests it with a
    plain `#ifdef NAME` / `#ifndef NAME` (not `#if defined NAME && ...`)."""
    settings = (SHADERS / "lib" / "settings.glsl").read_text()
    booleans = [m.group(2) for m in OPTION_RE.finditer(settings) if m.group(3) is None]
    sources = "\n".join(p.read_text() for p in SHADERS.rglob("*.glsl") if p.name != "settings.glsl")
    missing = [b for b in booleans if not re.search(rf"^\s*#\s*if(n)?def\s+{b}\b", sources, re.M)]
    for b in missing:
        print(f"FAIL option {b}: never tested with a plain #ifdef/#ifndef, so Iris will not list it")
    return len(missing)


def main() -> int:
    quick = "--quick" in sys.argv
    if check_option_detection():
        return 1
    with tempfile.TemporaryDirectory() as d:
        tmp = Path(d)
        failures = run({}, "default", tmp)
        variants = 0
        if not quick:
            for label, overrides in option_variants():
                failures += run(overrides, label, tmp)
                variants += 1
    print(f"{'OK' if failures == 0 else 'FAILED'}: default + {variants} option variants, {failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
