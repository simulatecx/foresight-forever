"""Harvest HelpMe data from live players' SavedVariables files.

The automated pull in the collection loop: the addon accumulates sessions, level-up
stat journals, verify results, and talent tooltip probes into HelpMeDB (written by the
client on logout/reload); this script finds those files, parses them in a Lua VM,
archives them as JSON, and runs the rank-rule analysis against generated data.

Usage: python harvest.py [--wow-root <path>]...
Scales from the pilot (this machine) to any contributor: future companion-app users
run exactly this against their own install and submit the JSON (the addon itself never
networks - compliance).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

import lupa

DEFAULT_ROOTS = [
    Path(r"D:\Games\World of Warcraft"),
    Path(r"D:\World of Warcraft"),
    Path(r"C:\Program Files (x86)\World of Warcraft"),
]
COLLECTED = Path(__file__).parent / "collected"
GENERATED = Path(__file__).parent.parent / "HelpMe" / "data" / "generated"


def lua_to_py(obj):
    if lupa.lua_type(obj) == "table":
        keys = list(obj.keys())
        if keys and all(isinstance(k, (int, float)) for k in keys):
            return [lua_to_py(obj[k]) for k in sorted(keys)]
        return {str(k): lua_to_py(v) for k, v in obj.items()}
    return obj


def find_savedvars(roots: list[Path]) -> list[Path]:
    found = []
    for root in roots:
        if root.exists():
            found.extend(root.glob("*/WTF/Account/*/SavedVariables/HelpMe.lua"))
    return found


MAX_SAVEDVARS_BYTES = 20 * 1024 * 1024

# Globals that must not exist while executing untrusted SavedVariables content.
# SavedVariables are DATA (table constructors); hostile files are the threat model
# for Phase B crowd submissions - they get a dead sandbox, not our filesystem.
SANDBOX_NEUTER = (
    "os=nil io=nil require=nil dofile=nil loadfile=nil load=nil loadstring=nil "
    "package=nil debug=nil python=nil collectgarbage=nil coroutine=nil"
)


def parse_savedvars_text(text: str) -> dict:
    if len(text.encode("utf-8", "ignore")) > MAX_SAVEDVARS_BYTES:
        raise ValueError("SavedVariables file exceeds size cap")
    lua = lupa.LuaRuntime(register_eval=False, register_builtins=False)
    lua.execute(SANDBOX_NEUTER)
    lua.execute(text)
    db = lua.globals().HelpMeDB
    return lua_to_py(db) if db is not None else {}


def parse_savedvars(path: Path) -> dict:
    return parse_savedvars_text(path.read_text(encoding="utf-8"))


def sandbox_selfcheck() -> bool:
    """Prove the sandbox: hostile payloads must fail, benign data must parse.
    Called by run_tests.py - a regression here blocks the ship."""
    benign = parse_savedvars_text('HelpMeDB = { ["version"] = 1, ["chars"] = {} }')
    if benign.get("version") != 1:
        return False
    hostile_payloads = [
        'HelpMeDB = {} os.remove("x")',
        'HelpMeDB = {} io.open("x")',
        'HelpMeDB = {} python.eval("1+1")',
        'HelpMeDB = {} require("os")',
        'HelpMeDB = {} load("return 1")()',
    ]
    for payload in hostile_payloads:
        try:
            parse_savedvars_text(payload)
            return False  # payload executed without error = sandbox hole
        except (lupa.LuaError, ValueError):
            pass
    return True


def load_generated() -> dict:
    lua = lupa.LuaRuntime()
    load_chunk = lua.eval("function(src, name) local c = assert(load(src, '@'..name)); return c() end")
    for name in ("build", "talent_tabs", "talents", "talent_impacts", "spells"):
        f = GENERATED / f"{name}.lua"
        load_chunk(f.read_text(encoding="utf-8"), f.name)
    return lua_to_py(lua.globals().HelpMe.gen)


NUM_RE = re.compile(r"(\d+\.?\d*)")


def analyze_rank_rule(probe: dict, gen: dict) -> dict:
    """Compare in-game tooltip numbers against generated maxValue under each hypothesis.

    A: stored value is the max-rank total  -> tooltip at rank R shows |v| * R / maxRank
    B: stored value is the per-rank value  -> tooltip at rank R shows |v| * R
    Values may be ms in data but seconds in tooltips, so /1000 variants are included.
    """
    talents_by_name = {}
    for tid, t in (gen.get("talents") or {}).items():
        talents_by_name.setdefault(t["name"], (tid, t))

    votes = {"A": 0, "B": 0, "either": 0, "none": 0}
    details = []
    for entry in probe.get("talents", []):
        rank = entry.get("rank") or 0
        if rank == 0:
            continue  # untrained talents often show rank-1 text; only trained ranks vote
        match = talents_by_name.get(entry["name"])
        if not match:
            continue
        tid, talent = match
        impacts = (gen.get("talentImpacts") or {}).get(tid) or {}
        tooltip_nums = {float(n) for n in NUM_RE.findall(entry.get("tooltip", ""))}
        for op in impacts.get("ops", []):
            v = abs(op.get("maxValue") or 0)
            if v == 0 or not tooltip_nums:
                continue
            max_rank = talent["maxRank"]
            pred_a = {round(v * rank / max_rank, 2), round(v / 1000 * rank / max_rank, 2)}
            pred_b = {round(v * rank, 2), round(v / 1000 * rank, 2)}
            hit_a = bool(pred_a & tooltip_nums)
            hit_b = bool(pred_b & tooltip_nums)
            if hit_a and hit_b:
                votes["either"] += 1
            elif hit_a:
                votes["A"] += 1
                details.append(f"A: {entry['name']} r{rank}/{max_rank} v={v}")
            elif hit_b:
                votes["B"] += 1
                details.append(f"B: {entry['name']} r{rank}/{max_rank} v={v}")
            else:
                votes["none"] += 1
    return {"votes": votes, "details": details}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow-root", action="append", type=Path, default=None)
    args = parser.parse_args()
    roots = args.wow_root or DEFAULT_ROOTS

    files = find_savedvars(roots)
    if not files:
        print("no HelpMe SavedVariables found - log out of the game at least once")
        return 1

    COLLECTED.mkdir(exist_ok=True)
    gen = load_generated()
    exit_code = 0
    for path in files:
        data = parse_savedvars(path)
        account = path.parent.parent.name
        stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(path.stat().st_mtime))
        dest = COLLECTED / f"harvest-{account.replace('#', '_')}-{stamp}.json"
        dest.write_text(json.dumps(data, indent=2), encoding="utf-8")

        collect = data.get("collect") or {}
        sessions = collect.get("sessions") or []
        levels = collect.get("levels") or []
        verify = collect.get("verify") or {}
        probe = collect.get("talentProbe") or {}
        print(f"\n== {path}")
        print(f"   archived -> {dest.name}")
        print(f"   sessions={len(sessions)} level-ups journaled={len(levels)} "
              f"reports={len(data.get('reports') or [])}")
        if verify:
            fails = [r for r in verify.get("results", []) if not r.get("ok")]
            print(f"   verify@{verify.get('at')}: {len(verify.get('results', []))} checks, "
                  f"{len(fails)} flagged")
            for r in fails:
                print(f"     CHECK {r['name']}: {r.get('detail')}")
        if probe:
            analysis = analyze_rank_rule(probe, gen)
            print(f"   talent tooltip probe: {len(probe.get('talents', []))} talents; "
                  f"rank-rule votes: {analysis['votes']}")
            for d in analysis["details"][:10]:
                print(f"     {d}")
        if not verify and not probe:
            print("   no verify/probe data yet - run /helpme verify in-game, then log out")
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
