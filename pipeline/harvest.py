"""Harvest Foresight data from live players' SavedVariables files.

The automated pull in the collection loop: the addon accumulates sessions, level-up
stat journals, verify results, and talent tooltip probes into ForesightDB (written by the
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
ADDON_DIR = Path(__file__).parent.parent / "Foresight"
GENERATED = ADDON_DIR / "data" / "generated"


def shipped_version() -> str | None:
    """The version currently in the source TOC - what a fresh in-game run should stamp."""
    toc = ADDON_DIR / "Foresight.toc"
    if not toc.exists():
        return None
    for line in toc.read_text(encoding="utf-8").splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    return None


def lua_to_py(obj):
    # A table becomes a list ONLY when it is a true Lua array (keys exactly 1..n).
    # Sparse integer keys (talent ids!) must stay dict keys - flattening them to a
    # list silently discards the ids and breaks every id-joined analysis.
    if lupa.lua_type(obj) == "table":
        keys = list(obj.keys())
        if (keys and all(isinstance(k, (int, float)) for k in keys)
                and sorted(keys) == list(range(1, len(keys) + 1))):
            return [lua_to_py(obj[k]) for k in range(1, len(keys) + 1)]
        return {str(k): lua_to_py(v) for k, v in obj.items()}
    return obj


def find_savedvars(roots: list[Path]) -> list[Path]:
    """Accepts either the WoW parent dir (scans every install under it) or a single
    install dir (its WTF directly) - cross-fork scoping catch 2026-10-12: the parent
    glob swept the RETAIL install's Foresight.lua into the Forever harvest."""
    found = []
    for root in roots:
        if root.exists():
            found.extend(root.glob("*/WTF/Account/*/SavedVariables/Foresight.lua"))
            found.extend(root.glob("WTF/Account/*/SavedVariables/Foresight.lua"))
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
    db = lua.globals().ForesightDB
    return lua_to_py(db) if db is not None else {}


def parse_savedvars(path: Path) -> dict:
    return parse_savedvars_text(path.read_text(encoding="utf-8"))


def sandbox_selfcheck() -> bool:
    """Prove the sandbox: hostile payloads must fail, benign data must parse.
    Called by run_tests.py - a regression here blocks the ship."""
    benign = parse_savedvars_text('ForesightDB = { ["version"] = 1, ["chars"] = {} }')
    if benign.get("version") != 1:
        return False
    hostile_payloads = [
        'ForesightDB = {} os.remove("x")',
        'ForesightDB = {} io.open("x")',
        'ForesightDB = {} python.eval("1+1")',
        'ForesightDB = {} require("os")',
        'ForesightDB = {} load("return 1")()',
    ]
    for payload in hostile_payloads:
        try:
            parse_savedvars_text(payload)
            return False  # payload executed without error = sandbox hole
        except (lupa.LuaError, ValueError):
            pass
    return True


def analyze_selfcheck() -> bool:
    """Prove the harvest->vote path end-to-end against real generated data: a synthetic
    probe must yield the expected hypothesis votes, trained and untrained. Called by
    run_tests.py - guards the lua_to_py table-shape contract (sparse ids stay keyed)
    and the voting math. Incident-to-gate: the id-flattening bug class stays dead."""
    gen = load_generated()
    talents = gen.get("talents")
    if not isinstance(talents, dict) or "26" not in talents:
        return False  # generated tables must arrive keyed by talent id, not as lists
    probe = {"talents": [
        # Concussion stores per-rank values (hypothesis B): rank-1 text says 1%.
        {"name": "Concussion", "rank": 0,
         "tooltip": "Increases the damage done by your Lightning Bolt, Chain Lightning, and Earth Shock spells by 1%."},
        {"name": "Concussion", "rank": 2,
         "tooltip": "Increases the damage done by your Lightning Bolt, Chain Lightning, and Earth Shock spells by 2%."},
        # Improved Fireball stores the max-rank total (hypothesis A): -500ms over 5
        # ranks -> rank-2 tooltip says 0.2 sec.
        {"name": "Improved Fireball", "rank": 2,
         "tooltip": "Reduces the casting time of your Fireball and Frostfire Bolt spells by 0.2 sec."},
    ]}
    analysis = analyze_rank_rule(probe, gen)
    if not (analysis["untrained_votes"]["B"] == 1 and analysis["votes"]["B"] == 1
            and analysis["votes"]["A"] == 1):
        return False
    # Captured-tooltip path (real in-game text incl. inspected players): the Rank
    # line must recover the rank, chrome must be stripped (its numbers would pollute
    # the vote), and the cleaned description must vote identically.
    tip_probe = probe_from_tooltips({"104753": {
        "name": "Concussion", "rank": None, "maxRank": 5,
        "text": "Concussion\nRank |cffffffff2|r/5\n \nIncreases the damage done by "
                "your Lightning Bolt, Chain Lightning, and Earth Shock spells by 2%."
                "\n \n|c0042b1fePress F6 to submit an issue for this Spell",
    }})
    t = tip_probe["talents"]
    if len(t) != 1 or t[0]["rank"] != 2 or "Rank" in t[0]["tooltip"] \
            or "F6" in t[0]["tooltip"]:
        return False
    tip_analysis = analyze_rank_rule(tip_probe, gen)
    if not (tip_analysis["votes"]["B"] == 1 and tip_analysis["votes"]["none"] == 0):
        return False
    # Per-talent rank-rule path: the tally must land on Concussion's id, decide
    # "perRank" from the trained vote, and render into the review draft.
    by_talent = tip_analysis["byTalent"]
    tid = next(iter(by_talent))
    if by_talent[tid]["trained"]["B"] != 1:
        return False
    rule, basis = decide_rank_rule(by_talent[tid])
    if rule != "perRank" or "trained" not in basis:
        return False
    draft = render_rank_rules_draft(by_talent, "testbuild", 1)
    return f'[{tid}] = "perRank"' in draft and "Concussion" in draft


