# Foresight - Capability Inventory

Answers "do we already have this?" in one read. IDs are durable handles; grep an ID in
CHANGELOG.md for its history. Last reviewed: 2026-10-10.

## DATA - data pipeline & shipped data
- ☑ `DATA-pipeline-fetch` - download Forever DB2 tables from wago.tools, cached per build -> `pipeline/fetch.py`
- ☑ `DATA-pipeline-generate` - compute talent->affected-spells via class masks, emit Lua tables -> `pipeline/generate.py`
- ☑ `DATA-generated-tables` - talents, tabs, impacts, 3,448 spells (cast/cost/tick/cooldown), 555 trait nodes -> `Foresight/data/generated/`
- ☑ `DATA-formula-registry` - confidence-tagged conversion math (regen, swing, coefficients, rank rule) -> `Foresight/data/formulas.lua`
- ☑ `DATA-overrides` - curated corrections layered over generated data -> `Foresight/data/overrides.lua`
- ☐ `DATA-items` - item stats into the pipeline (deferred)
- ☐ `DATA-professions` - profession recipes as modifier sources (deferred)
- ◐ `DATA-traits` - Retail Trait DB2 (TraitNode/TraitNodeEntry/TraitNodeXTraitNodeEntry/TraitDefinition/SkillLineXTraitTree) -> `traits.lua`: 555 nodes keyed by nodeID with spellID/name/maxRank/ops (via shared build_ops) + bySpell index + tree->class. Covers ALL live nodes incl new Forever talents; adapter resolves every selection by nodeID. Shipped v0.8.0. Phase 2: feed new-node ops into the what-if model (today classic-mapped nodes model via talentImpacts) -> `pipeline/generate.py`, `Foresight/data/generated/traits.lua`

## GRAPH - impact engine
- ☑ `GRAPH-impact-engine` - typed modifier DAG with stacking rules, breakdowns, cycle detection -> `Foresight/graph/graph.lua`
- ☑ `GRAPH-dimensions` - 8 outcome lenses (spellcasting, melee/ranged DPS, healing, tankability, survivability, sustain, threat), v0 heuristics -> `Foresight/graph/dimensions.lua`
- ◐ `GRAPH-threat` - threat as the 8th outcome lens: own-state threat % from talents (SPELL_AURA_MOD_THREAT mapped to a "threat" op, school-verified vs tooltips) folded through agg.threatModPct; (p) classic-presumed. Live signal pending the S3 talent-read unblock; per-ability base threat + stance are future (overrides.abilityThreat, k-of-n) -> `Foresight/graph/dimensions.lua`, `Foresight/data/formulas.lua`

## MODEL - character modelling
- ☑ `MODEL-snapshot` - live character capture, secret-guarded (API indices pending beta verification) -> `Foresight/model/snapshot.lua`
- ☑ `MODEL-loadout-whatif` - snapshot + delta stack (talents, stat tweaks); immutable what-if copies -> `Foresight/model/loadout.lua`
- ☑ `MODEL-impact-diff` - evaluate/diff loadouts, "+2 Spirit" human-terms explainer -> `Foresight/model/impact.lua`
- ☑ `MODEL-talent-summary` - per-talent humanized ops + affected spell names -> `Foresight/model/impact.lua`
- ☑ `MODEL-stat-advisor` - comparative marginal stat ranking ("For your Spellcasting: Intellect > ... per point"), built on explainStatDelta (no forked value path); /foresight advisor + panel "Stat value" rows; v0 heuristic -> `Foresight/model/impact.lua`

## CORE - addon plumbing
- ☑ `CORE-bootstrap` - namespace, events, slash commands (/foresight talent|stat|selftest) -> `Foresight/core/init.lua`
- ☑ `CORE-guards` - secret-value guard layer; ALL risky reads route here -> `Foresight/core/guards.lua`
- ☑ `CORE-talent-api` - talent API adapter: Forever talents are Retail C_Traits node trees (classic globals gone), per forever-addon-kit. Walks GetActiveConfigID -> GetConfigInfo -> GetTreeNodes -> GetNodeInfo -> GetEntryInfo -> GetDefinitionInfo.spellID, maps spellID -> our talent via spellRanks; classic globals are a fallback. CONFIRMED LIVE 2026-10-11 (Shaman: 77 nodes, 7 selected read, 38 classic nodes bridged to generated data) -> `Foresight/core/talent_api.lua`
- ☑ `CORE-saveddb` - versioned SavedVariables with per-character sections -> `Foresight/core/init.lua`

