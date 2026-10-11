# Foresight - Work Tracker

Single source of truth for work. Status glyphs: ☐ todo · ◐ in progress · ☑ done · ⚑ superseded.
Blow-by-blow history lives in `CHANGELOG.md`; this file is the status + roadmap.

## The endstate (from DESIGN.md)

Three pillars shipped, verified on Forever, and published to CurseForge/Wago/GitHub:
1. **Panic Advisor** - escape toolkit flashed when you're in a bind (S10).
2. **What-to-press HUD** - `C_AssistedCombat` next-cast highlight (S9).
3. **Talent Impact Map** - what every talent/stat/item does for *your* character, on the
   shared Character Impact Graph (S1-S8). This pillar came first (DATAFLOW build order);
   the other two build on its data + UI layer.

## Status index

| Sprint | Pillar | Status |
|---|---|---|
| S1 Foundation: pipeline + impact graph + modelling core | 3 | ☑ |
| S2 Talent Impact Map in-game MVP (tooltip + `/foresight talent`) | 3 | ◐ |
| S3 Beta verification pass (API shapes, rank rule, snapshot) | all | ◐ |
| S4 Report/feedback export strings | - | ☐ |
| S5 Stats panel (built + movable; render verify pending) | 3 | ◐ |
| S6 Crowd data-collection loop (pilot scale) | - | ☑ |
| S7 Talent Impact Map completion (trait modelling + mapping panel) | 3 | ◐ |
| S8 DATA-items: gear compare (live v0 ☑; offline DB deferred) | 3 | ◐ |
| S9 ASSIST-hud: what-to-press HUD | 2 | ☐ |
| S10 PANIC-advisor: escape registry + triggers + flash | 1 | ☐ |
| S11 QA-probe: empirical formula verification from live play | - | ☐ |
| S12 Publishing train: GitHub remote + packager CI + CurseForge/Wago | - | ◐ |
| S13 Crowd scale-up: companion uploader + ingestion + privacy pass | - | ☐ |

## Active / next

### S3 - Beta verification pass ◐  (the current gate)
Verifying Foresight against the live Forever beta (pilot: Orc Shaman). Full log in
CHANGELOG 0.5.1-0.8.2. State:
- **Verified live:** SavedVariables persistence; UnitStat/crit/haste/weapon reads;
  `C_SpecializationInfo`, `C_AssistedCombat` (+GetNextCastSpell), secret-values,
  `C_TooltipInfo`; talents are Retail **C_Traits** node trees (classic globals gone);
  the C_Traits walk + spellID->talent bridge (77 nodes, 7 selected, 38 mapped).
- **Render feedback (2026-10-11, v0.9.0 screenshots, L10 Shaman):** panel renders;
  playstyle subtitle works; **panel drag persists + reset works** (confirmed). Three bugs
  found and FIXED in v0.9.1: talent tooltips (wrong hook - `SetTraitEntry` exists but the
  `TraitEntry` data type doesn't; now hook the method), item tooltip flash-vanish (async
  rebuild + stale guard; now `OnTooltipCleared` flag), and What-if row overlap (fixed-height
  wide rows; now sized to wrapped height).
- **TALENT TOOLTIP SOLVED (v0.9.5, pending final in-game confirm):** diagnostics proved
  neither SetTraitEntry NOR C_TooltipInfo.GetTraitEntry fires on hover, BUT the tooltip's
  owner frame is named exactly the talent ("Ancestral Knowledge"). The hook now matches
  GameTooltip owner's frame name -> our trait node -> inject on next frame. Works for all
  nodes. Next harvest's `traitTipProbe {source:"ownerName", injected:true}` confirms.
  Also open: rank-scaling rule (still (p)); gear-compare "vs equipped" render. Beta closes
  **2026-10-21**.
  CONFIRMED WORKING in-game (v0.9.2): stat chain (`/foresight stat` + item tooltips show
  +AP/crit chain), item tooltip renders, What-if no longer overlaps, panel drag/reset.
