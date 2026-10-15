#!/usr/bin/env python3
"""Push the maintainer's play-verified rank rules to the Firebase `verifiedRules` collection.

The owner verifies rank scaling simply by PLAYING - hovering talents on their own tree and
inspecting other players captures tooltips into ForesightDB. This tool reads that local
SavedVariables file (through harvest.py's NEUTERED sandbox - SavedVariables is untrusted
input), votes each talent's rank rule with the SAME analyzer the crowd harvest uses, keeps
only TRAINED-BACKED decisions, and writes them to `verifiedRules`. The addon then bakes that
collection (pipeline/fetch_verified.py) so a fresh character gets the rules without scanning.

Owner fast lane, by design: `verifiedRules` is write:false in the Firestore rules, so no
client can touch it. This tool authenticates as the project owner with a gcloud OAuth token
(server-to-server bypasses the rules, exactly like fetch_baselines.py). NO service-account
key lives in the repo. Crowd votes still reach rank rules only through the reviewed overrides
path (harvest -> rank_rules_draft.lua -> human PR); this table is the owner/crowd layer
BENEATH the hand-curated overrides.rankRules.

Account-safety: offline maintainer tooling only. Never ships, never touches the game.

Usage:
    gcloud auth login                       # once, if the token has expired
    python pipeline/push_verified.py                # DRY RUN (default): show what would push
    python pipeline/push_verified.py --write        # push after reviewing the dry run
    python pipeline/push_verified.py --wow-root "C:/Program Files/World of Warcraft"
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

import harvest
from fetch_baselines import access_token

DEFAULT_PROJECT = "wow-foresight"
DOC = ("https://firestore.googleapis.com/v1/projects/{project}"
       "/databases/(default)/documents/verifiedRules/{tid}")


def collect_votes(gen: dict, roots: list[Path]) -> tuple[dict, int, int]:
    """Merge rank-rule votes across the owner's same-build characters.
    Returns (merged by-talent tallies, characters contributing, foreign-build skipped)."""
    files = harvest.find_savedvars(roots)
    merged: dict = {}
    chars = 0
    skipped_foreign = 0
    for path in files:
        data = harvest.parse_savedvars(path)
        if not harvest.archive_matches_build(data, gen):
            skipped_foreign += 1
            continue
        collect = data.get("collect") or {}
        contributed = False
        for probe in (harvest.probe_from_tooltips(collect.get("talentTooltips") or {}),
                      collect.get("talentProbe") or {}):
            if probe.get("talents"):
                harvest.merge_by_talent(merged, harvest.analyze_rank_rule(probe, gen)["byTalent"])
                contributed = True
        if contributed:
            chars += 1
    return merged, chars, skipped_foreign


def decide_pushable(merged: dict) -> tuple[list, list]:
    """(pushable, skipped). Only TRAINED-BACKED decisions ship to the owner table; an
    untrained-r1-text decision is too weak to be called 'verified' and is listed as skipped."""
    pushable, skipped = [], []
    for tid, slot in sorted(merged.items(), key=lambda kv: int(kv[0])):
        rule, basis = harvest.decide_rank_rule(slot)
        tr = slot["trained"]
        n = tr["A"] + tr["B"] + tr["either"]
        if rule and "untrained" not in basis:
            pushable.append({"tid": int(tid), "name": slot.get("name"), "rule": rule,
                             "n": n, "basis": basis})
        elif rule:
            skipped.append((tid, slot.get("name"), f"{basis} - hover it TRAINED to confirm"))
        elif "contradicted" in (basis or ""):
            skipped.append((tid, slot.get("name"), basis))
    return pushable, skipped


def write_doc(project: str, token: str, entry: dict, build: str) -> None:
    url = DOC.format(project=project, tid=entry["tid"])
    body = {"fields": {
        "rule": {"stringValue": entry["rule"]},
        "n": {"integerValue": str(entry["n"])},
        "basis": {"stringValue": "owner"},
        "build": {"stringValue": build},
    }}
    req = urllib.request.Request(
        url, data=json.dumps(body).encode("utf-8"), method="PATCH",
        headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as resp:
        resp.read()


def read_back(project: str, token: str, tid: int) -> dict | None:
    url = DOC.format(project=project, tid=tid)
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError:
        return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--project", default=DEFAULT_PROJECT)
    ap.add_argument("--wow-root", action="append", type=Path, default=None)
    ap.add_argument("--write", action="store_true",
                    help="actually push (default is a safe dry run that writes nothing)")
    args = ap.parse_args()
    roots = args.wow_root or harvest.DEFAULT_ROOTS

    gen = harvest.load_generated()
    build = str(gen.get("build") or harvest.shipped_version() or "?")
    merged, chars, foreign = collect_votes(gen, roots)
    if not merged:
        print("no talent captures found - hover talents in-game (and inspect other players), "
              "log out to flush SavedVariables, then retry.")
        return 1
    pushable, skipped = decide_pushable(merged)

    print(f"build {build} | {chars} character(s) scanned"
          + (f" | {foreign} foreign-build file(s) skipped" if foreign else ""))
    print(f"{len(pushable)} trained-backed rule(s) to push, {len(skipped)} skipped:\n")
    for e in pushable:
        print(f"  [{e['tid']}] {e['name']}: {e['rule']}  (n={e['n']}, {e['basis']})")
    for tid, name, why in skipped:
        print(f"  -- skip [{tid}] {name}: {why}")

    if not pushable:
        print("\nnothing trained-backed to push yet.")
        return 0
    if not args.write:
        print(f"\nDRY RUN - nothing written. Re-run with --write to push {len(pushable)} "
              f"rule(s) to verifiedRules, then bake with pipeline/fetch_verified.py.")
        return 0

    token = access_token()
    print()
    written = 0
    for e in pushable:
        write_doc(args.project, token, e, build)
        back = read_back(args.project, token, e["tid"])
        got = (((back or {}).get("fields") or {}).get("rule") or {}).get("stringValue")
        if got != e["rule"]:
            print(f"  FAIL [{e['tid']}] {e['name']}: wrote {e['rule']} but read back {got!r}")
            return 1
        written += 1
        print(f"  ok   [{e['tid']}] {e['name']}: {e['rule']} (verified)")
    print(f"\npushed + read-back-verified {written} rule(s). Now run "
          f"`python pipeline/fetch_verified.py` to bake them into the addon.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