## UI - surfaces
- ◐ `UI-stats-panel` - character-frame side panel (Dimensions/Regen/Mechanics/What-if/Stat-value), dark class-colored skin, zebra rows, colored deltas, playstyle subtitle; DRAGGABLE with per-character saved position (validated) + `/foresight panel reset`; model selftest-covered; in-game render pending next login -> `Foresight/ui/panel_model.lua`, `Foresight/ui/stats_panel.lua`
- ☑ `UI-export-window` - copyable scroll EditBox (/foresight export), fixes chat-copy gap -> `Foresight/ui/export.lua`
- ◐ `UI-talent-tooltip` - talent hover injection (S2): shared injection module, next-point marginal values, dimension delta, needs-curation/(p) honesty. SetTalent is dead on Forever's trait UI, so now hooks the TraitEntry tooltip type (entry->definition spell->our talent) as the live path; activates if the type is exposed, else discovery reports the real hook. Live confirm pending next harvest -> `Foresight/ui/tooltips.lua`
- ◐ `UI-spell-tooltip` - ability tooltip layman lines: client cast time + (p) coefficient translate live Spell/Healing Power into "+N to this spell per cast"; shares the ONE injection module; logic selftest-covered, in-game hook pending S3 verify -> `Foresight/ui/tooltips.lua`
- ◐ `UI-item-tooltip` - item tooltip layman stat impact ("+4 Agility -> +X% Melee DPS for you"); shares the ONE injection module + explainItemDelta (diff path, no forked value code); GetItemStats live source; logic selftest-covered, in-game hook pending S3 verify -> `Foresight/ui/tooltips.lua`
- ☑ `UI-playstyle-label` - build-profile line ("Caster-leaning - offense-focused") from dimension scores + stat lean; panel subtitle + /foresight build; v0 heuristic -> `Foresight/ui/panel_model.lua`
- ☐ `UI-mapping-panel` - talent<->skill mapping panel

## QA - verification & feedback
- ☑ `QA-selftest-harness` - 66-check selftest (in-game + headless via lupa) + harvest sandbox/analyze gates -> `Foresight/selftest.lua`, `pipeline/run_tests.py`
- ☑ `QA-compliance-gate` - static ToS/automation scan, first step of the ship gate; proven red on planted violation -> `pipeline/check_compliance.py`
- ☑ `QA-collector` - session + level-up stat journal into SavedVariables -> `Foresight/core/collect.lua`
- ☑ `QA-verify-command` - /foresight verify: live API checks + all-talents tooltip probe + raw talent-API shape probe; auto-runs once per login -> `Foresight/core/collect.lua`
- ☑ `QA-harvester` - SavedVariables -> JSON archive + rank-rule hypothesis voting -> `pipeline/harvest.py`
- ☑ `QA-deploy` - gate-then-copy deploy to the live install -> `pipeline/deploy.py`
- ◐ `QA-publish-train` - release/publishing infrastructure: git repo (root commit 2026-10-10) + `.pkgmeta` (BigWigsMods packager, only Foresight/ ships) + README official-channels front door + privacy-aware ignores; pending: packager CI action, CurseForge/Wago channels, branch protection (threat-model publish bindings, DATAFLOW.md 4b/4c) -> `.pkgmeta`, `README.md`, `.gitignore`
- ☐ `QA-probe` - empirical formula verification from live gameplay (regen/swing/tick measurement)
- ☐ `QA-report-export` - user feedback export strings + decoder (export window exists; report capture pending)

## PANIC / ASSIST - later pillars (DESIGN.md)
- ☐ `PANIC-advisor` - escape registry + trigger engine + button flash
- ☐ `ASSIST-hud` - C_AssistedCombat what-to-press wrapper
