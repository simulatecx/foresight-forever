# Foresight Architecture Audit - 2026-10-12 (v0.35.0, selftest 227)

Purpose: the measured module map, data-element inventory, and client-coupling census
that back (a) the modular split and (b) the Retail validation fork
(`docs/RETAIL-FORK-HANDOFF.md`). Method: `_G.<API>` reference census across all 38
TOC files + shape review of every generated table. Numbers below are measured, not
asserted.

## 1. The four layers (measured portability)

**ENGINE - zero client API touches (only the addon-namespace boilerplate). Fork-portable byte-for-byte:**
`graph/graph.lua` (typed modifier DAG), `graph/dimensions.lua` (8 lenses + humanValue),
`model/loadout.lua` (snapshot+delta stack, applyOps - the ONE op folder),
`model/impact.lua` (evaluate/diff/verdict/coaching/rankStats), `model/sim.lua`
(abilityHit/weaponSwap/cascades/standings - 542 lines, pure), `model/mapping.lua`,
`model/levers.lua` (op->lever taxonomy + completeness gate), `model/synergy.lua`,
`model/catalog.lua`, `model/plan.lua`, `model/racials.lua`, `ui/panel_model.lua`
(pure models incl. pathway/focus/matrix), `data/formulas.lua` STRUCTURE (the registry
+ resolution paths; the VALUES are data, see layer 3). Exceptions inside mostly-pure
files: `model/imbues.lua` touches IsPlayerSpell/IsSpellKnown (2 calls - move to
adapter on next touch).

**ADAPTER - all client coupling lives here (refs measured):**
`core/guards.lua` (5: secret-value system), `core/client.lua` (NEW v0.36.0: the
C_Item/global namespacing shims - THE swap point for API migrations),
`core/talent_api.lua` (25: C_Traits walk + classic fallback; built for Mainline =
retail-compatible by design), `model/snapshot.lua` (30: the stat-sheet read),
`core/collect.lua` (58: probes/journals/apiWatch), `core/init.lua` (39: slash, boot,
taint sentinel, Screenshot), and the frame halves of `ui/tooltips.lua` (63 - the pure
line builders in the same file are engine), `ui/stats_panel.lua` (21),
`ui/matrix_panel.lua` (23), `ui/synergy_highlight.lua` (22 - overlay layer, combat
gates), `ui/export.lua` (8).

**DATA - per-game artifacts, never cross forks:**
`data/generated/*` (11 files, regenerated per build), `data/overrides.lua` (curated,
harvest-fed, human-reviewed), `data/loops.lua` (class loops - curated per game),
`data/formulas.lua` VALUES (classic-presumed constants: regen, conversions,
normalization, crit mults - a Retail fork swaps these for retail laws or marks them
unknown).

**PIPELINE - shared tooling, parameterized by --build:**
`fetch.py` (wago.tools, hosts retail AND Forever), `generate.py` (the decode laws -
the modern SpellEffect layout is IDENTICAL on retail; that is the fork's whole
premise), `harvest.py` (sandboxed SV parsing, voting, drift/audit/report surfacing),
`run_tests.py` + `check_compliance.py` (ship gate incl. Lua 5.1 dialect lint),
`deploy.py`.

## 2. Data element inventory

**Generated tables (from build 1.60.1.70338):**
- `build.lua` - build/channel/generated stamp + counts (talents 432,
  talentsWithRankValues 31, tabs 27, spells 3520, spellsWithDamage 509,
  spellsWithWeaponHit 158, spellsWithHeal 145, impactsNeedingCuration 158, traitNodes
  555, racials 10 races / 45 spells, consumables 390, imbues 378, items 4621) +
  classNames. Counts exist so regressions show in diffs.
- `spells.lua` - per spell: name, school(mask), castMs, durationMs, level, baseLevel?,
  cooldownMs, cost/powerType/costPctBase, tickMs, dmg{base,var,lvl,maxLvl,coef},
  heal{same}, wpn{pct,flat,norm}, dotTick, grants[ops]+grantsFrom (totem chase).
