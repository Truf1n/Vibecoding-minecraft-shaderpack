#!/usr/bin/env python3
"""Build an installable shaderpack zip in dist/ (runs the compile check first).

    python3 tools/package.py [version-label]
"""
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACK_NAME = "UntitledShaders"  # placeholder until the pack is named


def main() -> int:
    if subprocess.run([sys.executable, str(ROOT / "tools" / "check.py")]).returncode != 0:
        print("compile check failed; not packaging")
        return 1
    label = sys.argv[1] if len(sys.argv) > 1 else "dev"
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    out = dist / f"{PACK_NAME}-{label}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted((ROOT / "shaders").rglob("*")):
            if f.is_file():
                z.write(f, f.relative_to(ROOT))
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