- **Design direction (user, 2026-10-11):** move the panel + mouseover popups toward the
  "Combat Matrix" mockup - dimension bars, a playstyle badge/chip, colored-accent advice
  sections, a clean popup card. Needs an honest fill-basis decision for dimension bars
  (our scores are relative indices, not 0-100%). Scheduled as a UI-redesign pass.
- **Next capture:** relog on the shipped build -> logout/login -> `python pipeline/harvest.py`.

### S2 / S5 - fold into the S3 render check
S2 (talent tooltips) and S5 (stats panel) are code-complete and gated; both flip to ☑
once their in-game render is confirmed in the S3 session.

## Roadmap to endstate (ordered)

### S7 - Talent Impact Map completion ◐
Make the talent map whole now that C_Traits coverage exists.
- **S7a DATA-traits Phase 2** (◐ -> this sprint): feed trait-node impact ops into the
  what-if model so EVERY Forever talent (not just classic-overlap) moves the dimensions.
  Enhance loadout.lua (one shared op-folder; `withTraitNode`). No new math path.
- **S7b UI-mapping-panel** (☐): per-build talent<->skill map; invert to "which talents
  touch spell X". Pure model in a new `ui/mapping_model.lua` (selftest-covered) + renderer.

### S8 - DATA-items + gear compare ◐  (strongest community demand)
v0 SHIPPED (v0.9.0): `Impact.compareItems` nets two items' per-dimension impact (reuses
explainItemDelta, no forked math); the item tooltip shows "vs equipped [slot]" using live
GetItemStats on the equipped item. SCOPE DECISION: the offline ItemSparse DB is
deliberately deferred - shipping ~all items is megabytes of addon bloat, and live
GetItemStats already covers every item the player holds (the leveling use case). A
curated/filtered item DB (for out-of-hand lookup/search) can follow if demand appears.
Remaining: in-game verify the "vs equipped" render + slot resolution (fold into S3).

### S9 - ASSIST-hud (Pillar 2) ☐
`C_AssistedCombat.GetNextCastSpell()` (confirmed present live) -> a movable HUD showing the
recommended next ability icon + keybind, optional action-button glow. Display/suggest-only
(compliant by construction). Degrade-safe when the API is unavailable. Resolver logic
(spell->icon->keybind, action-slot scan) pure/selftest-covered; frame render verified in-game.

### S10 - PANIC-advisor (Pillar 1) ☐  (the headline safety net)
Per-class escape registry (data table, level/known-spell filtered) + own-state trigger
engine (HP% + drop-rate tiers, all reads secret-guarded, degrade to display-only in
instances) + button-flash overlay + top-3 panic panel. Registry + trigger logic
pure/selftest-covered; glow/panel verified in-game. Biggest remaining build.

### S11 - QA-probe ☐
Measure own regen/swing/DoT-tick/GCD during play -> verify or flag each (p) formula;
auto-draft mismatch reports. Upgrades confidence tags from classic-presumed to verified@build.

### S12 - Publishing train ◐  (gated on your call)
Scaffolded: `.pkgmeta`, README front door, privacy-aware ignores. Remaining: GitHub remote
(public vs private - YOUR decision), BigWigsMods packager CI action, CurseForge + Wago
channels (slug registration), branch protection, SHA-pinned actions, data-freshness CI
(poll wago.tools -> fetch/generate/gate -> release PR). Threat-model publish bindings
(DATAFLOW 4b/4c).

### S13 - Crowd scale-up ☐
Opt-in companion uploader (reads SavedVariables, POSTs harvest JSON) + ingestion/aggregation;
k-of-n confirmation before any overrides change; privacy-by-design pass (consent, hashing,
retention). Phase B in DATAFLOW 4b. Full design (Cloudflare Worker + D1/R2, k-of-n via unique
index, companion sanitize) in `docs/RESEARCH-2026-10-11.md`.

