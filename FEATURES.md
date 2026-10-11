# Foresight - Capability Inventory

Answers "do we already have this?" in one read. IDs are durable handles; grep an ID in
CHANGELOG.md for its history. Last reviewed: 2026-10-10.

## DATA - data pipeline & shipped data
- ☑ `DATA-pipeline-fetch` - download Forever DB2 tables from wago.tools, cached per build -> `pipeline/fetch.py`
- ☑ `DATA-pipeline-generate` - compute talent->affected-spells via class masks, emit Lua tables -> `pipeline/generate.py`
- ☑ `DATA-generated-tables` - talents, tabs, impacts, 3,520 spells, 555 trait nodes, 45 racial spells across 10 races, 390 consumable buffs, 378 weapon imbues, 4,663 statted gear items -> `Foresight/data/generated/`
- ☑ `DATA-formula-registry` - confidence-tagged conversion math (regen, swing, coefficients, rank rule) -> `Foresight/data/formulas.lua`
- ☑ `DATA-overrides` - curated corrections layered over generated data -> `Foresight/data/overrides.lua`
- ◐ `DATA-items` - gear compare (v0.9.0): `Impact.compareItems` + item tooltip "vs equipped" via live GetItemStats (exact amounts). GEAR SEED (v0.19.0): `items.lua` = 4,663 statted equippable items decoded from client ItemSparse (name/slot/ilvl/reqLevel/quality + stat TYPES; amounts stay live, no budget-system guessing); `/foresight items <stat>` browse-by-stat. Secondary stats (Dodge/Parry/Defense/ratings/pen) now first-class in the vocabulary + levers. Remaining: offline amount computation (optional), bridge notable gear into synergy -> `pipeline/generate.py`, `Foresight/data/generated/items.lua`, `Foresight/model/catalog.lua`
- ☐ `DATA-professions` - profession recipes as modifier sources (deferred)
- ☑ `DATA-traits` - Retail Trait DB2 (TraitNode/TraitNodeEntry/TraitNodeXTraitNodeEntry/TraitDefinition/SkillLineXTraitTree) -> `traits.lua`: 555 nodes keyed by nodeID with spellID/name/maxRank/ops (via shared build_ops) + bySpell index + tree->class. Covers ALL live nodes incl new Forever talents; adapter resolves every selection by nodeID; `Loadout:withTraitNode` folds any node's ops into the what-if model (phase 2, v0.8.3) -> `pipeline/generate.py`, `Foresight/data/generated/traits.lua`, `Foresight/model/loadout.lua`

## GRAPH - impact engine
- ☑ `GRAPH-impact-engine` - typed modifier DAG with stacking rules, breakdowns, cycle detection -> `Foresight/graph/graph.lua`
- ☑ `GRAPH-dimensions` - 8 outcome lenses (spellcasting, melee/ranged DPS, healing, tankability, survivability, sustain, threat), v0 heuristics -> `Foresight/graph/dimensions.lua`
- ◐ `GRAPH-threat` - threat as the 8th outcome lens: own-state threat % from talents (SPELL_AURA_MOD_THREAT mapped to a "threat" op, school-verified vs tooltips) folded through agg.threatModPct; (p) classic-presumed. Live signal pending the S3 talent-read unblock; per-ability base threat + stance are future (overrides.abilityThreat, k-of-n) -> `Foresight/graph/dimensions.lua`, `Foresight/data/formulas.lua`

## MODEL - character modelling
- ☑ `MODEL-snapshot` - live character capture, secret-guarded (API indices pending beta verification) -> `Foresight/model/snapshot.lua`
- ☑ `MODEL-loadout-whatif` - snapshot + delta stack (classic talents, trait nodes, stat tweaks, racials/races); immutable what-if copies; one shared op-folder -> `Foresight/model/loadout.lua`
- ☑ `MODEL-impact-diff` - evaluate/diff loadouts; stat CHAIN explainer (statImpactDetail: +AP -> dmg/swing, live-derived crit%, mana -> dimensions); itemDerivedLines; compareItems -> `Foresight/model/impact.lua`
- ☑ `MODEL-talent-summary` - per-talent humanized ops + affected spell names -> `Foresight/model/impact.lua`
- ☑ `MODEL-stat-advisor` - comparative marginal stat ranking ("For your Spellcasting: Intellect > ... per point"), built on explainStatDelta (no forked value path); /foresight advisor + panel "Stat value" rows; v0 heuristic -> `Foresight/model/impact.lua`
- ◐ `WHATIF-planner` - persistent future-build workbench (v0.13.0, S16): typed plan deltas (stat / item bundle / trait / buff / racial / race) validated per read, composed through the one loadout delta stack; `/foresight plan add|remove|clear|show` + panel "Future build" section with net impact + chain. Remaining: clickable builder UI (plan-from-tooltip, per-row remove), in-game verify -> `Foresight/model/plan.lua`, `Foresight/ui/panel_model.lua`

