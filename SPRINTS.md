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
| S18 SIM-engine: simulation & synergy math core (PRD trio) | 3 | ◐ |
| S19 MODEL-ability-outcomes: what this button actually hits for | 3 | ◐ |
| S20 Stat coaching, derived never scripted | 3 | ◐ |
| S21 Rank-rule truth: decode first, vote second | 3 | ◐ |
| S22 Skill-centric Matrix + pathway rows | 3 | ◐ |
| S23 Weapon-swap honesty in the item verdict | 3 | ◐ |
| S24 Modular split + Retail validation fork program | all | ◐ |
| S25 School damage pools: +Frost means frost | 3 | ◐ |
| S26 Class loop parity: all nine classes on the Matrix | 3 | ◐ |
| S27 UI-display-grammar: one voice + the standing toggle | 3 | ◐ |
| S28 Goal-first: ability goals + plan-aware gear relevance | 3 | ◐ |
| S29 Class roster + per-class coverage report | - | ◐ |
| S30 CORE-options: settings surface, one spine two controls | 3 | ◐ |
| S31 Expanded Character Tab (top outputs, ledger, radar) | 3 | ◐ |
| S32 Action-bar synergy trigger (hold ALT, trace the button) | 3 | ☑ |
| S33 UI dynamics: motion spine, eco diagram, radar chart, gauges | 3 | ◐ |
| S34 Crowd pipeline hardening: single-source allow-list, verified-rules bake, show-off tier, coverage, auto-verify | - | ◐ |
| S35 Talent planner: interactive click-to-allocate tree (usable pre-10), save/load/import/export, preview glow | 3 | ◐ |
| S36 HeroLog-style progression: activity feed + team view + gear-level/raid-readiness (SCOPING only) | - | ☐ |
| S37 Gear -> your spells: per-ability item-impact under the verdict (ITEM-spellimpact) | 3 | ☑ |
| S38 UI flexibility + planner access: Matrix drag, stats collapse, resizable grouped options, talent-frame button, copy-as-snapshot, plan-from-current | 3 | ◐ |

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

### S35 - Talent planner (interactive tree, usable pre-10) ◐  (ref: CurseForge forever-talents)
CORE BUILT + GATED 2026-10-15 (gate 294, +1 rules selftest): `model/talentbuild.lua` (pure
rules - budget/tier/prereq + build-string encode/decode, selftest-pinned) + `ui/talent_tree.lua`
(interactive 3-tree render from `gen.talents`, left-click add / right-click remove, locks,
tooltips w/ desc + live impact, per-tree + total counters, Reset, Export/Import strings
data-only-validated, Save/Load/Delete named builds as chips, draggable+saved pos, NO auto-apply) +
`/foresight planner [class]`. Compliance green (our frames, no automation, no Blizzard writes).
LIVE OVERLAY BUILT 2026-10-15 (the centerpiece, per owner): after reviewing ForeverTalents'
source (C_Traits node-based; no embeddable rank data; FT2 code format open) - the plan now
glows the planned path on the REAL talent tree. `TB.toNodePlan` bridges the classic plan ->
C_Traits node ids via `gen.traits.bySpell`; `SynergyHighlight.setPlanPreview` glows each planned
node (blue = points remain, gold = done) with a per-node cur/planned badge, LIVE-DELTAs as you
spend (TRAIT_NODE_CHANGED/TRAIT_CONFIG_UPDATED/PLAYER_TALENT_UPDATE), AUTO-TRIGGERS on talent-frame
open, persists across reload, and is TAINT-SAFE (own anchored overlay pool, never parented into
Blizzard buttons - unlike ForeverTalents) and DISPLAY-ONLY (no auto-apply; they use
C_Traits.PurchaseRank, we never do). `plannerOverlay` toggle (default ON). Share: export an FT1
code -> recipient imports -> their overlay shows the same path. COPY-INSPECT + NEW-NODE PLANNING + FT2 INTEROP BUILT 2026-10-15: (1) `/foresight planner copy`
reads an inspected same-class player's live C_Traits allocation -> node plan -> overlay
(`SynergyHighlight.copyInspectedPlan`, read-only). (2) `/foresight planner edit` toggles an EDIT
MODE: the plan overlays become clickable (left + / right -) on EVERY node incl. Forever-new ones,
so you can plan the whole live tree (anchored Buttons on our layer, never spends). (3) FT2 interop
(`model/ft2.lua`, selftest-pinned round-trip): paste a ForeverTalents FT2 code into the planner's
Import -> full node plan on the overlay + classic subset in the grid; our arithmetic-only base64/
varint/zigzag/Adler-32 keeps the bit-op ban green. Node<->classic kept in sync via
`TB.classicNodeSet`/`TB.fromNodePlan` + `SynergyHighlight.mergeGridPlan` (grid edits preserve the
non-classic nodes). Gate 295. REMAINING: FT2 EXPORT (needs live node structs - entryID/posX/posY -
so it's an in-game-only write, next); in-game verify (copy from an inspect, edit-mode clicks, FT2
import, zero taint) -> flip ☑. Ships to players on the next addon version bump.
*Fit & Overlap - Category UI -> MODEL. Verdict: NET-NEW tree-grid UI + talent-point rules
engine, ENHANCE the planner spine (reuse `HM.gen.talents`/`talentTabs`, `loadout:withTalent`
impact folding, the `model/plan.lua` persistence pattern). Complements: WHATIF-planner,
SYNERGY-highlight (reuse its glow for the over-Blizzard-tree preview), UI-matrix. Touches:
a NEW `ui/talent_tree.lua` (render + click), a NEW `model/talentbuild.lua` (pure rules:
budget/tier/prereq + string encode-decode), `core/init.lua` (a `/foresight planner` command +
button), `core/settings.lua`. Avoid duplicating: the `HM.gen` data spine, `Plan` persistence,
`loadout` folding. Mobile: the 3-tree grid must read at 1280x720 @ 0.65 (scroll/compact).
Languages: all labels in display grammar strings. Trust: builds are the user's, saved/named by
them; export string is theirs. Data: no new SHARED data (reuses gen.talents; the build string
is local). Abuse: import strings + inspected-player copies are UNTRUSTED INPUT -> parse as DATA
only (no loadstring; validate tab/talent ids exist, rank <= maxRank, budget/tier/prereq legal).*

- As a Forever player, I want to open an interactive talent tree at ANY level (including
  before 10, when the Blizzard C_Traits frame is gated), click to allocate points into a
  PLANNED build, and see each talent's real impact - so I can plan and share builds without
  committing points. HARD COMPLIANCE BOUNDARY (differs from the reference): the planner is
  display/advice ONLY - it PLANS, VISUALIZES, GLOWS (shows what to click) and EXPORTS; it must
  NEVER auto-apply/spend points (LearnTalent / C_Traits.PurchaseRank / CommitConfig = automating
  a protected action; would red `check_compliance.py` + violate the account-safety doctrine).
  The player applies the plan manually.
- AC: ☐ renders all 3 class trees from `gen.talents` by tier×column at level 1 (own render,
  not the Blizzard frame). ☐ left-click adds / right-click removes a point; per-tree + total
  counters; respects `maxRank`. ☐ tier-unlock (5 points per prior tier) + prereq arrows
  (`talents[id].prereqs` {talent,rank}) enforced with an honest locked state. ☐ hover shows
  name + rank N/M + `descByRank[rank]` + live what-if impact via `loadout:withTalent`. ☐ save /
  load / delete NAMED builds (persisted per-char, Plan/SavedVariables pattern). ☐ export a
  compact build string + import one (data-only parse, shape-validated) + copy from an inspected
  same-class player. ☐ preview glow over the Blizzard tree when it IS open (reuse
  `synergy_highlight`). ☐ NO auto-apply; a "apply these yourself" hint. ☐ selftest: rules
  engine (budget/tier/prereq legal/illegal) + string encode->decode round-trip. ☐ gate green;
  ☐ mobile 1280x720 @ 0.65 readable.

### S37 - Gear -> your spells (per-ability item impact) ☑  (ref: competitor listing "see what gear does to each of your spells")
*Fit & Overlap - Category DATA-items. Verdict: ENHANCE the item tooltip (`Tooltips.itemLines`)
+ `model/impact.lua`; do NOT fork the item math. Complements: the item verdict (S23/S28) - this
is its per-ability drill-down, using the SAME swap-fold so numbers can't disagree. Touches:
`model/impact.lua` (new `itemSpellImpacts`), `ui/tooltips.lua` (render + retire the
caster-only `_casterRelevanceLines`), `core/settings.lua` (`spellImpact` toggle),
`selftest.lua`. Avoid duplicating: `Sim.topOutputs`/`abilityHit` (reused, not reimplemented).
Mobile: tooltip text, readable at the baseline (no new layout). Languages: spell names from the
client, labels are full phrases. Trust: owner-toggleable (`/foresight set spellImpact off`),
off on equipped gear (baseline law), honest-degrades to nothing with no Sim/spellbook. Data: no
new stored data. Abuse: read-only display, not externally reachable.*

As a player eyeing a drop, I want the tooltip to tell me which of the spells I actually cast
it improves, so the upgrade call is concrete instead of an abstract "+x% caster dps".
☑ `Impact.itemSpellImpacts` ranks the player's top outputs by % change under the item's
net-swap. ☑ rendered under the verdict for both added and vs-equipped, suppressed on equipped
gear + when nothing moves. ☑ every item type (melee/caster/heal) via `Sim.topOutputs`. ☑
`spellImpact` toggle. ☑ retired the caster-only prior art (no parallel line). ☑ selftest
(ranks Fireball under +spell-power; empty-candidate degrade) - gate 297/297. ☑ shipped v0.49.0.

### Verification pass (2026-10-15, full product-wide audit) ☑  -> v0.49.1
Six parallel read-only subsystem audits (engine, panels/stats, overlays/taint, share/crowd,
planner, tooltips) against a green gate. Verdict: structurally sound. FIXED + shipped v0.49.1:
☑ FT2.decode safe-fail - a checksum-valid but truncated/overlong foreign code raised (nil+1 in
  var_decode) instead of returning nil; one off-nil guard + a selftest fixture (gate 298/298).
☑ `/foresight oom` floored (fractional seconds truncated oddly via `%ds` on 5.1).
☑ honest-number hardening: data-sourced magnitudes (imbue proc chance, Windfury bonus AP,
  threat %) moved off `%d` (silent floor on the 5.1 client; the lupa 5.5 harness can't catch it
  because current data is integer) to `%g`/`%.0f`.
☑ planner Save nil-class guard.
TRACKED REFINEMENTS (deferred - want in-game eyes, not an un-eyeballed numbers-shift mid-release):
☐ `CONSISTENCY-itemfold`: unify `Impact.compareItems` onto the single modeled-loadout net-swap
  (−equipped +hovered, one diff) so it matches `itemVerdict`/`itemSpellImpacts` exactly instead
  of the two-base-relative subtraction (~0.5pp gap on non-linear lenses; different-metric, not a
  visible contradiction). Touches impact.lua + the selftest compare assertions.
☐ `UI-display-consolidation`: the panels/Matrix hand-roll `|cff..|r` colors + the cascade chip
  instead of delegating to `ui/display.lua`; colors match by hand today (hence 3 near-identical
  golds/greys), so it's drift-risk not a bug. A Display-adoption sweep would make the grammar
  single-source.

### S38 - UI flexibility + planner access ◐  (owner asks, 2026-10-15; lands in the 0.49.1 beta)
*Fit & Overlap - Category UI. Verdict: ENHANCE the existing panels + planner; no new systems.
Touches: `ui/matrix_panel.lua`, `ui/stats_panel.lua`, `ui/options_panel.lua`, `core/settings.lua`,
`ui/synergy_highlight.lua`, `ui/talent_tree.lua`, `core/init.lua`. Avoid duplicating: the plan
overlay (`setPlanPreview`/`mergeGridPlan`), the save/delete chips, `copyInspectedPlan`. Mobile:
all panels clamp on-screen + resizable/scalable (helps the 1280x720 @ 0.65 binding); in-game
verify pending. Trust: owner-toggleable, no auto-apply, read-only C_Traits reads. Data: copied
snapshots stored as re-validated node-plan tables in SavedVariables (untrusted-input law). Abuse:
display-only, not externally reachable.*

