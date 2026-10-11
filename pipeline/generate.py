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
import re
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
    # Label-only decodes (surface via tooltip/synergy; no fold - ground-truthed on the
    # racial rework tooltips 2026-10-11).
    49: "dodge chance",
    54: "hit chance",
    55: "spell hit chance",
    166: "attack power (%)",
    167: "ranged attack power (%)",
    317: "spell power (%)",
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


def races_for_masks(rm0: int, rm1: int, bit_to_race: dict) -> set:
    """Decode RaceMasks_0/_1 into ChrRaces IDs. The bit index is ChrRaces.PlayableRaceBit
    (verified this build: Human=0..Troll=7 in _0; the new Skyborne races 95/96 carry
    PlayableRaceBit 32/33 -> RaceMasks_1 bits 0/1, which is why the naive 1<<(ID-1)
    formula breaks for them). -1 masks (all races) normalize to the full word."""
    races = set()
    for base, mask in ((0, rm0 & 0xFFFFFFFF), (32, rm1 & 0xFFFFFFFF)):
        bit = 0
        while mask:
            if mask & 1 and (base + bit) in bit_to_race:
                races.add(bit_to_race[base + bit])
            mask >>= 1
            bit += 1
    return races


def build_ops(first, effects_by_spell, class_options, family_members, player_spells,
              equipped_items=None):
    """Derive impact ops from a passive/modifier spell's SpellEffect rows. Shared by
    classic talents, Retail trait nodes, racials, and consumable buffs - the same
    aura/spell-mod decoding everywhere. Forever stores multi-rank values only on the
    rank-1 spell as the max-rank total. equipped_items (spellID set from
    SpellEquippedItems) marks weapon/armor-conditional spells - their crit aura is
    label-only instead of foldable."""
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
        elif aura in (175, 174, 598):
            # Stat-CONVERSION auras (the chained-synergy primitive): a derived output
            # scales from a primary stat. 175 = spell damage, 174 = spell healing,
            # 598 = attack power; the SOURCE stat is whichever of misc0/misc1 is a
            # valid stat index (598/175 carry it in misc0, 174 in misc1). Ground-
            # truthed: Mental Dexterity (598, Int->AP), Mental Quickness (175, Int->
            # spell damage). This makes "what supports Attack Power" include Intellect.
            op["kind"] = "statConvert"
            op["isPct"] = True
            op["to"] = {175: "spellDamage", 174: "healingPower", 598: "attackPower"}[aura]
            src = misc0 if misc0 in (0, 1, 2, 3, 4) else misc1
            op["from"] = STAT_NAMES.get(src, f"stat:{src}")
            readable = {"spellDamage": "Spell Power", "healingPower": "Healing Power",
                        "attackPower": "Attack Power"}[op["to"]]
            op["property"] = f"{readable} from {op['from']}"
        elif aura == 133:
            # Ground-truthed vs tooltip: "Total Health increased by $s1%" (Tauren
            # Endurance 20550). Folds into stat.maxHealth as a what-if delta.
            op["kind"] = "maxHealth"
            op["isPct"] = True
        elif aura == 34:
            # MOD_INCREASE_HEALTH: flat max health (Flask of the Titans +1200).
            op["kind"] = "maxHealth"
            op["isPct"] = False
        elif aura == 22:
            # MOD_RESISTANCE: misc0 is a school mask; the physical bit means ARMOR
            # (Scroll of Protection) and folds; magic resistances stay label-only.
            if misc0 & 1:
                op["kind"] = "armor"
            else:
                op["kind"] = "aura"
                op["label"] = f"{school_label(misc0)} resistance"
        elif aura == 99 or aura == 124:
            # MOD_ATTACK_POWER / MOD_RANGED_ATTACK_POWER (flat; e.g. Well Fed food).
            op["kind"] = "attackPower" if aura == 99 else "rangedAttackPower"
        elif aura == 290:
            # Crit chance %: ground-truthed on Elixir of the Mongoose (+2% crit) and
            # the weapon-specialization racials. A SpellEquippedItems row makes the
            # spell CONDITIONAL ("while you have an axe equipped") -> label-only;
            # unconditional 290s fold into all three crit stats.
            if equipped_items and first in equipped_items:
                op["kind"] = "aura"
                op["label"] = "crit chance (%) (conditional)"
            else:
                op["kind"] = "critChance"
                op["isPct"] = True
                op["property"] = "crit chance"
        elif aura == 178:
            # "Maximum Mana/Rage/Energy increased by $s1%" (Expansive Mind rework);
            # misc0 = power type (0 mana, 1 rage, 3 energy). Only mana folds (graph node).
            op["kind"] = "maxPower"
            op["isPct"] = True
            op["powerType"] = misc0
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

    # Spells with a weapon/armor requirement: their auras are conditional (see the
    # aura-290 branch in build_ops).
    equipped_items = {to_int(r["SpellID"]) for r in read_csv(cache, "SpellEquippedItems")
                      if to_int(r["EquippedItemClass"]) > 0}

    # Player-learnable spells: abilities on class skill lines (SkillLine CategoryID 7).
    skill_lines = {to_int(r["ID"]): r for r in read_csv(cache, "SkillLine")}
    class_lines = {sid for sid, r in skill_lines.items() if to_int(r.get("CategoryID", "0")) == 7}

    # Racial skill lines: CategoryID 9 with "Racial" in the name (category 9 also holds
    # riding/cooking/etc., some of which are race-gated too - the name filter is the
    # discriminator on the enUS CSVs we generate from).
    racial_lines = {sid for sid, r in skill_lines.items()
                    if to_int(r.get("CategoryID", "0")) == 9
                    and "Racial" in (r.get("DisplayName_lang") or "")}
    # Rogue poisons are player abilities on their own category-9 line (not a class
    # line) - they join the shippable set so the imbue pass sees them.
    poison_lines = {sid for sid, r in skill_lines.items()
                    if to_int(r.get("CategoryID", "0")) == 9
                    and "Poison" in (r.get("DisplayName_lang") or "")}
    chr_races = {to_int(r["ID"]): r for r in read_csv(cache, "ChrRaces")}
    bit_to_race = {}
    for rid, r in chr_races.items():
        bit = r.get("PlayableRaceBit", "")
        if bit not in ("", "-1"):
            b = to_int(bit)
            if b not in bit_to_race or rid < bit_to_race[b]:
                bit_to_race[b] = rid
    # Per-line race gate (SkillRaceClassInfo) as fallback for mask-less ability rows.
    line_races = {}
    for r in read_csv(cache, "SkillRaceClassInfo"):
        if to_int(r["SkillID"]) in racial_lines:
            line_races[to_int(r["SkillID"])] = races_for_masks(
                to_int(r["RaceMasks_0"]), to_int(r["RaceMasks_1"]), bit_to_race)

    player_spells = set()
    racial_sla = defaultdict(dict)  # raceId -> {spellID: SLA ClassMask}
    racial_dropped = 0
    for r in read_csv(cache, "SkillLineAbility"):
        line = to_int(r["SkillLine"])
        if line in class_lines or line in poison_lines:
            player_spells.add(to_int(r["Spell"]))
        elif line in racial_lines:
            races = races_for_masks(to_int(r["RaceMasks_0"]), to_int(r["RaceMasks_1"]),
                                    bit_to_race) or line_races.get(line, set())
            if not races:
                racial_dropped += 1
                continue
            cm = to_int(r["ClassMask"])
            for rid in races:
                racial_sla[rid][to_int(r["Spell"])] = cm if cm > 0 else 0
    if racial_dropped:
        print(f"WARNING: {racial_dropped} racial ability rows dropped (no decodable race)")
    # Racials join the shippable set so their metadata lands in spells.lua and
    # spell-mod affected-lists can resolve to them.
    for spells in racial_sla.values():
        player_spells.update(spells)

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
        ops = build_ops(first, effects_by_spell, class_options, family_members, player_spells,
                        equipped_items)

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
                        family_members, player_spells, equipped_items)
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

    # ---- Racials (permanent race effects; NOT in the trait trees) --------------
    # Chain: racial SkillLine -> SkillLineAbility (RaceMasks -> races, ClassMask ->
    # class gate) -> spell -> build_ops (same decode as talents/traits). Passive vs
    # active comes from SPELL_ATTR0_PASSIVE; only passives are model-foldable - actives
    # surface via tooltip. Live snapshot stats ALREADY include racial passives, so the
    # model applies these as what-if deltas, never as unconditional permanent folds.
    SPELL_ATTR0_PASSIVE = 0x40
    racials_out, race_tokens, racials_by_spell = {}, {}, {}
    racial_curation = set()
    for rid in sorted(racial_sla):
        race = chr_races.get(rid)
        if not race:
            continue
        spells = []
        for sid in sorted(racial_sla[rid]):
            m = misc.get(sid)
            ops = build_ops(sid, effects_by_spell, class_options, family_members, player_spells,
                            equipped_items)
            entry = {
                "spellID": sid,
                "name": spell_names.get(sid, f"spell:{sid}"),
                "classMask": racial_sla[rid][sid],
                "passive": bool(m and to_int(m["Attributes_0"]) & SPELL_ATTR0_PASSIVE),
                "ops": ops,
                # Forever's racial rework adds new 1.25M+ spell ids alongside classic ones.
                "confidence": "forever-new-unverified" if sid >= 1_000_000 else "classic-presumed",
            }
            if not ops or all(o.get("kind") == "unmapped" for o in ops):
                entry["needsCuration"] = True
                racial_curation.add(sid)
            spells.append(entry)
            racials_by_spell.setdefault(sid, rid)
        racials_out[rid] = {"token": race["ClientFileString"], "name": race["Name_lang"],
                            "spells": spells}
        # Token fallback map (UnitRace #2): lowest raceId wins on collisions - both
        # Skyborne variants share the "Skyborne" token; "Scourge" = Undead lands as 5.
        token = race["ClientFileString"]
        if token not in race_tokens or rid < race_tokens[token]:
            race_tokens[token] = rid

    # ---- Consumables (CONSUME-buffs: item -> effect -> buff spell) --------------
    # Chain: Item(ClassID 0) -> ItemXItemEffect -> ItemEffect(TriggerType 0 = on use)
    # -> SpellID -> build_ops. Foods park their stats on a TRIGGERED Well-Fed spell -
    # when the direct spell has no decoded ops, chase EffectTriggerSpell one hop (the
    # triggered spell is also the aura the player actually carries). Only items whose
    # buff decodes to at least one mapped op ship (bloat control); enhancements (6,
    # applied to gear) and bandages (7) are out of scope for self-buffs.
    CONSUMABLE_TYPES = {0: "consumable", 1: "potion", 2: "elixir", 3: "flask",
                        4: "scroll", 5: "food", 8: "other"}
    consumable_sub, class0_items = {}, set()
    for r in read_csv(cache, "Item"):
        if to_int(r["ClassID"]) != 0:
            continue
        iid, sc = to_int(r["ID"]), to_int(r["SubclassID"])
        class0_items.add(iid)
        if sc in CONSUMABLE_TYPES:
            consumable_sub[iid] = sc
    sparse = {}
    for r in read_csv(cache, "ItemSparse"):
        iid = to_int(r["ID"])
        if iid in consumable_sub:
            sparse[iid] = (r["Display_lang"], to_int(r["RequiredLevel"]))
    item_effects = {to_int(r["ID"]): r for r in read_csv(cache, "ItemEffect")}
    item_links = defaultdict(list)
    for r in read_csv(cache, "ItemXItemEffect"):
        item_links[to_int(r["ItemID"])].append(to_int(r["ItemEffectID"]))
    max_stacks = {to_int(r["SpellID"]): to_int(r["CumulativeAura"])
                  for r in read_csv(cache, "SpellAuraOptions") if to_int(r["DifficultyID"]) == 0}

    def decoded(ops):
        return [o for o in ops if o.get("kind") != "unmapped"]

    consumables_out, buffs_by_spell = {}, {}
    for iid in sorted(consumable_sub):
        name, req_level = sparse.get(iid, ("", 0))
        for eid in sorted(item_links.get(iid, [])):
            eff = item_effects.get(eid)
            if not eff or to_int(eff["TriggerType"]) != 0:
                continue
            sid = to_int(eff["SpellID"])
            buff_sid = sid
            ops = build_ops(sid, effects_by_spell, class_options, family_members,
                            player_spells, equipped_items)
            if not decoded(ops):
                for e in effects_by_spell.get(sid, []):
                    tsid = to_int(e["EffectTriggerSpell"])
                    if tsid:
                        t_ops = build_ops(tsid, effects_by_spell, class_options,
                                          family_members, player_spells, equipped_items)
                        if decoded(t_ops):
                            # MAGNITUDE LAW (ground-truthed 2026-10-11): Forever's
                            # reworked foods park UNIT values (bp 1) on SHARED Well-Fed
                            # spells and carry the real magnitude on the trigger
                            # effect's BasePoints (Slitherskin Mackerel: aura227 bp6 ->
                            # Well Fed +1 AP unit = +6 AP; Mithril Head Trout bp20 ->
                            # +20). Classic foods keep the magnitude on the triggered
                            # spell (trigger bp 0/1, e.g. Dirge's Chops -> +25 Stam).
                            # So: scale hop ops by the trigger bp when it is > 1.
                            scale = float(e["EffectBasePointsF"] or 0)
                            if scale > 1:
                                for o in t_ops:
                                    o["maxValue"] = (o.get("maxValue") or 0) * scale
                            buff_sid, ops = tsid, t_ops
                            break
            if not decoded(ops):
                continue
            entry = {
                "buffSpellId": buff_sid,
                "name": name or spell_names.get(sid, f"item:{iid}"),
                "type": CONSUMABLE_TYPES[consumable_sub[iid]],
                "ops": ops,
                "confidence": "forever-new-unverified" if buff_sid >= 1_000_000
                              else "classic-presumed",
            }
            m = misc.get(buff_sid)
            dur = m and durations.get(to_int(m["DurationIndex"]))
            if dur and dur > 0:
                entry["durationMs"] = dur
            if max_stacks.get(buff_sid):
                entry["maxStacks"] = max_stacks[buff_sid]
            if req_level > 1:
                entry["reqLevel"] = req_level
            consumables_out[iid] = entry
            buffs_by_spell.setdefault(buff_sid, iid)
            break  # one buff effect per item is the consumable shape

    # ---- Weapon imbues (IMBUE-compare: temp weapon enchants from player spells) --
    # Chain: player spell -> SpellEffect (Effect 53/54/360, misc0 = enchantment id)
    # -> SpellItemEnchantment: type-3 EQUIP spells carry fold-able auras (Rockbiter
    # +AP/threat -> build_ops), type-1 PROC spells carry flat school damage with the
    # chance in EffectPointsMin (0 = unknown, stays honest). Flametongue's damage
    # basis lives OUTSIDE the enchant (dummy equip spell): the imbue tooltip macro
    # divides a basis spell's m1 by 77 and 25 = 100/1.3s and 100/4.0s (the weapon-
    # speed extremes), i.e. per-hit = basis_bp * weaponSpeed / 100 - parsed from the
    # description ($<id>m1/77 classic syntax, $/77;<id>m1 new syntax).
    enchants = {to_int(r["ID"]): r for r in read_csv(cache, "SpellItemEnchantment")}
    # Item-applied temp enchants (rogue poisons, sharpening stones, oils): the apply
    # spell hangs off a ClassID-0 item (poisons are subclass 8 "Other" on this build),
    # not a skill line - scan every consumable-class on-use spell; the enchant-effect
    # check below is the membership filter.
    enhance_spells = set()
    for iid in class0_items:
        for eid in item_links.get(iid, []):
            eff = item_effects.get(eid)
            if eff and to_int(eff["TriggerType"]) == 0:
                enhance_spells.add(to_int(eff["SpellID"]))
    imbues_out = {}
    for sid in sorted(player_spells | enhance_spells):
        for e in effects_by_spell.get(sid, []):
            if to_int(e["Effect"]) not in (53, 54, 360):
                continue
            er = enchants.get(to_int(e["EffectMiscValue_0"]))
            if not er:
                continue
            entry = {
                "name": spell_names.get(sid, f"spell:{sid}"),
                "enchant": to_int(er["ID"]),
                "confidence": "forever-new-unverified" if sid >= 1_000_000 else "classic-presumed",
            }
            ops, procs = [], []
            for i in range(3):
                etype = to_int(er.get(f"Effect_{i}") or 0)
                arg = to_int(er.get(f"EffectArg_{i}") or 0)
                pts = to_int(er.get(f"EffectPointsMin_{i}") or 0)
                if etype == 3 and arg:  # equip spell: fold its auras (AP, threat...)
                    ops.extend(op for op in build_ops(arg, effects_by_spell, class_options,
                                                      family_members, player_spells, equipped_items)
                               if op.get("kind") != "unmapped")
                    if pts and pts != 100:
                        entry["chance"] = pts  # Windfury-style on-hit chance
                elif etype == 2 and pts:  # flat weapon damage (sharpening stones)
                    entry["flatDamage"] = (entry.get("flatDamage") or 0) + pts
                elif etype == 1 and arg:  # proc-on-hit spell: flat school damage
                    dmg = sum(float(pe["EffectBasePointsF"] or 0)
                              for pe in effects_by_spell.get(arg, [])
                              if to_int(pe["Effect"]) == 2)
                    pm = misc.get(arg)
                    proc = { "spellID": arg, "name": spell_names.get(arg, "") }
                    if pts:
                        proc["chance"] = pts
                    if dmg:
                        proc["damage"] = dmg
                        proc["school"] = school_label(to_int(pm["SchoolMask"])) if pm else "?"
                    procs.append(proc)
            if ops:
                entry["ops"] = ops
            if procs:
                entry["procs"] = procs
            basis_ref = re.search(r"\$(\d+)m1/77", spell_desc.get(sid) or "") \
                or re.search(r"/77;(\d+)m1", spell_desc.get(sid) or "")
            if basis_ref:
                basis = to_int(basis_ref.group(1))
                bp = sum(float(pe["EffectBasePointsF"] or 0)
                         for pe in effects_by_spell.get(basis, []))
                bm = misc.get(basis)
                if bp:
                    entry["speedDamage"] = {
                        "per100Speed": bp, "basisSpellID": basis,
                        "school": school_label(to_int(bm["SchoolMask"])) if bm else "Fire",
                    }
            if entry.get("ops") or entry.get("procs") or entry.get("speedDamage") \
                    or entry.get("chance") or entry.get("flatDamage"):
                imbues_out[sid] = entry
            break  # one enchant effect per imbue spell

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
                "racialRaces": len(racials_out),
                "racialSpells": len(racials_by_spell),
                "racialSpellsNeedingCuration": len(racial_curation),
                "consumables": len(consumables_out),
                "imbues": len(imbues_out),
            },
            "classNames": CLASS_NAMES,
        }, out_dir, args.build),
        LuaWriter.file("talent_tabs", {"talentTabs": tabs_out}, out_dir, args.build),
        LuaWriter.file("talents", {"talents": talents_out}, out_dir, args.build),
        LuaWriter.file("talent_impacts", {"talentImpacts": impacts_out}, out_dir, args.build),
        LuaWriter.file("spells", {"spells": spells_out}, out_dir, args.build),
        LuaWriter.file("traits", {"traits": traits_out}, out_dir, args.build),
        LuaWriter.file("race_racials", {"racials": racials_out,
                                        "racialsBySpell": racials_by_spell,
                                        "raceTokens": race_tokens}, out_dir, args.build),
        LuaWriter.file("consumables", {"consumables": consumables_out,
                                       "buffsBySpell": buffs_by_spell}, out_dir, args.build),
        LuaWriter.file("weapon_imbues", {"imbues": imbues_out}, out_dir, args.build),
    ]
    for path in written:
        print(f"wrote {path.relative_to(root.parent)} ({path.stat().st_size:,} bytes)")
    print(f"\ntalents={len(talents_out)} tabs={len(tabs_out)} spells shipped={len(spells_out)} "
          f"trait nodes={len(trait_nodes)} talents needing curation={needs_curation}/{len(talents_out)}\n"
          f"racial races={len(racials_out)} racial spells={len(racials_by_spell)} "
          f"racials needing curation={len(racial_curation)} consumables={len(consumables_out)} "
          f"imbues={len(imbues_out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