## SYNERGY / CATALOG - how content connects
- ◐ `SYNERGY-engine` - groups impact sources by shared lever (stat/spell/school/mechanic) from ALL sources (talents + player racials + active buffs); CHAINED synergies v0.17.0 - stat-conversion ops (Mental Dexterity Int->AP) bridge a stat theme to the output it feeds, so "Attack Power" lists converters + direct sources and "Intellect" shows what it powers; `/foresight synergy` prints a chains section + tooltip "Synergy:" line. Remaining: tree-highlight dropdown (highlight shipped), deeper multi-hop chains -> `Foresight/model/synergy.lua`
- ◐ `CATALOG` - one normalized reference table over every impact source (talents/traits/racials/consumables-by-type/imbues) with a uniform entry shape; `/foresight catalog` counts-per-kind table + cross-kind search; the query spine for synergy/search/validation, grows cleanly as the pipeline (or crowd) adds content -> `Foresight/model/catalog.lua`
- ☑ `LEVER-taxonomy` - the ONE declarative op-kind -> canonical lever (axis+key) map; distinct axes for Attack Power / Spell Power / crit / defense / resource / tempo / ability; statConvert = dual lever (stat + output bridge); synergy groups entirely off it; completeness gate reds the ship if any shipped op kind is unclassified (growth-proof) -> `Foresight/model/levers.lua`
- ◐ `SYNERGY-highlight` - Diablo-4-style talent-tree highlight of a synergy theme (v0.13.0): `/foresight synergy <theme>` glows every member node (enumerator probe -> name-match fallback; house pulse textures, taint-free; theme saved per char, auto-applies on talent-UI open, `clear` stops). Remaining: in-game render verify, talent-frame dropdown, LibCustomGlow at packaging -> `Foresight/ui/synergy_highlight.lua`

## CONSUME / RACIAL / IMBUE - more impact sources (researched 2026-10-11)
- ◐ `IMBUE-compare` - weapon-imbue simulation (v0.14.0, S17): `weapon_imbues.lua` (377 temp enchants: shaman imbues/poisons/stones/oils via SpellItemEnchantment; Flametongue per-hit = basis x speed/100, ground-truthed from the tooltip macro) + pure `Imbues.compare` (per-swing/per-sec on the live weapon, proc EV only when the rate is known, rank dedupe) + `/foresight imbue` + imbue block on the apply-spell tooltip. Remaining: in-game verify, Windfury extra-attack EV (needs weapon damage baseline, now captured) -> `pipeline/generate.py`, `Foresight/model/imbues.lua`, `Foresight/ui/tooltips.lua`
- ◐ `CONSUME-buffs` - consumable buff impact (v0.12.0): `consumables.lua` (390 potions/elixirs/flasks/scrolls/foods; Well-Fed one-hop keyed by the triggered aura spell) + `Loadout:withBuff`/`Impact.buffDelta` (one diff = active gains / expiry loss); secret-safe live read (`Snapshot.captureActiveBuffs` via never-secret spellId, `Guards.aurasSecret` degrade); consumable tooltip "While active / On expiry" block + `/foresight buffs`. Remaining: in-game render verify -> `pipeline/generate.py`, `Foresight/data/generated/consumables.lua`, `Foresight/model/loadout.lua`, `Foresight/ui/tooltips.lua`
- ◐ `RACIAL-impact` - racial impact data + model (v0.11.0): `race_racials.lua` keyed by raceID (10 races, 45 spells; RaceMasks bit = ChrRaces.PlayableRaceBit, no Skyborne hardcode) with ops/class gates/passive split/confidence tags; `model/racials.lua` access + `Loadout:withRacial`/`withRace` what-ifs; new aura 133 (max-health%) + 178 (max-power%) folds. NOT folded into the base build (live stats already include racials - double-count law). Synergy surfacing shipped v0.12.0. Remaining: panel "Your <Race> racials" line + in-game verify -> `pipeline/generate.py`, `Foresight/data/generated/race_racials.lua`, `Foresight/model/racials.lua`, `Foresight/model/loadout.lua`

## CORE - addon plumbing
- ☑ `CORE-bootstrap` - namespace, events, slash commands (/foresight talent|stat|selftest) -> `Foresight/core/init.lua`
- ☑ `CORE-guards` - secret-value guard layer; ALL risky reads route here -> `Foresight/core/guards.lua`
- ☑ `CORE-talent-api` - talent API adapter: Forever talents are Retail C_Traits node trees (classic globals gone), per forever-addon-kit. Walks GetActiveConfigID -> GetConfigInfo -> GetTreeNodes -> GetNodeInfo -> GetEntryInfo -> GetDefinitionInfo.spellID, maps spellID -> our talent via spellRanks; classic globals are a fallback. CONFIRMED LIVE 2026-10-11 (Shaman: 77 nodes, 7 selected read, 38 classic nodes bridged to generated data) -> `Foresight/core/talent_api.lua`
- ☑ `CORE-saveddb` - versioned SavedVariables with per-character sections -> `Foresight/core/init.lua`

