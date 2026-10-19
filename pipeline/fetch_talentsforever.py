"""Fetch the talentsforever.com per-class JSON exports and generate tf_talents.lua.

CREDIT: the per-rank talent text is from talentsforever.com - a fan-made WoW Forever talent
calculator whose talents/racials/Legacy perks/spellbooks are read from the WoW Forever beta
client's own data files. We ingest their per-rank tooltip TEXT (the `desc` array, rank 1 first)
as the authoritative display until the live client verifies it at launch; `confirmed` lists the
ranks whose text is real (not estimated). The site is an ongoing/growing export - re-run with
--force to refresh. This is OFFLINE tooling; nothing here ships except the generated Lua.

Usage: python pipeline/fetch_talentsforever.py [--force]
"""

from __future__ import annotations

import json
import sys
import urllib.request
from pathlib import Path

CREDIT = "talentsforever.com"
CLASSES = {  # url slug -> class token
    "warrior": "WARRIOR", "paladin": "PALADIN", "hunter": "HUNTER", "rogue": "ROGUE",
    "priest": "PRIEST", "shaman": "SHAMAN", "mage": "MAGE", "warlock": "WARLOCK",
    "druid": "DRUID",
}
BASE = "https://talentsforever.com/export/{}.json"
ROOT = Path(__file__).parent
CACHE = ROOT / "cache" / "talentsforever"
OUT = ROOT.parent / "Foresight" / "data" / "generated" / "tf_talents.lua"


def fetch(slug: str, force: bool) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / f"{slug}.json"
    if dest.exists() and not force:
        return json.loads(dest.read_text(encoding="utf-8"))
    try:
        req = urllib.request.Request(BASE.format(slug), headers={"User-Agent": "foresight-pipeline"})
        raw = urllib.request.urlopen(req, timeout=30).read().decode("utf-8")
        parsed = json.loads(raw)  # validate BEFORE overwriting the cache
        dest.write_text(raw, encoding="utf-8")
        return parsed
    except Exception:
        if dest.exists():  # a --force refetch that fails falls back to the cached copy
            print(f"fetch failed for {slug}; using the cached copy")
            return json.loads(dest.read_text(encoding="utf-8"))
        raise


# Spellbook/proficiency names too generic to count as a cross-reference ("Attack" matches
# "Attack Power" in half the descriptions).
STOP_NAMES = {
    "attack", "shoot", "throw", "block", "dodge", "parry", "languages", "language",
    "shoot bow", "shoot gun", "shoot crossbow", "armor proficiency", "dual wield",
}


def _known_names(d: dict) -> set[str]:
    """Every spell + talent name this class export knows (mention-match vocabulary)."""
    names: set[str] = set()

    def add(n):
        if isinstance(n, str) and len(n) >= 5 and n.lower() not in STOP_NAMES:
            names.add(n)

    def walk(o):
        if isinstance(o, dict):
            add(o.get("name"))
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            # spellbook spells are ["Name", "Rank N"] PAIRS, not dicts
            if 1 <= len(o) <= 2 and isinstance(o[0], str) \
                    and (len(o) == 1 or isinstance(o[1], str)):
                add(o[0])
            else:
                for v in o:
                    walk(v)

    walk(d.get("spellbook") or {})
    for tree in (d.get("talents") or {}).get("trees", []) or []:
        for t in tree.get("talents", []) or []:
            n = t.get("name")
            if isinstance(n, str) and len(n) >= 5:
                names.add(n)
    return names


def extract_links(d: dict) -> dict[str, list[str]]:
    """talentName -> other spell/talent names its rank-1 description mentions.

    The cross-impact map (owner ask 2026-10-19): which abilities/talents a talent touches,
    straight from the authoritative per-rank text. Longest-match wins (so "Lesser Healing
    Wave" isn't also counted as "Healing Wave"); a talent never links to itself.
    """
    import re as _re
    known = sorted(_known_names(d), key=len, reverse=True)
    pats = [(n, _re.compile(r"(?<![A-Za-z])" + _re.escape(n) + r"(?![A-Za-z])", _re.I))
            for n in known]
    out: dict[str, list[str]] = {}
    for tree in (d.get("talents") or {}).get("trees", []) or []:
        for t in tree.get("talents", []) or []:
            name, desc = t.get("name"), t.get("desc") or []
            if not (name and desc):
                continue
            text = desc[0]
            taken: list[tuple[int, int]] = []  # claimed spans, longest names first
            links: list[str] = []
            for n, pat in pats:
                if n.lower() == str(name).lower():
                    continue
                m = pat.search(text)
                if not m:
                    continue
                if any(m.start() >= s and m.end() <= e for s, e in taken):
                    continue  # inside an already-claimed longer name
                taken.append((m.start(), m.end()))
                links.append(n)
            if links:
                out[name] = sorted(links)
    return out


def lua(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(int(v) if isinstance(v, float) and v.is_integer() else v)
    if isinstance(v, str):
        # "|" starts a WoW FontString escape sequence ("|cff...", "|T...") - third-party text
        # must render literally in GameTooltip, so escape it as "||".
        return ('"' + v.replace("\\", "\\\\").replace('"', '\\"')
                .replace("\n", "\\n").replace("\r", "").replace("|", "||") + '"')
    if isinstance(v, list):
        return "{" + ",".join(lua(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(f"[{lua(k)}]={lua(val)}" for k, val in v.items()) + "}"
    raise TypeError(type(v))


def main() -> int:
    force = "--force" in sys.argv
    out = {}
    total = 0
    for slug, token in CLASSES.items():
        try:
            d = fetch(slug, force)
        except Exception as e:  # noqa: BLE001 - network/parse failure degrades that class
            print(f"SKIP {slug}: {e}")
            continue
        tals = {}
        links = extract_links(d)
        for tree in (d.get("talents") or {}).get("trees", []) or []:
            for t in tree.get("talents", []) or []:
                name, desc = t.get("name"), t.get("desc") or []
                if name and desc:
                    tals[name] = {
                        "max": t.get("max", len(desc)),
                        "desc": desc,
                        "confirmed": t.get("confirmed", []),
                    }
                    if links.get(name):
                        tals[name]["links"] = links[name]
        out[token] = tals
        total += len(tals)
        print(f"{token:8s} {len(tals)} talents")

    # ALL NINE or refuse: a partial write silently regresses shipped data with exit 0
    # (audit 2026-10-16). A failed class must fail the run, not degrade the file.
    missing = [t for t in CLASSES.values() if not out.get(t)]
    if missing:
        print(f"ERROR: missing/empty classes {missing} - NOT writing {OUT}")
        return 1

    header = [
        "-- GENERATED by pipeline/fetch_talentsforever.py - DO NOT EDIT.",
        f"-- CREDIT: per-rank talent text from {CREDIT} (fan-made WoW Forever talent calculator,",
        "-- read from the Forever beta client's own data files). Ingested as the authoritative",
        "-- per-rank display until the live client verifies at launch; 'confirmed' = real ranks.",
        "local _, HM = ...",
        "if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end",
        "HM.gen = HM.gen or {}",
        f"HM.gen.tfCredit = {lua(CREDIT)}",
        f"HM.gen.tfTalents = {lua(out)}",
    ]
    OUT.write_text("\n".join(header) + "\n", encoding="utf-8")
    print(f"\nwrote {total} talents across {len(out)} classes -> {OUT} ({OUT.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
