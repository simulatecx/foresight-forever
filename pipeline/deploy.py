"""Deploy HelpMe to the local WoW Forever install - gate first, then copy.

Usage: python deploy.py [--target <AddOns\\HelpMe path>] [--skip-gate]
The gate (compliance scan + 28-check selftest) must be green before any copy;
a red gate blocks the deploy outright (release-train discipline).
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

ADDON_SRC = Path(__file__).parent.parent / "HelpMe"
DEFAULT_TARGETS = [
    Path(r"D:\Games\World of Warcraft\_classic_beta_\Interface\AddOns\HelpMe"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=Path, default=None)
    parser.add_argument("--skip-gate", action="store_true",
                        help="emergency only; the gate is the point")
    args = parser.parse_args()

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
        print("no deploy target found - pass --target <...\\Interface\\AddOns\\HelpMe>")
        return 1

    for target in targets:
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(ADDON_SRC, target, ignore=shutil.ignore_patterns("*.pyc"))
        files = len(list(target.rglob("*.*")))
        print(f"deployed {files} files -> {target}")
    print("in-game: /reload (or relog), then /helpme verify")
    return 0


if __name__ == "__main__":
    sys.exit(main())
