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

DEFAULT_BUILD = "1.60.1.70685"
# Release channel of the client these tables came from. Forever is in beta until
# 2026-10-21 (launches 2026-11-04); flip to "live" when generating from a launch build.
# Stamps every generated fact as "Forever-verified - <channel> <build>".
DEFAULT_CHANNEL = "beta"

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

# ITEM_MOD_* stat-type ids (ItemSparse.StatModifier_bonusStat) -> our stat vocabulary.
# The authoritative in-client gear-stat legend - no scraping. Secondary stats (dodge,
# parry, defense, ratings, resistances) become first-class stat-axis levers. Unknown
# ids fall back to "stat:N" (shown honestly, curated later).
ITEM_MOD = {
    0: "Mana", 1: "Health", 3: "Agility", 4: "Strength", 5: "Intellect", 6: "Spirit",
    7: "Stamina", 12: "Defense", 13: "Dodge", 14: "Parry", 15: "Block",
    16: "Melee Hit", 17: "Ranged Hit", 18: "Spell Hit", 19: "Melee Crit",
    20: "Ranged Crit", 21: "Spell Crit", 28: "Melee Haste", 29: "Ranged Haste",
    30: "Spell Haste", 31: "Hit", 32: "Crit", 35: "Resilience", 36: "Haste",
    37: "Expertise", 38: "Attack Power", 39: "Ranged Attack Power",
    41: "Spell Healing", 42: "Spell Damage", 43: "Mana Regen", 44: "Armor Penetration",
    45: "Spell Power", 46: "Health Regen", 47: "Spell Penetration", 48: "Block Value",
    49: "Mastery", 50: "Bonus Armor",
}

# InventoryType -> readable equip slot (gear catalog display).
INV_SLOT = {
    1: "Head", 2: "Neck", 3: "Shoulder", 4: "Shirt", 5: "Chest", 6: "Waist",
    7: "Legs", 8: "Feet", 9: "Wrist", 10: "Hands", 11: "Finger", 12: "Trinket",
    13: "One-Hand", 14: "Shield", 15: "Ranged", 16: "Back", 17: "Two-Hand",
    18: "Bag", 19: "Tabard", 20: "Robe", 21: "Main Hand", 22: "Off Hand",
    23: "Held", 25: "Thrown", 26: "Ranged", 28: "Relic",
}
QUALITY = {0: "Poor", 1: "Common", 2: "Uncommon", 3: "Rare", 4: "Epic", 5: "Legendary"}
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


def class_roster(cache: Path) -> dict:
    """S29: the class roster - id -> {name, token}. From ChrClasses when fetched (the
    client's own data, roster-law source); degrades to CLASS_NAMES (token = NAME) when
    the table is absent so a pre-fetch run still produces a usable roster. Resource/power
    type is deliberately NOT guessed here - S31's per-class honesty reads it LIVE
    (maxMana > 0), the most honest source."""
    try:
        rows = read_csv(cache, "ChrClasses")
    except FileNotFoundError:
        return {cid: {"name": name, "token": name.upper()}
                for cid, name in CLASS_NAMES.items()}
    out = {}
    for r in rows:
        cid = to_int(r["ID"])
        name = r.get("Name_lang") or CLASS_NAMES.get(cid, f"class:{cid}")
        token = (r.get("Filename") or name).upper()
        # Only the playable classes we model (the CLASS_NAMES set); the table may carry
        # non-playable/test rows.
        if cid in CLASS_NAMES:
            out[cid] = {"name": name, "token": token}
    return out or {cid: {"name": name, "token": name.upper()}
                   for cid, name in CLASS_NAMES.items()}


def eff_magnitude(e) -> tuple[float, float]:
    """(effective value, variance) of a SpellEffect row, across flavors.

    Modern (Forever/retail): value in EffectBasePointsF, spread in Variance
    (min/max = v*(1 -/+ var/2)). Classic Era 1.15 keeps the VANILLA pair:
    EffectBasePoints + EffectDieSides, roll = bp + random(1..die), so
    value = bp + (1+die)/2 (die==1 -> flat bp+1), spread = (die-1)/value.
    Verified on 1.15.9: Fireball r1 13+d9 -> 14-22, Arcane Intellect r1 1+1 -> +2,
    Imp Fireball r1 -101+1 -> -100ms - all exact classic truth.
    """
    bpf = float(e.get("EffectBasePointsF") or 0)
    if bpf != 0:
        return bpf, float(e.get("Variance") or 0)
    bp = float(e.get("EffectBasePoints") or 0)
    die = float(e.get("EffectDieSides") or 0)
    if die >= 1:
        base = bp + (1 + die) / 2.0
        return base, ((die - 1) / base if base != 0 else 0.0)
    return bp, float(e.get("Variance") or 0)


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