def load_generated() -> dict:
    lua = lupa.LuaRuntime()
    load_chunk = lua.eval("function(src, name) local c = assert(load(src, '@'..name)); return c() end")
    for name in ("build", "talent_tabs", "talents", "talent_impacts", "spells",
                 "consumables"):
        f = GENERATED / f"{name}.lua"
        load_chunk(f.read_text(encoding="utf-8"), f.name)
    return lua_to_py(lua.globals().Foresight.gen)


NUM_RE = re.compile(r"(\d+\.?\d*)")
# Matches "Rank 0/2" and the color-coded "Rank |cffffffff0|r/2" alike.
TIP_RANK_RE = re.compile(r"Rank \D*?(\d+)\D*?/(\d+)")


def clean_tip_text(text: str) -> str:
    """Strip tooltip chrome before number extraction: the name line, the 'Rank N/M'
    line (its numbers would pollute the vote), and the beta 'Press F6' footer."""
    lines = (text or "").split("\n")
    kept = []
    for i, ln in enumerate(lines):
        if i == 0:
            continue  # the talent name line
        if "Rank " in ln and TIP_RANK_RE.search(ln):
            continue
        if "Press F6" in ln:
            continue
        kept.append(ln)
    return "\n".join(kept)


def probe_from_tooltips(tips: dict) -> dict:
    """Convert captured talentTooltips (REAL in-game text - including INSPECTED
    players' trees, where the journal's rank field can't resolve) into the rank-rule
    probe shape. The tooltip's own 'Rank N/M' line recovers the rank; the cleaned
    description text carries the vote."""
    talents = []
    for _, e in sorted(tips.items(), key=lambda kv: str(kv[0])):
        if not isinstance(e, dict):
            continue
        text = e.get("text") or ""
        rank = 0
        m = TIP_RANK_RE.search(text)
        if m:
            rank = int(m.group(1))
        elif e.get("rank"):
            rank = int(e["rank"])
        name = e.get("name") or (text.split("\n")[0] if text else "")
        body = clean_tip_text(text)
        if name and body.strip():
            talents.append({"name": name, "rank": rank, "tooltip": body})
    return {"talents": talents}