- `talents.lua`/`talent_tabs.lua`/`talent_impacts.lua` - classic Talent.csv lineage:
  position/maxRank/spellRanks/descByRank/prereqs; ops {kind, aura, maxValue,
  values[perRank]?, rankRule, isPct, property, affected[], school, stat, to/from}.
- `traits.lua` - ALL 555 live C_Traits nodes (the real Forever talent system):
  nodes{tree,type,spellID,name,maxRank,ops(+bridged values),entries?,needsCuration},
  bySpell index, trees->skillLine.
- `race_racials.lua`, `consumables.lua`(+buffsBySpell), `weapon_imbues.lua`,
  `items.lua` (4,621 statted, speedMs on weapons), `sim_procs.lua` (critHaste).

**Formula registry (data/formulas.lua) - every law confidence-tagged:**
manaRegenTick, healthRegenTick (classic-presumed, byClass) · swingTime ·
spellCoefficient (castMs/3.5 fallback) · spellBaseDamage (datamined-presumed; fn +
the floor/ceil display envelope, live-verified on Lightning Bolt) · critMultiplier
(melee 2x / spell 1.5x) · armorMitigation · talentRankValue (disputed) +
talentRankValueFor (THE resolution path: op.values > overrides.rankRules > default) +
rankRuleMark · threatModel · statConversions (per-class AP/crit rates) ·
weaponNormalization (1.7/2.4/3.3/2.8) · flurryUptime · presumedMark/get/setConfidence.

**SavedVariables (ForesightDB; type-validated on every read - untrusted-input law):**
settings{goal, synergy{theme,focus}, matrix{pos,opacity,loop}, panel pos} ·
plan[typed deltas] · collect{sessions, levels, verify{results, apiWatch},
talentTooltips (no-downgrade law), traitTipProbe, buffTipLog, missedConsumables,
itemSightings, observedImpacts, hitAudit, unknownItemStats, taintEvents, reports,
lastTooltipOwner}.

**Pipeline artifacts (`pipeline/collected/`, gitignored - the data moat):**
harvest-*.json archives · rank_rules_draft.lua · overrides_draft.lua ·
observed_impacts.json · item_sightings.json · api_watch_last.json (drift baseline).

## 3. Client-coupling census (the fork work surface)

| file | _G refs | dominant APIs |
|---|---|---|
| ui/tooltips.lua | 63 | hooksecurefunc, C_Item, GameTooltip, GetInventoryItemLink |
| core/collect.lua | 58 | CreateFrame, C_Timer, UnitClass/Race, C_Container |
| core/init.lua | 39 | date, Screenshot, CreateFrame, PlayerSpellsFrame |
| model/snapshot.lua | 30 | UnitStat/Damage/Race, C_Item, Get*Chance |
| core/talent_api.lua | 25 | C_Traits, classic talent globals (fallback) |
| ui/matrix_panel.lua | 23 | CreateFrame, GameTooltip, C_Timer |
| ui/synergy_highlight.lua | 22 | InCombatLockdown, CreateFrame |
| ui/stats_panel.lua | 21 | CreateFrame, GameTooltip, RAID_CLASS_COLORS |
| everything else (29 files) | <=8 each | namespace boilerplate only |

Known API-migration pairs are shimmed in `core/client.lua` and watched by
`Collect.apiWatch` (~40 paths, journaled per login, drift-diffed by the harvest).

## 4. Modularization actions

Done (v0.36.0): `core/client.lua` extracted - item-API shims shared by tooltips +
snapshot; single swap point per fork.
Next (file-level, low risk, in order): move imbues.lua's IsPlayerSpell/IsSpellKnown
behind HM.Client · move tooltips' scan-frame helpers (weaponFacts/scanSpellRange/
liveTipTexts) into a `ui/scanner.lua` adapter · split tooltips.lua pure line-builders
from the hook half (same table, two files) when it next grows. NOT planned: a
folder-level engine/ restructure - the TOC order IS the module system and churn would
reset the beta verification state for no behavioral gain.
