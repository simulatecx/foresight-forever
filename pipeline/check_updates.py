"""Detect a new WoW Forever client build on wago.tools and (optionally) adopt it.

The data-freshness engine (owner, 2026-10-19: "automate this scan, push whenever blizz
does a new release"). Queries the wago.tools builds API, scans EVERY product for versions
matching the Forever prefix (robust to product renames - 1.60.x has moved between
products), and compares the newest against the pipeline's DEFAULT_BUILD.

--apply rewrites DEFAULT_BUILD in fetch.py / generate.py / audit_crosstalents.py so the
subsequent plain `fetch.py` + `generate.py` run against the new build. The CI workflow
then regenerates everything (client data + talentsforever exports), runs the ship gate,
and opens a REVIEW PR - data never auto-ships; the gate + human review + tag still stand.

Exit 0 always (detection is not failure); machine-readable lines + $GITHUB_OUTPUT.
Usage: python pipeline/check_updates.py [--apply] [--prefix 1.60.]
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).parent
BUILDS_API = "https://wago.tools/api/builds"
DEFAULT_FILES = ["fetch.py", "generate.py", "audit_crosstalents.py"]


def current_build() -> str:
    m = re.search(r'DEFAULT_BUILD = "([\d.]+)"', (ROOT / "fetch.py").read_text(encoding="utf-8"))
    if not m:
        raise SystemExit("cannot read DEFAULT_BUILD from fetch.py")
    return m.group(1)


def ver_key(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in v.split(".") if x.isdigit())


def latest_forever_build(prefix: str) -> str | None:
    req = urllib.request.Request(BUILDS_API, headers={"User-Agent": "foresight-pipeline"})
    data = json.loads(urllib.request.urlopen(req, timeout=60).read().decode("utf-8"))
    best = None
    for builds in (data.values() if isinstance(data, dict) else []):
        for b in (builds if isinstance(builds, list) else []):
            v = b.get("version") if isinstance(b, dict) else b
            if isinstance(v, str) and v.startswith(prefix):
                if best is None or ver_key(v) > ver_key(best):
                    best = v
    return best


def apply_build(new: str, old: str) -> None:
    for name in DEFAULT_FILES:
        p = ROOT / name
        src = p.read_text(encoding="utf-8")
        p.write_text(src.replace(f'DEFAULT_BUILD = "{old}"', f'DEFAULT_BUILD = "{new}"'),
                     encoding="utf-8")
    print(f"applied DEFAULT_BUILD {old} -> {new} in {', '.join(DEFAULT_FILES)}")


def gh_output(**kv) -> None:
    path = os.environ.get("GITHUB_OUTPUT")
    if path:
        with open(path, "a", encoding="utf-8") as fh:
            for k, v in kv.items():
                fh.write(f"{k}={v}\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="rewrite DEFAULT_BUILD when a newer build exists")
    parser.add_argument("--prefix", default="1.60.",
                        help="Forever version prefix to scan for")
    args = parser.parse_args()

    cur = current_build()
    try:
        latest = latest_forever_build(args.prefix)
    except Exception as e:  # noqa: BLE001 - an API hiccup must not red the cron
        print(f"builds API unavailable ({e}) - keeping {cur}")
        gh_output(new_build="", current=cur)
        return 0
    if not latest:
        print(f"no builds matching prefix {args.prefix!r} - keeping {cur}")
        gh_output(new_build="", current=cur)
        return 0
    if ver_key(latest) <= ver_key(cur):
        print(f"up to date: current {cur} >= latest {latest}")
        gh_output(new_build="", current=cur)
        return 0
    print(f"NEW BUILD: {latest} (current {cur})")
    gh_output(new_build=latest, current=cur)
    if args.apply:
        apply_build(latest, cur)
    return 0


if __name__ == "__main__":
    sys.exit(main())