def analyze_rank_rule(probe: dict, gen: dict) -> dict:
    """Compare in-game tooltip numbers against generated maxValue under each hypothesis.

    A: stored value is the max-rank total  -> tooltip at rank R shows |v| * R / maxRank
    B: stored value is the per-rank value  -> tooltip at rank R shows |v| * R
    Values may be ms in data but seconds in tooltips, so /1000 variants are included.

    Trained ranks are the authoritative votes. Untrained (rank 0) talents still vote -
    classic-style tooltips show rank-1 text on untrained talents - but into a separate,
    clearly-presumed tally so a pre-level-10 probe already gives rank-rule signal.
    """
    talents_by_name = {}
    for tid, t in (gen.get("talents") or {}).items():
        talents_by_name.setdefault(t["name"], (tid, t))

    votes = {"A": 0, "B": 0, "either": 0, "none": 0}
    untrained = {"A": 0, "B": 0, "either": 0, "none": 0}
    by_talent: dict = {}
    details = []
    for entry in probe.get("talents", []):
        rank = entry.get("rank") or 0
        match = talents_by_name.get(entry["name"])
        if not match:
            continue
        tid, talent = match
        impacts = (gen.get("talentImpacts") or {}).get(tid) or {}
        tooltip_nums = {float(n) for n in NUM_RE.findall(entry.get("tooltip", ""))}
        trained = rank > 0
        box = votes if trained else untrained
        slot = by_talent.setdefault(str(tid), {
            "name": entry["name"],
            "trained": {"A": 0, "B": 0, "either": 0, "none": 0},
            "untrained": {"A": 0, "B": 0, "either": 0, "none": 0},
        })
        tbox = slot["trained"] if trained else slot["untrained"]
        eff_rank = rank if trained else 1
        tag = "" if trained else " (untrained r1 text)"
        for op in impacts.get("ops", []):
            v = abs(op.get("maxValue") or 0)
            if v == 0 or not tooltip_nums:
                continue
            max_rank = talent["maxRank"]
            pred_a = {round(v * eff_rank / max_rank, 2), round(v / 1000 * eff_rank / max_rank, 2)}
            pred_b = {round(v * eff_rank, 2), round(v / 1000 * eff_rank, 2)}
            hit_a = bool(pred_a & tooltip_nums)
            hit_b = bool(pred_b & tooltip_nums)
            if hit_a and hit_b:
                box["either"] += 1
                tbox["either"] += 1
            elif hit_a:
                box["A"] += 1
                tbox["A"] += 1
                details.append(f"A: {entry['name']} r{eff_rank}/{max_rank} v={v}{tag}")
            elif hit_b:
                box["B"] += 1
                tbox["B"] += 1
                details.append(f"B: {entry['name']} r{eff_rank}/{max_rank} v={v}{tag}")
            else:
                box["none"] += 1
                tbox["none"] += 1
    return {"votes": votes, "untrained_votes": untrained, "details": details,
            "byTalent": by_talent}


def _idkey(k) -> str:
    """Normalize a Lua-sourced id key ('12175', 12175, 12175.0) to one string form."""
    return str(int(float(k)))


def merge_by_talent(target: dict, add: dict) -> dict:
    """Accumulate per-talent vote tallies across probes/accounts."""
    for tid, slot in (add or {}).items():
        t = target.setdefault(tid, {
            "name": slot.get("name"),
            "trained": {"A": 0, "B": 0, "either": 0, "none": 0},
            "untrained": {"A": 0, "B": 0, "either": 0, "none": 0},
        })
        for box in ("trained", "untrained"):
            for k in ("A", "B", "either", "none"):
                t[box][k] += (slot.get(box) or {}).get(k, 0)
    return target


RULE_NAME = {"A": "maxTotal", "B": "perRank"}


def decide_rank_rule(slot: dict):
    """One talent's verdict from its tallies: (rule, basis) or (None, reason).
    Trained votes are authoritative; untrained r1 text decides only when unanimous
    and is tagged as the weaker basis. Contradictions are surfaced, never averaged."""
    tr, un = slot["trained"], slot["untrained"]
    if tr["A"] > 0 and tr["B"] > 0:
        return None, "contradicted (trained votes split)"
    if tr["A"] > 0 or tr["B"] > 0:
        side = "A" if tr["A"] > 0 else "B"
        return RULE_NAME[side], f"trained A={tr['A']} B={tr['B']}"
    if (un["A"] > 0) != (un["B"] > 0):
        side = "A" if un["A"] > 0 else "B"
        return RULE_NAME[side], f"untrained r1 text only (A={un['A']} B={un['B']})"
    if un["A"] > 0 and un["B"] > 0:
        return None, "contradicted (untrained votes split)"
    return None, "no discriminating votes"


def render_rank_rules_draft(by_talent: dict, build: str, accounts: int) -> str:
    """Human-review draft for overrides.rankRules - fully commented-out Lua. The
    review law is stated in the file; nothing is ever auto-applied."""
    lines = [
        f"-- DRAFT per-talent rank rules from captured tooltips (build {build}, "
        f"{accounts} account(s)).",
        "-- NEVER auto-applied. Human review (prefer more trained captures) before any",
        "-- line moves into overrides.rankRules in Foresight/data/overrides.lua.",
        '-- "maxTotal": stored value is the max-rank total (rank N = value*N/maxRank).',
        '-- "perRank":  stored value is per rank (rank N = value*N).',
        "",
        "-- decided:",
    ]
    undecided = []
    for tid, slot in sorted(by_talent.items(), key=lambda kv: int(kv[0])):
        rule, basis = decide_rank_rule(slot)
        if rule:
            weak = "untrained" in basis
            lines.append(f"--   [{tid}] = \"{rule}\", -- {slot['name']} ({basis})"
                         + ("  -- WEAK: hover it trained to confirm" if weak else ""))
        elif "contradicted" in (basis or ""):
            undecided.append(f"--   {slot['name']} (id {tid}): {basis} - "
                             f"trained {slot['trained']} untrained {slot['untrained']}")
    lines.append("")
    lines.append("-- contradicted (needs more trained captures before any call):")
    lines.extend(undecided or ["--   (none)"])
    return "\n".join(lines) + "\n"