Built + lint-green (compliance/5.1-dialect/taint-law, 298/298), deployed to the beta - EVERY
item needs in-game eyes (frame code the headless gate can't exercise; WoW was down):
☑ Matrix: title-bar drag handle (click still cycles the view); on-screen clamp.
☑ Stats table: independent collapse/expand chevron (separate from the FS master); clamp.
☑ Options: Character-first grouping (+ General/Tooltips/Synergy Matrix/Layout), Character identity
  readout, Layout reset-positions / reset-Matrix-width actions, resizable + size-persistent +
  clamped window reflowing to live width.
☑ Talent-frame button (#5): own tree -> open planner; inspecting -> Copy to Foresight (saved
  snapshot); right-click -> plan mode. Anchored UIParent child, never parented (taint law).
☑ Copy-from-inspect saves a NAMED, DELETABLE snapshot chip (node-plan table, re-validated).
☑ Plan-from-current (#6): `copyMyPlan` seeds the planner from your live allocation so you can
  remove/reallocate display-only (never unlearns); Reset clears copied/edited highlights.
☑ Plan-for-a-future-level: a planning-level control (Lv -/+, default 30) + legacy-talent toggle
  -> `TB.budget(level, legacy) = max(0, level-(legacy and 5 or 10))` (owner model: 20 @ lv30, 25
  legacy; selftest-pinned); add-click gated to the plan budget, header flags over-budget.
☑ FIX (2026-10-16, owner "planner isnt showing talents"): talents carried generated classId=0;
  class now derived from the tab's classMask via `TB.talentClassId`. Real-data selftest added.
☑ FOREVER TALENTS (2026-10-16, owner "its using classic talents instead of Forever"): the real
  fix - the planner drew the dead classic Talent.csv. Now `generate.py` emits `foreverTalents`
  (466, 9 classes) from the Trait DB2 - TraitNode PosX/PosY -> classic 7x4x3 grid, tree->class
  via SkillRaceClassInfo.ClassMask, prereqs from TraitEdge, keyed by nodeID; `TB.talents()`
  feeds the whole planner; node<->grid bridge is identity; impact folds via withTraitNode.
  Authoritative (our DB2, auto-updates at launch); cross-checked vs wowforevertalent.com. Added
  TraitEdge/TraitNodeGroup to fetch.py. Gate 300/300. Per-rank values stay base+presumption
  (client ships only rank-1 effect data; live tooltips verify at launch). NEEDS in-game verify.
☑ TOOLTIP STATS (2026-10-16, owner "stats behind the trees + DPS impact, match the site"): planner
  hover shows the live game description (GetSpellDescription, matches the site) + OUR per-rank
  progression from the baseline (talentRankValueFor; tagged (p) when presumed, description =
  authoritative actual on top - owner "baseline is perfect to assume") + modeled next-point
  impact. In-game Blizzard-frame hover already has the richer nodeImpactLines. NEEDS in-game verify.
☑ TF TALENT TEXT + SYNERGIES (2026-10-16, owner "use talentsforever.com as the authoritative source,
  credited; expand synergies"): `pipeline/fetch_talentsforever.py` ingests the 9 class JSON exports
  from talentsforever.com -> `tf_talents.lua` (HM.gen.tfTalents, 466 talents, per-rank desc[] +
  confirmed[], credited HM.gen.tfCredit + planner footer). Tooltip prefers the credited per-rank
  text ((est) when unconfirmed), then reuses `nodeImpactLines` (Affects/At-max/Synergy) in the
  planner for all 9 classes. Chained synergies = engine's later layer. NEEDS in-game verify.

### S39 - FABLE PRE-RELEASE AUDIT (2026-10-16) ☑ -> 0.49.1 prod re-ship
Four parallel diff-auditors (pipeline / planner / UI-taint / release-readiness) over
v0.49.0..HEAD. ALL FIXED + gated (302/302):
☑ BLOCKER pkg: the v0.49.0 CurseForge zip was BROKEN - repo-root `data/` collided with the
  addon's data/ in move-folders (every data/*.lua stranded under Foresight/Foresight/), and the
  `- web` ignore had an inline comment the packager YAML doesn't strip (web/+functions/+
  firebase.json leaked into the zip). THIS was the 16:44 "install pollution" (the CF app
  installing the broken zip - NOT another session). .pkgmeta: ignores fixed, no-inline-comment
  law written in. MUST verify the v0.49.1 artifact layout post-tag.
☑ BLOCKER data: TraitEdge Type-0 back-edges -> prereq CYCLES deadlocking 4 talents (Druid
  Majesty<->Splendor, Hunter BW<->Intimidation). generate.py: type filter + down-tree-only +
  hard cycle guard; selftest walks the SHIPPED graph (acyclic + arrows-down).
☑ BLOCKER codes: old FT1 strings silently decoded into WRONG talents against the Forever slot
  order. Version fence: forever codes = FT1F-, bare FT1- refuses with a message; loadBuild
  returns ok,err and chips/import SPEAK failures; selftest pins the fence + round-trip.
☑ MAJORS: options saved-size normalized (restore+save, NaN-proof); snapshot chips validated
  (integer ranks, cross-class dropped); tf fetch all-9-or-refuse + cache fallback + "|" escape;
  charDb heals settings; confidence tags kept in planner tooltips; importBox/planControls swap.
☐ FOLLOW-UPS (minor, next sweep): options widget pooling; tf name-drift report (6/466 each way:
  Call of Thunder, Improved Fire Nova, Wake of Fire, Improved Fade, Shadow Affinity,
  Malediction); X-Wago-ID in TOC (Wago upload likely silently skipped); regeneration-determinism
  gate; prereq-rank presumption tag.

### ROADMAP (owner, 2026-10-16) - wrap this phase then move on
☑ Re-audit with Fable -> fixed -> TAG + publish 0.49.1 (the prod re-ship; v0.49.0 was broken).
☐ WEBSITE: "WHERE IT COMES FROM" section (data provenance: Blizzard client data via wago.tools,
  talentsforever.com credit, in-game crowdsourcing + verification loop, release notes as truth
  ladder) + LEADERBOARD EXPANSION (owner 2026-10-16). Deploy hosting so web prod is current.
☐ REDDIT VERIFICATION LOOP (owner 2026-10-16): automated Reddit search/scrape for Forever
  talent content (patch notes, datamined posts, screenshots - "all of them are posted there")
  feeding a VERIFICATION queue - never auto-applied: candidate values land in a review file
  (harvest-draft pattern), k-of-n + human review promote to overrides/verifiedRules. Source
  ladder stays: Blizzard/client data as source of truth > in-game scans > release notes >
  community (reddit/talentsforever). Needs: pipeline/fetch_reddit.py (public JSON API, UA
  etiquette, subreddit + query config), a diff/verify report, SPRINTS story w/ privacy triage.
☐ LOGIN/LOGOUT session data shared (crowd/companion, privacy-by-design, opt-in, crowd-schema).
☐ EXPAND TOOLTIP DATA: chained synergies, map remaining unmapped node ops, ingest talentsforever
  racials/Legacy perks/spellbooks ("take everything from the site").
☐ Then expand the RUN addon (ARR danger/rare advisor) - separate track, Forever launch.
☐ IN-GAME: button placement on the talent/inspect frame, resizable-options layout at extremes,
  the removal-overlay visual (planned < live rank) is a noted refinement, mobile 1280x720 @ 0.65.
☐ DEFERRED: pool the options widgets (layout() currently re-creates per call - pre-existing);
  FT2 EXPORT of a copied snapshot (needs live node structs).

### S36 - HeroLog-style progression (SCOPING ONLY, not built) ☐  (ref: CurseForge herolog-collector)
*Fit & Overlap - Category CROWD -> QA. Verdict: ENHANCE the crowd/companion spine, do NOT fork
it. HeroLog = own-character progression logger -> companion upload -> team activity-feed website
(herolog.io) - architecturally the SAME pattern as our COMPANION-APP.md + web ladders. It is
IDENTITY-ful (a team sees your characters) -> maps to our OPT-IN IDENTIFYING tier, never the
anon tier. Touches (when built): `core/collect.lua` (timestamped progression journal),
`data/crowd-schema.json` (new identifying fields behind `named`), `functions/` (per-character
activity aggregation), `web/` (an activity feed + a team side-by-side view), `privacy.html`.*

Scope to decide before building (each a future story):
- **S36a Progression timeline + activity feed ☐** (FLESHED 2026-10-15, owner-prioritised; buildable).
  *Fit & Overlap - Category CROWD -> QA. Verdict: ENHANCE `core/collect.lua` (new timestamped
  progression journal) + the crowd contribute + `functions/` + `web/`. Complements the named
  show-off tier (S34c) + the companion app. Avoid duplicating: the `Collect` journal spine, the
  single-source crowd schema (new fields go through `data/crowd-schema.json`, never hand-added).
  Data (privacy-by-design): progression EVENTS (level-up, gear-level change, spec/talent change,
  profession skill-up) are non-identifying game data (anon tier) AS NUMBERS; the per-character
  FEED that ties them to a handle is IDENTIFYING (opt-in `named`, like the ladders). Mobile: the
  feed is a vertical timeline, reads at a narrow viewport. Abuse: feed writes are shape-locked +
  rate-limited like contributions; the handle is display-only.*
  - As a player, I want a timeline of my character's milestones (dinged N, ilvl crossed X, swapped
    to a new spec, hit a profession rank) shown as an activity feed, and - if I opt in - on my
    public page, so I can see and share my progression. As a group, a shared feed of the team.
  - AC: ☐ `Collect` journals progression events with a monotonic in-game timestamp + the metric
    delta (dedup so a reload doesn't double-log); capped ring buffer. ☐ the events ride the
    existing contribute payload (new anon `progress` list field via the single-source schema +
    regenerated mirrors + selftest). ☐ `functions/` aggregates a per-handle activity feed doc
    (named submissions only) with small-bucket/rate safety. ☐ `web/` renders a per-character
    timeline (reuse the armory card styles) + links from the Champions/ladder entries. ☐
    `privacy.html` updated (policy-practice sync) - the feed is opt-in identifying. ☐ gate green;
    ☐ mobile verify. DEPENDS ON the companion app for a continuous feed (the manual share flow
    only updates on demand) - until then the feed updates when the player contributes.
- **S36b Team / guild side-by-side** - level, gear level, raid-readiness for a roster shown
  together (opt-in, by handle or guild). New web view; new identifying fields.
- **S36c Gear-level + raid-readiness metrics** - avg ilvl + key-slot-filled as new crowd metrics
  (could ride the anon tier as numbers; the NAMES/roster are identifying).
- Privacy gate: all of S36 is identifying/opt-in; T&Cs + `privacy.html` update in the same
  change (policy-practice sync). Depends on the companion app (an activity feed needs continuous
  data, which the manual share flow can't sustain).

### S34 - Crowd pipeline hardening wave ◐  (full spec: `docs/HANDOFF-next-build-wave.md`)
Make "the owner plays -> everyone gets it in-game-ready" real, add an opt-in show-off tier,
and harden the crowd contract against drift. Seven stories, build order A..G. Ships as the
0.48.0 minor once in-game confirmed (CurseForge tag only then). House laws (never-networks,
Lua 5.1, no-PII anon tier, k-of-n+review for overrides) bind every story.
FIREBASE DEPLOYED 2026-10-14: firestore rules + hosting + functions live on `wow-foresight`
(web show-off/Champions UI, `verifiedRules`/`leaderboards`/`crowdInsights` collections, named
leaderboard + item/observed aggregation). **v0.48.0 TAGGED + PUBLISHED to CurseForge 2026-10-15**
(owner confirmed in-game: "we did some scans and reloaded"; CI ship gate green;
`Foresight-v0.48.0-forever.zip` -> project 1744126 + GitHub Releases). Firebase deploys are
version-free (web/rules/functions + the crowd collections update live, no addon tag); only the
shipped addon zip needs a version. NOTE: the `verifiedRules` collection + the `main` bake grow
as the owner plays (47 owner-trained rules as of 2026-10-15); those reach players on the NEXT
addon version (v0.48.0 shipped with 26). STILL OWNER-GATED: App Check restore (G) waits on the
Firebase backend fix.
- **S34a Single-source the payload allow-list ☑** (prerequisite, built + gated 2026-10-14):
  the three hand-synced copies (addon `buildPayload`, web `sanitize`, `firestore.rules`)
  now derive from ONE schema `data/crowd-schema.json`; `pipeline/gen_crowd_schema.py`
  regenerates `data/generated/crowd_schema.lua` + `web/crowd-schema.js` + the
  `validContribution` block, and the ship gate fails on any drift. Kills the PII-drift risk
  before Story C adds fields. No payload behaviour change (gate 287, +2). Also the
  `CROWD-companion` prerequisite. *Fit & Overlap:* CORE/DATA, Enhance (refactor the existing
  contract to one source, no parallel one).
- **S34b Verified-rules table + owner push + bake-back ◐** (the core ask - addon + tools
  built & gated 2026-10-14): `verifiedRules` Firestore collection (read:true / write:false,
  owner gcloud-authed only - rule added to `web/firestore.rules`); `pipeline/push_verified.py`
  votes the owner's local captures with the harvest analyzer and writes TRAINED-BACKED rules
  (dry-run default, `--write` + read-back to commit); `pipeline/fetch_verified.py` bakes the
  collection into `data/generated/verified_rules.lua` (ships empty-safe); `formulas.F.crowdRule`
  consumes it as the "crowd" tier BENEATH hand-curated `overrides.rankRules`, above presumed,
  below the player's own scan + datamined values (resolution-order + empty-safe selftests,
  gate 289). SHIPPED in v0.48.0 (published to CurseForge 2026-10-15). `verifiedRules` rule
  live; `push_verified.py --write` has pushed + read-back-verified the owner's trained rules
  (26 baked into v0.48.0; collection + `main` bake now at 47 as of 2026-10-15 and growing as
  the owner plays - they reach players on the next version bump, the push/bake itself is
  version-free). *Fit & Overlap:* CROWD->DATA, Enhance the `peer_baselines` bake pattern +
  the rank-rule resolution order (no parallel one).
- **S34c Identifying show-off tier ◐** (web asks #2 + #3; built & gated 2026-10-14):
  OWNER CHOSE handle+armory. Opt-in named leaderboards, OFF by default. Schema gains
  `named` (bool gate), `name`/`armory` (identifying tier, allowed ONLY when `named==true` -
  enforced in the generated Firestore rule + the web sanitize + the addon builder), `buffs`
  (anon provenance). New settings `named`/`handle`/`armory` (a new `text` setting type +
  GUI EditBox); `Crowd.payload({contribute=true})` gathers them (gated behind the opt-in)
  plus active-buff names - skipped on the per-refresh peer readout. `functions/index.js`
  builds `leaderboards/<metricKey>` top-25 from named rows only; `web/` gains a Champions
  section + a named-submission consent notice; `privacy.html` discloses the tier. Gate 290
  (+1; anonymous-promise selftest proves name/armory never ride without opt-in, incl. a
  javascript: armory reject). PENDING (owner): deploy rules+functions+hosting, browser-verify
  the Champions render + consent at a narrow viewport, in-game verify the opt-in + GUI text
  box at 1280x720/0.65 -> flip ☑. *Fit & Overlap:* CROWD, Enhance CROWD-share (new tier on
  the same single-source contract).
- **S34d `/foresight coverage` + inspect-scan readout ◐** (built & gated 2026-10-14):
  `Collect.coverage` (pure, selftest-pinned) + the `coverage` slash command print
  "<captured>/<total multi-rank> captured across N classes; <verified> verified (own scan +
  shipped); missing classes: ...". Inspect-scan readout: a throttled, read-only line when
  captures land while the Blizzard InspectFrame is open. Gate 291. Pending: in-game verify.
- **S34e Zero-click self-verify ◐** (built & gated 2026-10-14): `Collect.hookAutoVerify`
  hooks `PlayerSpellsFrame:OnShow` (HookScript - the taint-safe pattern, lint-clean) and
  runs the read-only `probeTalentTooltips` pass debounced + out of combat; `autoVerify`
  setting default ON. Gate 293. Pending: in-game verify (no taint on a controller; the
  trained talents flip to "verified from your scan" with no hover).
- **S34f Backend aggregation of items + observed buffs ◐** (built 2026-10-14): `functions/`
  aggregates the raw items/observed rows into `crowdInsights/itemPopularity` (top-1000) +
  `crowdInsights/observedBuffs` (per spellId+stat n/mean/cv, `verified` at n>=5 & cv<=0.1 -
  a reviewed-harvest candidate, never auto-shipped). Rule added; doc'd in S13-CROWD-BACKEND.
  Pending: deploy + an emulator/live write check.
- **S34g Restore App Check on writes ☐** (when the Firebase App Check backend is fixed) -
  re-add `&& appChecked()` to the contribute + feedback create rules.

### S7 - Talent Impact Map completion ◐
Make the talent map whole now that C_Traits coverage exists.
- **S7a DATA-traits Phase 2** (◐ -> this sprint): feed trait-node impact ops into the
  what-if model so EVERY Forever talent (not just classic-overlap) moves the dimensions.
  Enhance loadout.lua (one shared op-folder; `withTraitNode`). No new math path.
- **S7b UI-mapping-panel** (◐, model shipped v0.21.0): `model/mapping.lua` - bidirectional
  talent<->ability map (inverse "what modifies Fireball" + forward "what Improved Fireball
  touches") off shared affected-spell edges; `/foresight affects`; pure + selftest-covered.
  MATRIX RENDERER SHIPPED (v0.26.0): `ui/matrix_panel.lua` + pure `matrixModel` build
  the mockup (`mockups/foresight-matrix-2026-10-12.html`) - standing badge, honest
  dimension bars (FILL-BASIS DECISION: relative WITHIN groups, strongest output lens =
  full bar, basis printed on the panel - never fake absolutes), Enabler/Engine/Payoff
  cards + insight box, title-click loop cycling, draggable + validated position,
  user-modifiable opacity (/foresight matrix opacity, validated). SKILL-CENTRIC MODE
  SHIPPED (v0.27.0): `/foresight affects <ability> show` dims the tree + glows the
  modifiers (enumerator path dims, name-scan fallback glows only; alphas restored on
  clear/close). PATHWAY ROWS SHIPPED (v0.27.0): "Best next points - <goal>" top-4 on
  the Matrix, cached + recomputed on talent events only. Remaining: in-game render
  verify (incl. mobile binding 1280x720 @ 0.65).

### S8 - DATA-items + gear compare ◐  (strongest community demand)
v0 SHIPPED (v0.9.0): `Impact.compareItems` nets two items' per-dimension impact (reuses
explainItemDelta, no forked math); the item tooltip shows "vs equipped [slot]" using live
GetItemStats on the equipped item. SCOPE DECISION: the offline ItemSparse DB is
deliberately deferred - shipping ~all items is megabytes of addon bloat, and live
GetItemStats already covers every item the player holds (the leveling use case). A
curated/filtered item DB (for out-of-hand lookup/search) can follow if demand appears.
Remaining: in-game verify the "vs equipped" render + slot resolution (fold into S3).
GEAR SEED SHIPPED (v0.19.0): the offline ItemSparse DB that S8 deferred is now in as a
stat-TYPE catalog (items.lua, 4,663 statted equippable items from the client - name/slot/
ilvl/reqLevel/quality/stat-types; amounts stay live via GetItemStats, no budget-system
guessing). `/foresight items <stat>` browse-by-stat (Dodge/Parry/AP/...). Secondary stats
first-class in vocabulary + levers. Web-source note: ForeverDB/Wowhead/TheWoWDB all datamine
the SAME beta client we fetch from wago.tools - scraping them is redundant + ToS-risky +
gives nothing the raw client data lacks. Forever is in BETA (ends 2026-10-21, launches
2026-11-04) so there is no mature external corpus anyway. Optional next: offline stat-amount
computation (item-budget curves), bridge notable gear into synergy, trim catalog by quality.

### S9 - ASSIST-hud (Pillar 2) ☐  (NEXT BUILD - its own project; new chat)
`C_AssistedCombat.GetNextCastSpell()` (confirmed present live) -> a movable HUD showing the
recommended next ability icon + keybind, optional action-button glow. Display/suggest-only
(compliant by construction). Degrade-safe when the API is unavailable. Resolver logic
(spell->icon->keybind, action-slot scan) pure/selftest-covered; frame render verified in-game.
PACKAGING DECISION (2026-10-11): ships as a SEPARATE project "Foresight: Assist" (download
#2 of 3), its own repo/TOC + CurseForge/Wago project, sharing the generated data layer.
To be built in a NEW chat.

### S10 - PANIC-advisor (Pillar 1) ☐  (the headline safety net)
Per-class escape registry (data table, level/known-spell filtered) + own-state trigger
engine (HP% + drop-rate tiers, all reads secret-guarded, degrade to display-only in
instances) + button-flash overlay + top-3 panic panel. Registry + trigger logic
pure/selftest-covered; glow/panel verified in-game. Biggest remaining build.

### S11 - QA-probe ◐  (phase A v0.16.0; phase B auto-compare v0.24.0)
PHASE A DONE: buff impact observatory - single-buff-change attribution diffs the live stat
sheet and journals observed per-spellId impacts (gain-shaped, conservative: simultaneous
changes discarded). PHASE B DONE (v0.24.0): observed-vs-generated AUTO-COMPARE - harvest
verdicts every observation per stat field (confirmed/mismatch/learned), aggregates across
accounts, and drafts `collected/overrides_draft.lua` (verifiedBuffs candidates upgrade the
tooltip "(p)" to green "play-verified <build>"; correction leads propose consumableImpacts
replacements) - k-of-n (>=3 accounts) + human review, never auto-applied; new ship-gate
selfcheck. FIRST LIVE CATCH: Oil of Olaf +50 armor confirmed; Goretusk Liver Pie observed
+1 Str vs generated +3 (n=2) - suspected Forever LEVEL-SCALED Well-Fed values; needs
observations at more levels before a correction is drafted (if confirmed, the fix is a
scaling rule in generate.py, not a flat override). EVIDENCE STATE 2026-10-13: Oil of
Olaf +50 armor CONFIRMED exact (n=12); Goretusk +1 Str vs gen +3 holds at n=5;
Slitherskin Mackerel observed +80 AP vs gen +6 at n=20 (a 13x gap - the scaling theory
strengthens). ALL observations still sit at ONE character level, so the theory stays
PARKED for multi-level data; the standing law holds (generate.py scaling rule when
confirmed, never a flat override).
CAPTURED-TOOLTIP VOTING SHIPPED (v0.25.1): harvest now parses the "Rank N/M" line off
every captured talent tooltip (recovers ranks even on INSPECTED players' trees, where
the journal's rank field can't resolve), strips chrome (rank line + the beta F6 footer
would pollute number extraction), and feeds the real description text into the
rank-rule voting. First live run over the user's 141-node capture (own tree + inspected
org players, incl. a warlock + a mage): 8 trained-rank captures -> trained votes A=2
B=4 none=5; untrained-r1 A=50 B=32 either=10 none=45. VERDICT: the rank rule is
PER-TALENT on Forever (mixed evidence is real, not noise).
PER-TALENT RANK RULES SHIPPED (v0.27.0): overrides.rankRules consulted by
talentRankValueFor through every value path (loadout folding incl. trait bridge,
summaries, tooltip next-point); verified talents drop the (p) (green header). Harvest
drafts the table per talent (trained votes authoritative; unanimous untrained = weak +
"hover it trained" flag; contradictions surfaced, never averaged) ->
collected/rank_rules_draft.lua. First run: 108 voted, 62 decided (4 trained-backed),
1 contradicted. More inspect-scans = more trained votes.
REMAINING: regen/swing/DoT-tick/GCD measurement during play; equip-delta observation
(item stat ground truth); paste reviewed rankRules entries after more trained captures.

### S12 - Publishing train ◐  (repo LIVE v0.23.1; CurseForge/Wago registration remains)
DONE: `.pkgmeta` + README + privacy ignores; CI workflows (gate / packager-on-tag /
data-freshness); PUBLIC GitHub remote `simulatecx/foresight-forever` (decision 2026-10-11:
public - the crowd-harvested `pipeline/collected/` corpus is gitignored and never
publishes, so "our data stays ours"); action refs SHA-pinned + dependabot; branch
protection (CI gate required on PRs, force-push/deletion blocked, owner direct-push kept
for the solo-dev flow). CurseForge project **"Foresight - Forever"** (id `1744126`)
created; first public build v0.46.4 submitted manually 2026-10-13 (new-project
moderation). **AUTOMATED RELEASE TRAIN PROVEN LIVE 2026-10-14 (v0.46.5):** tag `v*` ->
gate -> BigWigs packager -> uploaded to CurseForge (project 1744126, game version 1.60.1)
+ GitHub Releases, both confirmed Success. Fixes that got it green: (a) dropped `.pkgmeta`
`manual-changelog` (the full CHANGELOG.md overflowed GitHub's 125k release-body cap -> now
auto-generates a per-tag changelog from commit messages; retro-tagged v0.46.4 to bound the
range); (b) the publish credential is the CurseForge **Upload API Token**
(legacy.curseforge.com/account/api-tokens, header `x-api-token`) set as the `CF_API_TOKEN`
secret - NOT the Overwolf/Core API key (console.curseforge.com, approval-gated, for
*reading* mod data; unused here). MIT + open-distribution on the page (docs/CURSEFORGE.md).
Remaining: CurseForge moderation approval -> upload logo + listing copy; Wago slug +
`WAGO_API_TOKEN` (optional). Threat-model publish bindings (DATAFLOW 4b/4c).
LOCAL-INSTALL DISCIPLINE (2026-10-15, after a double install-clobber this session): the
ONLY supported way to install to the local WoW client is `python pipeline/deploy.py` - it
gates, wipes the target, copies `Foresight/`, then verifies every TOC-referenced file
landed. TWICE this session an external folder-copy of the repo ROOT (a parallel orca
worktree/session, not deploy.py) overwrote the install, nesting the addon under `Foresight/`
and leaving `data/` with only the pipeline source -> client "Error loading"s every `data/`
file -> `HM.formulas` nil -> talent-hover crash (`loadout.lua`). deploy.py now also exposes
`--verify` (byte-compares the live install vs the addon, no writes) for a pre-launch health
check; CLAUDE.md Commands documents deploy.py as canonical + bans hand-copying. The release
train itself is unaffected (CI builds from the tag, not the local install).

### S13 - Crowd scale-up ◐  (phase A shipped v0.15.0)
PHASE A DONE: item-sightings journal (equipped+bags at login/logout, IDs only, capped) +
harvest aggregation into `collected/item_sightings.json` with distinct-account counts (the
k-of-n seed) + consumable cross-check. The user's crowd-DB intent ("each logout updates what
items are actually in game") lands at every flush - locally, compliantly (addon never networks).
PHASE B remaining: opt-in companion uploader (reads SavedVariables, POSTs sanitized JSON) +
ingestion/aggregation backend; k-of-n confirmation before any overrides change; privacy-by-
design pass (consent, hashing, retention). Full design (Cloudflare Worker + D1/R2, k-of-n via
unique index, companion sanitize) in `docs/RESEARCH-2026-10-11.md` C2.
BACKEND DECISION 2026-10-13 (user, FINAL): **Firebase** (not Cloudflare - supersedes the
C2 Cloudflare sketch for the transport/store; the k-of-n + sanitize + consent design
carries over). SEQUENCING (user, 2026-10-13): build phase B AFTER the UI-tuning pass is
done ("lets finish tuning the UI, then we will do the backend"). Capture side already
works for every downloader (no dev gate - verified v0.45.3); this phase is the
transport + aggregation only. Still gated on S12 publish (real users first).
HEADLINE FEATURE (user, 2026-10-13): the crowd payoff is **"compare to others in your
spec"** - a same-spec/same-level peer baseline so the standing lenses read against a
real reference that stays meaningful as you grow (this is what the retired zero-floor
"+X% vs base" should become; growthView is the interim toggle, default off). This
needs: the Firebase uploader + ingestion, per-spec/level aggregates (percentiles, not
raw PII), and a panel readout ("your Spellcasting is top ~30% of your spec at your
level (p)"). Privacy-by-design: aggregates only, small-bucket suppression, consent.
PHASE B FOUNDATION SHIPPED v0.46.0 (full design: `docs/S13-CROWD-BACKEND.md`): addon
share contract `core/crowd.lua` (allow-list `/foresight share` JSON, selftest-proven
no-PII) + `web/` app skeleton (consent, re-validate, contribute/compare) +
`web/firestore.rules` (default-deny, App-Check + shape-locked write, aggregate-read) +
`web/privacy.html`. REMAINING: Cloud Function aggregation (percentiles + suppression);
pipeline bake-back `peer_baselines.lua` + in-game "vs your spec" readout.
DEPLOYED + TESTED LIVE 2026-10-14: rules + hosting on wow-foresight
(https://wow-foresight.web.app); owner did the console setup (Firestore / Anonymous
auth / App Check "Fraud Defense" / Hosting). Playwright E2E: page clean, validation
gates, Compare read works, Contribute passes auth+shape+write (App Check token still
PROPAGATING on the minutes-old reCAPTCHA Enterprise key - resolves backend-side; key
config verified: domains web.app/firebaseapp.com/localhost, SCORE). Added
firebase.json/.firebaserc; rule numeric fields use `is number`; JS no-cache + versioned
import. CLOUD FUNCTION AGGREGATION SHIPPED + PROVEN LIVE 2026-10-14 (functions/index.js,
Node 22): aggregateOnWrite (Firestore trigger) + aggregateDaily; dedups by clientId,
per class/spec/level-bucket quantiles (min/p25/p50/p75/p90/max) with MIN_BUCKET=5
suppression; web Compare places your value → percentile (tested: 7-contributor bucket,
"spellcasting 118 = top ~8%", "meleeDps 145 = top ~90%"; seeded data then deleted).
Owner IAM grants (Gen2): compute SA got roles/cloudbuild.builds.builder +
roles/datastore.user. STILL REMAINING: pipeline bake-back `peer_baselines.lua` +
in-game "vs your spec" readout; confirm a real Contribute once App Check propagates
(write gate pending token validation; reads/aggregation unaffected).
CHALLENGES / GAMIFICATION SHIPPED + PROVEN LIVE 2026-10-14 (v0.46.2, user ask): the
crowd payload carries a generic `metrics` map (key->number: stat.armor, stat.maxHealth,
school.<frost/fire/...>); aggregator builds per-metric quantiles with MAX = the live
record; web compare shows a Challenges block ("Most Frost Spell Damage: you 50 - top
~31% (record 70)"). Anonymous, non-identifying; extensible (new challenge = new key).
ABILITY-HIT CHALLENGES SHIPPED 2026-10-14 (v0.46.3): /foresight share ranks the
player's own known abilities (Spellbook.known + Sim.topOutputs) and shares top 6 dmg +
3 heal as "ability:<name>" -> hit; per-class automatic (each class surfaces its own
spells). Rides the generic metrics pipeline (aggregator per-ability quantiles, max =
record; web shows "Biggest Earth Shock: you X - top Y%"). Anonymous (name is game data).
APPROVED NEXT (owner 2026-10-14): a+b+c with a toggle - (b) opt-in NAMED leaderboards
via the Armory tier, showing name + optional Twitch handle (both consent-gated, doc
S8/S8a); (c) in-game "your rank / vs your spec" readout + show-hide toggle; ability
challenges for each class AND an all-classes view. Then: talent-copy import; a
"report a feature" + voting board. Talent sharing deferred.
WEB ARMORY REDESIGN SHIPPED 2026-10-14 (frontend-design skill): the site went from a
textarea to a Blizzard character-sheet - Cinzel/Spectral type, dark stone + gold
filigree, ornate framed panels w/ corner diamonds, class colours. New surfaces: a DAILY
TRIAL hero rotating by day-of-year ("Today: Biggest Greater Heal - submit if you're the
highest!") with the standing record; THE LADDERS browser (class filter -> every
challenge's record from public aggregates, graceful-empty); the compare now renders
gold percentile bars + "top N%" badges + records; share-link prefill/contribute intact.
0 console errors, mobile-friendly, no build step.
IN-GAME PEER READOUT SHIPPED v0.46.6 (the "vs your spec" payoff): the Matrix "Among your
spec" section ranks your lenses + challenge metrics against your class/spec/level bracket
("Spellcasting: top ~10%, median 110") + today's featured challenge rotating by
day-of-year to MATCH the web (date("*t").yday; D.featured mirrors web FEATURED order);
pure `PanelModel.peerModel` + a `pctFromQuantiles` port of the web logic, selftest 278;
`peerReadout` toggle (default on); honest degrade (be-first prompt / small-bucket
suppressed / dark until baked). Baselines baked OFFLINE by `pipeline/fetch_baselines.py` -
reads the public `aggregates` with the maintainer's gcloud OAuth token (App Check blocks
anonymous REST reads; NO service-account key in the repo) into
`data/generated/peer_baselines.lua` (ships EMPTY, fills as the crowd grows). NEW TOC FILE
-> full client restart to load (/reload won't). BAKE PATH PROVEN END-TO-END 2026-10-14
(commit e7ebd76): `fetch_baselines.py` ran clean - gcloud OAuth token -> Firestore REST
read of the public `aggregates` (App Check bypassed) -> wrote valid Lua; 0 buckets today
(no live crowd data yet - the test seed was deleted). Needed a `shutil.which("gcloud")`
fix so Python subprocess finds `gcloud.cmd` on Windows (bare "gcloud" is shell-only).
REMAINING in-game: owner FULL-RESTARTS + verifies the "Among your spec" section renders
(empty state = featured challenge + be-first prompt); re-bake when real contributions
exist; then tag v0.46.6 to publish. The leaderboard / all-classes view + named Armory tier
come later.
LEVEL/SKILL-AWARE ENGINE CARD SHIPPED v0.46.7 (same in-game review, user: "we dont have
stormstrike" - make it dynamic to current level + skills): the Matrix eco/loop card hides
abilities the character hasn't learned, LEADS with current biggest hits (topOutputs on
known spells - the "rockbiter + flame shock now" ask), shows only trained loop members as
the engine, and frames the unlearned ones as "Building toward ... (spec via talents)".
Learned = `Spellbook.known` names + `walkTraits` rank>0; `PanelModel.ecoMembership` pure +
selftested (gate 279); FAIL OPEN to the full loop when no spellbook data (never blanks).
UI-matrix-panel; edits only, /reload loads it. In-game verify queued.
TAINT FIX v0.46.8 (ACCOUNT-SAFETY, user hit it on `/foresight share`): Crowd.payload
called `C_SpecializationInfo.GetSpecialization()` for the bucket spec; CSI calls carry
"Lua Taint: Foresight" (the v0.37.1 lead) and the payload now runs every Matrix refresh
(peer readout) - the tainted call propagated and the client blocked the next protected
action (ADDON_ACTION_FORBIDDEN on share). FIX: removed the CSI call; buckets are per-class
("any" spec) - also correct for Forever's classic talent trees (no retail specs). HARDEN:
compliance lint now reds any `C_SpecializationInfo.*()` invocation (presence checks + name
strings allowed). Gate 279. In-game re-verify share = zero taint queued. A safe spec signal
(dominant talent tree via walkTraits) could restore per-spec buckets later.
SHARE LINK TRUNCATED v0.46.9 (user: the share URL was huge): the one-link `#d=` payload
now carries only the compare-essential data (class/level, lenses, metrics, talent build),
NOT the bulk item-sightings + observed-buff journals (those stay local; a dedicated bulk
path can contribute the item DB later). `buildPayload` still sanitizes items/observed for
that future path (selftest intact). Buckets/rankings unchanged.
WEB PASTE FIX 2026-10-14 (user pasted the share URL into the textarea -> "doesn't look
like valid data"): `web/app.js` parsePayload now accepts a pasted share LINK or bare
`#d=...` fragment (extract + decodeURIComponent), not only raw JSON - the in-game text
says "paste it here". Deployed to wow-foresight (app.js?v=9). CurseForge now shows ~14
downloads (project approved/LIVE).
**v0.46.9 TAGGED + PUBLISHED 2026-10-14** (user go-ahead): release.yml ran green -> CF
project 1744126 (`Foresight-v0.46.9-forever.zip`, 1.60.1 release) + GitHub Release, both
Success. This is the first automated public release carrying the session's work (peer
readout + engine card + TAINT FIX + share truncation); existing v0.46.4/0.46.5 installs
will see "update available" (managed installs, matched to game version 1.60.1, after the
managers' refresh cycle). RELEASE_NOTES.md consolidated the span for the notes.
RESOLVED v0.46.11 - SECOND SHARE TAINT VECTOR (account-safety): `/foresight share` kept
firing the taint block on v0.46.10 even AFTER the v0.46.8 CSI fix. Pinned 2026-10-14: the
crowd clientId pseudonym was generated with `math.randomseed` + `math.random`, and
reseeding the shared Lua RNG from addon code TAINTS it on the classic client - so the
GAMEPAD interact secure path (`SetPreferredGamepadInteractTarget`, which reads the RNG) gets
blocked. User CONFIRMED by unplugging the gamepad -> no block. Both share taint vectors came
from v0.46.0's crowd.lua (CSI + the RNG reseed); removing CSI alone wasn't enough. Harvest
caught 8 new v0.46.10 gamepad-taint events (19:45-19:46, open=[none-open]) confirming it was
live. FIX: clientId now derived from the wall clock + high-res profiler (no RNG); compliance
lint reds any `math.random`/`math.randomseed` so it can't regress. KEY LESSON: never
reseed/advance the shared RNG from addon code on classic - it taints every RNG-reading
secure op (gamepad interact the most visible). In-game re-verify queued (gamepad reconnected,
/reload, /foresight share = no block). NOTE: existing cached clientIds are untouched.
CORRECTION + REAL CONTROLLER VECTOR (v0.46.12): the RNG fix above was a genuine latent bug
but NOT the user's active vector - the clientId is CACHED, so clientId() returns early and
never reseeds (RNG only bites a BRAND-NEW install's first generation). The taint kept
firing on v0.46.11 (8+ gamepad events captured 2026-10-14 20:08, open=[none-open], on the
v0.46.11 session). THE LIVE VECTOR: `core/collect.lua` `probeTalentApiShape` (run once per
login via `/foresight verify`) still CALLED `C_SpecializationInfo.GetSpecialization` +
`GetNumSpecializations` through its `record()` helper, hidden behind a `local CSI =` alias
the direct-call lint didn't see. CSI calls carry Foresight taint -> login env tainted ->
every gamepad interact blocked all session. v0.37.1 retired GetTalentInfo but left these
two. FIX: probe records only `_G.C_SpecializationInfo ~= nil` (namespace presence) - no
alias, no member touch, no call; compliance lint now also reds aliasing C_SpecializationInfo
to a local. THREE addon taint sites found + fixed as real hardening: crowd.lua CSI
(0.46.8) + crowd.lua RNG (0.46.11) + collect.lua login CSI probe (0.46.12).
** DEFINITIVE ROOT CAUSE (taint.log, 2026-10-14) - NONE of the above was the gamepad
block.** The user captured `_classic_beta_/Logs/taint.log` via `/console taintLog 2`: the
block comes from BLIZZARD's chat parser - `ChatFrame1EditBox:ParseText` ->
`ImportAllListsToHash` -> `secureexecuterange()` reads every addon's `SLASH_*` globals; our
`SLASH_FORESIGHT1/2/3` (tainted simply because an addon set them - UNAVOIDABLE, every
addon's are) taint that secure execution, and on a CONTROLLER the gamepad interact op
(`SetPreferredGamepadInteractTarget`) in it is then blocked. Fires on TYPING any
`/foresight` command; gamepad-only. NOT a Foresight defect and NOT code-fixable on our side
(no addon can set a non-tainting global). THE FIX = UI BUTTONS (the user's standing "no
slash commands, all UI" directive): a gamepad player who CLICKS Share / Matrix / Options
never routes through the chat-parse path, so no taint, no block. Slash commands stay for
keyboard users (harmless there). Worth a Forever beta bug report (secure ImportAllListsToHash
tainting gamepad interact from addon slash globals). The 0.46.8/0.46.11/0.46.12 fixes still
stand as legit taint hygiene + the lints prevent regression.
UI BUTTONS SHIPPED v0.46.13 (the fix + the "all within the UI" directive; Fit & Overlap:
Enhance UI-stats-panel, complements CROWD-share + UI-matrix-panel, no duplication, taint-
safe): **Matrix** + **Share** buttons on the character-sheet Foresight panel (beside the FS
toggle + options cog), UIParent-anchored to the char frame, shown/hidden with it. Each calls
`HM.onSlash("matrix"/"share")` DIRECTLY - a function call, NOT a chat dispatch - so it never
reads the SLASH_* globals and never taints the gamepad path. Controller players can now open
the Matrix + grab the share link with zero typing. Gate 279; /reload loads it (edits only).
Follow-ups: a minimap launcher for always-available access (taint-parenting care needed);
more actions as buttons (focus/report already have button homes).
BUTTON RESTRUCTURE v0.46.14 (user): the char-sheet furniture is now FS + Share + Options
(Matrix button folded in). FS is the ONE master toggle - expands/collapses the stats panel
AND the Matrix in lockstep (MatrixPanel.setShown added); the Matrix stays independent once
open (draggable/resizable = pinnable). Controller-confirmed no taint. KNOWN LIMIT (user):
the gamepad can't directionally-navigate to these frame buttons (needs the gamepad cursor);
true gamepad frame-nav is a bigger future item.
WEB UX v0.46.14 (user, after a working submission): dropped the "Read the Omens" compare
button - valid data in the box now AUTO-shows standings (one "Contribute & see your
standings" button remains). The compare result is reframed into DAILY ACHIEVEMENT (today's
featured challenge + your standing, same day-of-year pick as the hero) then OVERALL
SUBMISSIONS (all your lenses + challenge metrics). "Submissions stack" = the aggregator
already accumulates distinct clientIds + updates your entry on re-submit (no dup inflation);
working as intended. app.js?v=13.
APP CHECK WRITES UNBLOCKED (temporary): proven the reCAPTCHA Enterprise token validates
client-side but the backend won't set request.app on writes (permission-denied even with a
valid token + valid shape, browser-reproduced repeatedly). RELAXED `appChecked()` on the
contributions + feedback create rules (kept anon-auth + hasOnly shape-lock + small-bucket
suppression); both writes verified working, test rows deleted. RESTORE `&& appChecked()`
once the Firebase/reCAPTCHA Enterprise backend validation is fixed (documented in
web/firestore.rules). The feedback form is now fully live.
LIVE SELF-VERIFY + SCAN->DB SHIPPED v0.47.0 (S33, user: "do the live self-verify and scan,
then deploy to curseforge"). (1) LIVE SELF-VERIFY: `formulas.lua` now scores the player's
OWN captured talent tooltips (`db.collect.talentTooltips`) in-Lua against the harvest's two
hypotheses (maxTotal `v*R/maxRank` vs perRank `v*R`, +/1000 ms variant), stripping colour
codes + the "Rank N/M" line so their digits can't pollute the vote; a decisive, non-
conflicting TRAINED capture settles that talent's rule for THIS client via `selfVerifiedRule`
(priority 2, ABOVE the shipped crowd rule - local ground truth), and `rankRuleSource` flips
the tooltip header green to "verified from your scan" (talentLines + nodeImpactLines).
Ambiguous/conflicting votes record nothing (presumed stands - confirm-or-correct-only,
never worse). Cached by a key+rank signature. This answers the user's v0.46.10 complaint
("talents I've scanned still say rank rule presumed"). (2) SCAN->DB: `Crowd.payload()` now
rides the item-sightings + observed-buff journals (capped via `Crowd.topSightings`/`capMap`:
100 items most-seen-first / 40 observed) so everything scanned reaches the DB; browser
compare ignores them, only the backend reads them; `firestore.rules` shape-lock them as
size-capped maps (<=500/<=150). Exhaustive uncapped export stays the future companion app.
NEXT: backend item/observed aggregation; restore App Check writes. Gate 284. Deploy as the
CurseForge catch-up release (publishes 0.46.11-0.47.0 at once; CF was stuck at 0.46.10).
FIX v0.47.1 SHIPPED (user caught a panel break after 0.47.0): the self-verify ran unguarded
on the hot value path (every impact eval + talent tooltip) over user-editable captures +
talentForSpell, so one bad capture/throw cascaded into a full panel break. Now fail-safe -
buildSelfVerified is pcall-wrapped (error -> no self-verified rules, presumed stands) +
per-capture spell-bridge guard; regression test added. Also: the Matrix now opens RIGHT
BESIDE the stats panel on FS (via the stats panel's screen rect; a user drag still wins).
Gate 285. User-confirmed "looks better"; tagged v0.47.1 -> CurseForge (fixes the CF users
on the broken 0.47.0).
COMPANION APP SPEC'd (user 2026-10-14: "build what you would actually build - spec the
companion app"; the always-on "play = contribute"). ☐ CROWD-companion, full design in
`docs/COMPANION-APP.md`. Fit & Overlap - Category CROWD. Verdict: Net-new surface
(`companion/`, not yet created) COMPLEMENTING CROWD-share (same contract, same Firestore).
The addon CANNOT network (sandbox + ToS + doctrine), so a tiny Python/PyInstaller tray app
reads the addon SavedVariables (read-only; never game/memory/input/file-writes) and uploads
the same sanitized payload - Warcraft Logs/WowUp pattern. Anonymous client auth (public
apiKey, NO shipped creds), neutered-sandbox safe-parse (untrusted-input law), consent
asked+recorded+revocable (anonymous tier default / names+armory strict opt-in). Touches:
new `companion/`, a rate-limit guard in `functions/`, a privacy-page update, and - the
PREREQUISITE - single-sourcing the payload allow-list (today mirrored in crowd.lua +
app.js + firestore.rules; a 4th hand-synced copy is a PII-leak risk). Mobile: n/a (desktop
tray). Data: re-uses the existing non-identifying contract (no NEW fields). Abuse:
always-on uploader is easier to spam -> per-clientId write-rate guard in the Cloud Fn.
Addon's "never networks" promise UNCHANGED (companion is a separate, disclosed process).
Decisions FINAL in the doc: Python+PyInstaller (reuse the harvest sandbox), REST not Admin
SDK, App Check-on-desktop deferred to anon-auth + rate-limit. Build order in the doc;
step 1 (single-source the allow-list) gates the rest.
NEXT-WAVE HANDOFF (2026-10-14, for a fresh build session): full paste-ready spec at
`docs/HANDOFF-next-build-wave.md`. Stories, in order: A single-source the payload allow-list
(PREREQUISITE), B verified-table + owner push tool + bake-back (the "my scans -> everyone's
in-game-ready data" fast lane), C identifying show-off tier (opt-in handle+armory named
leaderboards + buff provenance = web asks #2/#3), D `/foresight coverage` + inspect-scan
readout, E zero-click self-verify (auto-probe on talent-frame open), F backend item/observed
aggregation, G restore App Check writes. Each story carries its Fit & Overlap, quoted
anchors, final decisions, AC, and out-of-scope. OWNER DECISION PENDING in Story C: named
leaderboard uses a chosen HANDLE+armory by default (recommended) vs real character name/realm
(owner to confirm; same opt-in gate either way).
RETAIL INSTALL DELETED this session: `_retail_` Foresight (stale v0.37.0 addon + both SV
files) removed to stop version confusion; only `_classic_beta_` (Forever, v0.46.10) has
Foresight now.
APP CHECK CONFIRMED WORKING (do NOT relax): Firestore App Check is Enforced at 98% verified
(owner console); Playwright confirmed the client gets a valid reCAPTCHA Enterprise token +
anon auth both succeed. The contribute `permission-denied` was a first-click warmup race,
not a config break - retry after the page settles, or add a token pre-warm (await getToken
before the write). Rule stays `appChecked()`.
WEB FEEDBACK FORM built but NOT committed/deployed (pending the App Check path): `web/`
"Send Word" panel -> a separate `feedback` collection (same project/console as
`contributions`), create-only + App Check + shape-lock, free text capped, optional contact
opt-in; `web/firestore.rules` + `privacy.html` updated. Deploy it with the App Check call.
RANK-RULE clarification (user: scanned talents still show "(p) presumed"): in-game scanning
only CAPTURES tooltips; promotion to "crowd-verified" is harvest -> review ->
`overrides.rankRules` -> rebuild (dev-side), NOT an in-game auto-flip; and captures only
reach disk on `/reload`/logout. PROPOSED enhancement: LIVE SELF-VERIFY - the addon consults
the player's OWN trained scans at runtime so a trained talent flips immediately, crowd
pipeline still ships it for everyone (awaiting owner go-ahead).
OPT-IN IDENTIFYING TIER (user ask 2026-10-14, DESIGNED not built - doc S8): share full
talent tree + WoW Armory link (= name+realm = PII) as a SEPARATE opt-in `sharedBuilds`
collection (own consent/disclosure, public-by-choice, erasure path), enabling named
leaderboards ("submit your character to the Earthshock challenge") + a future data-only
"copy talents" import (never loadstring). Ships only after owner confirms the approach.

### S14 - Buffs & consumables impact ◐  (SHIPPED code-complete v0.12.0)
"How does a flask/elixir/food impact me while active, and what do I lose when it expires."
DONE: consumables.lua (390 items; Well-Fed one-hop keys the TRIGGERED aura spell);
`Loadout:withBuff(itemId|spellId)` + `Impact.buffDelta` (one diff = active vs expiry);
`Snapshot.captureActiveBuffs` via never-secret spellId probe + `Guards.aurasSecret` degrade;
consumable tooltip "While active / On expiry these gains reverse" block; `/foresight buffs`.
Decodes: 290 crit% (SpellEquippedItems discriminates weapon-conditional ones), 34 flat
max health (Titans), 22 armor (Scrolls of Protection), 99/124 AP (Well Fed).
Remaining: in-game render verify (fold into S3 session). Details: research doc A.
Journal triage 2026-10-13: the hovered-without-data items are RESTORE/USE effects
outside the stat-buff decode - healing potions (118 x17), bandages (1251 x3), and
subclass-8 utility items (Incense Candle x17, First Aid Kit x20, Faintly Glowing
Skull x3). Deferred ON THE RECORD: restore effects carry no stat impact for this
model; their natural home is S10 PANIC's consumable registry (heal/escape options),
not a buff-impact tooltip.
Profession pass 2026-10-13 (user did profession work; 18 without-data hovers): combat
potions (Venomous Blood/Dragonfire/Smog/Elemental Purging, subclass 1), engineering
gadgets/bombs (SAF-T Dynamite/Copper Bombs/Stealthman/battery, subclass 0/14), and
bandages/first-aid - all combat/restore tools with no persistent stat buff, same
S10-Panic deferral. EXCEPTION NOTED: ARMOR KITS (Mystic Rugged 252487, Forceful Thick
252463, subclass 6) DO add stats, but as a GEAR-APPLIED enchant (permanent on a slot),
not a buff - so they belong to a future gear-enchant/kit model, not consumables. On the
record, not dropped; backlog candidate `DATA-gear-kits`. No generated-data change.
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

### S16 - WHATIF-planner: the future-build workbench ◐  (triaged 2026-10-12)
Fit & Overlap - Category MODEL -> UI. Verdict: Enhance `model/loadout.lua` delta stack +
`ui/panel_model.lua` What-if surface. Complements: SYNERGY-engine, DATA-items gear compare.
Touches: new `model/plan.lua` (pure), `model/impact.lua` (chainLines wrapper), `ui/panel_model.lua`
(new "Future build" section), `core/init.lua` (/foresight plan), selftest. Avoid duplicating: the
diff path (compose existing withX only) and the stats panel (one renderer). Mobile: panel section
reuses the 240px wide-row renderer (passes the 1280x720 @ 0.65 binding). Languages: enUS addon
strings (house state, no i18n layer yet). Trust: display-only, user's own composition, (p) tags
carry through. Data: new per-char SavedVariables `plan` (typed delta list, no PII, type-validated
on read - untrusted-input law, cleared via /foresight plan clear). Abuse: not externally reachable;
tampered SavedVariables degrade to an empty plan.

As a hardcore player, I want to compose a persistent "future build" plan - talents I'll take,
gear stats I'm hunting ("pants with +5 Agility"), buffs I'd run - and see the net dimension
impact vs my character now, so I can plan builds Path-of-Exile-style inside the game.
AC: ☑ plan persists per character and survives tampering (validated, drops garbage with a note)
· ☑ deltas compose through the ONE loadout path (stat, item bundle, trait, buff, racial, race)
· ☑ `/foresight plan` add/remove/clear/show with net impact + chain lines · ☑ panel "Future
build" section renders the plan + top net deltas live · ☐ clickable builder UI (add-from-tooltip
"plan this", per-delta remove buttons) - next iteration · ☐ in-game render verify (S3 session).

### S17 - IMBUE-compare: weapon-imbue simulation ◐  (triaged 2026-10-11, live user case)
Fit & Overlap - Category MODEL -> UI. Verdict: Net-new data chain (SpellItemEnchantment, now
fetched) + Enhance model/tooltip surfaces. Complements: MODEL-impact-diff (one AP->per-swing
law, 14 AP = 1 DPS), UI-spell-tooltip (same injection module), WHATIF-planner (plan an imbue,
later). Touches: pipeline fetch/generate (`weapon_imbues.lua`), new `model/imbues.lua` (pure),
`core/init.lua` (/foresight imbue), `ui/tooltips.lua` (imbue block), snapshot (weapon damage).
Avoid duplicating: swing/AP math. Mobile: chat + tooltip text (low-res binding ok). Languages:
enUS addon strings (house state). Trust: display-only, (p) tags, unknown proc rates say
"unverified" - never invented. Data: no new stored data. Abuse: not externally reachable.

As a shaman with a slow 2H axe, I want Rockbiter (+AP, +threat) vs Flametongue (per-hit fire
scaling with weapon speed) compared on MY weapon - per swing and per second - so the imbue
choice is a number, not a guess (the user's live case, 2026-10-11).
Ground truth (this build): imbue spell -> effect 360/54 -> SpellItemEnchantment; type-3 equip
spells carry +AP/threat auras (Rockbiter r1 +29 AP); Flametongue's basis rides the tooltip
macro ($8026m1/77../25 = the 1.3s/4.0s speed extremes -> per-hit = basis x speed / 100; r1
basis 326 = the in-game "3-13"); type-1 procs carry flat school damage + chance in
EffectPointsMin (Instant Poison 20% x 15 Nature; Frostbrand chance absent -> "unverified").
AC: ☑ weapon_imbues.lua generated (377 temp enchants incl. item-applied poisons/stones/oils -
poisons are ClassID-0 subclass-8 items here, not skill-line spells) · ☑ Imbues.compare pure +
selftest (per-swing/per-sec, rank dedupe, speed scaling, honest unknown proc rates) ·
☑ /foresight imbue on the live weapon speed · ☑ imbue block on the apply-spell tooltip ·
☐ in-game verify · ☑ Windfury extra-attack EV (v0.25.0, S18: extraAttacks decode + burst/EV
on the live weapon through Sim.windfuryBurst; folded into Imbues.compare).

### S18 - SIM-engine: simulation & synergy math core ◐  (triaged 2026-10-12, PRD trio)
Source: three user PRDs (simulation architecture / demystification / class formulas), folded
into one sprint; design mapping + corrections in `docs/SIM-ENGINE-2026-10-12.md`.
Fit & Overlap - Category MODEL -> UI (secondary DATA). Verdict: Net-new `model/sim.lua` (Tier-2
engine) + Enhance formulas.lua (normalization, flurry uptime), imbues.lua (Windfury EV),
tooltips.lua (OOM line, standing-shift flag, Windfury weapon line), panel_model.lua (standing),
generate.py (extraAttacks / critHaste / gear speedMs decodes). Complements: IMBUE-compare (one
AP->DPS law), MODEL-impact-diff (standings/pathways ride Impact.evaluate - no second value
path), WHATIF-planner (pathway candidates are the same what-if loadouts), SYNERGY (loops = the
curated why-layer). Avoid duplicating: hand-copied constants - Windfury AP/count and Flurry
haste are DECODED from client data via tooltip-macro chase; only normalization constants + the
FSR law are community formulas, tagged classic-presumed. Mobile: chat + tooltip text (passes
1280x720 @ 0.65). Languages: enUS house state. Trust: display-only, every model line carries
(p), missing data said out loud (no invented proc rates or hit numbers). Data: no new stored
data. Abuse: not externally reachable.

As a player new or old, I want the game's hidden math - proc engines, mana economy, weapon
speed scaling, build identity - explained on my own numbers, so gear/talent/imbue choices are
informed decisions instead of folklore.

AC: ☑ Tier-1: weapon normalization constants + flurry steady-state uptime in the formula
registry (tagged) · ☑ pipeline decodes: Windfury extraAttacks (20% / 2 attacks / +46..333 AP by
rank), Flurry critHaste (+10% for 3 swings via the $Nn macro chase), weapon `speedMs` on gear ·
☑ melee cascade crit -> Flurry uptime -> effective speed -> Windfury burst/EV -> first-order
DPS (`/foresight sim`) · ☑ time-to-OOM chain-cast model with five-second-rule honesty
(`/foresight oom <spell>` + ability-tooltip line) · ☑ standings (stat-space ratios, honest:
Glass Cannon/Bruiser, Endurance, Primal Hybrid, Threat Anchor) on the panel subtitle + item
tooltip "Shifts your build" flag · ☑ Windfury-engine weapon-hover line (AP-term delta from
offline speed) · ☑ goal pathways ranking unspent trait steps per dimension (`/foresight path`)
· ☑ class-loops registry (Shatter / Windfury / Flurry; Enabler -> Engine -> Payoff;
selftest-gated name resolution; `/foresight loop`) · ☑ selftest 165 (+21) · ☐ in-game render
verify (next session) · ☐ Matrix side-panel UI consuming loops + pathways (S7b renderer, next
build).

PRD corrections recorded (the data wins): Instant Poison is a flat 20% in client data, not
PPM · Intellect does not alter spell coefficients (cast-time law) · Windfury extra attacks
keep ACTUAL weapon speed (normalization governs instant yellow abilities) · %-threshold
archetypes replaced with within-character ratios (dimension indices are not cross-comparable) ·
Flurry per-rank scaling UNRESOLVED in data (rank-1 buff decoded; talent-tooltip capture
upgrades it).

### S19 - MODEL-ability-outcomes: what this button actually hits for ◐  (triaged 2026-10-12, handoff spec)
Fit & Overlap - Category MODEL -> DATA/UI. Verdict: Net-new capability ID, zero new
addon files - Enhance generate.py (ship_spells pass), sim.lua (abilityHit beside
windfuryBurst), formulas.lua (spellBaseDamage law + critMultiplier framing constants),
tooltips.lua spellLines/nodeImpactLines (the ONE injection module), loops.lua (Shatter
claim). Complements: SIM-engine, UI-spell-tooltip (retires the backlog line), DATA-loops,
QA-probe (captured tooltips verify our numbers). Avoid duplicating: build_ops,
talentRankValue, spellCoefficient, Mapping edges, the injection module. Mobile:
tooltip/chat text (passes the 1280x720 @ 0.65 binding). Languages: enUS house state.
Trust: display-only, (p) until probe-verified, nil-degrade on missing decode - never
invented. Data: no new stored data. Abuse: not externally reachable.

As a player, I want my ability tooltip to say "hits for ~141-156 with your gear" and
a talent hover to say "+21 to Stormstrike", so the translator covers the thing I
actually press.

AC: ☑ generate.py decodes dmg{base,var,lvl,maxLvl,coef}/heal/wpn{pct,flat,norm}/dotTick
+ counts in build.lua (509 damage / 158 weapon / 145 heal) · ☑ data gates (Fireball
14-22, HS flat 138, Backstab 150%+norm, coef 0.429, Ice Lance decodable) ·
☑ F.spellBaseDamage tagged datamined-presumed · ☑ Sim.abilityHit/abilityHitDelta pure,
selected-spellmods via affected edges at talentRankValue, normalization substitution,
nil degrade · ☑ spellLines absolute line + datamined-coefficient upgrade ·
☑ nodeImpactLines before->after deltas (<=3 lines) · ☑ Shatter loop claims level-capped
numbers, fallback retained · ☑ /foresight hit · ☑ selftest >= 189 (shipped 191) ·
◐ in-game verify >= 3 abilities vs rendered tooltips before 2026-10-21 - 1/3 done:
Lightning Bolt r2 CONFIRMED live 2026-10-12 (base + level law + coefficient; display
corrected to the floor/ceil envelope the game renders, v0.31.2, selftest-pinned).
AUTOMATED at scale (v0.33.0): `/foresight audit` scans every known decoded spell's
rendered tooltip and verdicts vs base + gear-composed envelopes - one command
completes this criterion and journals for the harvest.

### S20 - Stat coaching, derived never scripted (enhance MODEL-stat-advisor) ◐  (triaged 2026-10-12, handoff spec)
Fit & Overlap - Category MODEL -> UI. Verdict: Enhance impact.lua rankStats surface +
panel_model statvalue + tooltips itemLines. Complements: MODEL-stat-advisor,
UI-item-tooltip. Avoid duplicating: any per-class string registry (rejected-on-record:
hardcoded math) - the line is composed from statConversions zeros + rankStats
marginals + the live graph's crit derivation only. USER BINDING: never
anti-flexibility - the net-swap verdict stays the headline; coaching is attribution
("what carries this item"), never judgment. Mobile: text lines. Languages: enUS full
sentences. Trust: display-only, (p) tags. Data: none. Abuse: not externally reachable.

As a leveling Shaman, I want Foresight to explain that Agility does nothing for my
melee power - with the mechanism and live numbers - while still judging any item by
its honest net impact, so I understand my scaling without the addon policing my
choices.

AC: ☑ Impact.coachingLine derives trigger (dead focus marginal + conversion-table
zero), names mechanism + winner with live marginals (crit/pt read off the graph) ·
☑ max ONE line, threshold-gated (display-gate constants, relative deadness because
crit leaks into the melee lens) · ☑ surfaces: advisor, panel statvalue footer, item
tooltip only when the dead stat dominates AND beneath an unchanged verdict ·
☑ selftest +5 incl. the anti-registry numbers-move check · ☑ no string registry
anywhere · ☐ in-game render verify.

### S21 - Rank-rule truth: decode first, vote second ◐  (triaged 2026-10-12, handoff spec)
Fit & Overlap - Category DATA -> MODEL. Verdict: Enhance generate.py (per-rank op
decode via spellRanks + trait-node values bridge), formulas.lua (talentRankValueFor
resolution order), selftest. The per-talent rank-rule SYSTEM (overrides.rankRules +
harvest voting + honesty marks) is ALREADY SHIPPED (v0.27.0) - do not rebuild it; this
story feeds it datamined per-rank values so the rule is only needed where rank spells
don't exist (single-spell trait nodes). Avoid duplicating: the ONE talentRankValue
resolution path. Trust: datamined values drop (p); fallbacks keep it; nothing invented
on misalignment. Data: generated shape change (shared-spine law). Abuse: not
externally reachable.

AC: ☑ per-op values arrays for aligned classic talents (31 decoded, 13 skipped on op
misalignment, skip-count printed) + counts in build.lua + bridge onto classic-overlap
trait nodes (live path) · ☑ resolution order values > override > presumed, ONE
function (loadout/impact/tooltips/sim all pass op.values) · ☑ rankRuleMark "" for
datamined values ("rank values datamined" header) · ☑ selftest +6 (exact per-rank
value, (p) drop, missing-values fallback, order, counts gate, bridge gate; legacy
override checks green) · ◐ operational: review collected/rank_rules_draft.lua ->
promote lines to overrides.rankRules before 2026-10-21 (human review - user). FIRST
PROMOTION 2026-10-12 (v0.31.3): all 4 trained-backed lines promoted (Improved
Frostbolt/Deflection/Thundering Strikes = perRank, Ancestral Knowledge = maxTotal);
63 weak untrained lines + the contradicted Destructive Reach held for more trained
captures - keep hovering trained talents and inspecting players until 10-21. FOURTH
ROUND 2026-10-13 (v0.44.3): +8 trained-backed (Lightning Reflexes, Improved Sinister
Strike, Endurance, Improved Eviscerate, Blood Frenzy, Feral Swiftness, Heart of the
Wild = maxTotal; Dual Wield Specialization = perRank); DEMOTED Ferocity + Tidal Focus
to (p) on conflicted trained evidence (new r5/5 Ferocity capture votes B vs round-3's
A; Tidal Focus trained votes gone from the corpus, untrained B x3) · ☐ in-game trained
mid-rank hover (r2-r4) on Ferocity + Tidal Focus to settle direction. 25 verified;
5 contradictions held.

### S22 - Skill-centric Matrix + pathway rows ◐  (triaged 2026-10-12, handoff spec)
Fit & Overlap - Category UI (model support in mapping/panel_model). Verdict: Enhance
Mapping.forSpell (classified buckets), synergy_highlight (dual glow + overlay dim,
taint-free law), matrix_panel (focus mode + pathway chip row), panel_model
(pathwayModel pure). Complements: MODEL-ability-outcomes (pathway endpoint),
SYNERGY-highlight (one overlay system), UI-matrix-panel. Avoid duplicating: the lever
taxonomy / statConvert chain logic (statFeeders ride it), the ONE highlight plumbing.
Mobile: chip row wraps at 1280x720 @ 0.65. Trust: display-only; segments only from
computed values; (p) propagates. Data: none new. Abuse: not externally reachable.

AC: ☑ classifiedForSpell pure (direct/school/statFeeders) on existing machinery
(Levers.of; priority dedupe) · ☑ gold solid vs blue pulse vs overlay-dim, zero
Blizzard-frame mutation (v0.27.0's SetAlpha dim REPLACED per the overlay-dim law) ·
☑ /foresight focus (saved per char, validated) + Matrix insight lists the classes +
tree light-up via hookTalentUI (focus outranks theme) · ☑ pathwayModel chip row,
nil-degrade per link, (p) propagation, wrapped FontStrings (mobile wrap) · ☑ selftest
+8 across both halves · ☑ what-if AP correctness fix in abilityHit's weapon branch
(snapshot-AP substitution; marginal AP folds on non-normalized strikes) · ☐ in-game
render verify.

### S23 - Weapon-swap honesty in the item verdict ◐  (triaged 2026-10-12, live catch)
Fit & Overlap - Category UI -> MODEL. Verdict: Enhance tooltips.lua (scan + render),
sim.lua (pure weaponSwap/apFromStats beside windfuryBurst), impact.lua (the ONE
itemVerdict gains the swap term). Complements: S20's USER BINDING ("count everything
the item brings - weapon DPS, other stats"), the Windfury weapon line (same hover).
Avoid duplicating: ForesightScanTooltip (collect.lua's hidden frame, reused - never a
second scanner), AP_PER_DPS/statConversions laws, the one verdict judge. Mobile:
tooltip text (1280x720 binding). Languages: enUS parse patterns (house state; the
parser is one localized seam). Trust: display-only, (p)-tagged, base ranges from the
game's own rendered tooltips. Data: none new. Abuse: not externally reachable.

As a melee player at the auction house, I want a weapon's verdict to count the weapon's
own damage range - an 18-27 -> 34-52 swap is not "+4.7% Melee DPS" - so the number I
see is the number that decides the buy.

AC: ☑ Tooltips.parseWeaponTip pure (base range + speed; bonus-damage lines skipped;
comma numbers) · ☑ Sim.weaponSwap white-DPS law (baseAvg/speed + AP/14; apDelta nets
BOTH items' AP-equivalent stats via apFromStats) · ☑ verdict uses the swap pct for
melee goals only; stat-less weapons still judged (block renders with the swap line) ·
☑ swap line beneath the verdict ("~X -> ~Y per swing, ~A -> ~B white DPS (+N%) vs
your main hand (p)"); scans both tooltips via the ONE hidden frame; nil-degrades on
empty main hand / unscannable / same item · ☑ CAPTURE NO-DOWNGRADE LAW: trained
talent-tooltip captures never overwritten by untrained re-hovers (the Deflection
degradation) · ☑ selftest +5 · ☐ in-game verify on the 18-27 vs 34-52 pair. Known
limits (honest): main-hand compare only (no offhand/ranged v1); crit/proc stats not
in the swap pct; offline damage ranges (ItemDamage* tables) stay deferred.

### S24 - Modular split + Retail validation fork program ◐  (user directive 2026-10-12)
Fit & Overlap - Category CORE/QA -> program. Verdict: AUDIT first (measured, not
asserted: the engine layer has ZERO client-API coupling; all _G touches concentrate
in 8 adapter/surface files - census in docs/ARCHITECTURE-AUDIT-2026-10-12.md), then
Enhance: new `core/client.lua` (the ONE item-API namespacing swap point; tooltips +
snapshot delegate), docs/RETAIL-FORK-HANDOFF.md (the fork procedure, what retail CAN
validate - decode laws, composition, envelope, audit loop, plumbing - vs what must
NEVER port back - formula values, data/, loops). Avoid duplicating: a folder-level
engine/ restructure (the TOC order IS the module system; churn resets beta
verification for zero behavioral gain). Trust: both forks keep the same gate +
compliance + taint laws. Data: none new. Abuse: not externally reachable.

As the product owner, I want the engine validated against RETAIL's fully-known live
data before 2026-11-04, so the Forever launch starts with proven math and
crowdsourcing opens on day one.

AC: ☑ measured architecture audit (module map, data inventory, coupling census) ·
☑ core/client.lua extracted + delegations (selftest-pinned nil-safe) · ☑ fork
handoff with validation protocol (/foresight verify -> audit -> hit -> swap hovers)
and the port-back law (engine/pipeline cherry-picks only; data and formula VALUES
never cross) · ☐ execute the fork (new repo, retail build fetch/generate, re-pin
data gates to retail ground truth) · ☐ retail in-game validation to audit
mismatch=0 · ☐ port-back + Forever launch-build regen on 2026-11-04 + flip channel
to live + open crowdsourcing.

### S25 - School damage pools: +Frost means frost ◐  (S25-S28 handoff, 2026-10-12)
Fit & Overlap - Category MODEL -> GRAPH. Verdict: Enhance snapshot (retain per-school
reads), loadout (six school nodes + max formula node, one delta-folding law), sim
abilityHit (school-aware power), ITEM_STAT_MAP/PLAN_STATS/levers vocabulary (school
stats first-class). Complements: MODEL-ability-outcomes (school-true hit numbers),
SYNERGY (school axis already exists). Avoid duplicating: the SCHOOLS id map (one
source: Snapshot.SCHOOLS/SCHOOL_MASKS/schoolPoolName), the lever school axis, the one
op-folder. Mobile: no new UI surface. Languages: existing sentence patterns. Trust:
display-only; pool law tagged classic-presumed (F.schoolPoolLaw); nil-degrade keeps
today's generic behavior. Data: no new stored data. Abuse: not externally reachable.
Compliance: reads already Guards-routed.

As a caster, I want +Frost Damage gear to move my frost spells specifically - and my
Frostbolt tooltip to read from the frost pool - so school gear decisions are honest
instead of averaged.

AC: ☑ snapshot retains all six school totals (guarded, headless-zero) · ☑ six
stat.school.* nodes + stat.spellDamage = max formula node (dimensions untouched) ·
☑ folding law: generic -> all six, school-specific -> one (classic-presumed tagged) ·
☑ abilityHit reads the spell's school pool, falls back honestly (frost != best
fixture) · ☑ school item keys mapped (pattern family; unknown-key journal stays the
tripwire), PLAN_STATS updated · ☑ verify prints the six pools (the in-game check) ·
☑ selftest >= 235 (shipped 236) · ☐ in-game verify one school read + one frost-gear
hover before 2026-10-21.

### S26 - Class loop parity: all nine classes on the Matrix ◐  (S25-S28 handoff)
Fit & Overlap - Category DATA. Verdict: Enhance data/loops.lua (six new curated loops;
Gemini name-level input, gate-verified - "Improved Aspect of the Hawk" and "Curse of
Agony" failed the name gate and were substituted, never forced). Complements:
UI-matrix-panel, MODEL-ability-outcomes (payoff numbers via abilityHit + the shared
loopCompute). Avoid duplicating: Shatter compute pattern; abilityHit the only hit
source; NO proc math - undecoded proc rates say so (PROC_GAP line). Roster law
applied: all 9 client classes covered, selftest-gated. Mobile: existing cards.
Trust: display-only, confidence-tagged, honest gaps. Data: none new.

AC: ☑ six new loops, every member resolves (gate) · ☑ computes only where math
exists (abilityHit payoffs + Instant Poison per-swing for ROGUE); proc gaps say
"not yet decoded" · ☑ backlog groomed: DATA-proc-families · ☑ roster-law selftest
(9/9 classes) · ☑ selftest 242 (+3... +4 incl. roster gate) · ☐ one new class card
render verify in-game.

### S27 - UI-display-grammar: one voice for every number + the standing toggle ◐
Fit & Overlap - Category UI -> GRAPH. Verdict: Net-new ui/display.lua (pure) as a
CONSOLIDATION; delegates dimension values to D.display (never a second renderer).
Touches (phased): tooltips (verdict + comparison MIGRATED, phase b), panel/matrix/
commands + deletion of remaining superseded formatters = phases c/d (next cut).
Trust: THE owner-control story - settings.show.standing (default ON, user decision
2026-10-12), /foresight set standing on|off, respected at all four render sites
(playstyleLabel prefix, Matrix badge, item Shifts-your-build line, /foresight build);
OFF hides the NAME never the numbers; options GUI menu backlogged. Data: one
validated settings key. Abuse: not externally reachable.

AC: ☑ six claim shapes string-for-string selftested · ☑ weakest-tag inheritance ·
☑ one color table + bracket exclusivity · ☑ /foresight set standing on|off validated
(tamper defaults ON), four render sites respect it · ◐ phased migration (b done:
tooltip verdict + comparison; c/d remaining: panel/matrix/command printers + formatter
deletion) · ☑ options-menu GUI backlogged · ☑ selftest 246 (+4) · ☐ in-game render
spot-check.

### S28 - Goal-first: ability-level goals + plan-aware gear relevance ◐
Fit & Overlap - Category MODEL -> UI. Verdict: Enhance gearGoal vocabulary +
itemVerdict + goalPathways + plan store + the ONE injection module. Boundary kept:
focus (S22a) LIGHTS, goal JUDGES - shared level-capped resolver, distinct settings.
Avoid duplicating: the resolver, the loadout delta path, abilityHit. Trust: user
goals ARE the owner control; verdict fallback is honest (never a silent wrong judge);
no invented closeness %. Data: two validated settings fields.

AC: ☑ goal grammar auto|dimension|ability:<id>, validated + tamper/unjudgeable ->
auto · ☑ ability-goal verdicts via net-swap abilityHit (baseline law), honest
fallback note · ☑ pathways rank by abilityHitDelta under an ability goal (unit-honest
rows) · ☑ plan goals cap 3 (/foresight plan goal) + ONE relevance line beneath the
verdict, concrete units, never on equipped · ☑ selftest 252 (+6) · ☐ pilot
goal/relevance verify in-game.

### S29 - Class roster + per-class coverage report ◐  (carry-over, S25-S28 handoff)
Fit & Overlap - Category DATA. Verdict: Enhance generate.py + fetch.py (gen.classes
from ChrClasses, degrade to CLASS_NAMES) + harvest (coverage matrix) + selftest
(conversions-per-class gate). The data-backed source for the roster law - loop
coverage + S31's per-class ledger honesty enumerate from it, never a remembered list.
Trust: honest degrade when ChrClasses isn't fetched; resource type read LIVE not
guessed. Data: generated shape addition. Abuse: not externally reachable.

AC: ☑ gen.classes (id/name/token) emitted, ChrClasses-sourced when present ·
☑ conversions-per-class completeness gate (selftest) · ☑ S26 loop coverage enumerates
gen.classes · ☑ harvest per-class coverage matrix · ☑ selftest 254 (+2).

### S30 - CORE-options: the settings surface, one spine two controls ◐  (S30-S32 handoff)
Fit & Overlap - Category CORE -> UI. Verdict: Net-new core/settings.lua (the declared
SETTINGS_KEYS spine) + ui/options_panel.lua (GUI) + Enhance init.lua (/foresight set
generalized, standing migrated). Complements: /foresight set + the eye icon (two
controls, one key). Avoid duplicating: one settings store, one validation path, no
Blizzard Settings API fork risk. Trust: THE owner-controls surface; tabs render only
for shipped groups (no Panic tab). Data: validated settings keys. Abuse: not
externally reachable.

AC: ☑ SETTINGS_KEYS declared (type/default/validator/description), standing migrated ·
☑ new keys coaching (3 surfaces honor OFF), actionTrigger (off|alt|shift), panelAlpha
(Matrix opacity aliased to it) · ☑ /foresight options + /foresight set <key> <value>;
report button wired · ☑ tabs from shipped groups only · ☑ combat-gated; validators
heal tamper (false-value read bug caught + pinned) · ☑ selftest 259 (+5) · ☐ in-game
render + toggle verify.

### S31 - The Expanded Character Tab: top outputs, the ledger, the radar ◐  (S30-S32 handoff)
Fit & Overlap - Category UI -> MODEL. Verdict: Enhance UI-stats-panel (new sections,
keep drag/pos/refresh) + net-new PURE models (core/spellbook.lua adapter,
Sim.topOutputs, PanelModel.ledgerModel, PanelModel.radarModel) rendered display-grammar
native (= S27 phase c). Trust: ranking-basis law (per-use non-crit, kind-split, NO DPS
claim), ledger RECONCILIATION law (Base+other remainder + over-attribution (p)), radar
per-axis independent normalization + basis line. New guarded reads Guards-routed +
apiWatch. Mobile: radar edges-only (fallback law) pending the screenshot polygon.

AC: ☑ spellbook adapter (guarded, apiWatch, headless-empty) · ☑ top-3 ranking law,
kind-split · ☑ ledgerModel sources + reconciliation + discrepancy · ☑ radarModel
per-axis independence + plan layer 2 + basis · ☑ sections wired into the FS panel ·
☑ selftest 264 (+5) · ◐ spoke polygon + header/eye + top-3 hover->ledger = screenshot
pass · ☐ in-game verify pilot + one other class.

### S32 - Action-bar synergy trigger: hold ALT, trace the button ☑  (S30-S32 handoff)
Fit & Overlap - Category UI. Verdict: Enhance focus mode (S22a) with a TRANSIENT
modifier-hover input path. Complements: S30 (actionTrigger setting), classification,
the talent-UI hint. Avoid duplicating: classification/glow/dim; the persistent focus
setting is NEVER overwritten. Trust: off|alt|shift owner control; action buttons never
touched (taint law - we read GetActionInfo and highlight the talent tree only);
combat-gated. Data: the S30 key. Abuse: not externally reachable.

AC: ☑ modifier-hover applies transient focus, restores prior state on release/close ·
☑ slot->spell guarded resolve, honest macro/item/unknown skip · ☑ setting off|alt|shift
honored (S30 spine) · ☑ no action-button frames touched; combat-gated · ☑ apiWatch
(GetActionInfo, IsAltKeyDown, IsShiftKeyDown) · ☑ talent-UI hint line · ☑ selftest 266
(+2 state machine + resolver) · ☑ in-game gesture verify (user-confirmed 2026-10-13:
"the alt toggle on talents works well").

INCIDENT 2026-10-13 (fixed v0.44.2): the first live trace session fired
ADDON_ACTION_FORBIDDEN x2 (SetPreferredGamepadInteractTarget) naming Foresight - the
taint sentinel journaled it, the harvest surfaced it. Vector: the talent-UI hint was
created ON PlayerSpellsFrame + a psf.foresightHint key write - the one taint-law
violation in v0.44.x (all pre-v0.44 archives taint-free). Fixed: hint on our own
UIParent frame, anchored only; compliance gained the TAINT-LAW LINT (proven red on
the pre-fix lines). Causality presumed, not proven (client taint blame is fuzzy) ·
☐ in-game verify: next session shows zero sentinel taint events.

### S33 - UI dynamics: motion spine, eco diagram, radar chart, gauges ◐  (user directive 2026-10-13)
Fit & Overlap - Category UI -> CORE. Verdict: Enhance matrix_panel + stats_panel +
panel_model (new pure gaugeModel) with ONE net-new shared spine `ui/motion.lua`
(tweens/pulses/lines/radial gauges/polygon math - neither panel forks animation code).
Complements: S30 (new uiMotion key on the spine), S31 (closes the deferred radar
spoke-polygon), S22a (same overlay discipline). Avoid duplicating: the synergy house
glow stays untouched; fill-basis math stays in the model; the 0.2s debounce pattern is
reused, never rewritten. Mobile: chart/diagram sized inside existing panel widths,
labels keep full values; uiMotion=off restores today's static render exactly; verify
at 1280x720 @ 0.65. Trust: owner control uiMotion off|subtle|full (default subtle);
honesty laws unchanged - fill-basis lines stay, (p) never animates away, text REDUCED
not removed (eco descs move to hover tooltips; numbers + grammar lines stay). Data:
none new. Abuse: not externally reachable. Compliance: all drawing on OUR frames (the
taint-law lint enforces); animation only while panels shown (throttle law - tweens
self-terminate, continuous pulses stop on hide).

As the player, I want the Matrix and Character Tab to SHOW relationships and change -
bars that sweep, a connected Enabler->Engine->Payoff diagram, a real radar shape,
rings for uptime/OOM - so the UI reads at a glance instead of as stacked text.

AC (shipped v0.45.0): ☑ uiMotion key on the S30 spine (off|subtle|full, default
subtle; off = the v0.44.x static render, including text-card eco + text-row radar) ·
☑ Matrix dimension bars tween to new fills + top-lens accent pulse; value text
flashes on change · ☑ eco = connected 3-node diagram (our lines + traveling pulse in
full; node descs on hover; insight box + computed numbers unchanged) · ☑ radar
renders as a drawn chart (spokes + SetVertexOffset polygon fill + plan outline
overlay + abbreviated tip labels; display-law rows + basis line kept BELOW the chart)
· ☑ radial gauges where a TRUE fraction exists (Flurry uptime when the engine is
trained; chain-cast OOM ring for the focused mana spell, 60s cap printed) - honest
absence otherwise · ☑ value-change flashes on FS dimension/ledger rows · ☑ pure
selftests +5 (geometry points/fan/layout, gaugeModel both paths + honest-empty,
uiMotion validation; 272 total) · ☑ gate green + deployed · ☐ in-game verify incl.
mobile binding + uiMotion=off round-trip (the P1 sweep).

IN-GAME FEEDBACK 2026-10-13 (v0.45.1): radar user-confirmed ("Radar is good!").
Fixes: (1) STUCK FOCUS - a persisted focus auto-relit the tree every login; focus +
theme are now SESSION-ONLY (nothing lights until asked this session; login wipes the
legacy value) - also kills a login-time talent-overlay taint vector. (2) MATRIX
HORIZONTAL STRETCH - the panel is now resizable (drag grip, width 300-680 validated +
saved) and re-flows off the live width so the eco diagram/bars/gauges stop cramping.
Selftest 274 (+2). TAINT FOLLOW-UP (v0.45.2): the reported block did NOT re-journal -
the recorder was blind to blocks firing before its store existed (early login); now it
buffers+flushes with richer context (uptime + open surface). No new event in the
v0.45.x sessions (only the two pre-fix morning ones). HORIZONTAL LAYOUT (v0.45.4, user
ask "run horizontal for all the context"): the Matrix goes TWO-COLUMN past ~500px wide
(bars/pathways/focus | eco diagram/gauges), narrow stays single-column (mobile binding
holds). ☐ in-game verify the two-column wide layout + resize + session-focus behavior.

TAINT VECTOR PINNED + FIXED (v0.45.5): the hardened recorder captured the login block
with full context - func=SetPreferredGamepadInteractTarget, open=[char+fs], uptime
15852s. Cause: the stats panel + its FS/options buttons were CHILDREN of CharacterFrame
(inherited its secure context; our taint blocked a gamepad interact-target op). Fixed:
panel + buttons are now UIParent children ANCHORED to the char frame (shown/hidden via
hooks), never inside its tree. Compliance taint-law lint gained a PARENT rule (reds on
CreateFrame into an interactive Blizzard frame; proven red on the 3 pre-fix sites).
☐ in-game verify: character tab opens with zero taint block. (v0.45.5 loaded in-game
2026-10-13, character tab open, radar rendering, NO block popup - fix holding; awaiting
a clean full-session confirm.) RADAR HOVER-EXPAND (v0.45.6, user tuning ask): axis tips
hover to show the dimension's value + plan + description; per-axis rows collapse into
the chart (numbers stay in the Dimensions section). ☐ in-game verify the hover.


v0 engine SHIPPED (v0.10.0): group nodes by stat/spell/school/mechanic; tooltip "Synergy:" line +
/foresight synergy. ALL-SOURCES SHIPPED (v0.12.0): with player context (race/class/active buffs),
themes include the player's racials and active consumables alongside talents - typed members
(racial:<spellID>, buff:<itemId>) through one op-walker; trait-only without context.
TREE-HIGHLIGHT SHIPPED (v0.13.0): /foresight synergy <theme> glows member nodes (enumerator
probe -> name-match fallback; house pulse textures, taint-free; settings.synergy.theme saved,
auto-applies on talent-UI open; clear stops). Remaining: in-game render verify, talent-frame
dropdown, LibCustomGlow swap at packaging (doc C1). CHAINED SYNERGIES SHIPPED (v0.17.0):
stat-conversion ops (Mental Dexterity Int->AP) bridge a stat theme to the output it feeds;
synergy query returns a chains section. Plus CATALOG (v0.17.0): one normalized reference table
over every impact source (`/foresight catalog`), the query spine for synergy/search/validation.
Remaining: deeper multi-hop chains, catalog-backed planner/search UI.

## Backlog (not yet scheduled)
- ☐ DATA-freshness AUTO-SYNC completion (owner asked 2026-10-15 "do we auto-stay-in-sync
  with WoW updates or wait for crowdsourcing?"). The STRUCTURAL game data (talents/spells/
  items/trait trees) comes from the client DB2 via wago.tools (`fetch.py` -> `generate.py`) -
  deterministic, NOT crowdsourced. `.github/workflows/data-freshness.yml` scaffolds a daily
  fetch+generate+gate, BUT `fetch.py` hardcodes `DEFAULT_BUILD` (no latest-build detect) and
  the PR/issue steps are stubbed - so a new Forever build is NOT auto-picked-up today; a patch
  = manual `fetch.py --build <new>` + `generate.py` + gate + version bump. TO MAKE IT
  CONTINUOUS: (1) query wago.tools for the latest Forever build id, (2) fetch+generate+gate it,
  (3) auto-open a regen PR (or auto-ship after gate). Crowdsourcing is a SEPARATE layer - it
  only fills the gaps the raw data leaves (rank-scaling presumptions, buff magnitudes), it does
  not keep structural data in sync. (Verified-rule feed itself is continuous + version-free into
  Firestore via push_verified/bake, but captures reach disk only on /reload/logout and only
  TRAINED hovers decide a rule; those baked rules reach players on the next addon version.)
- ☐ Options GUI menu: one panel listing every /foresight setting (standing toggle,
  opacity, goal, focus) - groomed via S27; until then /foresight set is the lever.
- ☐ DATA-proc-families: pipeline decode of proc rates beyond critHaste (Nightfall /
  Omen of Clarity / Seal of Command / Hawk-family) extending sim_procs.lua - upgrades
  the S26 loop cards from honest gaps to expected values.
- ☐ UI skill picker for focus mode (user ask 2026-10-12, after the first live focus
  render): an in-UI way to enter skill-centric mode - click an ability on the Matrix /
  type-to-search among the CHARACTER'S known spells (IsPlayerSpell over gen.spells,
  resolved via the level-capped resolver) - instead of typing /foresight focus. Rides
  the existing focus plumbing (setFocus/applyAbility/focusModel) end to end; UI only.
  Candidate home: Matrix focused-skill block header -> search row (title-click
  precedent). Mobile binding applies. ALSO (user ask, same date): a one-click REPORT
  button on the panels riding the shipped /foresight report plumbing (v0.35.0).
- ☐ DATA-professions: SkillLine/recipes -> consumables/crafted gear as modifier sources.
- ☐ GRAPH-rotation-weights: fold cast-time/cost/cooldown mods into throughput via per-spell
  rotation weights (today they surface via tooltips only).
- ☐ Per-ability base threat + stance/form multipliers for GRAPH-threat (overrides, k-of-n).
- ◐ DATA-live-imbue-ap (user catch 2026-10-14, Rockbiter hover: WoW 75 AP vs our 58):
  weapon-imbue `linearToMax-presumed` AP rendered from the stored classic-presumed
  `maxValue`, stale/low vs the live level-scaled client value. DONE v0.46.10: the
  spell-tooltip "Its buff gives you: N Attack Power" line now reads the AP the client
  prints on the hovered tooltip (`ui/tooltips.lua` `liveAttackPower` -> `spellLines` live
  param), falling back to `maxValue` only when unreadable. REMAINING: the imbue
  DPS-per-swing compare (`imbueLines` / `Imbues.compare`) still uses `maxValue` - feed it
  the live AP too, or record an observed override. In-game verify.

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
