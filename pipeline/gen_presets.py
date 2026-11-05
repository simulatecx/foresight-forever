"""Preset/example talent builds for the planner (UI-talent-planner enhance).

For each class and each talent tree (tab), compute ONE legal "deep" example build that
spends points down to that tree's capstone - the recognizable "spec deep into this tree"
starting point a new player can load and tweak. Pure + data-driven: it reads the same
generated talent grid the addon ships and replays the planner's own legality rules
(POINTS_PER_TIER tier unlocks + prerequisites + maxRank), so a preset is legal BY
CONSTRUCTION and never needs hand-maintenance across balance patches. Emitted as the
flavor's own build code (FT1F for Forever / FT1 for classic) so the addon loads it through
the one existing `loadBuild` -> `TB.decode` path, which re-validates with `isLegal`.

generate.py calls `build_presets(...)` and writes `preset_builds.lua`; run_tests pins that
every emitted build is legal on both flavors.
"""

POINTS_PER_TIER = 5     # mirror TB.POINTS_PER_TIER (classic tier-unlock basis)
TARGET_POINTS = 31      # the classic deep-spec number: 30 below + the tier-6 capstone


def _tabs_for_class(tabs, class_mask):
    """Tab ids whose classMask == this class's mask, in display order."""
    out = [tid for tid, t in tabs.items() if t.get("classMask") == class_mask]
    out.sort(key=lambda tid: (tabs[tid].get("order", 0), tid))
    return out


def _talents_in_tab(talents, tab_id):
    """Talent ids in a tab, canonical (tier, column, id) order - the encode slot order."""
    out = [tid for tid, t in talents.items() if t.get("tab") == tab_id]
    out.sort(key=lambda tid: (talents[tid].get("tier", 0),
                              talents[tid].get("column", 0), tid))
    return out


def _points_below_tier(talents, build, tab_id, tier):
    return sum(r for tid, r in build.items()
               if talents[tid].get("tab") == tab_id and talents[tid].get("tier", 0) < tier)


def _can_add(talents, build, tid):
    t = talents[tid]
    if build.get(tid, 0) >= t.get("maxRank", 1):
        return False
    if _points_below_tier(talents, build, t.get("tab"), t.get("tier", 0)) \
            < POINTS_PER_TIER * t.get("tier", 0):
        return False
    for pr in t.get("prereqs", []):
        if build.get(pr["talent"], 0) < pr.get("rank", 1):
            return False
    return True


def _add_prereq_chain(talents, build, tid):
    """Satisfy tid's prereqs (recursively) to their required rank. Returns False if a
    prereq points at an unknown talent (defensive - never raise on odd data)."""
    t = talents.get(tid)
    if not t:
        return False
    for pr in t.get("prereqs", []):
        ptid, prank = pr["talent"], pr.get("rank", 1)
        if ptid not in talents:
            return False
        if not _add_prereq_chain(talents, build, ptid):
            return False
        build[ptid] = max(build.get(ptid, 0), prank)
    return True


