"""Fetch WoW Forever client DB2 tables as CSV from wago.tools into pipeline/cache/<build>/.

Usage: python fetch.py [--build 1.60.1.70338] [--force]
Tables are skipped if already cached (use --force to refetch).
"""

from __future__ import annotations

import argparse
import sys
import time
import urllib.request
from pathlib import Path

DEFAULT_BUILD = "1.60.1.70338"

# Tables needed for the Talent Impact Map and the impact graph foundation.
# ItemSparse/Item are deferred to the item-impact phase (large, not yet consumed).
TABLES = [
    "Talent",
    "TalentTab",
    "Spell",              # Description_lang / AuraDescription_lang
    "SpellName",
    "SpellEffect",        # aura types, spell-mod ops, class masks, periods, coefficients
    "SpellClassOptions",  # per-spell family set + class mask (modifier matching)
    "SpellMisc",          # school, cast-time index, duration index, attributes
    "SpellPower",         # resource costs
    "SpellCastTimes",
    "SpellDuration",
    "SpellCooldowns",
    "SpellLevels",
    "SkillLineAbility",   # class/profession skill-line membership
    "SkillLine",
    "ChrRaces",           # race id/token (racial SkillLineAbility.RaceMasks bit = 1<<(ID-1))
    "SkillRaceClassInfo", # race/class gating of skill lines (racial availability)
    # Retail trait system = the LIVE talent system on Forever (classic globals are gone).
    "TraitNode",               # node id, tree id, position, type
    "TraitNodeEntry",          # entry -> definition + max ranks
    "TraitNodeXTraitNodeEntry",# node <-> entry link (+ index)
    "TraitDefinition",         # definition -> SpellID + override name (the spell bridge)
    "SkillLineXTraitTree",     # tree -> class skill line
]

BASE_URL = "https://wago.tools/db2/{table}/csv?build={build}"


def fetch_table(table: str, build: str, cache_dir: Path, force: bool) -> str:
    dest = cache_dir / f"{table}.csv"
    if dest.exists() and not force:
        return f"cached  {table} ({dest.stat().st_size:,} bytes)"
    url = BASE_URL.format(table=table, build=build)
    req = urllib.request.Request(url, headers={"User-Agent": "Foresight-addon-pipeline/0.1"})
    started = time.time()
    with urllib.request.urlopen(req, timeout=120) as resp:
        data = resp.read()
    if not data or b"," not in data.split(b"\n", 1)[0]:
        raise RuntimeError(f"{table}: response does not look like CSV")
    dest.write_bytes(data)
    return f"fetched {table} ({len(data):,} bytes in {time.time() - started:.1f}s)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=DEFAULT_BUILD)
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    cache_dir = Path(__file__).parent / "cache" / args.build
    cache_dir.mkdir(parents=True, exist_ok=True)

    failures = []
    for table in TABLES:
        try:
            print(fetch_table(table, args.build, cache_dir, args.force), flush=True)
        except Exception as exc:  # noqa: BLE001 - report and continue
            failures.append(table)
            print(f"FAILED  {table}: {exc}", flush=True)

    if failures:
        print(f"\n{len(failures)} table(s) failed: {', '.join(failures)}")
        return 1
    print(f"\nAll {len(TABLES)} tables cached in {cache_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