## UI - surfaces
- ◐ `UI-stats-panel` - character-frame side panel (Dimensions/Regen/Mechanics/What-if/Future-build/Stat-value), dark class-colored skin, zebra rows, colored deltas, playstyle subtitle; DRAGGABLE with per-character saved position (validated) + `/foresight panel reset`; LIVE refresh (gear/stats/talents/buffs, 0.2s debounce, v0.13.0); model selftest-covered; in-game render pending next login -> `Foresight/ui/panel_model.lua`, `Foresight/ui/stats_panel.lua`
- ☑ `UI-export-window` - copyable scroll EditBox (/foresight export), fixes chat-copy gap -> `Foresight/ui/export.lua`
- ◐ `UI-talent-tooltip` - talent hover injection (S2): hooks `GameTooltip.SetTraitEntry` (live-verified; the TraitEntry data type isn't exposed). `nodeImpactLines` shows, for EVERY trait node (classic + new Forever), the affected spells, each op at max rank, and the derived "what this does for you now" chain. `traitTipProbe` diagnostic records hook fires. Live render confirm pending next harvest -> `Foresight/ui/tooltips.lua`
- ◐ `UI-spell-tooltip` - ability tooltip layman lines: client cast time + (p) coefficient translate live Spell/Healing Power into "+N to this spell per cast"; shares the ONE injection module; logic selftest-covered, in-game hook pending S3 verify -> `Foresight/ui/tooltips.lua`
- ◐ `UI-item-tooltip` - item tooltip layman stat impact ("+4 Agility -> +X% Melee DPS for you"); shares the ONE injection module + explainItemDelta (diff path, no forked value code); GetItemStats live source; logic selftest-covered, in-game hook pending S3 verify -> `Foresight/ui/tooltips.lua`
- ☑ `UI-playstyle-label` - build-profile line ("Caster-leaning - offense-focused") from dimension scores + stat lean; panel subtitle + /foresight build; v0 heuristic -> `Foresight/ui/panel_model.lua`
- ◐ `UI-mapping-panel` - bidirectional talent<->ability impact map (v0.21.0): `model/mapping.lua` inverse ("what modifies Fireball") + forward ("what Improved Fireball touches") off the shared affected-spell edges; `/foresight affects <ability|talent>`; pure + selftest-covered. Remaining: a visual panel renderer -> `Foresight/model/mapping.lua`

## QA - verification & feedback
- ☑ `QA-selftest-harness` - 136-check selftest (in-game + headless via lupa; incl. the lever-taxonomy completeness gate) + harvest sandbox/analyze + version-sync gates -> `Foresight/selftest.lua`, `pipeline/run_tests.py`
- ☑ `QA-compliance-gate` - static ToS/automation scan, first step of the ship gate; proven red on planted violation -> `pipeline/check_compliance.py`
- ☑ `QA-collector` - session + level-up stat journal + ITEM SIGHTINGS (v0.15.0: equipped+bag item IDs scanned at login/logout - the "what's actually in game" ground truth, crowd-DB phase A; capped, IDs only) into SavedVariables -> `Foresight/core/collect.lua`
- ☑ `QA-verify-command` - /foresight verify: live API checks + all-talents tooltip probe + raw talent-API shape probe; auto-runs once per login -> `Foresight/core/collect.lua`
- ☑ `QA-harvester` - SavedVariables -> JSON archive + rank-rule hypothesis voting + sightings aggregation (`collected/item_sightings.json`, distinct-account counts = the k-of-n seed, consumable cross-check) -> `pipeline/harvest.py`
- ☑ `QA-deploy` - gate-then-copy deploy to the live install -> `pipeline/deploy.py`
- ◐ `QA-publish-train` - release/publishing infra: `.pkgmeta` (BigWigs packager, only Foresight/ ships) + README + privacy ignores + CI workflows (v0.20.0: `ci.yml` gate on push/PR, `release.yml` packager-on-tag to CurseForge/Wago/GH, `data-freshness.yml` wago.tools poll->regen->gate->PR). PENDING (your call): GitHub remote + public/private + license, CurseForge/Wago slug registration + API-token secrets, SHA-pin action refs, branch protection (DATAFLOW 4b/4c) -> `.github/workflows/`, `.pkgmeta`, `README.md`
- ☐ `QA-probe` - empirical formula verification from live gameplay (regen/swing/tick measurement)
- ☐ `QA-report-export` - user feedback export strings + decoder (export window exists; report capture pending)

## PANIC / ASSIST - later pillars (DESIGN.md)
- ☐ `PANIC-advisor` - escape registry + trigger engine + button flash
- ☐ `ASSIST-hud` - C_AssistedCombat what-to-press wrapper