def archive_matches_build(data, gen) -> bool:
    """Cross-fork guard (2026-10-12): the Forever harvest once swept the RETAIL
    install's SavedVariables in. An archive only contributes to aggregation when the
    build its sessions recorded matches OUR generated build; build-less archives pass
    (legacy shape, pre-journal)."""
    collect = (data or {}).get("collect") or {}
    sessions = collect.get("sessions") or []
    rows = list(sessions.values()) if isinstance(sessions, dict) else sessions
    build = None
    for s in rows:
        if isinstance(s, dict) and s.get("build"):
            build = s["build"]
    return build is None or str(build) == str(gen.get("build") or "?")


def aggregate_rank_rules(gen) -> None:
    """Merge per-talent rank-rule votes across archived harvests (newest per account,
    captured tooltips + the legacy probe) and write collected/rank_rules_draft.lua."""
    newest = {}
    for f in sorted(COLLECTED.glob("harvest-*.json")):
        newest[f.name.rsplit("-", 2)[0]] = f
    merged: dict = {}
    accounts = 0
    skipped_foreign = 0
    for account, f in newest.items():
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not archive_matches_build(data, gen):
            skipped_foreign += 1
            continue
        collect = data.get("collect") or {}
        contributed = False
        for probe in (probe_from_tooltips(collect.get("talentTooltips") or {}),
                      collect.get("talentProbe") or {}):
            if probe.get("talents"):
                merge_by_talent(merged, analyze_rank_rule(probe, gen)["byTalent"])
                contributed = True
        if contributed:
            accounts += 1
    if not merged:
        return
    build = str(gen.get("build") or "?")
    draft = render_rank_rules_draft(merged, build, accounts)
    (COLLECTED / "rank_rules_draft.lua").write_text(draft, encoding="utf-8")
    verdicts = [decide_rank_rule(s) for s in merged.values()]
    decided = sum(1 for rule, _ in verdicts if rule)
    trained_backed = sum(1 for rule, basis in verdicts
                         if rule and "untrained" not in basis)
    contradicted = sum(1 for _, basis in verdicts if "contradicted" in (basis or ""))
    foreign = (f" [{skipped_foreign} foreign-build archive(s) excluded]"
               if skipped_foreign else "")
    print(f"\nper-talent rank rules: {decided} decided ({trained_backed} trained-backed), "
          f"{contradicted} contradicted, {len(merged)} voted total -> "
          f"rank_rules_draft.lua (human review){foreign}")


# S11 observed-vs-generated: op kind -> snapshot field with a predicted flat value.
# Mirrors Collect.claimedFields in core/collect.lua - keep the two in sync.
OBS_STAT_FIELDS = {"Strength": "strength", "Agility": "agility", "Stamina": "stamina",
                   "Intellect": "intellect", "Spirit": "spirit"}


def predicted_fields(ops) -> dict:
    """field -> {"value", "exact"}: what the generated ops claim the stat sheet moves.
    Percent-based and statConvert ops predict no flat number (their base is
    per-character) - they are deliberately absent, never guessed. Melee/ranged crit
    are at-least predictions (exact=False): a stat op in the same buff (e.g. +Agility)
    adds derived crit on top of the flat critChance op."""
    out: dict = {}

    def add(field, value, exact=True):
        cur = out.setdefault(field, {"value": 0.0, "exact": True})
        cur["value"] += float(value)
        cur["exact"] = cur["exact"] and exact

    for op in ops or []:
        kind, v = op.get("kind"), op.get("maxValue") or 0
        if op.get("isPct"):
            continue
        if kind == "stat" and op.get("stat") in OBS_STAT_FIELDS:
            add(OBS_STAT_FIELDS[op["stat"]], v)
        elif kind == "armor":
            add("armor", v)
        elif kind == "attackPower":
            add("attackPower", v)
        elif kind == "rangedAttackPower":
            add("rangedAttackPower", v)
        elif kind == "maxHealth":
            add("maxHealth", v)
        elif kind == "maxPower" and (op.get("powerType") or 0) == 0:
            add("maxMana", v)
        elif kind == "critChance":
            add("spellCritPct", v)
            add("meleeCritPct", v, exact=False)
            add("rangedCritPct", v, exact=False)
        elif kind == "schoolDamage":
            add("spellDamage", v)
    return out


OBS_TOLERANCE = 0.5