### S14 - Buffs & consumables impact ◐  (SHIPPED code-complete v0.12.0)
"How does a flask/elixir/food impact me while active, and what do I lose when it expires."
DONE: consumables.lua (390 items; Well-Fed one-hop keys the TRIGGERED aura spell);
`Loadout:withBuff(itemId|spellId)` + `Impact.buffDelta` (one diff = active vs expiry);
`Snapshot.captureActiveBuffs` via never-secret spellId probe + `Guards.aurasSecret` degrade;
consumable tooltip "While active / On expiry these gains reverse" block; `/foresight buffs`.
Decodes: 290 crit% (SpellEquippedItems discriminates weapon-conditional ones), 34 flat
max health (Titans), 22 armor (Scrolls of Protection), 99/124 AP (Well Fed).
Remaining: in-game render verify (fold into S3 session). Details: research doc A.
Fit & Overlap: reuses applyOps/diff (no forked math); complements S10 PANIC (consumable registry).

### S15 - Racials impact ◐  (phase 1 SHIPPED v0.11.0)
Data + model DONE: `race_racials.lua` (10 races, 45 spells; RaceMasks bit =
ChrRaces.PlayableRaceBit so Skyborne needed no hardcode), ops via shared build_ops, class
gates, passive/active split, confidence tags (classic-presumed / forever-new-unverified);
snapshot captures raceId (token fallback, Scourge=5); `model/racials.lua` +
`Loadout:withRacial`/`withRace`; aura 133/178 folds. PLAN CORRECTION: no unconditional
fold into the base build - live stats already include racial passives (double-count).
Synergy ingestion SHIPPED v0.12.0. Remaining: panel "Your <Race> racials" line + in-game
verify; curation -> overrides.racialImpacts. Details: research doc B.

### SYNERGY - impact sources that work together ◐
v0 engine SHIPPED (v0.10.0): group nodes by stat/spell/school/mechanic; tooltip "Synergy:" line +
/foresight synergy. ALL-SOURCES SHIPPED (v0.12.0): with player context (race/class/active buffs),
themes include the player's racials and active consumables alongside talents - typed members
(racial:<spellID>, buff:<itemId>) through one op-walker; trait-only without context.
NEXT (baked-in UI, researched 2026-10-11 doc C1): talent-tree node highlight
(Diablo-4 paragon selection) - node buttons are named by talent (proven), locate via
PlayerSpellsFrame probe + name-match fallback, glow via LibCustomGlow PixelGlow (key-scoped, no
taint; NOT the tainting ActionButton glow). Dropdown on the talent frame + a stats-panel Synergies
section, one validated settings.synergy.theme syncing all surfaces. New ui/synergy_highlight.lua.
Then: chained synergies (A boosts Int -> B converts Int to AP).

## Backlog (not yet scheduled)
- ☐ DATA-professions: SkillLine/recipes -> consumables/crafted gear as modifier sources.
- ☐ GRAPH-rotation-weights: fold cast-time/cost/cooldown mods into throughput via per-spell
  rotation weights (today they surface via tooltips only).
- ☐ Per-ability base threat + stance/form multipliers for GRAPH-threat (overrides, k-of-n).
- ☐ Spell-tooltip absolute hit numbers once base spell damage per rank is in the data.

## Shipped (archived)
- ☑ S6 Crowd data-collection loop (2026-10-10): collector + harvester + gated deploy;
  first in-game run 28/28 on a L9 Shaman; persistence confirmed. (CHANGELOG 0.3.0.)
- ☑ S1 Foundation (2026-10-10): DB2 fetch/generate, impact graph, formula registry,
  loadout what-if + diff + stat explainer, selftest harness. (CHANGELOG 0.1.0.)

## Rejected on the record (do not re-litigate)
From the "Layman's Oracle" triage (2026-10-10): hardcoded math (we generate from client
DB2 + confidence-tag), multi-version targeting (Forever-only is the beachhead), and
secret-value-blind realtime calc (guards/degrade discipline is law). The four adopted
items shipped as GRAPH-threat, UI-spell-tooltip, UI-playstyle-label, MODEL-stat-advisor,
plus the user-requested UI-item-tooltip (all in FEATURES.md / CHANGELOG 0.6.x-0.7.0).
