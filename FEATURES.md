# Foresight - Capability Inventory

Answers "do we already have this?" in one read. IDs are durable handles; grep an ID in
CHANGELOG.md for its history. Last reviewed: 2026-10-10.

## DATA - data pipeline & shipped data
- ☑ `DATA-pipeline-fetch` - download Forever DB2 tables from wago.tools, cached per build -> `pipeline/fetch.py`
- ☑ `DATA-pipeline-generate` - compute talent->affected-spells via class masks, emit Lua tables -> `pipeline/generate.py`
- ☑ `DATA-generated-tables` - talents, tabs, impacts, 3,448 spells (cast/cost/tick/cooldown) -> `Foresight/data/generated/`
- ☑ `DATA-formula-registry` - confidence-tagged conversion math (regen, swing, coefficients, rank rule) -> `Foresight/data/formulas.lua`
- ☑ `DATA-overrides` - curated corrections layered over generated data -> `Foresight/data/overrides.lua`
- ☐ `DATA-items` - item stats into the pipeline (deferred)
- ☐ `DATA-professions` - profession recipes as modifier sources (deferred)

## GRAPH - impact engine
- ☑ `GRAPH-impact-engine` - typed modifier DAG with stacking rules, breakdowns, cycle detection -> `Foresight/graph/graph.lua`
- ☑ `GRAPH-dimensions` - 7 outcome lenses (spellcasting, melee/ranged DPS, healing, tankability, survivability, sustain), v0 heuristics -> `Foresight/graph/dimensions.lua`
- ☐ `GRAPH-threat` - threat as the 8th outcome lens + per-ability threat values (classic-presumed; crowd corrections via overrides k-of-n) - triaged 2026-10-10

## MODEL - character modelling
- ☑ `MODEL-snapshot` - live character capture, secret-guarded (API indices pending beta verification) -> `Foresight/model/snapshot.lua`
- ☑ `MODEL-loadout-whatif` - snapshot + delta stack (talents, stat tweaks); immutable what-if copies -> `Foresight/model/loadout.lua`
- ☑ `MODEL-impact-diff` - evaluate/diff loadouts, "+2 Spirit" human-terms explainer -> `Foresight/model/impact.lua`
- ☑ `MODEL-talent-summary` - per-talent humanized ops + affected spell names -> `Foresight/model/impact.lua`
- ☐ `MODEL-stat-advisor` - comparative marginal stat ranking ("for your build: Crit > Haste"), built on explainStatDelta, never a forked value path - triaged 2026-10-10

## CORE - addon plumbing
- ☑ `CORE-bootstrap` - namespace, events, slash commands (/foresight talent|stat|selftest) -> `Foresight/core/init.lua`
- ☑ `CORE-guards` - secret-value guard layer; ALL risky reads route here -> `Foresight/core/guards.lua`
- ◐ `CORE-talent-api` - talent API adapter: classic globals absent on Forever, so known C_SpecializationInfo conventions are pcall-probed, auto-locked, normalized to classic shape; ALL talent reads (snapshot, probe, S2 hook) route here; live convention lock pending next read-back -> `Foresight/core/talent_api.lua`
- ☑ `CORE-saveddb` - versioned SavedVariables with per-character sections -> `Foresight/core/init.lua`

## UI - surfaces
- ◐ `UI-stats-panel` - character-frame side panel (Dimensions/Regen/Mechanics/What-if), dark class-colored skin, zebra rows, colored deltas; model selftest-covered; in-game render pending next login -> `Foresight/ui/panel_model.lua`, `Foresight/ui/stats_panel.lua`
- ☑ `UI-export-window` - copyable scroll EditBox (/foresight export), fixes chat-copy gap -> `Foresight/ui/export.lua`
- ◐ `UI-talent-tooltip` - talent hover injection (S2): shared injection module with position+name resolver, next-point marginal values, dimension delta, needs-curation/(p) honesty; in-game verify pending (S3 session) -> `Foresight/ui/tooltips.lua`
- ☐ `UI-spell-tooltip` - ability tooltip layman damage lines; MUST share one injection module with UI-talent-tooltip (core now exists in `ui/tooltips.lua`) - triaged 2026-10-10
- ☐ `UI-playstyle-label` - build-profile line derived from dimension scores, on the stats panel title area - triaged 2026-10-10
- ☐ `UI-mapping-panel` - talent<->skill mapping panel

## QA - verification & feedback
- ☑ `QA-selftest-harness` - 46-check selftest (in-game + headless via lupa) + harvest sandbox/analyze gates -> `Foresight/selftest.lua`, `pipeline/run_tests.py`
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