def compare_observed(observed: dict, gen: dict) -> list[dict]:
    """Per observed buff, verdict each stat field against the generated prediction:
    confirmed = play agrees with the datamined op (within tolerance; at-least for
    derived-topped melee/ranged crit) · mismatch = play disagrees (correction evidence)
    · learned = play moved a field we had no claim for (an unknown buff teaching us)."""
    bys = {_idkey(k): v for k, v in (gen.get("buffsBySpell") or {}).items()}
    cons = {_idkey(k): v for k, v in (gen.get("consumables") or {}).items()}
    verdicts = []
    for sid, e in sorted(observed.items(), key=lambda kv: _idkey(kv[0])):
        key = _idkey(sid)
        item_id = bys.get(key)
        item_key = _idkey(item_id) if item_id is not None else None
        entry = cons.get(item_key) if item_key else None
        predicted = predicted_fields((entry or {}).get("ops"))
        fields = {}
        for f, ov in sorted((e.get("stats") or {}).items()):
            ov = float(ov)
            p = predicted.get(f)
            if p is None:
                fields[f] = {"observed": ov, "verdict": "learned"}
            elif p["exact"]:
                ok = abs(ov - p["value"]) <= OBS_TOLERANCE
                fields[f] = {"observed": ov, "predicted": p["value"],
                             "verdict": "confirmed" if ok else "mismatch"}
            else:
                ok = ov >= p["value"] - 0.01
                fields[f] = {"observed": ov, "predicted": p["value"],
                             "verdict": "confirmed" if ok else "mismatch",
                             "note": "flat + stat-derived (at-least)"}
        verdicts.append({"spellId": key, "itemId": item_key,
                         "name": (entry or {}).get("name") or f"spell {key}",
                         "n": int(e.get("n") or 1), "fields": fields})
    return verdicts


K_OF_N = 3  # distinct accounts that must agree before a draft line is paste-eligible


def render_overrides_draft(agg: dict, accounts: int, build: str) -> str:
    """The human-review draft: fully commented-out Lua, never loadable by accident.
    Confirmations become overrides.verifiedBuffs candidates; mismatches become
    consumableImpacts correction leads. The k-of-n + human-review law is stated in
    the file itself so a copy-paste can't outrun the doctrine."""
    lines = [
        f"-- DRAFT overrides from observed-vs-generated (build {build}, "
        f"{accounts} account(s) harvested).",
        f"-- NEVER auto-applied. Law: k-of-n (>= {K_OF_N} distinct accounts) + human",
        "-- review before any line moves into Foresight/data/overrides.lua.",
        "",
        "-- verifiedBuffs candidates (play CONFIRMED the generated values):",
    ]
    corrections = []
    for sid, per_field in sorted(agg.items()):
        confirmed, item_id, name = {}, None, f"spell {sid}"
        for f, slot in sorted(per_field.items()):
            item_id, name = slot.get("itemId") or item_id, slot.get("name") or name
            if slot["mismatch"] == 0 and slot["confirm"] >= 1:
                confirmed[f] = slot["observed"][-1]
            elif slot["mismatch"] >= 1:
                corrections.append(
                    f"--   item {item_id or '?'} {name} field {f}: generated "
                    f"{slot.get('predicted')}, observed {slot['observed']} "
                    f"({slot['confirm'] + slot['mismatch']} account(s))")
        if confirmed and item_id:
            n = max(s["confirm"] for s in per_field.values())
            tag = "" if n >= K_OF_N else f"  -- n<{K_OF_N}: pilot evidence only"
            fields = ", ".join(f"{f} = {v:g}" for f, v in sorted(confirmed.items()))
            lines.append(f"--   [{item_id}] = {{ build = \"{build}\", accounts = {n}, "
                         f"fields = {{ {fields} }} }}, -- {name}{tag}")
    lines.append("")
    lines.append("-- consumableImpacts correction leads (play DISAGREED - investigate,")
    lines.append("-- then draft a replacement entry with the observed numbers):")
    lines.extend(corrections or ["--   (none)"])
    return "\n".join(lines) + "\n"


