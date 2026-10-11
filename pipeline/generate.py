"""Generate Foresight addon Lua data tables from cached Forever DB2 CSVs.

Usage: python generate.py [--build 1.60.1.70338]

Reads pipeline/cache/<build>/*.csv, computes the talent -> affected-spells mapping via
spell-family class masks (the same mechanism the game engine uses), and writes Lua tables
to Foresight/data/generated/. Run fetch.py first.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import sys
from collections import defaultdict
from pathlib import Path

DEFAULT_BUILD = "1.60.1.70338"

# Classic-lineage SpellModOp ids -> human label + which ability property they move.
SPELL_MOD_OPS = {
    0: ("damage/healing", "pct_or_flat"),
    1: ("duration", "value"),
    2: ("threat", "value"),
    3: ("effect 1 value", "value"),
    4: ("charges", "value"),
    5: ("range", "value"),
    6: ("radius", "value"),
    7: ("crit chance", "value"),
    8: ("all effect values", "value"),
    9: ("cast pushback", "value"),
    10: ("cast time", "value"),
    11: ("cooldown", "value"),
    12: ("effect 2 value", "value"),
    14: ("resource cost", "value"),
    15: ("crit damage bonus", "value"),
    16: ("miss/resist chance", "value"),
    17: ("chain targets", "value"),
    18: ("proc chance", "value"),
    19: ("activation time", "value"),
    20: ("chain amplitude", "value"),
    21: ("global cooldown", "value"),
    22: ("periodic damage/healing", "value"),
    23: ("effect 3 value", "value"),
    24: ("bonus multiplier", "value"),
    26: ("procs per minute", "value"),
    27: ("value multiplier", "value"),
    28: ("dispel resist chance", "value"),
}

# Non-spellmod auras we interpret as character-level modifiers.
AURA_LABELS = {
    13: "school damage done (flat)",
    79: "school damage done (%)",
    135: "healing done (flat)",
    29: "stat (flat)",
    137: "stat (%)",
    85: "mana regen (flat)",
    234: "silence duration reduction",
    57: "spell crit chance",
    52: "melee crit chance",
    108: "spell modifier (%)",
    107: "spell modifier (flat)",
}

STAT_NAMES = {-1: "all stats", 0: "Strength", 1: "Agility", 2: "Stamina", 3: "Intellect", 4: "Spirit"}
STAT_BITS = {1: "Strength", 2: "Agility", 4: "Stamina", 8: "Intellect", 16: "Spirit"}


def stat_label(misc0: int, misc1: int) -> str:
    """Decode which stat a stat-aura moves. Modern-format clients (Forever build
    1.60.1.x) encode it as a BITMASK in EffectMiscValue_1 (1<<statIndex; 31 = all five;
    verified against talent tooltips: Ancestral Knowledge misc1=8 -> Intellect, Toughness
    4 -> Stamina, Blessing of Kings 31 -> all). MiscValue_0 as an index is the legacy
    encoding, still used when misc1 is 0 (e.g. Divine Spirit, Demonic Embrace's Spirit op)."""
    if misc1:
        names = [name for bit, name in STAT_BITS.items() if misc1 & bit]
        if len(names) == len(STAT_BITS):
            return "all stats"
        if len(names) == 1:
            return names[0]
        return "/".join(names) if names else f"statmask:{misc1}"
    return STAT_NAMES.get(misc0, f"stat:{misc0}")
SCHOOL_NAMES = {1: "Physical", 2: "Holy", 4: "Fire", 8: "Nature", 16: "Frost", 32: "Shadow", 64: "Arcane"}

CLASS_NAMES = {
    1: "Warrior", 2: "Paladin", 3: "Hunter", 4: "Rogue", 5: "Priest",
    7: "Shaman", 8: "Mage", 9: "Warlock", 11: "Druid",
}


def read_csv(cache: Path, table: str) -> list[dict]:
    with open(cache / f"{table}.csv", newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_int(value: str) -> int:
    if value in ("", None):
        return 0
    return int(float(value))


def lua_escape(text: str) -> str:
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")


def school_label(mask: int) -> str:
    names = [name for bit, name in SCHOOL_NAMES.items() if mask & bit]
    return "/".join(names) if names else f"school:{mask}"


def build_ops(first, effects_by_spell, class_options, family_members, player_spells):
    """Derive impact ops from a passive/modifier spell's SpellEffect rows. Shared by
    classic talents and Retail trait nodes - the same aura/spell-mod decoding either way.
    Forever stores multi-rank values only on the rank-1 spell as the max-rank total."""
    ops = []
    fam = class_options.get(first)
    for eff in effects_by_spell.get(first, []):
        aura = to_int(eff["EffectAura"])
        misc0 = to_int(eff["EffectMiscValue_0"])
        misc1 = to_int(eff["EffectMiscValue_1"])
        masks = tuple(to_int(eff[f"EffectSpellClassMask_{i}"]) for i in range(4))
        op = {
            "aura": aura,
            "maxValue": float(eff["EffectBasePointsF"] or 0),
            "rankRule": "linearToMax-presumed",
        }
        if aura in (107, 108):
            label, _ = SPELL_MOD_OPS.get(misc0, (f"mod-op:{misc0}", "value"))
            op["kind"] = "spellmod"
            op["property"] = label
            op["isPct"] = aura == 108
            affected = []
            if fam and any(masks):
                for sid, smask in family_members[fam[0]]:
                    if sid in player_spells and any(masks[i] & smask[i] for i in range(4)):
                        affected.append(sid)
            op["affected"] = sorted(affected)
        elif aura == 13 or aura == 79:
            op["kind"] = "schoolDamage"
            op["isPct"] = aura == 79
            op["school"] = school_label(misc0)
        elif aura in (29, 137):
            op["kind"] = "stat"
            op["isPct"] = aura == 137
            op["stat"] = stat_label(misc0, misc1)
        elif aura == 10:
            # SPELL_AURA_MOD_THREAT: misc0 is a school mask, value is the threat %
            # modifier (negative = reduction). Ground-truthed against tooltips:
            # Subtlety 72 = Nature/Arcane, Silent Resolve 2 = Holy, Frost Chan. 16 = Frost.
            op["kind"] = "threat"
            op["isPct"] = True
            all_schools = misc0 != 0 and (misc0 & 126) == 126  # all magic (or +physical)
            schools = school_label(misc0)
            op["school"] = "all" if all_schools else schools
            op["property"] = "threat" if all_schools else f"threat ({schools})"
        elif aura in AURA_LABELS:
            op["kind"] = "aura"
            op["label"] = AURA_LABELS[aura]
        elif aura == 0:
            continue  # non-aura effect (e.g. learn/trigger); not a passive modifier
        else:
            op["kind"] = "unmapped"
        ops.append(op)
    return ops


class LuaWriter:
    """Minimal Lua table serializer for our generated data shapes."""

    @staticmethod
    def value(v) -> str:
        if isinstance(v, bool):
            return "true" if v else "false"
        if isinstance(v, (int, float)):
            if isinstance(v, float) and v.is_integer():
                v = int(v)
            return repr(v)
        if isinstance(v, str):
            return f'"{lua_escape(v)}"'
        if isinstance(v, list):
            return "{" + ",".join(LuaWriter.value(x) for x in v) + "}"
        if isinstance(v, dict):
            parts = []
            for k in sorted(v, key=str):
                key = f"[{k}]" if isinstance(k, int) else k
                parts.append(f"{key}={LuaWriter.value(v[k])}")
            return "{" + ",".join(parts) + "}"
        raise TypeError(f"unsupported: {type(v)}")

    @staticmethod
    def file(module: str, payload: dict, out_dir: Path, build: str) -> Path:
        lines = [
            f"-- GENERATED by pipeline/generate.py from client build {build} - DO NOT EDIT.",
            "local _, HM = ...",
            "if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end",
            "HM.gen = HM.gen or {}",
        ]
        for key, val in payload.items():
            lines.append(f"HM.gen.{key} = {LuaWriter.value(val)}")
        dest = out_dir / f"{module}.lua"
        dest.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return dest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", default=DEFAULT_BUILD)
    args = parser.parse_args()

    root = Path(__file__).parent
    cache = root / "cache" / args.build
    out_dir = root.parent / "Foresight" / "data" / "generated"
    out_dir.mkdir(parents=True, exist_ok=True)

    spell_names = {to_int(r["ID"]): r["Name_lang"] for r in read_csv(cache, "SpellName")}
    spell_desc = {to_int(r["ID"]): r["Description_lang"] for r in read_csv(cache, "Spell")}

    # Spell family data: SpellClassSet groups a class's spells; masks pick spells within it.
    class_options = {}
    family_members = defaultdict(list)  # SpellClassSet -> [(spellID, mask0..3)]
    for r in read_csv(cache, "SpellClassOptions"):
        sid = to_int(r["SpellID"])
        entry = (
            to_int(r["SpellClassSet"]),
            (to_int(r["SpellClassMask_0"]), to_int(r["SpellClassMask_1"]),
             to_int(r["SpellClassMask_2"]), to_int(r["SpellClassMask_3"])),
        )
        class_options[sid] = entry
        family_members[entry[0]].append((sid, entry[1]))

    effects_by_spell = defaultdict(list)
    for r in read_csv(cache, "SpellEffect"):
        if to_int(r["DifficultyID"]) == 0:
            effects_by_spell[to_int(r["SpellID"])].append(r)

    # Player-learnable spells: abilities on class skill lines (SkillLine CategoryID 7).
    skill_lines = {to_int(r["ID"]): r for r in read_csv(cache, "SkillLine")}
    class_lines = {sid for sid, r in skill_lines.items() if to_int(r.get("CategoryID", "0")) == 7}
    player_spells = set()
    for r in read_csv(cache, "SkillLineAbility"):
        if to_int(r["SkillLine"]) in class_lines:
            player_spells.add(to_int(r["Spell"]))

    cast_times = {to_int(r["ID"]): to_int(r["Base"]) for r in read_csv(cache, "SpellCastTimes")}
    durations = {to_int(r["ID"]): to_int(r["Duration"]) for r in read_csv(cache, "SpellDuration")}
    misc = {to_int(r["SpellID"]): r for r in read_csv(cache, "SpellMisc") if to_int(r["DifficultyID"]) == 0}
    levels = {to_int(r["SpellID"]): r for r in read_csv(cache, "SpellLevels") if to_int(r["DifficultyID"]) == 0}
    cooldowns = {to_int(r["SpellID"]): r for r in read_csv(cache, "SpellCooldowns") if to_int(r["DifficultyID"]) == 0}
    powers = defaultdict(list)
    for r in read_csv(cache, "SpellPower"):
        powers[to_int(r["SpellID"])].append(r)

    # ---- Talent tabs ----------------------------------------------------------
    tabs_out = {}
    for r in read_csv(cache, "TalentTab"):
        tab_id = to_int(r["ID"])
        tabs_out[tab_id] = {
            "name": r["Name_lang"],
            "classMask": to_int(r["ClassMask"]),
            "order": to_int(r["OrderIndex"]),
        }

    # ---- Talents + impact computation ----------------------------------------
    talents_out, impacts_out = {}, {}
    needs_curation = 0
    for r in read_csv(cache, "Talent"):
        tid = to_int(r["ID"])
        ranks = [to_int(r[f"SpellRank_{i}"]) for i in range(9)]
        ranks = [s for s in ranks if s]
        if not ranks:
            continue
        first = ranks[0]
        prereqs = []
        for i in range(3):
            pt = to_int(r[f"PrereqTalent_{i}"])
            if pt:
                prereqs.append({"talent": pt, "rank": to_int(r[f"PrereqRank_{i}"]) + 1})
        talents_out[tid] = {
            "name": spell_names.get(first, f"talent:{tid}"),
            "tab": to_int(r["TabID"]),
            "tier": to_int(r["TierID"]),
            "column": to_int(r["ColumnIndex"]),
            "classId": to_int(r["ClassID"]),
            "maxRank": len(ranks),
            "spellRanks": ranks,
            "descByRank": [spell_desc.get(s, "") for s in ranks],
            "prereqs": prereqs,
        }

        # Impact ops from the rank-1 spell. Forever stores effect values ONLY on rank 1
        # (verified against the client data: rank-2+ talent spells have no SpellEffect
        # rows), and the stored value matches the classic MAX-RANK total. Rank scaling is
        # therefore presumed linear (rank N = value * N / maxRank) until verified in-game;
        # the addon surfaces this flag and the probe/beta check confirms or corrects it.
        ops = build_ops(first, effects_by_spell, class_options, family_members, player_spells)

        if not ops or all(o.get("kind") == "unmapped" for o in ops):
            needs_curation += 1
            impacts_out[tid] = {"ops": ops, "needsCuration": True}
        else:
            impacts_out[tid] = {"ops": ops}

    # ---- Player spell metadata (mechanics the graph consumes) -----------------
    talent_spells = {s for t in talents_out.values() for s in t["spellRanks"]}
    affected_spells = {
        sid for imp in impacts_out.values() for op in imp["ops"] for sid in op.get("affected", [])
    }
    ship_spells = (player_spells | talent_spells | affected_spells) & set(spell_names)
    spells_out = {}
    for sid in sorted(ship_spells):
        m = misc.get(sid)
        entry = {"name": spell_names[sid]}
        if m:
            entry["school"] = to_int(m["SchoolMask"])
            ct = cast_times.get(to_int(m["CastingTimeIndex"]))
            if ct:
                entry["castMs"] = ct
            dur = durations.get(to_int(m["DurationIndex"]))
            if dur and dur > 0:
                entry["durationMs"] = dur
        lv = levels.get(sid)
        if lv and to_int(lv["SpellLevel"]):
            entry["level"] = to_int(lv["SpellLevel"])
        cd = cooldowns.get(sid)
        if cd and to_int(cd["RecoveryTime"]):
            entry["cooldownMs"] = to_int(cd["RecoveryTime"])
        for p in powers.get(sid, []):
            if to_int(p["ManaCost"]):
                entry["cost"] = to_int(p["ManaCost"])
                entry["powerType"] = to_int(p["PowerType"])
            elif float(p["PowerCostPct"] or 0) > 0:
                entry["costPctBase"] = float(p["PowerCostPct"])
                entry["powerType"] = to_int(p["PowerType"])
        ticks = [to_int(e["EffectAuraPeriod"]) for e in effects_by_spell.get(sid, []) if to_int(e["EffectAuraPeriod"])]
        if ticks:
            entry["tickMs"] = min(ticks)
        spells_out[sid] = entry

    # ---- Traits (Retail node trees = the LIVE talent system on Forever) -------
    # Chain: TraitNode -> (TraitNodeXTraitNodeEntry) -> TraitNodeEntry -> TraitDefinition
    # -> SpellID. That SpellID is exactly what the in-game C_Traits walk returns, so this
    # covers EVERY live node - new Forever talents and baseline passives, not just the
    # classic-overlap talents. Impact ops come from the definition spell's SpellEffect
    # rows via the same build_ops() used for classic talents.
    def read_opt(name):
        try:
            return read_csv(cache, name)
        except FileNotFoundError:
            return []

    trait_defs = {to_int(r["ID"]): r for r in read_opt("TraitDefinition")}
    trait_entries = {to_int(r["ID"]): r for r in read_opt("TraitNodeEntry")}
    node_entry_links = defaultdict(list)
    for r in read_opt("TraitNodeXTraitNodeEntry"):
        node_entry_links[to_int(r["TraitNodeID"])].append(
            (to_int(r["_Index"]), to_int(r["TraitNodeEntryID"])))
    tree_skill = {to_int(r["TraitTreeID"]): to_int(r["SkillLineID"])
                  for r in read_opt("SkillLineXTraitTree")}

    trait_nodes, trait_by_spell = {}, {}
    trait_curation = 0
    for r in read_opt("TraitNode"):
        nid = to_int(r["ID"])
        entries = []
        for _idx, eid in sorted(node_entry_links.get(nid, [])):
            entry = trait_entries.get(eid)
            defrow = entry and trait_defs.get(to_int(entry["TraitDefinitionID"]))
            sid = defrow and to_int(defrow["SpellID"])
            if not sid:
                continue
            entries.append({
                "spellID": sid,
                "maxRank": to_int(entry["MaxRanks"]) or 1,
                "name": (defrow.get("OverrideName_lang") or "").strip()
                        or spell_names.get(sid, f"spell:{sid}"),
            })
        if not entries:
            continue
        primary = entries[0]
        ops = build_ops(primary["spellID"], effects_by_spell, class_options,
                        family_members, player_spells)
        node = {
            "tree": to_int(r["TraitTreeID"]), "type": to_int(r["Type"]),
            "spellID": primary["spellID"], "name": primary["name"],
            "maxRank": primary["maxRank"], "ops": ops,
        }
        if len(entries) > 1:
            node["entries"] = entries  # choice node: multiple selectable spells
        if not ops or all(o.get("kind") == "unmapped" for o in ops):
            node["needsCuration"] = True
            trait_curation += 1
        trait_nodes[nid] = node
        for e in entries:
            trait_by_spell.setdefault(e["spellID"], nid)

    traits_out = {
        "nodes": trait_nodes,
        "bySpell": trait_by_spell,
        "trees": {t: {"skillLine": s} for t, s in tree_skill.items()},
    }

    # ---- Emit ------------------------------------------------------------------
    stamp = dt.date.today().isoformat()
    written = [
        LuaWriter.file("build", {
            "build": args.build,
            "generated": stamp,
            "counts": {
                "talents": len(talents_out),
                "tabs": len(tabs_out),
                "spells": len(spells_out),
                "impactsNeedingCuration": needs_curation,
                "traitNodes": len(trait_nodes),
                "traitNodesNeedingCuration": trait_curation,
            },
            "classNames": CLASS_NAMES,
        }, out_dir, args.build),
        LuaWriter.file("talent_tabs", {"talentTabs": tabs_out}, out_dir, args.build),
        LuaWriter.file("talents", {"talents": talents_out}, out_dir, args.build),
        LuaWriter.file("talent_impacts", {"talentImpacts": impacts_out}, out_dir, args.build),
        LuaWriter.file("spells", {"spells": spells_out}, out_dir, args.build),
        LuaWriter.file("traits", {"traits": traits_out}, out_dir, args.build),
    ]
    for path in written:
        print(f"wrote {path.relative_to(root.parent)} ({path.stat().st_size:,} bytes)")
    print(f"\ntalents={len(talents_out)} tabs={len(tabs_out)} spells shipped={len(spells_out)} "
          f"trait nodes={len(trait_nodes)} talents needing curation={needs_curation}/{len(talents_out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
