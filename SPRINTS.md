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
- ☐ DATA-items: ItemSparse into pipeline; item stat deltas -> same loadout modelling.
  PRIORITY RAISED 2026-10-10: gear evaluation was the strongest demand signal in the
  "Layman's Oracle" community spec - schedule next after the S3 beta pass.
- ☐ DATA-professions: SkillLine/recipes -> consumables/crafted gear as modifier sources
- ☐ PANIC-advisor: escape registry + trigger engine + button flash (DESIGN.md pillar 1)
- ☐ ASSIST-hud: C_AssistedCombat what-to-press wrapper (DESIGN.md pillar 2)
- ☐ GRAPH-rotation-weights: fold cast-time/cost/cooldown mods into throughput dimensions
  using per-spell rotation weights (post-beta; today they surface via tooltips only)

### Triaged 2026-10-10 - "Layman's Oracle" (Reddit/Gemini) spec alignment

Adopted 4 below after the full gate. REJECTED on the record (do not re-litigate):
hardcoded math (we generate from client DB2 + confidence-tag; hardcoding goes stale
every patch), multi-version targeting (Forever-only is the beachhead), and
secret-value-blind realtime calc (guards/degrade discipline is law).

- ☐ GRAPH-threat: threat as the 8th outcome dimension, plus per-ability threat values.
  As a hardcore dungeon leveler, I want to see how gear/talents shift my threat vs
  damage so I don't rip aggro and die. AC: threat lens evaluates from own-state only;
  per-ability threat mods live in overrides.lua (k-of-n for crowd corrections); every
  value tagged classic-presumed until verified; panel row readable at 1280x720/0.65;
  selftest covers the lens; compliance gate green.
  Fit & Overlap - GRAPH (-> DATA). Verdict: Enhance graph/dimensions.lua + formula
  registry entries - never a second math path outside the graph. Complements:
  tankability/survivability. Touches: dimensions.lua, formulas.lua, overrides.lua,
  panel_model.lua. Mobile: one panel row, existing templates. Languages: full-sentence
  strings. Trust: (p)-tagged, display-only. Data: none captured. Abuse: not reachable.

- ☐ UI-spell-tooltip: ability-tooltip injection with layman damage lines ("with your
  AP/SP this hits for ~X"). As a leveler comparing buttons, I want each ability's
  tooltip to say what it actually does for MY character. AC: injected lines append
  without taint or breaking other tooltip addons; reads route through guards and
  degrade to no-injection (never error) when restricted; coefficient-based values
  carry (p) until probe-verified; readable at mobile baseline; compliance green.
  Fit & Overlap - UI (-> MODEL). Verdict: Net-new surface BUT must share ONE
  tooltip-injection module with UI-talent-tooltip (S2) - two parallel hook systems is
  the duplicate to avoid. Complements: S2; sequence immediately after it. Touches:
  new shared ui/tooltips.lua, spells.lua data, impact.lua per-spell eval. Mobile:
  game tooltip templates. Languages: full sentences. Trust: honest (p) claims.
  Data: none. Abuse: not reachable.

- ☐ UI-playstyle-label: one-line build profile (e.g. "Caster-leaning - defensive")
  derived from dimension scores. As a new player, I want the addon to tell me what my
  build IS before I read seven numbers. AC: label derives purely from existing
  dimension scores in panel_model.lua (selftest-covered, no new math); renders in the
  panel title area; labeled "(v0 heuristic)"; mobile baseline readable.
  Fit & Overlap - UI (-> GRAPH). Verdict: Enhance UI-stats-panel - a line on the
  existing panel, NOT a second dashboard. Complements: GRAPH-dimensions. Touches:
  panel_model.lua, stats_panel.lua. Languages: full sentences. Trust: heuristic
  labeled as such. Data: none. Abuse: not reachable.

- ☐ MODEL-stat-advisor: comparative marginal stat ranking ("for your build right now:
  Crit > Haste > Spirit per point"). As a gearing player, I want stats ranked for MY
  character so vendor/drop choices are obvious. AC: ranking built on the existing
  explainStatDelta/marginal-conversion path (no forked stat-value code); ties to
  dimension deltas; output is one human sentence + optional panel row; labeled
  "(v0 heuristic)"; selftest-covered; mobile baseline readable.
  Fit & Overlap - MODEL (-> UI). Verdict: Enhance MODEL-impact-diff (impact.lua) -
  reuse explainStatDelta over the what-if stat set; the duplicate to avoid is any
  second marginal-value computation. Complements: UI what-if section, future
  DATA-items gear compare. Touches: impact.lua, panel_model.lua, selftest.lua.
  Languages: full sentences. Trust: heuristic labeled. Data: none. Abuse: not reachable.