def aggregate_observed(gen) -> None:
    """Merge observedImpacts across archived harvests (newest per account), compare
    against generated predictions, and write collected/observed_impacts.json plus the
    human-review draft collected/overrides_draft.lua. Nothing is ever auto-applied."""
    newest = {}
    for f in sorted(COLLECTED.glob("harvest-*.json")):
        newest[f.name.rsplit("-", 2)[0]] = f
    agg: dict = {}
    harvested = 0
    for account, f in newest.items():
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if not archive_matches_build(data, gen):
            continue
        obs = (data.get("collect") or {}).get("observedImpacts") or {}
        if not obs:
            continue
        harvested += 1
        for v in compare_observed(obs, gen):
            for fname, fv in v["fields"].items():
                slot = agg.setdefault(v["spellId"], {}).setdefault(fname, {
                    "name": v["name"], "itemId": v["itemId"],
                    "confirm": 0, "mismatch": 0, "learned": 0,
                    "predicted": fv.get("predicted"), "observed": []})
                key = {"confirmed": "confirm", "mismatch": "mismatch",
                       "learned": "learned"}[fv["verdict"]]
                slot[key] += 1
                slot["observed"].append(fv["observed"])
    if not agg:
        return
    build = str(gen.get("build") or "?")
    (COLLECTED / "observed_impacts.json").write_text(
        json.dumps({"build": build, "accounts": harvested, "spells": agg}, indent=1),
        encoding="utf-8")
    draft = render_overrides_draft(agg, harvested, build)
    (COLLECTED / "overrides_draft.lua").write_text(draft, encoding="utf-8")
    n_confirm = sum(1 for pf in agg.values() for s in pf.values()
                    if s["mismatch"] == 0 and s["confirm"] >= 1)
    n_mismatch = sum(1 for pf in agg.values() for s in pf.values() if s["mismatch"] >= 1)
    n_learned = sum(1 for pf in agg.values() for s in pf.values() if s["learned"] >= 1)
    print(f"\nobserved-vs-generated: {len(agg)} buff(s) across {harvested} account(s) -> "
          f"{n_confirm} field(s) confirmed, {n_mismatch} mismatch(es), "
          f"{n_learned} learned -> overrides_draft.lua (k-of-n + human review)")


