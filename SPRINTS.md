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
- **S7b UI-mapping-panel** (◐, model shipped v0.21.0): `model/mapping.lua` - bidirectional
  talent<->ability map (inverse "what modifies Fireball" + forward "what Improved Fireball
  touches") off shared affected-spell edges; `/foresight affects`; pure + selftest-covered.
  Remaining: the visual panel renderer (in-game).

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
scaling rule in generate.py, not a flat override).
REMAINING: regen/swing/DoT-tick/GCD measurement during play; equip-delta observation
(item stat ground truth).

### S12 - Publishing train ◐  (repo LIVE v0.23.1; CurseForge/Wago registration remains)
DONE: `.pkgmeta` + README + privacy ignores; CI workflows (gate / packager-on-tag /
data-freshness); PUBLIC GitHub remote `simulatecx/foresight-forever` (decision 2026-10-11:
public - the crowd-harvested `pipeline/collected/` corpus is gitignored and never
publishes, so "our data stays ours"); action refs SHA-pinned + dependabot; branch
protection (CI gate required on PRs, force-push/deletion blocked, owner direct-push kept
for the solo-dev flow). Remaining (user account actions): register CurseForge + Wago
project slugs, add `CF_API_TOKEN`/`WAGO_API_TOKEN` repo secrets, project IDs in the TOC
(or slug-resolve), then tag the first release. Threat-model publish bindings (DATAFLOW
4b/4c).

### S13 - Crowd scale-up ◐  (phase A shipped v0.15.0)
PHASE A DONE: item-sightings journal (equipped+bags at login/logout, IDs only, capped) +
harvest aggregation into `collected/item_sightings.json` with distinct-account counts (the
k-of-n seed) + consumable cross-check. The user's crowd-DB intent ("each logout updates what
items are actually in game") lands at every flush - locally, compliantly (addon never networks).
PHASE B remaining: opt-in companion uploader (reads SavedVariables, POSTs sanitized JSON) +
ingestion/aggregation backend; k-of-n confirmation before any overrides change; privacy-by-
design pass (consent, hashing, retention). Full design (Cloudflare Worker + D1/R2, k-of-n via
unique index, companion sanitize) in `docs/RESEARCH-2026-10-11.md` C2. GATED ON: S12 publish
decisions (users need CurseForge/Wago to exist) + the user's backend choice (Cloudflare vs
Firebase) + companion distribution.

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

### SYNERGY - impact sources that work together ◐
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
