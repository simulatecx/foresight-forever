# Foresight - Work Tracker

Single source of truth for work. Status glyphs: ☐ todo · ◐ in progress · ☑ done · ⚑ superseded.

## Status index

| Story | Status |
|---|---|
| S1 Foundation: data pipeline + impact graph + modelling core | ☑ |
| S2 Talent Impact Map in-game MVP (tooltip + /foresight talent) | ☐ |
| S3 Beta verification pass (API shapes, rank rule, snapshot) | ☐ |
| S4 Report/feedback export strings | ☐ |
| S5 ECS-style stats panel (code-complete, render pending beta) | ◐ |
| S6 Crowd data-collection loop (pilot scale) | ☑ |

## Active work

### S2 - Talent Impact Map in-game MVP ☐
Hover a talent in the talent frame -> injected "Affects: ..." lines + per-rank values;
`/foresight talent <id>` already works. **Features:** UI-talent-tooltip.
AC: tooltip lines render on Forever beta client without taint errors; needs-curation
talents say so honestly; mobile check N/A (game UI).
Fit & Overlap: enhances MODEL-talent-summary (same data path, new surface). No overlap -
nothing else renders talent impacts.

### S3 - Beta verification pass ☐
On the Forever beta client, verify: talent API shape (Snapshot.captureTalents),
UnitStat/crit/haste API indices, `C_AssistedCombat` presence, SavedVariables
persistence bug status, and THE RANK-SCALING RULE - evidence is mixed (see
formulas.talentRankValue): compare in-game rank 1 vs max tooltips for Improved
Fireball (26), Concussion, Improved Reincarnation, Ancestral Knowledge; outcome is
either one rule or a per-talent field in generated data. Pilot class: Shaman.
**Features:** MODEL-snapshot, DATA-formula-registry. Beta window closes 2026-10-21.

### S5 - ECS-style stats panel ◐
Side panel on CharacterFrame (pattern: Extended Character Stats; mockup in DESIGN.md
"UI map"). Model built + selftest-covered headless; renderer written. Remaining: verify
render/anchoring/toggle on the Forever beta client (fold into the S3 session), then ☑.
**Features:** UI-stats-panel. Fit & Overlap: net-new surface (no prior UI); complements
MODEL-impact-diff (same evaluate path). Mobile: default font templates, 230px panel -
check readability at 1280x720 / 0.65 UI scale during the beta pass.

## Shipped (archived)

- ☑ S6 Crowd data-collection loop, pilot scale (2026-10-10): collector (sessions,
  level journal, /foresight verify + all-talents tooltip probe) -> SavedVariables ->
  harvester (JSON archive + rank-rule voting) -> gated deploy script. First in-game
  run passed 28/28 on a level-9 Shaman; SavedVariables persistence CONFIRMED live.
  Scale-up to other users (companion uploader + ingestion) is in the backlog.

- ☑ S1 Foundation (2026-10-10): DB2 fetch+generate pipeline against build 1.60.1.70338,
  impact graph engine, formula registry, loadout what-if modelling, +stat explainer,
  19-check headless selftest harness. Details: CHANGELOG v0.1.0.

## Backlog

- ☐ Crowd scale-up: opt-in companion uploader (reads SavedVariables, submits harvest
  JSON) + ingestion/aggregation service; consent + privacy pass per privacy-by-design
- ☐ QA-probe: empirical probe module (regen/swing/DoT tick measurement -> formula verification)
- ☐ QA-report-export: in-game report button -> compressed export string; decoder in pipeline/
- ☐ UI-mapping-panel: talent->skills mapping panel; invert to "which talents touch spell X"
- ☐ MODEL-talent-capture-link: match captured talents (tab/tier/column) to generated talent ids
- ☐ DATA-items: ItemSparse into pipeline; item stat deltas -> same loadout modelling
- ☐ DATA-professions: SkillLine/recipes -> consumables/crafted gear as modifier sources
- ☐ PANIC-advisor: escape registry + trigger engine + button flash (DESIGN.md pillar 1)
- ☐ ASSIST-hud: C_AssistedCombat what-to-press wrapper (DESIGN.md pillar 2)
- ☐ GRAPH-rotation-weights: fold cast-time/cost/cooldown mods into throughput dimensions
  using per-spell rotation weights (post-beta; today they surface via tooltips only)