def observed_selfcheck() -> bool:
    """Prove observed-vs-generated end-to-end on real generated data: an observation
    matching the datamined ops reads confirmed, a skewed one mismatch, an unknown
    spell learned - and the draft renderer emits both sections. Called by
    run_tests.py; a regression here blocks the ship."""
    gen = load_generated()
    entry = (gen.get("consumables") or {}).get("10305")  # Scroll of Protection IV
    if not entry or not entry.get("buffSpellId"):
        return False
    sid = _idkey(entry["buffSpellId"])
    armor = entry["ops"][0]["maxValue"]
    verdicts = {v["spellId"]: v for v in compare_observed({
        sid: {"stats": {"armor": armor}, "n": 2},
        "999999999": {"stats": {"spirit": 9}, "n": 1},
    }, gen)}
    if verdicts[sid]["fields"]["armor"]["verdict"] != "confirmed":
        return False
    if verdicts["999999999"]["fields"]["spirit"]["verdict"] != "learned":
        return False
    bad = compare_observed({sid: {"stats": {"armor": armor - 100}, "n": 1}}, gen)[0]
    if bad["fields"]["armor"]["verdict"] != "mismatch":
        return False
    agg = {sid: {"armor": {"name": entry["name"], "itemId": "10305", "confirm": 1,
                           "mismatch": 0, "learned": 0, "predicted": float(armor),
                           "observed": [float(armor)]}},
           "2": {"spirit": {"name": "spell 2", "itemId": None, "confirm": 0,
                            "mismatch": 1, "learned": 0, "predicted": 5.0,
                            "observed": [9.0]}}}
    draft = render_overrides_draft(agg, 1, str(gen.get("build") or "?"))
    return ("[10305]" in draft and "pilot evidence" in draft
            and "field spirit: generated 5.0, observed [9.0]" in draft)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wow-root", action="append", type=Path, default=None)
    args = parser.parse_args()
    roots = args.wow_root or DEFAULT_ROOTS

    files = find_savedvars(roots)
    if not files:
        print("no Foresight SavedVariables found - log out of the game at least once")
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
        newest = sessions[-1] if sessions else {}
        newest_ver = newest.get("addonVersion")
        want = shipped_version()
        print(f"\n== {path}")
        print(f"   archived -> {dest.name}")
        print(f"   file written: {stamp} | newest session: v{newest_ver} @ {newest.get('at')}")
        if want and newest_ver and newest_ver != want:
            print(f"   !! STALE: newest in-game session is v{newest_ver} but the shipped "
                  f"build is v{want}. Reload/relog in-game to load + flush the current "
                  f"version before trusting this data.")
        print(f"   sessions={len(sessions)} level-ups journaled={len(levels)} "
              f"reports={len(data.get('reports') or [])}")
        if verify:
            fails = [r for r in verify.get("results", []) if not r.get("ok")]
            print(f"   verify@{verify.get('at')}: {len(verify.get('results', []))} checks, "
                  f"{len(fails)} flagged")
            for r in fails:
                print(f"     CHECK {r['name']}: {r.get('detail')}")
            for r in verify.get("results", []):
                if r.get("name") == "talent API shape discovery" and r.get("detail"):
                    print(f"     talent API shape: {r['detail']}")
        ttp = collect.get("traitTipProbe")
        if ttp:
            print(f"   trait-tooltip hook last fired: {json.dumps(ttp, ensure_ascii=False)}")
        if collect.get("lastTooltipOwner"):
            print(f"   last tooltip owner frame: {collect['lastTooltipOwner']}")
        # CONSUME-buffs QA loop: what the consumable tooltip actually did in-game.
        buff_log = collect.get("buffTipLog") or []
        if buff_log:
            print(f"   consumable tooltips injected ({len(buff_log)} recent):")
            for e in buff_log:
                print(f"     {e.get('at')} item {e.get('itemId')} {e.get('name')}")
        missed = collect.get("missedConsumables") or {}
        if missed:
            print(f"   !! consumables hovered WITHOUT data ({len(missed)}) - pipeline gaps:")
            for iid, e in sorted(missed.items(), key=lambda kv: str(kv[0])):
                print(f"     item {iid} {e.get('name')} subclass={e.get('subClass')} "
                      f"seen x{e.get('count')}")
        shape = collect.get("talentApiShape") or {}
        if shape:
            print(f"   talent API shape probe @{shape.get('at')}:")
            for label, info in (shape.get("calls") or {}).items():
                print(f"     {label}: {json.dumps(info, ensure_ascii=False)}")
            if shape.get("setTalentProbe"):
                print(f"     GameTooltip:SetTalent(1,1) -> {json.dumps(shape['setTalentProbe'], ensure_ascii=False)}")
            tw = shape.get("traitWalk")
            if tw:
                print(f"     C_Traits walk: nodes={tw.get('nodes')} purchased={tw.get('purchased')} "
                      f"mapped-to-generated={tw.get('mappedToGenerated')}")
                for s in (tw.get("sample") or []):
                    print(f"       {json.dumps(s, ensure_ascii=False)}")
        if probe:
            analysis = analyze_rank_rule(probe, gen)
            print(f"   talent tooltip probe: {len(probe.get('talents', []))} talents; "
                  f"rank-rule votes (trained): {analysis['votes']}; "
                  f"presumed (untrained r1 text): {analysis['untrained_votes']}")
            for d in analysis["details"][:20]:
                print(f"     {d}")
        reports = collect.get("reports") or {}
        if reports:
            rrows = list(reports.values()) if isinstance(reports, dict) else reports
            print(f"   USER REPORTS ({len(rrows)}) pending review (/foresight report):")
            for rpt in rrows:
                if isinstance(rpt, dict):
                    print(f"      {rpt.get('at')} v{rpt.get('version')} "
                          f"L{rpt.get('level')} {rpt.get('classToken')}: "
                          f"{rpt.get('note') or '(no note - check Screenshots folder)'}")
        vr = collect.get("verify") or {}
        watch = vr.get("apiWatch") if isinstance(vr, dict) else None
        if watch:
            absent = sorted(k for k, present in watch.items() if not present)
            if absent:
                print("   API WATCH - absent on this client: " + ", ".join(absent))
            # Drift vs the previous harvest: the live-launch tripwire (the GetItemInfo
            # class - a build moving an API must be a report, never a silent outage).
            last_path = COLLECTED / "api_watch_last.json"
            if last_path.exists():
                try:
                    prev = json.loads(last_path.read_text(encoding="utf-8"))
                except (ValueError, OSError):
                    prev = {}
                drift = [f"{k}: {prev[k]} -> {watch[k]}"
                         for k in sorted(watch) if k in prev and prev[k] != watch[k]]
                if drift:
                    print("   !! API DRIFT since the last harvest (update the shims):")
                    for d in drift:
                        print(f"      {d}")
            last_path.write_text(json.dumps(watch, indent=1, sort_keys=True),
                                 encoding="utf-8")
        taints = collect.get("taintEvents") or {}
        if taints:
            rows = list(taints.values()) if isinstance(taints, dict) else taints
            print(f"   !! TAINT EVENTS ({len(rows)}) - the client blocked a protected "
                  "action naming Foresight (account-safety doctrine: fix before anything):")
            for t in rows:
                if isinstance(t, dict):
                    print(f"      {t.get('at')}: {t.get('event')} func={t.get('func')} "
                          f"talentUIopen={t.get('talentUIOpen')} combat={t.get('inCombat')}")
        sightings = collect.get("itemSightings") or {}
        if sightings:
            print(f"   item sightings: {len(sightings)} distinct items seen on this account")
        unknown_stats = collect.get("unknownItemStats") or {}
        if unknown_stats:
            top = sorted(unknown_stats.items(), key=lambda kv: -int(kv[1] or 0))[:10]
            print("   UNMAPPED item stat keys seen live (map or defer, never drop "
                  "silently): " + ", ".join(f"{k} x{v}" for k, v in top))
        audit = collect.get("hitAudit") or {}
        audit_rows = audit.get("rows") if isinstance(audit, dict) else None
        if audit_rows:
            rows = list(audit_rows.values()) if isinstance(audit_rows, dict) else audit_rows
            tally: dict = {}
            for r in rows:
                if isinstance(r, dict):
                    v = r.get("verdict") or "?"
                    tally[v] = tally.get(v, 0) + 1
            print(f"   spell-tooltip AUDIT ({audit.get('at', '?')}): {tally} "
                  "(gear = model confirmed incl. gear fold; base = tooltip ignores "
                  "gear; mismatch = investigate)")
            for r in rows:
                if isinstance(r, dict) and r.get("verdict") == "mismatch":
                    print(f"     !! {r.get('name')}: tooltip {r.get('tipMin')}-"
                          f"{r.get('tipMax')} vs base {r.get('baseMin')}-"
                          f"{r.get('baseMax')} / gear {r.get('gearMin')}-{r.get('gearMax')}")
        tips = collect.get("talentTooltips") or {}
        if tips:
            tip_probe = probe_from_tooltips(tips)
            trained = sum(1 for t in tip_probe["talents"] if t["rank"] > 0)
            print(f"   talent tooltips captured (real in-game text): {len(tips)} nodes "
                  f"({trained} at a trained rank via the Rank-line parse - "
                  f"rank-scaling ground truth)")
            for nid, e in list(tips.items())[:4]:
                if isinstance(e, dict):
                    first = (e.get("text") or "").split("\n")[0]
                    print(f"     {e.get('name') or nid} r{e.get('rank')}/{e.get('maxRank')}: {first!r}")
            analysis = analyze_rank_rule(tip_probe, gen)
            print(f"   captured-tooltip rank-rule votes: trained {analysis['votes']}; "
                  f"presumed (untrained r1 text) {analysis['untrained_votes']}")
            for d in analysis["details"][:12]:
                print(f"     {d}")
        observed = collect.get("observedImpacts") or {}
        if observed:
            print(f"   observed buff impacts ({len(observed)}) - live ground truth "
                  f"vs generated:")
            marks = {"confirmed": "OK", "mismatch": "!!", "learned": "??"}
            for v in compare_observed(observed, gen):
                parts = []
                for f, fv in sorted(v["fields"].items()):
                    pred = ("" if fv.get("predicted") is None
                            else f" (gen {fv['predicted']:+g})")
                    parts.append(f"{marks[fv['verdict']]} {f} {fv['observed']:+g}{pred}")
                print(f"     {v['name']} (spell {v['spellId']}, n={v['n']}): "
                      f"{', '.join(parts)}")
        if not verify and not probe:
            print("   no verify/probe data yet - run /foresight verify in-game, then log out")

    aggregate_sightings(gen)
    aggregate_observed(gen)
    aggregate_rank_rules(gen)
    return exit_code