def _deep_build(talents, tab_id):
    """A legal build that reaches this tab's capstone and spends up to TARGET_POINTS.

    Minimum-spine-then-fill: lay the prereq chain to the deepest talent, fill the base
    bottom-up until the capstone tier unlocks, allocate the capstone, then round out the
    remaining budget into the deepest talents still addable. Every step goes through
    _can_add, so the result passes TB.isLegal."""
    in_tab = _talents_in_tab(talents, tab_id)
    if not in_tab:
        return {}
    max_tier = max(talents[tid].get("tier", 0) for tid in in_tab)
    # Capstone = a deepest-tier talent, preferring one with a prereq chain (the real
    # capstone), tiebreak lowest column for determinism.
    capstones = [tid for tid in in_tab if talents[tid].get("tier", 0) == max_tier]
    capstones.sort(key=lambda tid: (0 if talents[tid].get("prereqs") else 1,
                                    talents[tid].get("column", 0), tid))
    capstone = capstones[0]
    build = {}

    # 1) prereq chain to the capstone (so the spine is present and legal)
    _add_prereq_chain(talents, build, capstone)

    def total():
        return sum(build.values())

    # 2) fill the base bottom-up until the capstone's tier is unlocked
    guard = 0
    while _points_below_tier(talents, build, tab_id, max_tier) < POINTS_PER_TIER * max_tier \
            and total() < TARGET_POINTS and guard < 500:
        guard += 1
        # lowest-tier addable talent below the capstone tier; prefer ones already
        # started (finish what we began) then prereqs, for a tidy spine.
        cands = [tid for tid in in_tab
                 if talents[tid].get("tier", 0) < max_tier and _can_add(talents, build, tid)]
        if not cands:
            break
        cands.sort(key=lambda tid: (talents[tid].get("tier", 0),
                                    0 if build.get(tid) else 1,
                                    0 if talents[tid].get("prereqs") else 1,
                                    talents[tid].get("column", 0), tid))
        build[cands[0]] = build.get(cands[0], 0) + 1

    # 3) the capstone itself (max it if budget allows)
    guard = 0
    while _can_add(talents, build, capstone) and total() < TARGET_POINTS and guard < 20:
        guard += 1
        build[capstone] = build.get(capstone, 0) + 1

    # 4) spend the remainder into the deepest talents still addable (round out the spec)
    guard = 0
    while total() < TARGET_POINTS and guard < 500:
        guard += 1
        cands = [tid for tid in in_tab if _can_add(talents, build, tid)]
        if not cands:
            break
        cands.sort(key=lambda tid: (-talents[tid].get("tier", 0),
                                    0 if build.get(tid) else 1,
                                    talents[tid].get("column", 0), tid))
        build[cands[0]] = build.get(cands[0], 0) + 1

    return build


def _encode(prefix, class_token, talents, tabs, tab_ids, build):
    """Port of TB.encode: per tab, the ranks of its talents in canonical order, trailing
    zeros trimmed, joined. Same slot order TB.decode reads back, so the code round-trips."""
    parts = []
    for tab_id in tab_ids:
        digits = "".join(str(min(9, build.get(tid, 0))) for tid in _talents_in_tab(talents, tab_id))
        parts.append(digits.rstrip("0"))
    return "{}-{}-{}".format(prefix, class_token.upper(), "-".join(parts))


def build_presets(talents, tabs, classes, flavor):
    """Return a list of {class, classId, spec, tab, points, code} - one deep example per
    (class, tree). `talents` keyed by talent/node id, `tabs` by tab id, `classes` maps
    classId -> {token,...}. Pure; generate.py writes the Lua."""
    prefix = "FT1F" if flavor != "classic" else "FT1"
    out = []
    # class mask for a classId: tabs carry classMask; map via any tab's talents' classId.
    # Build classId -> mask from the tabs the talents actually use.
    cid_mask = {}
    for tid, t in talents.items():
        cid = t.get("classId")
        tab = tabs.get(t.get("tab"))
        if cid is not None and tab and tab.get("classMask"):
            cid_mask.setdefault(cid, tab["classMask"])
    for cid in sorted(classes):
        token = classes[cid].get("token") or classes[cid].get("name", "").upper()
        mask = cid_mask.get(cid)
        if not mask:
            continue
        for tab_id in _tabs_for_class(tabs, mask):
            # only this class's talents in the tab (guard against shared-mask oddities)
            tab_talents = {tid: t for tid, t in talents.items()
                           if t.get("tab") == tab_id and t.get("classId") == cid}
            if not tab_talents:
                continue
            build = _deep_build(talents, tab_id)
            # keep only this tab's allocations (the spine never leaves its tab)
            build = {tid: r for tid, r in build.items() if talents[tid].get("tab") == tab_id}
            if not build:
                continue
            code = _encode(prefix, token, talents, tabs,
                           _tabs_for_class(tabs, mask), build)
            out.append({
                "class": token,
                "classId": cid,
                "spec": tabs[tab_id].get("name", "Tree"),
                "tab": tab_id,
                "points": sum(build.values()),
                "code": code,
            })
    return out
