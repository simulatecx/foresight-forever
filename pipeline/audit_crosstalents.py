"""Cross-impact audit: how talents/skills impact one another - JSON text vs our decode.

Owner ask (2026-10-19): "we have the synergies - we need how all talents/skills impact one
another - do an audit since we have the json." For every talent in all 9 classes this
compares two views of its cross-references:
  TEXT view  - the spells/talents its authoritative per-rank description MENTIONS
               (talentsforever.com export, extract_links in fetch_talentsforever.py);
  MODEL view - the spells our DB2 op decode actually LINKS (op.affected spell IDs in
               forever_talents.lua, plus prereq edges).
A mention the model doesn't cover = a modeling gap: the tooltip can SAY it (the tf text +
links line) but the impact engine can't FOLD it yet. The gap list is the curation queue.

Writes pipeline/collected/crosstalent_audit.md (+ .json). Read-only; never ships.
Usage: python pipeline/audit_crosstalents.py [--build X]
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

from fetch_talentsforever import CLASSES, extract_links

ROOT = Path(__file__).parent
TF_CACHE = ROOT / "cache" / "talentsforever"
OUT_DIR = ROOT / "collected"
FOREVER_LUA = ROOT.parent / "Foresight" / "data" / "generated" / "forever_talents.lua"
DEFAULT_BUILD = "1.60.1.70532"

CLASS_IDS = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 3, "ROGUE": 4, "PRIEST": 5,
             "SHAMAN": 7, "MAGE": 8, "WARLOCK": 9, "DRUID": 11}


def spell_names(build: str) -> dict[int, str]:
    path = ROOT / "cache" / build / "SpellName.csv"
    out = {}
    with open(path, newline="", encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            try:
                out[int(row["ID"])] = row["Name_lang"]
            except (KeyError, ValueError):
                continue
    return out


def parse_forever() -> dict[int, dict]:
    """forever_talents.lua -> {nodeId: {classId, name, affected:set[int], prereqs:set[int],
    ops:int, unmapped:int}}. Top-level entries are the only [N]={ in the file (int keys
    inside entries are lists, serialized without keys)."""
    src = FOREVER_LUA.read_text(encoding="utf-8")
    heads = [(m.start(), int(m.group(1))) for m in re.finditer(r"\[(\d+)\]=\{", src)]
    out: dict[int, dict] = {}
    for i, (pos, nid) in enumerate(heads):
        end = heads[i + 1][0] if i + 1 < len(heads) else len(src)
        chunk = src[pos:end]
        name_m = re.search(r'name="((?:[^"\\]|\\.)*)"', chunk)
        cid_m = re.search(r"classId=(\d+)", chunk)
        affected: set[int] = set()
        for ids in re.findall(r"affected=\{([0-9,]+)\}", chunk):
            affected.update(int(x) for x in ids.split(",") if x)
        prereqs = {int(x) for x in re.findall(r"talent=(\d+)", chunk)}
        out[nid] = {
            "classId": int(cid_m.group(1)) if cid_m else 0,
            "name": (name_m.group(1).replace('\\"', '"') if name_m else f"node:{nid}"),
            "affected": affected, "prereqs": prereqs,
            "ops": len(re.findall(r'kind="', chunk)),
            "unmapped": len(re.findall(r'kind="unmapped"', chunk)),
        }
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=DEFAULT_BUILD)
    args = parser.parse_args()

    names_by_id = spell_names(args.build)
    forever = parse_forever()
    by_class_name = defaultdict(dict)  # classId -> lower(name) -> entry
    for nid, e in forever.items():
        e["nid"] = nid
        by_class_name[e["classId"]][e["name"].lower()] = e

    totals = {"talents": 0, "withMentions": 0, "fullyCovered": 0, "partial": 0,
              "uncovered": 0, "mentions": 0, "coveredMentions": 0}
    rows_by_class: dict[str, list[dict]] = {}
    for slug, token in CLASSES.items():
        f = TF_CACHE / f"{slug}.json"
        if not f.exists():
            print(f"SKIP {token}: no tf cache")
            continue
        d = json.loads(f.read_text(encoding="utf-8"))
        links = extract_links(d)
        cid = CLASS_IDS[token]
        ours = by_class_name.get(cid, {})
        # this class's talent names (a mention of a TALENT is covered by a prereq edge)
        talent_names = {e["name"].lower(): e["nid"] for e in ours.values()}
        rows = []
        for tname, mentioned in sorted(links.items()):
            mine = ours.get(tname.lower())
            totals["talents"] += 1
            totals["withMentions"] += 1
            covered_names = set()
            if mine:
                for sid in mine["affected"]:
                    nm = names_by_id.get(sid)
                    if nm:
                        covered_names.add(nm.lower())
            gaps, hits = [], []
            for m in mentioned:
                totals["mentions"] += 1
                ml = m.lower()
                is_covered = ml in covered_names
                # a mentioned TALENT counts covered if a prereq edge links the two nodes
                if not is_covered and ml in talent_names and mine:
                    other = talent_names[ml]
                    if other in mine["prereqs"] or (mine["nid"] in
                            (ours.get(ml, {}).get("prereqs") or set())):
                        is_covered = True
                if is_covered:
                    totals["coveredMentions"] += 1
                    hits.append(m)
                else:
                    gaps.append(m)
            if not gaps:
                totals["fullyCovered"] += 1
            elif hits:
                totals["partial"] += 1
            else:
                totals["uncovered"] += 1
            rows.append({"talent": tname, "covered": hits, "gaps": gaps,
                         "unmappedOps": (mine or {}).get("unmapped", 0),
                         "ops": (mine or {}).get("ops", 0),
                         "inModel": mine is not None})
        rows_by_class[token] = rows

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "crosstalent_audit.json").write_text(
        json.dumps({"totals": totals, "classes": rows_by_class}, indent=1),
        encoding="utf-8")

    pct = (100 * totals["coveredMentions"] / totals["mentions"]) if totals["mentions"] else 0
    lines = [
        "# Cross-talent impact audit - text mentions vs model links",
        "",
        "For each talent: what its authoritative description MENTIONS (talentsforever.com)",
        "vs what our decoded ops actually LINK (op.affected / prereq edges). A gap means the",
        "tooltip can say it but the impact engine can't fold it - the curation queue.",
        "",
        f"**{totals['withMentions']}** talents carry cross-references · "
        f"**{totals['mentions']}** mentions total · "
        f"**{totals['coveredMentions']}** covered by the model ({pct:.0f}%) · "
        f"fully covered {totals['fullyCovered']} / partial {totals['partial']} / "
        f"uncovered {totals['uncovered']}",
        "",
    ]
    for token, rows in rows_by_class.items():
        gap_rows = [r for r in rows if r["gaps"]]
        lines.append(f"## {token} - {len(rows)} cross-referencing talents, "
                     f"{len(gap_rows)} with gaps")
        for r in sorted(gap_rows, key=lambda r: -len(r["gaps"])):
            flag = "" if r["inModel"] else " (NOT IN MODEL)"
            unm = f" · {r['unmappedOps']}/{r['ops']} ops unmapped" if r["unmappedOps"] else ""
            lines.append(f"- **{r['talent']}**{flag}{unm}")
            lines.append(f"  - gaps: {', '.join(r['gaps'])}")
            if r["covered"]:
                lines.append(f"  - covered: {', '.join(r['covered'])}")
        lines.append("")
    (OUT_DIR / "crosstalent_audit.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"mentions covered by the model: {totals['coveredMentions']}/{totals['mentions']}"
          f" ({pct:.0f}%) · talents fully covered {totals['fullyCovered']},"
          f" partial {totals['partial']}, uncovered {totals['uncovered']}")
    print(f"-> {OUT_DIR / 'crosstalent_audit.md'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