def aggregate_sightings(gen) -> None:
    """Crowd-DB phase A (pilot scale): merge item sightings across ALL archived
    harvests - newest archive per account wins (the journal is cumulative) - into
    collected/item_sightings.json with a distinct-ACCOUNT count per item (the k-of-n
    seed). Cross-checks the generated consumables table: a sighted id is live-game
    CONFIRMED; data the crowd never sees stays datamined-only until it is."""
    newest_per_account = {}
    for f in sorted(COLLECTED.glob("harvest-*.json")):
        account = f.name.rsplit("-", 2)[0]
        newest_per_account[account] = f  # sorted() leaves the newest stamp last
    merged = {}
    for account, f in newest_per_account.items():
        try:
            data = json.loads(f.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        for item_id, entry in ((data.get("collect") or {}).get("itemSightings") or {}).items():
            m = merged.setdefault(str(item_id), {"accounts": 0, "seen": 0})
            m["accounts"] += 1
            m["seen"] += int(entry.get("c") or 1) if isinstance(entry, dict) else 1
    if not merged:
        return
    out = COLLECTED / "item_sightings.json"
    out.write_text(json.dumps({"items": merged, "accounts": len(newest_per_account)},
                              indent=1), encoding="utf-8")
    consumable_ids = set((gen.get("consumables") or {}).keys()) if gen else set()
    confirmed = [i for i in merged if int(i) in consumable_ids or i in consumable_ids]
    print(f"\ncrowd DB (pilot): {len(merged)} distinct items sighted across "
          f"{len(newest_per_account)} account(s) -> {out.name}")
    if consumable_ids:
        print(f"   {len(confirmed)} sighted item(s) confirm generated consumable data "
              f"as live-obtainable")


if __name__ == "__main__":
    sys.exit(main())