# Set from --flavor in main(). A few aura decodes are flavor-semantic (vanilla's client
# hardcodes behavior the modern data expresses in misc values), so build_ops needs to know.
FLAVOR = "forever"


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
            "maxValue": eff_magnitude(eff)[0],
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
            if FLAVOR == "classic" and aura in (174, 175):
                # Vanilla hardcodes these auras to SPIRIT in the client (Spiritual
                # Guidance is the only such conversion in 1.12); the 1.15 rows carry
                # no stat index (174's misc0 is a school mask, misc1 unused) so the
                # modern misc decode below would misread stat 0 = Strength.
                op["from"] = "Spirit"
            else:
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
        elif aura == 22 or aura == 674:
            # MOD_RESISTANCE: misc0 is a school mask; the physical bit means ARMOR
            # (Scroll of Protection) and folds; magic resistances stay label-only.
            # Build 70450 SPLIT flat armor into its own aura 674 (every 674 row carries
            # school mask 1; verified Scroll of Protection IV kept spell/value/item chain
            # with only the aura id renumbered 22 -> 674) - same fold, both ids.
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
    parser.add_argument("--channel", default=DEFAULT_CHANNEL,
                        help="release channel stamped on the data (beta/live)")
    parser.add_argument("--flavor", default="forever", choices=["forever", "classic"],
                        help="classic writes to data/generated_classic (the Classic Era "
                             "flavor dataset loaded by Foresight_Vanilla.toc)")
    args = parser.parse_args()
    global FLAVOR
    FLAVOR = args.flavor

    root = Path(__file__).parent
    cache = root / "cache" / args.build
    out_dir = root.parent / "Foresight" / "data" / (
        "generated_classic" if args.flavor == "classic" else "generated")
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
    # Column-name drift across flavors: Forever/retail = RaceMasks_0/_1, Classic Era 1.15 =
    # RaceMask_0/_1 (singular). Same data, same bit semantics - read whichever exists.
    def race_mask_pair(r):
        return (to_int(r.get("RaceMasks_0", r.get("RaceMask_0"))),
                to_int(r.get("RaceMasks_1", r.get("RaceMask_1"))))

    # Per-line race gate (SkillRaceClassInfo) as fallback for mask-less ability rows.
    line_races = {}
    for r in read_csv(cache, "SkillRaceClassInfo"):
        if to_int(r["SkillID"]) in racial_lines:
            m0, m1 = race_mask_pair(r)
            line_races[to_int(r["SkillID"])] = races_for_masks(m0, m1, bit_to_race)

    player_spells = set()
    racial_sla = defaultdict(dict)  # raceId -> {spellID: SLA ClassMask}
    racial_dropped = 0
    for r in read_csv(cache, "SkillLineAbility"):
        line = to_int(r["SkillLine"])
        if line in class_lines or line in poison_lines:
            player_spells.add(to_int(r["Spell"]))
        elif line in racial_lines:
            local_m0, local_m1 = race_mask_pair(r)
            races = races_for_masks(local_m0, local_m1,
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
    # Per-rank op alignment signature (S21): the same logical op across rank spells.
    def op_signature(op):
        return (op.get("kind"), op.get("property"), op.get("isPct"),
                op.get("school"), op.get("stat"), op.get("to"), op.get("from"),
                tuple(op.get("affected") or ()))

    talents_out, impacts_out = {}, {}
    needs_curation = 0
    values_decoded, values_skipped, values_partial = 0, 0, 0
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

        # Impact ops from the rank-1 spell. MOST multi-rank talents (291/347 this build)
        # store an effect value ONLY on rank 1 - rank scaling stays presumed (rank N =
        # value * N / maxRank) until a SCAN verifies it. The per-rank magnitudes for those
        # genuinely aren't in the client's static data: the higher-rank spells carry neither
        # SpellEffect rows nor magnitude tokens (verified 2026-10-15), which is exactly why
        # the scan/crowd layer exists. But 44 talents DO carry SpellEffect rows on every
        # rank: decode the TRUE per-rank values (S21), PER OP - an op that signature-matches
        # across all ranks gets its exact `values` array even when a SIBLING op on the same
        # talent doesn't align (the old all-or-nothing dropped the whole talent on any
        # mismatch; per-op recovers ~13). An op without aligned rows keeps maxValue + the
        # presumed/scan rule path (honest degrade, never a guess).
        ops = build_ops(first, effects_by_spell, class_options, family_members, player_spells,
                        equipped_items)

        if ops and len(ranks) > 1 and all(effects_by_spell.get(s) for s in ranks):
            rank_ops = [build_ops(s, effects_by_spell, class_options, family_members,
                                  player_spells, equipped_items) for s in ranks]
            decoded_ops = 0
            for op in ops:
                s0 = op_signature(op)
                vals, ok = [], True
                for ro in rank_ops:
                    matches = [o for o in ro if op_signature(o) == s0]
                    if len(matches) != 1:
                        ok = False
                        break
                    vals.append(matches[0].get("maxValue", 0.0))
                if ok:
                    op["values"] = vals  # exact per-rank for THIS op (per-op, not whole-talent)
                    decoded_ops += 1
            if decoded_ops == len(ops):
                values_decoded += 1          # fully datamined - drops the (p)
            elif decoded_ops > 0:
                values_partial += 1          # some ops exact, siblings presumed (honest hybrid)
            else:
                values_skipped += 1

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
    # Name index for the totem-pattern buff chase (only consulted for "... Totem"
    # ship spells, built once).
    ids_by_name = defaultdict(list)
    for nid, nm in spell_names.items():
        ids_by_name[nm].append(nid)
    spells_out = {}
    multi_damage, multi_heal, scaling_flagged = [], [], set()
    totem_links = 0
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

        # Ability-outcome decode (MODEL-ability-outcomes): what the button itself does.
        # Modern SpellEffect layout (no EffectDieSides): magnitude in EffectBasePointsF,
        # spread in Variance (min/max = bp*(1 -/+ var/2)), real SP/HP coefficient in
        # EffectBonusCoefficient (meaningful ONLY on Effect 2/10 rows - weapon rows carry
        # a junk 1), level term in EffectRealPointsPerLevel clamped by SpellLevels.MaxLevel.
        # Cross-checked vs classic: rank-1 Fireball bp 18 var 0.444 -> 14-22.
        wpn = {}
        for e in effects_by_spell.get(sid, []):
            et = to_int(e["Effect"])
            if et not in (2, 6, 10, 17, 31, 58, 121):
                continue
            if to_int(e.get("ScalingClass")):  # forever/retail-only column; absent on 1.15
                scaling_flagged.add(f"{sid} ({entry['name']})")
            bp, eff_var = eff_magnitude(e)
            if et in (2, 10):
                key = "dmg" if et == 2 else "heal"
                if key in entry:
                    (multi_damage if et == 2 else multi_heal).append(sid)
                    continue  # first row wins; the printed count feeds curation
                coef = float(e["EffectBonusCoefficient"] or 0)
                if not bp and coef <= 0:
                    continue  # empty row claims nothing (nil-degrade, never invent)
                if args.flavor == "classic":
                    # 1.15's EffectBonusCoefficient is NOT the vanilla coefficient
                    # (Fireball reads 0.123 vs the classic truth ~1.0 for a 3.5s cast).
                    # Ship NO coef on classic: the runtime derives castTime/3.5 - which IS
                    # the vanilla law - and tags it (p) until live tooltips verify.
                    coef = 0
                shape = {"base": bp}
                var = eff_var
                if var:
                    shape["var"] = var
                ppl = float(e["EffectRealPointsPerLevel"] or 0)
                if ppl:
                    shape["lvl"] = ppl
                    ml = to_int(lv["MaxLevel"]) if lv else 0
                    if ml:
                        shape["maxLvl"] = ml
                if coef > 0:
                    shape["coef"] = coef
                entry[key] = shape
            elif et == 31:
                if "pct" not in wpn:
                    wpn["pct"] = bp
            elif et in (17, 58, 121):
                wpn["flat"] = wpn.get("flat", 0.0) + bp
                if et == 121:
                    wpn["norm"] = True
            elif et == 6 and to_int(e["EffectAura"]) == 3 and bp and "dotTick" not in entry:
                entry["dotTick"] = bp
        if wpn:
            if not wpn.get("flat"):
                wpn.pop("flat", None)  # consumer defaults 0
            entry["wpn"] = wpn
        # The ppl level term anchors at BaseLevel, which can diverge from the shipped
        # SpellLevel (246 spells this build); emit it only where the law needs it.
        if lv and (("dmg" in entry and "lvl" in entry["dmg"])
                   or ("heal" in entry and "lvl" in entry["heal"])):
            bl = to_int(lv["BaseLevel"])
            if bl != entry.get("level", 0):
                entry["baseLevel"] = bl

        # Totem-pattern buff chase (user ask 2026-10-12: "Strength of Earth should say
        # 7 Strength -> X AP -> Y DPS"): "X Totem" summons a creature (Effect 28) whose
        # aura is the spell named exactly "X" - the creature hop isn't in our tables,
        # so pair by NAME at the SAME SpellLevel (rank-exact in this data: totem 8075
        # L10 <-> buff 8076 L10, etc.). Decoded ops land as entry["grants"]; no match
        # or unmapped ops = no claim.
        if entry["name"].endswith(" Totem") \
                and any(to_int(e["Effect"]) == 28 for e in effects_by_spell.get(sid, [])):
            cast_level = entry.get("level") or 0
            best_id, best_level, best_ops = None, -1, None
            for cid in sorted(ids_by_name.get(entry["name"][:-6], [])):
                lv_c = levels.get(cid)
                c_level = to_int(lv_c["SpellLevel"]) if lv_c else 0
                if c_level <= cast_level and c_level > best_level:
                    c_ops = build_ops(cid, effects_by_spell, class_options,
                                      family_members, player_spells, equipped_items)
                    c_ops = [o for o in c_ops if o.get("kind") and o["kind"] != "unmapped"]
                    if c_ops:
                        best_id, best_level, best_ops = cid, c_level, c_ops
            if best_id:
                entry["grants"] = best_ops
                entry["grantsFrom"] = best_id
                totem_links += 1
        spells_out[sid] = entry

    n_dmg = sum(1 for s in spells_out.values() if "dmg" in s)
    n_heal = sum(1 for s in spells_out.values() if "heal" in s)
    n_wpn = sum(1 for s in spells_out.values() if "wpn" in s)
    print(f"ability decode: damage={n_dmg} weapon={n_wpn} heal={n_heal}")
    print(f"per-rank values: {values_decoded} fully decoded, {values_partial} partial "
          f"(some ops exact), {values_skipped} skipped (no op aligned)")
    print(f"totem buff links: {totem_links}")
    if multi_damage:
        print(f"multi-damage-row spells: {len(multi_damage)}")
    if multi_heal:
        print(f"multi-heal-row spells: {len(multi_heal)}")
    for flagged in sorted(scaling_flagged):
        print(f"WARNING: ScalingClass != 0 on spell {flagged}")

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
    # S21 values bridge: a classic-overlap node's definition spell is ONE of the
    # talent's rank spells (usually rank 1, sometimes higher), and the talent-loop
    # alignment already proved its ops signature-match across ranks - copy the
    # talent's datamined per-rank values onto signature-matching ops so the LIVE
    # talent path (node.ops via C_Traits) sees them too.
    talent_by_rank_spell = {}
    for t_id, t in talents_out.items():
        for s in t["spellRanks"]:
            talent_by_rank_spell.setdefault(s, t_id)
    node_pos = {}  # nodeID -> {tree, posX, posY}: the classic-grid layout (UI-talent-planner)
    # Classic Era carries a handful of STUB TraitNode rows (junk for 1.15): shipping them
    # poisons the flavor split (impactNodes/usingForever key on "any trait nodes present").
    # The trait system is Forever/retail-only - classic ships traits EMPTY by design.
    trait_rows = [] if args.flavor == "classic" else read_opt("TraitNode")
    for r in trait_rows:
        nid = to_int(r["ID"])
        node_pos[nid] = {"tree": to_int(r["TraitTreeID"]),
                         "posX": to_int(r["PosX"]), "posY": to_int(r["PosY"])}
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
        bridged = talent_by_rank_spell.get(primary["spellID"])
        bimp = bridged and impacts_out.get(bridged)
        if bimp and bimp["ops"] and len(bimp["ops"]) == len(ops):
            for op, top in zip(ops, bimp["ops"]):
                if "values" in top and op_signature(op) == op_signature(top):
                    op["values"] = top["values"]
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

    # ---- Forever TALENT GRID (UI-talent-planner) -------------------------------
    # The trait nodes ARE Forever's talents, and their TraitNode positions form the
    # classic layout: PosY = 7 tier rows (600 steps), PosX = 3 spec clusters of 4 columns.
    # We map each node into that grid (keyed by nodeID), reuse the classic tab names/order
    # per class, and read prereq arrows from TraitEdge - so the planner renders Forever's
    # REAL talents (not the dead classic Talent.csv). Class comes from the tree's skill line
    # (SkillRaceClassInfo.ClassMask). Per-rank values keep the base+rank-rule path (ranks 2+
    # carry no DB2 effect data - the live tooltip scan verifies at launch). classId here is
    # the real ChrClasses id (the classic Talent.csv ships classId=0).
    def classid_from_mask(cm):
        for cid in range(1, 21):
            if (1 << (cid - 1)) == cm:
                return cid
        return 0
    skill_classmask = defaultdict(set)  # a skill line can have several rows; keep each mask
    for r in read_opt("SkillRaceClassInfo"):
        sl = to_int(r.get("SkillID"))
        cm = to_int(r.get("ClassMask"))
        if sl and cm:
            skill_classmask[sl].add(cm)
    tree_class = {}
    for tree, sl in tree_skill.items():
        cid = 0  # first mask that is a single known class (never OR them - that breaks Hunter)
        for cm in skill_classmask.get(to_int(sl), ()):
            c = classid_from_mask(cm)
            if c:
                cid = c
                break
        if cid:
            tree_class[tree] = cid
    class_tabs = defaultdict(list)  # classId -> [classic tabId...] sorted by display order
    for tab_id, tab in tabs_out.items():
        cid = classid_from_mask(tab.get("classMask", 0))
        if cid:
            class_tabs[cid].append(tab_id)
    for cid in class_tabs:
        class_tabs[cid].sort(key=lambda t: (tabs_out[t].get("order", 0), t))
    prereq_of = defaultdict(list)   # right(dependent) node -> [left(required) nodes]
    trait_edges = read_opt("TraitEdge")
    if not trait_edges:
        print("WARNING: TraitEdge missing/empty - forever talents will ship with NO prereqs")
    for r in trait_edges:
        # Type 0 edges are the VISUAL back-reference of a real edge (reciprocal pairs) -
        # never a requirement. Ingesting them created prereq cycles that deadlocked talents
        # (Druid Nature's Majesty <-> Splendor, audit 2026-10-16). Types 2/3 are requirements.
        if to_int(r.get("Type")) == 0:
            continue
        L, R = to_int(r.get("LeftTraitNodeID")), to_int(r.get("RightTraitNodeID"))
        if L and R:
            prereq_of[R].append(L)
    nodes_by_tree = defaultdict(list)
    for nid in trait_nodes:
        nodes_by_tree[node_pos[nid]["tree"]].append(nid)
    forever_talents = {}
    for tree, nids in nodes_by_tree.items():
        cid = tree_class.get(tree)
        if not cid or len(class_tabs.get(cid, [])) < 3:
            continue
        xs = sorted({node_pos[n]["posX"] for n in nids})
        ys = sorted({node_pos[n]["posY"] for n in nids})
        clusters = []  # PosX clustered into spec columns (gap > 1000 = new cluster)
        for x in xs:
            if not clusters or x - clusters[-1][-1] > 1000:
                clusters.append([x])
            else:
                clusters[-1].append(x)
        # Keep the 3 LARGEST clusters as the specs (a stray off-grid node can form a 4th,
        # single-value cluster), restored to left->right order. Off-spec nodes then fall out
        # via the tier/column bound below. (Fixes Hunter, which had such a stray node.)
        clusters = sorted(sorted(clusters, key=len, reverse=True)[:3], key=lambda c: c[0])
        if len(clusters) != 3:
            continue
        y0, tabs = ys[0], class_tabs[cid]
        for nid in nids:
            node = trait_nodes.get(nid)
            x, y = node_pos[nid]["posX"], node_pos[nid]["posY"]
            spec = next((i for i, c in enumerate(clusters) if c[0] <= x <= c[-1]), None)
            if spec is None:
                continue
            tier, column = (y - y0) // 600, (x - clusters[spec][0]) // 600
            if not (0 <= tier <= 9 and 0 <= column <= 3):
                continue  # off-grid node (e.g. a hidden/legacy node far outside the grid)
            e = {"name": node["name"], "tab": tabs[spec], "tier": tier, "column": column,
                 "classId": cid, "maxRank": node["maxRank"], "spellRanks": [node["spellID"]],
                 "ops": node["ops"]}
            if node.get("entries"):
                e["entries"] = node["entries"]
            forever_talents[nid] = e
    for R, lefts in prereq_of.items():
        if R in forever_talents:
            prs = []
            for L in lefts:
                lt = forever_talents.get(L)
                # An arrow must point DOWN the tree. A "requirement" at a DEEPER tier than
                # its dependent is the reciprocal half of a mutual pair (Hunter Bestial
                # Wrath <-> Intimidation are mutual Type-2 edges); keep the lower->higher
                # leg only, or both talents deadlock (audit 2026-10-16).
                if lt and lt["tier"] <= forever_talents[R]["tier"]:
                    prs.append({"talent": L, "rank": lt["maxRank"]})
            if prs:
                forever_talents[R]["prereqs"] = prs

    # Cycle guard (incident-to-gate, 2026-10-16): a prereq cycle makes BOTH talents
    # permanently unclickable in the planner. Fail generation loudly, never ship one.
    def _prereq_cycles():
        state = {}  # 1 = visiting, 2 = done

        def visit(n):
            if state.get(n) == 1:
                return True
            if state.get(n) == 2:
                return False
            state[n] = 1
            for pr in forever_talents.get(n, {}).get("prereqs", []):
                if visit(pr["talent"]):
                    return True
            state[n] = 2
            return False

        return [n for n in sorted(forever_talents) if state.get(n) != 2 and visit(n)]

    cyc = _prereq_cycles()
    if cyc:
        raise SystemExit(f"forever_talents prereq CYCLE at nodes {cyc[:8]} - edge filter broken")
    bad_tiers = sorted({(e["classId"], e["tier"]) for e in forever_talents.values() if e["tier"] > 6})
    if bad_tiers:
        print(f"WARNING: forever talents beyond tier 6 (planner frame clips >7 tiers): {bad_tiers}")

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
    if (cache / "ItemXItemEffect.csv").exists():
        for r in read_csv(cache, "ItemXItemEffect"):
            item_links[to_int(r["ItemID"])].append(to_int(r["ItemEffectID"]))
    else:
        # Classic Era 1.15 has no ItemXItemEffect - the link lives directly on
        # ItemEffect.ParentItemID (the pre-split schema). Same chain, one hop shorter.
        for eid, r in item_effects.items():
            pid = to_int(r.get("ParentItemID"))
            if pid:
                item_links[pid].append(eid)
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
                            scale = eff_magnitude(e)[0]
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

    # ---- Item catalog (DATA-items: the in-client gear DB, the authoritative seed) ----
    # Every equippable item that carries stat mods, straight from ItemSparse - name,
    # slot, item/required level, quality, and WHICH stats it has (by type). Exact stat
    # AMOUNTS are intentionally omitted: they ride the item-budget system (StatPercent
    # Editor x ilvl curve), which live GetItemStats already computes precisely for any
    # item the player touches - so the offline catalog answers "what exists / what is it
    # for / what has Dodge", and the live read answers "exactly how much" (no guessing).
    item_cls = {}
    for r in read_csv(cache, "Item"):
        item_cls[to_int(r["ID"])] = (to_int(r["ClassID"]), to_int(r["InventoryType"]))
    items_out = {}
    for r in read_csv(cache, "ItemSparse"):
        iid = to_int(r["ID"])
        cls = item_cls.get(iid)
        inv = cls and cls[1] or 0
        if inv <= 0:
            continue  # not equippable
        stat_types = []
        for i in range(10):
            t = to_int(r.get(f"StatModifier_bonusStat_{i}", "") or 0)
            if t > 0:
                stat_types.append(ITEM_MOD.get(t, f"stat:{t}"))
        if not stat_types:
            continue  # only statted gear (the planning-relevant set)
        name = r.get("Display_lang") or f"item:{iid}"
        if "(Test)" in name or "OLD" in name or "DEPRECATED" in name.upper():
            continue  # client scaffolding, not real gear
        quality = to_int(r.get("OverallQualityID", "") or 0)
        if quality < 2:
            continue  # drop Poor/Common - Uncommon+ is the planning-relevant gear (user call)
        items_out[iid] = {
            "name": name, "slot": INV_SLOT.get(inv, f"slot:{inv}"),
            "ilvl": to_int(r.get("ItemLevel", "") or 0),
            "reqLevel": to_int(r.get("RequiredLevel", "") or 0),
            "quality": QUALITY.get(quality, "?"),
            "stats": stat_types,
        }
        # Weapon swing speed (SIM-engine): proc engines (Windfury burst, poison
        # application) scale with it, so gear hover can say "slower = bigger procs"
        # with a real number. Weapons only (ClassID 2) - armor has no delay.
        delay = to_int(r.get("ItemDelay", "") or 0)
        if cls and cls[0] == 2 and delay > 0:
            items_out[iid]["speedMs"] = delay

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
                    dmg = sum(eff_magnitude(pe)[0]
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
                bp = sum(eff_magnitude(pe)[0]
                         for pe in effects_by_spell.get(basis, []))
                bm = misc.get(basis)
                if bp:
                    entry["speedDamage"] = {
                        "per100Speed": bp, "basisSpellID": basis,
                        "school": school_label(to_int(bm["SchoolMask"])) if bm else "Fire",
                    }
            # Windfury-style extra-attack payload (SIM-engine): the tooltip macro names
            # the basis spell ("$8233s2 extra attacks with $8233s1 extra melee attack
            # power") - s1 = bonus AP (aura 99), s2 = attack count (effect 19). Ground-
            # truthed on this build: r1-r4 = +46/119/249/333 AP, always 2 attacks, the
            # on-hit chance rides the enchant (entry["chance"]).
            xa_ref = re.search(r"\$(\d+)s2 extra \$lattack", spell_desc.get(sid) or "")
            if xa_ref:
                basis = to_int(xa_ref.group(1))
                bonus_ap, count = 0.0, 0.0
                for pe in effects_by_spell.get(basis, []):
                    bp = eff_magnitude(pe)[0]
                    if to_int(pe["Effect"]) == 6 and to_int(pe["EffectAura"]) == 99:
                        bonus_ap = bp
                    elif to_int(pe["Effect"]) == 19:
                        count = bp
                if count:
                    entry["extraAttacks"] = {"count": count, "bonusAp": bonus_ap,
                                             "basisSpellID": basis}
            if entry.get("ops") or entry.get("procs") or entry.get("speedDamage") \
                    or entry.get("chance") or entry.get("flatDamage"):
                imbues_out[sid] = entry
            break  # one enchant effect per imbue spell

    # ---- Crit-triggered haste engines (SIM-engine: the Flurry family) ------------
    # The talent spell's own effect is a dummy; the real payload is the triggered buff
    # the tooltip macro names ("for your next $16257n swings"): aura 319 (melee haste)
    # bp on that buff + its ProcCharges = the swing count. Per-rank scaling is
    # UNRESOLVED on this build (the talent dummy carries bp=1 at maxRank 5) - the
    # decoded value is the rank-1 buff's, tagged unverified; the talent-tooltip
    # capture upgrades or corrects it.
    aura_opts = {to_int(r["SpellID"]): r for r in read_csv(cache, "SpellAuraOptions")
                 if to_int(r["DifficultyID"]) == 0}
    crit_haste = {}
    for sid, desc in spell_desc.items():
        m = re.search(r"attack speed by \$m1% for your next \$(\d+)n swings", desc or "")
        if not m:
            continue
        buff = to_int(m.group(1))
        haste = 0.0
        for pe in effects_by_spell.get(buff, []):
            if to_int(pe["Effect"]) == 6 and to_int(pe["EffectAura"]) == 319:
                haste = eff_magnitude(pe)[0]
        opts_row = aura_opts.get(buff)
        charges = to_int(opts_row["ProcCharges"]) if opts_row else 0
        if haste and charges:
            crit_haste[sid] = {
                "name": spell_names.get(sid, f"spell:{sid}"),
                "hastePct": haste, "swings": charges, "buffSpellID": buff,
                "confidence": "forever-new-unverified",
            }

    # ---- Emit ------------------------------------------------------------------
    stamp = dt.date.today().isoformat()
    written = [
        LuaWriter.file("build", {
            "build": args.build,
            "channel": args.channel,
            "flavor": args.flavor,   # selftest + code branch on this, never on build strings
            "generated": stamp,
            "counts": {
                "talents": len(talents_out),
                "talentsWithRankValues": values_decoded,
                "talentsWithPartialRankValues": values_partial,
                "tabs": len(tabs_out),
                "spells": len(spells_out),
                "spellsWithDamage": n_dmg,
                "spellsWithWeaponHit": n_wpn,
                "spellsWithHeal": n_heal,
                "impactsNeedingCuration": needs_curation,
                "traitNodes": len(trait_nodes),
                "traitNodesNeedingCuration": trait_curation,
                "foreverTalents": len(forever_talents),
                "foreverPrereqs": sum(1 for e in forever_talents.values() if e.get("prereqs")),
                "racialRaces": len(racials_out),
                "racialSpells": len(racials_by_spell),
                "racialSpellsNeedingCuration": len(racial_curation),
                "consumables": len(consumables_out),
                "imbues": len(imbues_out),
                "items": len(items_out),
                "critHasteProcs": len(crit_haste),
            },
            "classNames": CLASS_NAMES,
            "classes": class_roster(cache),  # S29: roster-law source (id -> name/token)
        }, out_dir, args.build),
        LuaWriter.file("talent_tabs", {"talentTabs": tabs_out}, out_dir, args.build),
        LuaWriter.file("talents", {"talents": talents_out}, out_dir, args.build),
        LuaWriter.file("talent_impacts", {"talentImpacts": impacts_out}, out_dir, args.build),
        LuaWriter.file("spells", {"spells": spells_out}, out_dir, args.build),
        LuaWriter.file("traits", {"traits": traits_out}, out_dir, args.build),
        LuaWriter.file("forever_talents", {"foreverTalents": forever_talents}, out_dir, args.build),
        LuaWriter.file("race_racials", {"racials": racials_out,
                                        "racialsBySpell": racials_by_spell,
                                        "raceTokens": race_tokens}, out_dir, args.build),
        LuaWriter.file("consumables", {"consumables": consumables_out,
                                       "buffsBySpell": buffs_by_spell}, out_dir, args.build),
        LuaWriter.file("weapon_imbues", {"imbues": imbues_out}, out_dir, args.build),
        LuaWriter.file("items", {"items": items_out}, out_dir, args.build),
        LuaWriter.file("sim_procs", {"critHaste": crit_haste}, out_dir, args.build),
    ]
    for path in written:
        print(f"wrote {path.relative_to(root.parent)} ({path.stat().st_size:,} bytes)")
    print(f"\ntalents={len(talents_out)} tabs={len(tabs_out)} spells shipped={len(spells_out)} "
          f"trait nodes={len(trait_nodes)} talents needing curation={needs_curation}/{len(talents_out)}\n"
          f"racial races={len(racials_out)} racial spells={len(racials_by_spell)} "
          f"racials needing curation={len(racial_curation)} consumables={len(consumables_out)} "
          f"imbues={len(imbues_out)} items={len(items_out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
