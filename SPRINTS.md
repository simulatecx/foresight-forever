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
Firebase console setup (owner - Firestore/Anon-Auth/App-Check/Hosting/rules deploy, see
doc S6); pipeline bake-back `peer_baselines.lua` + in-game "vs your spec" readout.

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
