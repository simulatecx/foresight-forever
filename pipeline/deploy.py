"""Deploy Foresight to the local WoW Forever install - gate first, then copy.

Usage: python deploy.py [--target <AddOns\\Foresight path>] [--skip-gate] [--verify]
The gate (compliance scan + selftest) must be green before any copy; a red gate blocks
the deploy outright (release-train discipline).

THIS IS THE ONLY SUPPORTED WAY TO INSTALL LOCALLY. Never hand-copy the repo (or Foresight/)
into Interface\\AddOns\\Foresight: copying the repo ROOT nests the addon under Foresight/
and leaves data/ holding only the pipeline source, so the TOC points at missing files and
the client "Error loading"s every data/ file (HM.formulas nil -> talent-hover crash). Run
`--verify` any time to confirm the live install still byte-matches the addon.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import subprocess
import sys
from pathlib import Path

ADDON_SRC = Path(__file__).parent.parent / "Foresight"
DEFAULT_TARGETS = [
    Path(r"D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\Foresight"),
]


def verify_layout(target: Path) -> list[str]:
    """Every .lua the TOC lists must exist on disk at the target.

    The client reports a bare "Error loading <file>" when a TOC-referenced file is
    missing (e.g. a copy that landed the repo root instead of the addon, so
    data\\formulas.lua is absent and HM.formulas is never set). We'd rather fail the
    deploy here than let that reach the game. Returns the list of missing files.
    """
    missing = []
    for toc_name in ("Foresight.toc", "Foresight_Vanilla.toc"):
        toc = target / toc_name
        if not toc.exists():
            if toc_name == "Foresight.toc":
                return ["Foresight.toc"]
            continue  # the classic flavor TOC is optional
        for raw in toc.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.lower().endswith(".lua"):
                rel = line.replace("\\", "/")
                if not (target / rel).exists():
                    missing.append(f"{rel} [{toc_name}]")
    return missing


def _tree(base: Path) -> dict:
    out = {}
    for root, _, files in os.walk(base):
        for f in files:
            p = Path(root) / f
            out[p.relative_to(base).as_posix()] = p
    return out


def _sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def verify_install(target: Path) -> bool:
    """Confirm the live install byte-matches the addon source (ADDON_SRC).

    Catches the recurring failure where an EXTERNAL copy (a folder drag, a sync tool, a
    sibling worktree that copied the repo root) overwrites a clean deploy with the wrong
    layout. Reports missing / extra (pollution) / content-diff, and prints OK only when
    the install is exactly the addon. No writes.
    """
    if not target.exists():
        print(f"NOT INSTALLED: {target}")
        return False
    src, dst = _tree(ADDON_SRC), _tree(target)
    missing = sorted(set(src) - set(dst))
    extra = sorted(set(dst) - set(src))
    differ = sorted(r for r in (set(src) & set(dst))
                    if src[r].stat().st_size != dst[r].stat().st_size or _sha(src[r]) != _sha(dst[r]))
    ok = not (missing or extra or differ)
    print(f"verify {target}")
    print(f"  addon files {len(src)} | installed {len(dst)} | identical {len(set(src) & set(dst)) - len(differ)}")
    for tag, items in (("MISSING", missing), ("EXTRA (pollution)", extra), ("DIFFERS", differ)):
        if items:
            print(f"  {tag} ({len(items)}):")
            for i in items[:25]:
                print(f"    {i}")
    print("  RESULT:", "CLEAN - install matches the addon" if ok else "DIRTY - redeploy with `python pipeline/deploy.py`")
    return ok


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=None)
    parser.add_argument("--skip-gate", action="store_true",
                        help="emergency only; the gate is the point")
    parser.add_argument("--verify", action="store_true",
                        help="only check the live install byte-matches the addon; no copy")
    args = parser.parse_args()

    if args.verify:
        targets = [args.target] if args.target else [t for t in DEFAULT_TARGETS if t.exists()]
        if not targets:
            print("no install found to verify - pass --target <...\\Interface\\AddOns\\Foresight>")
            return 1
        return 0 if all(verify_install(t) for t in targets) else 1

    if not args.skip_gate:
        gate = subprocess.run(
            [sys.executable, str(Path(__file__).parent / "run_tests.py")],
            capture_output=True, text=True,
        )
        tail = "\n".join(gate.stdout.strip().splitlines()[-2:])
        if gate.returncode != 0:
            print("GATE RED - deploy blocked:\n" + gate.stdout + gate.stderr)
            return 1
        print(f"gate green ({tail})")

    targets = [args.target] if args.target else [t for t in DEFAULT_TARGETS if t.parent.exists()]
    if not targets:
        print("no deploy target found - pass --target <...\\Interface\\AddOns\\Foresight>")
        return 1

    for target in targets:
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ADDON_SRC, target, ignore=shutil.ignore_patterns("*.pyc"))
        missing = verify_layout(target)
        if missing:
            print(f"DEPLOY BROKEN - {len(missing)} TOC-referenced file(s) missing at {target}:")
            for m in missing[:20]:
                print(f"  - {m}")
            return 1
        files = len(list(target.rglob("*.*")))
        print(f"deployed {files} files -> {target} (TOC layout verified)")
    print("in-game: /reload (or relog), then /foresight verify")
    return 0


if __name__ == "__main__":
    sys.exit(main())
