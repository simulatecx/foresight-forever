# HelpMe - WoW: Forever addon

The hardcore player's safety net for official WoW: Forever (Interface 16001, Mainline
12.x API over classic-era mechanics, launches 2026-11-04). Three pillars: Talent Impact
Map (current priority), Panic Advisor, what-to-press HUD. Design docs: `DATAFLOW.md`
(authoritative architecture + build order), `DESIGN.md` (product pillars),
`FEASIBILITY.md` (platform research).

## Commands

- `python pipeline/fetch.py [--build X]` - download Forever DB2 CSVs from wago.tools
- `python pipeline/generate.py [--build X]` - regenerate `HelpMe/data/generated/*.lua`
- `python pipeline/run_tests.py` - headless selftest (lupa Lua VM); THE ship gate for
  addon-logic changes; also runs in-game via `/helpme selftest`

## Architecture (one line each)

- `pipeline/` - Python tooling; offline only, never ships
- `HelpMe/` - the addon. Load order = `HelpMe.toc`
- `HelpMe/core/guards.lua` - ALL reads of possibly-secret game state go through Guards;
  never call issecretvalue or compare raw unit values elsewhere
- `HelpMe/graph/` - impact graph engine + outcome dimensions
- `HelpMe/model/` - snapshot -> loadout (what-if deltas) -> impact evaluation/diff
- `HelpMe/data/generated/` - GENERATED, DO NOT EDIT; regenerate via pipeline
- `HelpMe/data/overrides.lua` - hand-curated corrections (edit this, not generated/)

## Hard invariants

- Addon code is Lua 5.1-compatible (the client's dialect); test harness runs newer Lua,
  so avoid constructs that differ (no goto, no integer-division operator, no bit ops).
- Suggest-only: the addon never automates protected actions; display and advice only.
  ENFORCED by `pipeline/check_compliance.py` (first step of the ship gate): any
  casting/targeting/movement/item-use/macro call or os/io/require/loadstring escape is
  red and blocks the ship. Justified false positives need `-- compliance-allow: <reason>`
  on the line. Never weaken the banned list to make a feature fit; redesign the feature.
- Account-safety doctrine: everything ships as a normal Interface\AddOns addon using
  official APIs only. No memory reading, no input injection, no game-file modification,
  no out-of-game automation. A future companion app may READ our SavedVariables file
  (the WowUp/Warcraft Logs pattern) and nothing else.
- Untrusted-input laws (threat model: DATAFLOW.md 4c): SavedVariables content is
  user-editable data - the addon type-validates it on load, and ANY tool parsing
  someone else's SavedVariables must use the neutered Lua sandbox in
  `pipeline/harvest.py` (gated by `sandbox_selfcheck()` in run_tests). HelpMe never
  executes imported content - future import features are data-only parsing, never
  loadstring. Crowd data changes `overrides.lua` only via k-of-n confirmation plus
  human-reviewed PR.
- Every formula/assumption carries a confidence tag; unverified-on-Forever facts say so
  (`classic-presumed`, `linearToMax-presumed`). The beta probe upgrades or corrects them.
- Secret-value discipline: in restricted contexts features degrade to display-only,
  never error.

## Doc governance & feature lifecycle

Doc spine (one home per fact): `SPRINTS.md` work tracker (status index -> active ->
shipped -> backlog) · `FEATURES.md` capability inventory (`PREFIX-slug` durable IDs) ·
`CHANGELOG.md` dated versions, each with a `*Features:*` IDs line.

Lifecycle: check backlog -> feature-triage (duplication gate: enhance over net-new) ->
story with Fit & Overlap -> build ◐ -> ship ☑ + changelog + inventory update, all three
in the same change. No new top-level `.md` without retiring one. Status glyphs:
☐ ◐ ☑ ⚑. Hooks in `.claude/` enforce the record loop; the discipline applies even
where hooks don't run.

Mobile-check binding for this repo: "mobile" = the in-game UI at low resolution +
UI scale extremes; a surface passes if readable at 1280x720 with 0.65 UI scale.
