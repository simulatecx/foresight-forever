# Changelog

## 0.25.1 - 2026-10-12

Captured talent tooltips now VOTE (the user's in-game scans become rank-rule evidence).

- harvest.py `probe_from_tooltips`: parses the "Rank N/M" line off every captured
  tooltip (recovers ranks on INSPECTED players' trees, where the journal field can't),
  strips chrome (the rank line + beta "Press F6" footer would pollute number
  extraction), and feeds the real descriptions into the existing rank-rule voting.
  Gate-covered in analyze_selfcheck (rank parse + chrome strip + identical vote).
- First live run over the 141-node capture (own Shaman tree + inspected Orgrimmar
  players): trained votes A=2 B=4 none=5 (incl. an inspected mage's Improved Frostbolt
  r4); untrained-r1 A=50 B=32 either=10 none=45. VERDICT: Forever's rank rule is
  PER-TALENT - next step is a harvest-drafted per-talent rank-rule table.
- `mockups/foresight-matrix-2026-10-12.html`: the user's Matrix UI spec versioned into
  the repo; S7b carries the render binding + the honest fill-basis decision
  (within-group relative bars, basis labeled).

*Features:* QA-harvester, QA-probe, UI-mapping-panel

## 0.25.0 - 2026-10-12

SIM-ENGINE (S18): the simulation tier - the math behind the class, on your numbers.
Design record + PRD corrections: `docs/SIM-ENGINE-2026-10-12.md`.

- NEW `model/sim.lua` (pure, out-of-combat surfaces only):
  - melee cascade: crit -> Flurry uptime (steady-state 1-(1-c)^N) -> effective swing
    speed -> Windfury burst/EV -> first-order sustained DPS. `/foresight sim`.
  - time-to-OOM: chain-cast drain vs your pool with five-second-rule honesty
    (`/foresight oom <spell>`, plus a "Chain-cast: ~N casts, empty in ~Xs (p)" line on
    ability tooltips).
  - standings: plain-English build identity (Glass Cannon/Bruiser, Endurance,
    Primal Hybrid, Threat Anchor) - ratio-honest (stat-space, not cross-index); leads
    the panel subtitle; item tooltips flag "Shifts your build: X -> Y" on swaps that
    change it.
  - goal pathways: `/foresight path [dimension]` ranks your unspent trait steps by
    marginal impact on the dimension you're building toward.
- NEW `data/loops.lua`: curated Enabler -> Engine -> Payoff class loops (The Shatter
  Loop, The Windfury Engine, The Flurry Engine) with live computed lines
  (`/foresight loop`); every named member is selftest-gated against shipped data so
  renames can't rot it.
- PIPELINE decodes (never hand-copied): Windfury `extraAttacks` via tooltip-macro
  chase (20% on hit, 2 extra attacks, +46/119/249/333 AP by rank); Flurry-family
  `critHaste` via the $Nn macro -> trigger buff aura 319 (+10% x 3 swings, Shaman r1;
  per-rank scaling tagged unverified); weapon `speedMs` on all 4,621 gear items.
- Imbue compare now folds the Windfury expected value on YOUR weapon (slow weapon =
  bigger burst); gear hover shows the Windfury-engine AP-term delta for other speeds.
- Formula registry: weapon normalization constants (dagger 1.7 / 1H 2.4 / 2H 3.3 /
  ranged 2.8, classic-presumed) + flurry steady-state uptime (model-presumed).
- Snapshot captures main-hand weapon class (dagger/oneHand/twoHand) for normalization.
- Selftest 165 (+21). PRD claims the data refuted are recorded, not shipped (Instant
  Poison is flat 20% not PPM; Int doesn't bend coefficients; WF rides actual speed).

*Features:* SIM-engine, DATA-loops, IMBUE-compare, UI-item-tooltip, UI-spell-tooltip,
UI-playstyle-label, DATA-generated-tables, MODEL-snapshot, QA-selftest-harness

## 0.24.0 - 2026-10-11

OBSERVED-VS-GENERATED auto-compare (S11 phase B): real play now grades the datamined data.

- harvest.py compares every journaled buff observation against the generated ops and
  verdicts each stat field: OK confirmed / !! mismatch / ?? learned (percent and
  statConvert ops predict no flat number - never guessed; melee/ranged crit are
  at-least checks because stat ops add derived crit on top).
- Cross-account aggregation (newest harvest per account) -> `collected/
  observed_impacts.json` + a human-review draft `collected/overrides_draft.lua`
  (fully commented-out Lua - never loadable by accident) holding verifiedBuffs
  candidates and correction leads, with the k-of-n (>= 3 accounts) + human-review
  law stated in the file. Nothing is ever auto-applied.
- `overrides.lua` grows `verifiedBuffs` (consumable tooltip header upgrades grey
  "(p) presumed" to green "play-verified <build>") and `consumableImpacts` (a
  reviewed correction fully replaces the generated entry and relinks the live-aura
  index). Override application factored into `HM.overrides.apply()`.
- New ship-gate step: observed-compare selfcheck (verdict paths + draft render on
  real generated data). Selftest 144 (+2: verified-tag upgrade, correction round-trip).
- FIRST REAL RESULTS (pilot account): Oil of Olaf +50 armor play-CONFIRMED vs
  datamined; Goretusk Liver Pie FLAGGED - observed +1 Strength vs generated +3
  (n=2), suspected Forever level-scaled Well-Fed values; lead journaled in the draft.

*Features:* QA-probe, QA-harvester, DATA-overrides, CONSUME-buffs, QA-selftest-harness

## 0.23.1 - 2026-10-11

S12 publish train ACTIVATED: the repo is live at github.com/simulatecx/foresight-forever.

- GitHub remote created (PUBLIC - user decision 2026-10-11; code+datamined tables only,
  the crowd-harvested `pipeline/collected/` corpus stays local/gitignored, never published).
- All workflow action refs SHA-pinned (checkout/setup-python/BigWigsMods-packager);
  `.github/dependabot.yml` added so pins update by reviewed PR, never by hand.
- Branch protection on `main`: CI gate required on PRs, force-push/deletion blocked
  (owner direct-push allowed - solo-dev flow until community PRs arrive).
- TOC X-Website now points at the real repo URL.
- Remaining for full S12: CurseForge + Wago slug registration and API-token secrets
  (user account actions), then the first `vX.Y.Z` tag ships via the packager.

*Features:* QA-publish-train

## 0.23.0 - 2026-10-11

Gear verdict + gearing goal (borrowing Pawn's best UX, done honestly).

- HEADLINE VERDICT on item tooltips: a one-line at-a-glance answer at the top of the
  Foresight block - "Upgrade for Spellcasting (+4.1%)" / "Downgrade" / "Sidegrade" -
  so the detail no longer buries the answer. Unlike Pawn's one-directional stat weights,
  it uses the real diff: the NET swap vs your equipped item when comparable, or a marginal
  add otherwise (tagged "(added)"). `Impact.itemVerdict` (pure).
- GEARING GOAL: `/foresight goal <survival|tank|dps|caster|healing|...|auto>` picks the
  dimension the verdict judges against, per character - so a hardcore player gearing for
  survival sees survival verdicts, not raw DPS. Default "auto" follows the build's primary
  output. Validated on read (tampered goal -> auto). `HM.gearGoal()`.
- Selftest 142 (+6: verdict upgrade/goal-flip/vs-equipped net, headline placement, goal
  validation).

*Features:* UI-item-tooltip, MODEL-impact-diff, CORE-saveddb, QA-selftest-harness

## 0.22.0 - 2026-10-11

- FIX (talents-affecting block not showing): the ability-map tooltip now resolves by the
  spell's NAME, not its id - the game hands us a rank/variant id that isn't our shipped
  one, so the id lookup silently failed. Name resolution always matches our name-keyed
  map (Lightning Bolt has 440 modifier edges in the data); sources deduped by talent name.
- CurseForge readiness: `LICENSE` (MIT), TOC `X-License`/`X-Website`, and
  `docs/CURSEFORGE.md` - the listing copy, the 3-product lineup (Foresight / Foresight:
  Assist / Foresight: Panic), a logo prompt, and the deploy checklist.
- Selftest 137 (+1 name-resolution).

*Features:* UI-mapping-panel, UI-spell-tooltip, QA-publish-train

## 0.21.1 - 2026-10-11

- Impact map on the ability tooltip: hovering a spell now shows "talents affecting this"
  - the inverse map (Improved Fireball -0.5s cast, Fire Power +10% damage...) right where
  you decide what to press. Appends to the existing spell-power/imbue block, or stands
  alone. Pure line builder; selftest 136 (+1).

*Features:* UI-mapping-panel, UI-spell-tooltip, QA-selftest-harness

## 0.21.0 - 2026-10-11

IMPACT MAP (S7b) - the Talent Impact Map's bidirectional core.

- New `model/mapping.lua`: the talent<->ability index, both directions off the same
  affected-spell edges. INVERSE - "what modifies this ability" (`/foresight affects
  Fireball` -> every talent/trait that changes it, with the magnitude). FORWARD - "what
  does this talent touch" (name a talent -> the abilities it changes). One data source,
  so the two views can never disagree.
- `/foresight affects <ability|talent>` surfaces it; `Mapping.describeOp` humanizes each
  modifier (-0.5s cast time, +15% damage...).
- Pure + selftest-covered (135 checks, +4): inverse find, forward find, humanized op,
  honest nil for unknown abilities.

*Features:* UI-mapping-panel, SYNERGY-engine, CATALOG, QA-selftest-harness

## 0.20.0 - 2026-10-11

Provenance stamp + publish-train (S12) scaffolding.

- Every generated fact now carries its source: `HM.provenance()` = "Forever-verified -
  <channel> <build>" (e.g. "beta 1.60.1.70338"), built from a new `channel` stamp in
  the generated build metadata. Gear tooltips (for items in our client-decoded catalog),
  `/foresight items`, and `/foresight catalog` show it - so the player knows the data is
  real Forever client content at a known patch, not a datamined guess. Flip the channel
  to "live" at launch (`generate.py --channel live`).
- CI scaffolding (`.github/workflows/`): `ci.yml` runs the full ship gate on push/PR;
  `release.yml` packages + uploads to CurseForge/Wago/GitHub Releases on a version tag
  (BigWigsMods/packager, gate-first); `data-freshness.yml` daily-polls wago.tools and
  regenerates+gates when Forever ships a new build. All inert until the repo has a remote
  + secrets; action refs flagged for SHA-pinning before public use.
- TALENT VERIFICATION CAPTURE: hovering a talent now journals the REAL rendered node
  tooltip text + the node's current rank (`collect.talentTooltips`), via the working
  owner-name hook - the classic SetTalent probe is dead on Forever, so mousing over
  talents previously captured nothing for rank-scaling. Now "mouse over all talents"
  gathers authoritative per-node text; the harvest surfaces it to settle the (p) rank
  rules against the generated ops.
- Selftest 131 checks (+1 provenance).

*Features:* DATA-generated-tables, DATA-items, QA-publish-train, QA-collector, CORE-bootstrap

## 0.19.2 - 2026-10-11

- Gear seed trimmed to Uncommon+ quality (your call) - statted gear only existed at
  Uncommon+ anyway, so 4,663 -> 4,621 (~594KB).
- FIX (observatory pollution, caught in the first live harvest): an elixir was recorded
  with +22 Agility / +225 armor / +all-stats - a coincidental gear swap mis-attributed
  to one buff. The observatory now CLAIM-FILTERS each observation to the stats the buff
  is actually known to move (from its generated ops), so a gear change or second buff in
  the same window can no longer pollute the ground truth. We confirm what the buff
  claims, nothing else. Unknown buffs (no ops) still record raw, to be learned.

*Features:* DATA-items, QA-collector, QA-selftest-harness

## 0.19.0 - 2026-10-11

GEAR SEED + secondary-stat vocabulary - the in-client item database, no scraping.

- `data/generated/items.lua`: 4,663 equippable items with stat mods, decoded straight
  from the client's own ItemSparse (the SAME source ForeverDB/Wowhead datamine from) -
  name, slot, item level, required level, quality, and WHICH stats each carries. Exact
  stat AMOUNTS are intentionally omitted: they ride the item-budget system, and live
  GetItemStats already computes them precisely for any item the player touches. So the
  catalog answers "what exists / what has Dodge / what's my next upgrade", the live read
  answers "exactly how much" - neither guesses. (~600KB; trimmable by quality/level if
  bloat matters at publish.)
- Secondary stats are now first-class: the ITEM_MOD legend maps Dodge, Parry, Defense,
  Block, Hit/Crit/Haste/Mastery/Expertise/Resilience ratings, Attack/Spell Power, Mana
  Regen, Armor/Spell Penetration into the stat vocabulary; the lever taxonomy accepts
  ANY stat name, so gear and talents touching the same secondary stat synergize like
  primaries do.
- `/foresight items <stat>` browses the seed ("Dodge", "Attack Power", "Intellect"),
  sorted by required level so the nearest upgrades surface first. `/foresight catalog`
  now counts gear too.
- Note: items stay OUT of the talent/build synergy index (which remains focused on
  build-defining talents/racials/buffs); gear is browsable + stat-filterable instead.
- Selftest 129 checks (+3: gear scale, stat search + sort, secondary-stat axis).

*Features:* DATA-items, CATALOG, LEVER-taxonomy, DATA-pipeline-generate, QA-selftest-harness

## 0.18.0 - 2026-10-11

LEVER TAXONOMY - makes the synergy/relationship graph principled and growth-proof.

- New `model/levers.lua`: the ONE declarative map from an impact op to the canonical
  levers it pushes (axis + key). Attack Power, Spell Power, Healing, crit, defense,
  resource and tempo are DISTINCT keys - "attacks" never blur into "spells". statConvert
  yields two levers (its source stat + the output it feeds - the chained-synergy bridge);
  spellmod routes affected spells to the ability axis (so "what touches this skill" and
  "skills this talent touches" are the same edge, both directions free).
- `model/synergy.lua` now groups ENTIRELY off the taxonomy (the hand-written per-op-kind
  chain is gone) - one source of truth shared by synergy, and available to the catalog
  and tooltips.
- COMPLETENESS GATE (selftest): every op kind present in the shipped data must be
  classified by the taxonomy or declared label-only - otherwise the ship gate reds. New
  pipeline content can no longer silently drop out of synergies; it either classifies
  cleanly or blocks the release. This is the "grows without breaking for users" guarantee.
- Selftest 126 checks (+5: completeness gate, AP-vs-SP distinct keys, the statConvert
  bridge, ability-axis routing, unknown-kind flagged).

*Features:* SYNERGY-engine, CATALOG, QA-selftest-harness, DATA-pipeline-generate

## 0.17.0 - 2026-10-11

CONTENT CATALOG + CHAINED SYNERGIES + crit tooltips - the "all content in one table,
with real relationships" build.

- CATALOG (`model/catalog.lua`): one normalized table over every impact source -
  talents, trait nodes, racials, consumables (by potion/elixir/flask/food/scroll),
  weapon imbues - with a uniform entry shape. `/foresight catalog` prints the reference
  table (counts + how many carry decoded impact + how many need curation);
  `/foresight catalog <name>` searches across all kinds. Adding a source to the pipeline
  makes it appear here (and in synergy/search) for free - clean as new content lands.
- CHAINED SYNERGIES: new stat-conversion decode (aura 598 Attack Power, 175 Spell
  Power, 174 Healing - each "= N% of a primary stat"; ground-truthed on Mental
  Dexterity Int->AP 100% and Mental Quickness Int->spell power). The synergy engine now
  bridges: querying "Attack Power" lists the converters (Mental Dexterity) AND the
  direct sources (Flurry, Elemental Weapons, Rockbiter); querying "Intellect" shows it
  feeds Attack Power via Mental Dexterity - the Diablo-style "what connects to what".
  `/foresight synergy <theme>` prints a "chains (stat -> output)" section. The model
  folds a conversion as a flat amount off your live source stat (take Mental Dexterity
  -> "+150 Attack Power from your Intellect").
- Thundering Strikes & crit talents: the trait tooltip now renders the crit op's value
  ("+1% crit chance"), the for-you DPS chain, AND your CURRENT crit ("Your crit now:
  23.4% melee, 18.1% spell") so the number reads against a real baseline.
- Selftest 121 checks (+5: catalog unify/search/op-kinds, Int->AP decode, synergy chain
  shape).

*Features:* SYNERGY-engine, CATALOG, UI-talent-tooltip, MODEL-loadout-whatif, DATA-pipeline-generate, QA-selftest-harness

## 0.16.0 - 2026-10-11

MAX-HEALTH FIX (user report: sheet says 267, panel said 340) + the IMPACT OBSERVATORY
(S11 phase A) - gameplay now verifies the datamined model automatically.

- FIX: pool maxima (max health/mana) now read the LIVE character sheet - the classic
  10 hp/stamina and 15 mana/int rules hold only above the ~20 base points, so deriving
  pools from them overstated low-level characters (34 stamina -> 340 vs real 267).
  What-if deltas still convert at the per-point rules, marginal-only - the same law
  the AP/crit nodes already follow. Regression selftest pins the exact 267 case.
- IMPACT OBSERVATORY: when exactly ONE known consumable buff appears or fades (and
  gear didn't change / no level-up in the window), the live stat sheet is diffed
  around the event and the OBSERVED impact is journaled per buff spellId
  (`collect.observedImpacts`, capped, gain-shaped). Conservative attribution: any
  simultaneous change discards the sample. The harvester prints each observation
  resolved to its consumable name - the ground truth that upgrades/corrects (p) ops.
- Selftest 116 checks (+3: the 267 regression, statDiff field selection,
  single-change attribution incl. fade sign).

*Features:* MODEL-snapshot, MODEL-loadout-whatif, QA-collector, QA-harvester, QA-selftest-harness

## 0.15.0 - 2026-10-11

ITEM-SIGHTINGS JOURNAL - crowd-DB phase A (S13): each login AND logout, the addon
journals which item IDs this character actually encountered (equipped + bags; IDs and
a seen-counter only - no quantities, no bank, no money). The logout scan is the last
write before the SavedVariables flush, so every logout updates the local record of
"what items are actually in game"; the harvester merges archives into
`collected/item_sightings.json` with a distinct-ACCOUNT count per item - the k-of-n
seed for the future backend - and cross-checks generated consumables ("sighted =
confirmed live-obtainable"). The addon still never networks: the companion app
(S13 phase B) is what will upload sanitized JSON for multi-user validation.

- `Collect.scanItems()` (read-only container/inventory APIs, both C_Container and
  classic shapes, capped 400 ids/account, self-heals a tampered journal); PLAYER_LOGOUT
  wired; verify gains an "item sightings journaled" line.
- harvest.py: per-account sightings count + `aggregate_sightings` (newest archive per
  account wins; consumable cross-check).
- Selftest 113 checks (+1 headless degrade + self-heal).

*Features:* QA-collector, QA-harvester, QA-verify-command, QA-selftest-harness

## 0.14.0 - 2026-10-11

WEAPON-IMBUE SIMULATION (S17, the user's live Rockbiter-vs-Flametongue question):
every temp weapon enchant becomes per-swing and per-second numbers on YOUR weapon.

- Pipeline: fetch `SpellItemEnchantment`; generate `weapon_imbues.lua` (377 entries:
  shaman imbues, rogue poisons, sharpening stones, oils - via class/poison-line spells
  AND ClassID-0 item on-use spells, since poisons are items subclass 8 here). Decodes:
  type-3 equip spells through build_ops (Rockbiter +AP & threat aura), type-1 procs
  (flat school damage + chance from EffectPointsMin), type-2 flat weapon damage
  (sharpening stones). Flametongue's basis rides the tooltip macro - /77 and /25 are
  the 1.3s/4.0s weapon-speed extremes, so per-hit = basis x speed / 100 (r1 basis 326
  = the in-game "3-13"); parsed for both macro syntaxes.
- New pure `model/imbues.lua`: Imbues.compare(snapshot, ids) -> per-swing/per-second
  rows on the live weapon speed (14 AP = 1 DPS, one law with the chain explainer),
  expected value for known proc rates (Instant Poison 20% x 15), honest "proc rate
  not in the data (unverified)" for unknown ones (Frostbrand), rank dedupe keeps the
  strongest known rank. Imbues.known() filters by IsPlayerSpell (read-only).
- Surfaces: `/foresight imbue` compares every known imbue on your weapon and names
  the best-DPS and biggest-swing choice; hovering an imbue spell/poison item's APPLY
  spell injects "On your 3.6s weapon: ~+11.7 damage per swing (+3.26 DPS)" + notes
  ("slower weapon = bigger hits, same DPS" / "extra threat, tank-friendly").
- Snapshot captures the main-hand damage range (UnitDamage, guarded) as the baseline
  for future proc expected-values (Windfury extra-attack EV needs it).
- Selftest 112 checks (+6: chain decodes, speed scaling vs constant DPS, the 2H-axe
  verdict incl. threat note, rank dedupe, honest proc rates, tooltip block).

*Features:* IMBUE-compare, DATA-pipeline-fetch, DATA-pipeline-generate, DATA-generated-tables, MODEL-snapshot, UI-spell-tooltip, QA-selftest-harness

## 0.13.1 - 2026-10-11

Field-report fixes (pilot hover session) + the in-game verify/write-back loop for
consumable data.

- FIX (fish +6): Forever's reworked foods park UNIT values on shared Well-Fed spells
  and carry the real magnitude on the aura-227 trigger effect - Slitherskin Mackerel
  showed "+1 Attack Power" instead of +6. generate.py now scales hop ops by the trigger
  bp when > 1 (Mackerel x6, Mud Snapper x10, Mithril Head Trout x20, Mightfish x40);
  the classic pattern (magnitude on the triggered spell, Dirge's Chops +25) unchanged.
- FIX (version drift, incident-to-gate): `HM.version` sat at 0.10.0 for three releases,
  so session journals mislabeled the running build and the harvester's staleness
  warning fired wrongly. run_tests.py now REDS when Foresight.toc and core/init.lua
  versions differ (permanent gate).
- Stale-file-list detection: a client started before a deploy that ADDS .toc files
  never loads them on /reload (full restart required). Login + verify now run
  `HM.staleCodeCheck()` (expected modules present + TOC metadata vs code version) and
  print a loud restart warning when it trips.
- In-game verify additions (/foresight verify, auto-collected every login):
  "running code matches the loaded file list", "all-sources data loaded"
  (consumables/racials/trait counts), "live buff read available"
  (C_UnitAuras.GetPlayerAuraBySpellID), "active known buffs captured".
- WRITE-BACK LOOP: every consumable hover journals to SavedVariables - injections into
  `collect.buffTipLog` (last 15), ClassID-0 items with NO data into
  `collect.missedConsumables` (capped 100, with name/subclass/count). harvest.py
  surfaces both, so "this elixir shows nothing" becomes a named pipeline gap on the
  next harvest. The addon never edits its own data in-game - gaps close through the
  pipeline/overrides (account-safety doctrine).
- Selftest 106 checks (+1 Mackerel/Trout magnitude law).

*Features:* CONSUME-buffs, QA-verify-command, QA-harvester, QA-selftest-harness, CORE-bootstrap

## 0.13.0 - 2026-10-12

SYNERGY TREE-HIGHLIGHT + the FUTURE-BUILD PLANNER (the PoE-style "what if I got those
pants" workbench), plus fully dynamic panel scores.

- SYNERGY-highlight: `/foresight synergy <theme>` now also lights up every talent node
  in that theme on the talent tree (Diablo-paragon selection) and saves the theme per
  character - the tree glows whenever you open it; `/foresight synergy clear` stops it.
  New `ui/synergy_highlight.lua`: pure selector (theme -> trait node ids/names; racial/
  buff members excluded - no buttons) + locator (official enumerator PROBED first,
  bounded name-match scan fallback - node button frame name = talent name, the proven
  owner-name signal) + house glow (own pulsing border/fill textures parented to the
  buttons; no Blizzard glow reuse, no taint; LibCustomGlow can slot in at packaging).
- WHATIF-planner (triaged S16): compose a persistent future build - `/foresight plan
  add stat Agility 5`, `add item Pants Agility=5,Stamina=3`, `add buff mongoose`,
  `add talent ancestral knowledge 5`, `remove <n>`, `clear` - and the plan + its net
  dimension impact render in a new stats-panel "Future build" section and in
  `/foresight plan`. New pure `model/plan.lua`: typed deltas validated against the
  generated data on EVERY read (untrusted-input law - tampered SavedVariables heal to
  the valid subset), composed through the ONE loadout delta stack (no new math);
  `Impact.chainLines` exposes the derived-stat chain between any two loadouts.
- Panel scores are now fully live: refresh on talent changes (TRAIT_CONFIG_UPDATED /
  PLAYER_TALENT_UPDATE / CHARACTER_POINTS_CHANGED) and buff changes (UNIT_AURA) in
  addition to gear/stats - debounced to one rebuild per 0.2s; event names pcall-
  registered so client drift degrades silently.
- Selftest 105 checks (+6 planner, +2 highlight selector; panel section count now 6).

*Features:* SYNERGY-highlight, WHATIF-planner, SYNERGY-engine, UI-stats-panel, MODEL-loadout-whatif, QA-selftest-harness

## 0.12.0 - 2026-10-11

CONSUMABLE BUFFS + ALL-SOURCES SYNERGY (phases 2+3 of the expansion): hover a flask/
elixir/food/scroll and see what it's worth for YOUR character while active - and what
you lose when it expires; synergy themes now draw from talents + racials + active buffs.

- Pipeline: fetch `Item`/`ItemSparse`/`ItemEffect`/`ItemXItemEffect`/`SpellAuraOptions`/
  `SpellEquippedItems`; generate `consumables.lua` (390 items: potion/elixir/flask/
  scroll/food) via Item(ClassID 0) -> ItemXItemEffect -> ItemEffect(on-use) -> buff
  spell -> the shared build_ops. Foods chase `EffectTriggerSpell` ONE hop and key the
  TRIGGERED Well-Fed spell (the aura the player actually carries). durationMs/maxStacks/
  reqLevel + `buffsBySpell` index. Validated: Mongoose 13452 -> 17538 (+25 Agi, +2%
  crit, 30m); Supreme Power +150 all-magic; Titans +1200 health; Dirge's Chops -> +25 Stam.
- New foldable ops (ground-truthed): aura 290 crit% folds into all three crit stats,
  with the SpellEquippedItems discriminator (weapon-conditional racial 290s stay
  label-only - resolves the phase-1 deferral); aura 34 flat max health (Flask of the
  Titans); aura 22 armor (Scrolls of Protection; magic resistances label-only);
  aura 99/124 flat attack power (Well Fed).
- Model: `Loadout:withBuff(itemId or buff spellId)` + `Impact.buffDelta` (one diff =
  while-active gains; sign-flipped = the expiry loss). `Snapshot.captureActiveBuffs()`
  probes the generated index via `C_UnitAuras.GetPlayerAuraBySpellID` - spellId is
  NeverSecret; new `Guards.aurasSecret` (C_Secrets.ShouldAurasBeSecret) degrades buff
  features to display-only in restricted contexts.
- UI: consumable item tooltips inject "While active: ... (30m)" + the derived chain +
  "On expiry these gains reverse." (the hardcore warning). New `/foresight buffs`
  lists active known buffs with time left and what each is worth.
- SYNERGY from all sources: `Synergy.build/query/themes` accept player context
  (raceId/class/active buffs) - `/foresight synergy intellect` lists racials and
  flasks alongside talents (typed members `racial:<spellID>`/`buff:<itemId>`, one
  shared op-walker). Without context the index stays trait-only, so tooltip synergy
  counts are unchanged.
- Selftest 97 checks (+14: chain decode cases, exact crit/health folds, spellId-keyed
  withBuff, the 290 discriminator, tooltip block, headless degrade, synergy ingestion
  + class gating + static-view isolation).

*Features:* CONSUME-buffs, RACIAL-impact, SYNERGY-engine, DATA-pipeline-fetch, DATA-pipeline-generate, DATA-generated-tables, MODEL-snapshot, MODEL-loadout-whatif, CORE-guards, UI-item-tooltip, QA-selftest-harness

## 0.11.0 - 2026-10-11

RACIAL IMPACT (phase 1 of the all-sources expansion): the pipeline now generates every
race's racials, and the model answers racial what-ifs through the same ops engine.

- Pipeline: fetch `ChrRaces` + `SkillRaceClassInfo`; generate.py decodes the racial
  skill lines into `data/generated/race_racials.lua` - 10 races (the classic 8 + both
  Skyborne variants), 45 racial spells with build_ops impact ops, per-spell class gates,
  passive/active split (SPELL_ATTR0_PASSIVE), and confidence tags (`classic-presumed`
  vs `forever-new-unverified` for the 1.25M+ rework ids), plus `racialsBySpell` and
  `raceTokens` (Scourge=5) indexes.
- Decode discovery: the RaceMasks bit index is `ChrRaces.PlayableRaceBit` (verified
  Human=0..Troll=7 in _0; Skyborne 95/96 = bits 32/33 -> _1 bits 0/1), so the planned
  Skyborne hardcode was unnecessary - the decode is fully data-driven.
- New ops (tooltip-ground-truthed): aura 133 max-health% (Tauren Endurance) and aura
  178 max-power% (Expansive Mind rework; misc0 = power type) fold via applyOps into
  stat.maxHealth / stat.maxMana; label-only decodes for dodge/hit/AP%/SP%/crit%
  (49/54/55/166/167/317/290) surface without folding - 290 is weapon-conditional on
  racials (fold decision deferred to the consumables phase).
- Model: snapshot captures `raceId`/`raceToken` (guarded UnitRace, token fallback);
  new `model/racials.lua` (class-mask gating, bySpell/forRace access);
  `Loadout:withRacial` + `withRace` what-ifs reuse applyOps - no forked math.
- PLAN CORRECTION (recorded in docs/RESEARCH-2026-10-11.md): racial passives are NOT
  folded unconditionally into the base build. Live snapshot stats already include them
  (UnitStat/UnitHealthMax/GetDodgeChance...), so a permanent fold would double-count.
  They model as what-if deltas and surface via synergy/panel in phase 3.
- Selftest 83 checks (+9): race coverage incl. both Skyborne, Scourge token, Human
  Spirit/Endurance/Expansive Mind decodes, class gating (Mage gets mana - not the
  rage/energy variants), confidence tags, active exclusion, tankability/maxMana folds.

*Features:* RACIAL-impact, DATA-pipeline-fetch, DATA-pipeline-generate, DATA-generated-tables, MODEL-snapshot, MODEL-loadout-whatif, QA-selftest-harness

## 0.10.0 - 2026-10-11

Talent tooltips CONFIRMED working in-game (the owner-name hook landed). New feature:
SYNERGIES - which talents work together.

- New `model/synergy.lua`: groups every trait node by the lever it pushes - stat
  (Intellect, Strength...), affected spell (Lightning Bolt...), school (Nature...), or
  mechanic (crit, threat, cost, cast time, cooldown) - from the generated trait data.
- Talent tooltips gain a "Synergy:" line (the top shared levers + how many other talents
  feed them). `/foresight synergy <name>` lists every talent on a theme
  (e.g. "intellect", "crit", "lightning"); no-arg lists the themes.
- Pure + selftest-covered (74 checks). Next: bake synergies into a persistent UI view
  (talent-tree highlight, feasible now that node buttons are named by talent) and extend
  the impact engine to buffs/consumables and racials.

*Features:* SYNERGY-engine, UI-talent-tooltip, CORE-bootstrap, QA-selftest-harness

## 0.9.5 - 2026-10-11

Talent tooltip - SOLVED via the owner-name signal. The diagnostic showed neither
SetTraitEntry nor GetTraitEntry fires on hover, but the tooltip's owner frame is named
exactly the talent ("Ancestral Knowledge"). So match the owner name to our trait node.

- The trait-tooltip hook now matches `GameTooltip` owner's frame name against our trait
  node names (`traitNameIndex`) and injects the impact block on the next frame once the
  base node tooltip is built. No dependency on SetTraitEntry/GetTraitEntry (kept as
  fallbacks). Works for every node - classic and new Forever - since names come from the
  generated trait data.
- Diagnostic now records `source="ownerName"` so the harvest confirms the path + inject.

*Features:* UI-talent-tooltip, QA-verify-command

## 0.9.4 - 2026-10-11

Safety-net diagnostic so the next harvest completes the talent tooltip regardless of
outcome: hook `GameTooltip:SetOwner` to record the frame each tooltip anchors to. If the
`GetTraitEntry` hook fired, the talent block renders; if not, the last-hovered talent
node's frame name (`lastTooltipOwner`) tells us exactly which button frame to hook
`OnEnter` on next. Harvester prints it.

*Features:* UI-talent-tooltip, QA-verify-command

## 0.9.3 - 2026-10-11

Talent-tree tooltip hook, take two - the harvest proved SetTraitEntry is NEVER called on
Forever's trait UI, so hook the actual data getter instead.

- The `traitTipProbe` diagnostic came back ABSENT: `GameTooltip:SetTraitEntry` is not how
  Forever builds node tooltips. But `C_TooltipInfo.GetTraitEntry` (the 10.0.2 tooltip-data
  API) IS present - that's the getter the trait UI calls on hover.
- Now hook `C_TooltipInfo.GetTraitEntry(configID, entryID)` via hooksecurefunc, then inject
  on the next frame (once the base tooltip is populated) into GameTooltip. Resolution tries
  (cfg,entry) and (activeConfig,firstArg) so arg-order surprises still resolve. SetTraitEntry
  stays as a fallback. The diagnostic now records which hook fired + the raw args.
- Research: confirmed against forever-addon-kit + the cjber/tweaks-forever Forever addon and
  the retail trait-tooltip pattern (TooltipDataProcessor / C_TooltipInfo, 10.0.2).

*Features:* UI-talent-tooltip, QA-verify-command

## 0.9.2 - 2026-10-11

Impact depth + accuracy overhaul - the "+1 Agility shows 0.00%" complaint. Now the
answer is the CHAIN and the SKILLS, and it's right at your level.

- ACCURACY: crit-per-point is now DERIVED from your live crit and stat (critPct / stat),
  which auto-scales to your level and gear. The old fixed level-60 constant badly
  understated crit from Agility while leveling (hence the ~0% readings). Falls back to
  the classic constant only when live crit is unavailable.
- DEPTH: new `Impact.statImpactDetail` / `derivedChainLines` show the chain step by step:
  "+2 Attack Power -> ~+0.5 damage per main-hand swing (3.2s weapon)", "+0.21% melee crit
  (your swings + special attacks)", "+N max mana", then the net dimension deltas.
  `/foresight stat <name> <amount>` now prints this.
- TALENTS now show an impact block for EVERY node, not just classic-overlap ones.
  `Tooltips.nodeImpactLines` (via the generated trait data) lists the affected spells,
  each op's effect at max rank, AND the derived "what this does for you now" chain
  (e.g. Ancestral Knowledge's +Intellect% -> your spell crit + max mana). The
  SetTraitEntry hook now resolves spell -> node -> this block, and records a diagnostic
  (`traitTipProbe`) so a harvest confirms it fires + what it resolved.
- ITEM tooltips now show the concrete derived gains too (`Impact.itemDerivedLines`):
  "+1 Agility -> +X% melee crit" instead of only a tiny dimension %.
- Selftest grows to 72 (stat chain AP/per-swing + crit, trait node impact block).

*Features:* MODEL-impact-diff, MODEL-loadout-whatif, UI-talent-tooltip, UI-item-tooltip,
DATA-formula-registry, QA-verify-command, QA-selftest-harness

## 0.9.1 - 2026-10-11

Three live-render bugs fixed from the first real in-game screenshots (level-10 Shaman).

- TALENT TOOLTIPS now hook the right method. The harvest proved `GameTooltip.SetTraitEntry`
  exists but `Enum.TooltipDataType.TraitEntry` does NOT, so the data-processor hook never
  installed. Now we hook `SetTraitEntry` directly (like SetTalent): entry -> definition
  spell -> talent -> block. (Classic-overlap talents show; purely new Forever nodes - e.g.
  the pilot's cooking traits - have no combat impact block yet.)
- ITEM TOOLTIP "flash then vanish" fixed. Items load async and rebuild the tooltip; the
  old per-item guard then refused to re-inject, so our block showed once and was wiped.
  Now a single `foresightInjected` flag is cleared on `OnTooltipCleared` (fires on every
  rebuild) and set before attach (so attach's Show() can't recurse) - re-injects cleanly
  on each rebuild, for item/spell/trait alike.
- WHAT-IF / wide panel rows no longer overlap: wide rows anchor their text to the top,
  wrap, and the row is sized to the wrapped height instead of a fixed 15px.
- `/foresight verify` reports the SetTraitEntry hook status.

*Features:* UI-talent-tooltip, UI-item-tooltip, UI-spell-tooltip, UI-stats-panel

## 0.9.0 - 2026-10-11

Gear compare (DATA-items v0): the item tooltip now tells you whether a drop is an upgrade
for *your* character, dimension by dimension.

- `Impact.compareItems(loadout, statsA, statsB)` nets two items' per-dimension impact,
  built on the existing explainItemDelta diff path (no forked value math).
- The item tooltip gains a "vs equipped [slot]" line: it reads the item currently in the
  slot this one would occupy (live GetItemStats) and shows the net dimension swing of
  equipping it ("+3.0% Spellcasting, -2.0% Tankability"). Degrade-safe; nothing shown
  when the slot is empty or the item isn't comparable gear.
- SCOPE: the offline ItemSparse database is deliberately NOT shipped - it would add
  megabytes of addon bloat, and live GetItemStats already covers every item in hand (the
  leveling use case). A curated/filtered item DB can follow if out-of-hand lookup is wanted.
- Selftest grows to 69 (compare nets Int-item vs Stamina-item to the right dimensions;
  the vs-equipped block renders).

*Features:* DATA-items, UI-item-tooltip, MODEL-impact-diff, QA-selftest-harness

## 0.8.3 - 2026-10-11

DATA-traits Phase 2: Forever's trait talents now move the what-if model, not just show
their name. Closes the "recognized but doesn't model" gap.

- `Loadout:withTraitNode(nodeId, rank)` folds a trait node's impact ops into the graph,
  so modelling any Forever node (including new ones with no classic talent) shifts the
  dimension scores - the same what-if path as classic talents.
- The op-folding logic is now one shared `applyOps()` used by both the classic-talent and
  trait paths (no second math path); `addTalentModifiers` / `addTraitModifiers` wrap it.
- Captured talents now carry `nodeId` alongside `talentId` for future "model my current
  build" use.
- Selftest grows to 67 (modelling trait node 104756, an Intellect% node, raises a
  caster's spellcasting). DATA-traits is now ☑ (data + coverage + modelling).

*Features:* DATA-traits, MODEL-loadout-whatif, MODEL-snapshot, QA-selftest-harness

## 0.8.2 - 2026-10-11

S2 talent tooltips on Forever's trait UI. SetTalent renders nothing there (confirmed by
the probe), so Foresight now hooks the trait-entry tooltip instead.

- New TraitEntry-tooltip hook: TooltipDataProcessor.AddTooltipPostCall for
  Enum.TooltipDataType.TraitEntry -> resolve the hovered entry -> its definition spell
  -> our classic talent -> the same "Affects / next point / for-you-now" talentLines
  block. Degrade-safe; activates only when the TraitEntry type is exposed.
- `TalentAPI.talentForSpell(spellID)` exposes the classic spell->talent bridge for it.
- Discovery now probes the trait-tooltip surfaces (Enum.TooltipDataType.TraitEntry,
  GameTooltip.SetTraitEntry, C_TooltipInfo.GetTraitEntry, ClassTalentFrame,
  PlayerSpellsFrame); `/foresight verify` shows the classic vs trait S2 hook status.
- Best-effort pending live confirmation: if the TraitEntry type isn't exposed, the next
  harvest names the real hook. New Forever nodes without a classic talent fall through
  for now (the spell-tooltip hook may already cover them on hover).
- Selftest grows to 66 (talentForSpell resolves 11069 -> Improved Fireball).

*Features:* UI-talent-tooltip, CORE-talent-api, QA-verify-command, QA-selftest-harness

## 0.8.1 - 2026-10-11

The Foresight panel is now movable - it defaults to docking beside the character sheet,
which can sit on top of other panels.

- Drag the panel anywhere; the position is saved per character and restored on login.
  `/foresight panel reset` re-docks it beside the character frame (and `/foresight panel`
  toggles it).
- The saved position is validated (`PanelModel.normalizePanelPos`) - a malformed or
  out-of-range value (tampered SavedVariables) falls back to the default instead of
  flinging the panel off-screen or erroring the renderer (untrusted-input law).
- Selftest grows to 65 (position validation: good value kept, junk/off-screen/bad-anchor
  rejected or clamped).

*Features:* UI-stats-panel, CORE-bootstrap, QA-selftest-harness

## 0.8.0 - 2026-10-11

`DATA-traits`: full talent coverage. Foresight now has data for EVERY Forever trait node,
not just the ones that overlap the classic trees.

- Pipeline: `fetch.py` pulls the Retail Trait DB2 (TraitNode, TraitNodeEntry,
  TraitNodeXTraitNodeEntry, TraitDefinition, SkillLineXTraitTree). `generate.py` walks
  TraitNode -> entry -> definition -> SpellID (the same SpellID the live C_Traits walk
  returns) and emits `traits.lua`: 555 nodes keyed by nodeID (spellID, name, maxRank,
  impact ops) + a bySpell index + tree->class skill-line map.
- Impact ops for trait nodes come from the definition spell's SpellEffect rows via the
  SAME `build_ops()` now shared with the classic-talent path (extracted, no behavior
  change - talent_impacts.lua is byte-identical).
- The C_Traits adapter resolves EVERY selected node by nodeID (name/maxRank), so capture
  is no longer limited to classic-overlap nodes. `/foresight verify` now reports
  resolved vs classic-mapped counts.
- Selftest grows to 64 (trait load + node coverage, the 16178->"Purification" bridge,
  ops present, 50+ non-classic nodes covered).
- Phase 2 (noted): feed new-node ops into the what-if model/dimensions; classic-mapped
  nodes already model via talentImpacts.

*Features:* DATA-traits, DATA-pipeline-fetch, DATA-pipeline-generate, DATA-generated-tables,
CORE-talent-api, QA-verify-command, QA-selftest-harness

## 0.7.2 - 2026-10-11

The C_Traits repoint is CONFIRMED LIVE, and the harvest exposed the next gap.

- Live confirmation (Shaman, after a clean logout/login flush): the C_Traits walk works -
  config 13926795, tree 1082, 77 nodes, 7 selected, adapter `mode=traits`. The
  spellID->talent bridge is proven: 38/77 nodes map to our generated talents. All three
  tooltip hooks install and their live APIs are confirmed present (TooltipDataType
  Item/Spell, C_Item.GetItemStats, GameTooltip.GetItem). SetTalent renders 0 lines, so
  S2 talent-tooltip injection still needs a different (trait-node) hook.
- Harvester staleness guard: prints the newest in-game session version + file write time
  and shouts STALE when it differs from the shipped TOC version. (A prior "we ran it"
  turned out to be last night's 0.5.3 capture - this stops that misread recurring.)
- Shape probe now samples ALL purchased nodes (+10 others), not the first 15, so the
  next harvest shows exactly which talents the player has and how each maps.
- GAP: only 1 of the pilot's 7 selections maps - Forever trait trees include new nodes
  and baseline passives absent from our classic-Talent-derived data. Logged as the
  triaged `DATA-traits` backlog item (pull the Trait DB2 tables for full coverage).

*Features:* CORE-talent-api, QA-harvester, QA-verify-command

## 0.7.1 - 2026-10-10

Repoint talent reads to C_Traits - the real Forever talent system, confirmed against a
working addon kit (not a guess, not an AI summary).

- FINDING (Thunderz96/forever-addon-kit): Forever talents are Retail's C_Traits node
  trees; the classic GetTalentInfo/GetNumTalentTabs globals are gone. This invalidated
  both a Google AI Overview (which described the classic global signature as if it were
  Forever's) and this addon's own three C_SpecializationInfo.GetTalentInfo guesses -
  all aimed at the wrong system, hence the earlier "none-answered".
- `core/talent_api.lua` rewritten to walk C_Traits exactly like the kit's dumpTraits:
  GetActiveConfigID -> GetConfigInfo -> GetTreeNodes -> GetNodeInfo -> GetEntryInfo ->
  GetDefinitionInfo.spellID, with node.ranksPurchased as the rank. That spellID maps
  back to our generated talent via spellRanks (the capture bridge). Classic globals
  remain a fallback; degrade-safe when no talent surface exists.
- `Snapshot.captureTalents` now returns talents matched to our generated talent ids.
- The shape probe runs the same C_Traits walk and records nodes/purchased/
  mapped-to-generated + a sample; `/foresight verify`'s adapter line reports it. The
  next harvest confirms the path live and proves the spellID bridge.
- Selftest (60) now mocks C_Traits end-to-end (node -> spell 11069 -> talent 26 rank 2).
- STILL OPEN: the S2 talent-tooltip injection hook (GameTooltip.SetTalent) is classic-
  only and won't fire on the trait UI; identifying the trait-node tooltip hook is the
  remaining S2 unknown. Talent DATA capture is now correct.

*Features:* CORE-talent-api, MODEL-snapshot, QA-verify-command, QA-harvester,
QA-selftest-harness

## 0.7.0 - 2026-10-10

`GRAPH-threat`: threat becomes the 8th outcome lens, built on real client data.

- Generator: discovered + mapped SPELL_AURA_MOD_THREAT (aura 10, EffectMiscValue_0 =
  school mask) to a "threat" op. Ground-truthed against tooltips - Subtlety mask 72 =
  Nature/Arcane, Silent Resolve 2 = Holy, Frost Channeling 16 = Frost - the same
  base-points-match-tooltip bar as the stat-bitmask fix. Side effect: 4 threat talents
  moved OUT of needs-curation (186 -> 182).
- Threat ops fold through a new `agg.threatModPct` graph node (not a second math path);
  the `threat` dimension scores 100% baseline + your own talent threat %, (p)
  classic-presumed. The talent tooltip now surfaces threat lines for free.
- Per-ability base threat + stance multipliers are explicitly future, scaffolded in
  `overrides.abilityThreat` under the k-of-n crowd rule - no fabricated values now.
- Selftest grows to 60 checks (op mapping + school, lens baseline, modeled Suppression
  lowering the lens to 80%). Live signal depends on the S3 talent-read unblock; panel
  8th-row readability folds into the S3 pass.

*Features:* GRAPH-threat, GRAPH-dimensions, DATA-pipeline-generate, DATA-generated-tables,
DATA-formula-registry, QA-selftest-harness

## 0.6.2 - 2026-10-10

`UI-spell-tooltip`: ability tooltips now translate your gear onto the button.

- `Tooltips.spellLines`: uses the client cast time + the (p) spell-coefficient formula
  to show how much of your live Spell/Healing Power lands on a spell per cast ("Your
  Spell Power (+250) adds about +179 to this spell per cast (71% coefficient at a
  2.5s cast)"). Deliberately NOT a flat hit number - base spell damage per rank isn't
  in the shipped tables yet; when DATA-items/probe add it, this upgrades to an absolute.
- Shares the ONE injection module (TooltipDataProcessor(Spell) path + OnTooltipSetSpell
  fallback, per-spell guard, degrade-safe). `/foresight verify` gains a spell-hook line.
- Selftest grows to 57 checks (coefficient translation, zero-power nil case).
- In-game hook verify folds into the S3 pass.

*Features:* UI-spell-tooltip, DATA-formula-registry, QA-verify-command, QA-selftest-harness

## 0.6.1 - 2026-10-10

New `UI-item-tooltip` (user ask): item tooltips now translate stats into what they do
for YOUR character - the "+1 Agility, so what?" answer, on gear.

- Item hook on the SHARED injection module (ui/tooltips.lua) - no second hook system.
  GetItemStats -> `mapItemStats` (GetItemStats keys -> our stat names) ->
  `Impact.explainItemDelta` (applies all the item's stat deltas at once and diffs vs
  your current character - reuses the diff path, no forked value math) -> injected
  "This item: +4 Agility, +6 Stamina" + colored dimension lines ("+1.8% Melee DPS").
- Modern TooltipDataProcessor(Item) path with a legacy OnTooltipSetItem fallback;
  per-item guard prevents re-stacking; degrades to no injection on any failure.
- v0 covers primaries + spell/healing power (all base graph nodes); gear ratings
  (crit/haste/hit) wait until the model converts ratings. All values (p)-tagged.
- `/foresight verify` gains an "item tooltip injection hook" status line.
- Selftest grows to 55 checks (mapper, line builder, explainItemDelta, empty case).
- In-game verify (no taint, GetItemStats key shape on Forever) folds into the S3 pass.

*Features:* UI-item-tooltip, MODEL-impact-diff, QA-verify-command, QA-selftest-harness

## 0.6.0 - 2026-10-10

Two layman-impact features from the "Layman's Oracle" triage - what each stat is worth
for YOUR build, and what your build even is. Both pure/selftest-covered (51 checks).

- MODEL-stat-advisor: `Impact.rankStats` / `statPrioritySentence`, built entirely on
  the existing explainStatDelta path (no forked value code). Headline sentence orders
  stats by the build's primary output lens ("For your Spellcasting right now: Intellect
  > ... per point"); the per-stat breakdown names each stat's strongest dimension move.
  Surfaced via `/foresight advisor` and a new panel "Stat value (per +1)" section.
- UI-playstyle-label: `PanelModel.playstyleLabel` classifies the build from dimension
  scores (top output lens = Caster/Melee/Ranged/Healer) plus a within-character
  offense/survival stat lean. Shown in the panel subtitle and `/foresight build`.
- Both labeled "(v0 heuristic)". /foresight help + command list updated. In-game checks
  (panel subtitle fit, advisor readability at mobile baseline) fold into the S3 pass.

*Features:* MODEL-stat-advisor, UI-playstyle-label, MODEL-impact-diff, UI-stats-panel,
QA-selftest-harness

## 0.5.4 - 2026-10-10

Level-10 read-back: the adapter's guessed conventions still return no data, so stop
guessing - capture the raw API shape and auto-collect on every login.

- Level-10 finding: C_SpecializationInfo.GetTalentInfo exists but none of the three
  guessed calling conventions returns usable data (adapter mode none-answered, probe 0
  talents) even after allocating a point - the S2 hook installs but injects nothing.
- New `Collect.probeTalentApiShape`: records the LITERAL return of five GetTalentInfo
  call shapes (positional, 3-arg, and table-queries), C_SpecializationInfo spec calls,
  C_ClassTalents/C_Traits config calls, and a GameTooltip:SetTalent(1,1) render test -
  table keys, scalars, or the error string - into SavedVariables. The harvester prints
  it. Next read-back hands us the real signature to write the adapter against.
- `/foresight verify` now AUTO-RUNS once per login (silent, C_Timer-deferred 1s, one
  summary line) - a reload alone gathers verify + probes, no typing needed.
- Shape discovery expanded to item/spell tooltip surfaces (Enum.TooltipDataType.Item/
  Spell, GetItemStats, SetSpellByID, TooltipDataProcessor) for the upcoming spell- and
  item-tooltip layman-impact features.
- Selftest grows to 46 checks (describeValue, shape-probe headless persistence).

*Features:* QA-verify-command, QA-collector, QA-selftest-harness

## 0.5.3 - 2026-10-10

Shape-discovery read-back answered S3's API question; this build is the response.

- VERDICT (live, build 70338): talent info lives on C_SpecializationInfo.GetTalentInfo
  (convention undocumented); GameTooltip.SetTalent EXISTS (the S2 hook was blocked only
  by its install guard requiring the classic global); C_TooltipInfo.GetTalent,
  TooltipDataProcessor, C_ClassTalents, C_Traits present. Absent: classic globals,
  C_SpecializationInfo.GetNum* enumerators, Enum.TooltipDataType.Talent.
- New `core/talent_api.lua`: THE talent-read adapter. Pcall-probes known conventions
  (classic multi-return / spec table-query / spec positional), locks the first that
  yields a sane result, normalizes to classic shape { name, tier, column, rank,
  maxRank }; enumerates by brute coordinate probing with a consecutive-miss cutoff
  (no GetNum* needed); selftest-reset hook so mocks never poison the live adapter.
- Rerouted ALL talent reads through the adapter: Snapshot.captureTalents, the tooltip
  probe (now also records adapterMode), and the S2 hook install/inject.
- `/foresight verify` gains "talent API adapter returns data" - reports the locked
  convention and a sample talent; this line is the next read-back's payload.
- Selftest grows to 44 checks (adapter normalization, sparse cutoff, capture path).

*Features:* CORE-talent-api, MODEL-snapshot, QA-verify-command, QA-collector,
UI-talent-tooltip, QA-selftest-harness

## 0.5.2 - 2026-10-10

First live harvest read-back (build 70338): big S3 finding plus three fixes it exposed.

- FINDING: the classic talent API is ABSENT on Forever (GetTalentInfo/GetNumTalentTabs
  nil) - talent capture, the tooltip probe, and the S2 hook all degraded as designed,
  which the verify results proved. `/foresight verify` now runs a 16-candidate
  talent-API shape discovery (C_SpecializationInfo.*, C_ClassTalents, C_Traits,
  C_TooltipInfo.GetTalent, TooltipDataProcessor, GameTooltip.SetTalent, ...) so the
  next harvest tells us exactly what S2 hooks instead.
- VERIFIED LIVE: SavedVariables persistence under ForesightDB, UnitStat indices,
  crit/haste/weapon-speed reads, C_SpecializationInfo, C_AssistedCombat (with
  GetNextCastSpell - the ASSIST-hud pillar is feasible), secret-values system,
  C_TooltipInfo.
- FIXED armor=0: UnitArmor return #3 is classic-only; effectiveArmor is #2 on both
  shapes - read via new `Guards.select(n, fn, ...)` (multi-return guarded reads).
- FIXED dataBuild journaled as "?" and the login line printing "data build ? (?
  talents)": HM.gen.build is the build STRING and was indexed like a table.
- Harvester prints the discovered talent-API shape; selftest grows to 43 checks
  (Guards.select, session dataBuild journaling).

*Features:* QA-verify-command, QA-collector, CORE-guards, MODEL-snapshot, QA-harvester,
QA-selftest-harness

## 0.5.1 - 2026-10-10

S3 initial pass: two latent pipeline bugs found via harvest dry-run, fixed, and gated
(incident-to-gate both times). Live pilot confirmed v0.5.0 login + verify at level 9.

- FIXED generator stat decode: modern-format clients encode a stat aura's stat as a
  BITMASK in EffectMiscValue_1 (8=Intellect, 31=all stats); reading MiscValue_0 as an
  index mislabeled six talents "Strength" (Ancestral Knowledge, Arcane Mind, Heart of
  the Wild, Mental Strength, Lightning Reflexes, Toughness, Demonic Embrace's Stamina
  op) - the model would have buffed the wrong stat. All twelve stat ops now match
  their tooltips; data regenerated; selftest pins the decode (41 checks).
- FIXED harvester lua_to_py: any all-integer-keyed table became a Python list, so
  sparse talent-id tables silently lost their ids - rank-rule voting would have
  crashed on the first real probe. Lists now only for true 1..n Lua arrays.
- GATE: `harvest.analyze_selfcheck()` wired into run_tests.py - synthetic probe must
  vote A (Improved Fireball) + B (Concussion), trained and untrained, against real
  generated data on every ship.
- Harvester now votes on untrained talents' rank-1 tooltip text as a separate
  clearly-presumed tally - a pre-level-10 probe already gives rank-rule signal.
- Harvest dry-run also confirmed: SavedVariables on disk is still the migration
  skeleton (client flushes only on logout//reload) - pilot read-back pending.

*Features:* DATA-pipeline-generate, DATA-generated-tables, QA-harvester,
QA-selftest-harness, MODEL-loadout-whatif

## 0.5.0 - 2026-10-10

S2 build: Talent Impact Map tooltip injection, code-complete (in-game verify folds
into the S3 beta session - no taint, line rendering, resolver vs live positions).

- New `ui/tooltips.lua`: THE shared tooltip-injection module (triage law: the future
  UI-spell-tooltip surface reuses this core, never a second hook system). Talent
  provider ships now: post-hook on `GameTooltip.SetTalent` (this object only - the
  hidden probe tooltip keeps capturing clean text; inspect skipped) appends the
  approved mockup block: "Foresight | (p) rank rule presumed" header, "Affects: ..."
  (capped +N more), per-op "Next point: -0.1s cast time (now -0.2s, max -0.5s)"
  marginal values, and a "-> for you now: +0.2 Spellcasting" dimension delta computed
  by diffing rank r vs r+1 (snapshot double-count cancels in the diff). Cast-time/
  cost/cooldown ops honestly show NO dimension line until GRAPH-rotation-weights.
- Talent resolver: classic-API position (tab order/tier/column, 1-based) -> generated
  talent id, with displayed-name arbitration and name fallback; pure + selftest-covered.
- Needs-curation talents say so in the tooltip; every injection failure path degrades
  to "no injected lines", never an error (pcall-wrapped, guards law).
- `Impact.talentSummary` ops now carry `maxValue` (per-rank recompute without a second
  data walk); `presumedMark` promoted to the formula registry (`F.presumedMark`) so
  panel and tooltips tag presumed values identically.
- `/foresight verify` gains a "talent tooltip injection hook (S2)" checklist line.
- `HM.version` synced to the TOC (was stale at 0.1.0; collect journals this stamp).
- Selftest grows to 40 checks (resolver position/name/unknown, header tag, marginal
  values, maxed-rank, dimension fragment presence AND honest absence, curation line).

*Features:* UI-talent-tooltip, MODEL-talent-summary, DATA-formula-registry,
QA-verify-command, QA-selftest-harness, CORE-bootstrap

## 0.4.0 - 2026-10-10

Renamed: HelpMe -> **Foresight** (naming research before the public repo: "HelpMe"
collides with HelpMePlay on CurseForge - a quest-automation addon, exactly the
association a compliance-first project must avoid; Foresight captures both pillars -
see what a point does before you commit, see danger before it kills you - and fits
the ecosystem's one-word pattern: Pawn, Details, Recount).

- Renamed addon folder, TOC, SavedVariables global (ForesightDB), slash commands
  (/foresight, /fore; /helpme kept as a legacy alias), pipeline, docs, packager
  config; generated data regenerated with new headers.
- New TOC icon (Spell_Nature_FarSight) and Notes one-liner; version stamp 0.4.0.
- Live install migrated: AddOns folder replaced, WTF SavedVariables carried over
  (HelpMeDB -> ForesightDB) so pilot journals/probes survive.
- Historical entries below intentionally keep the HelpMe name.
- Character-frame toggle button relabeled "HM" -> "FS" (missed by the string sweep:
  it was a literal, not a name reference).
- HTML/CSS design replica of the full UI added at `mockups/foresight-ui.html`
  (panel as shipped + S2 tooltip-injection preview; repo-only, packager ignores it).

*Features:* CORE-bootstrap, QA-publish-train, UI-stats-panel

## 0.3.1 - 2026-10-10

Tamper/abuse hardening (threat model in DATAFLOW.md 4c; incident-to-gate applied).

- FIXED a real vulnerability: harvest.py executed SavedVariables Lua with os/io/python
  reachable - hostile crowd submissions could have run code on the harvesting machine.
  Now parsed in a neutered sandbox (os/io/require/load/package/debug/python nil,
  register_eval off, 20MB cap).
- GATE: `harvest.sandbox_selfcheck()` (5 hostile payloads must fail, benign must
  parse) wired into run_tests.py - a sandbox regression blocks the ship.
- Addon-side: SavedVariables load is now type-validated (`HM.initSavedVariables`);
  tampered/corrupted files degrade to defaults; collect store self-heals.
- Untrusted-input laws added to CLAUDE.md (data-only imports forever, k-of-n rule for
  crowd-sourced database changes). Selftest grows to 32 checks.
- Git repo created (root commit) with publishing scaffolding per DATAFLOW.md 4b:
  `.pkgmeta` (BigWigsMods packager; only HelpMe/ ships), `.gitignore` (DB2 cache and
  harvested account data stay local), README as the official-channels front door,
  `.gitattributes` line normalization. HelpMe.toc version stamp synced to the release
  (was stale at 0.1.0) and redeployed, gate green 32/32.

*Features:* QA-harvester, QA-selftest-harness, CORE-saveddb, QA-publish-train

## 0.3.0 - 2026-10-10

Crowd data-collection loop (pilot scale), copyable export, fancy panel skin, gated
deploys. First confirmed in-game run: 28/28 on a level-9 Shaman, and SavedVariables
persistence CONFIRMED on the live client (S3 item resolved).

- New `core/collect.lua`: session journal, PLAYER_LEVEL_UP stat journal, `/helpme
  verify` (automated S3 checklist: API shapes, live snapshot sanity, C_AssistedCombat,
  secret-values presence) and a talent tooltip probe capturing EVERY talent's in-game
  tooltip text - the authoritative data that settles the rank-scaling rule.
- New `ui/export.lua`: copyable scroll/EditBox window (`/helpme export`) - fixes
  "can't copy from the chat window"; `HM.serialize` for readable dumps.
- New `pipeline/harvest.py`: finds HelpMe SavedVariables across WoW installs, parses
  in a Lua VM, archives JSON to pipeline/collected/, prints verify summary, and runs
  rank-rule hypothesis voting (A: max-total vs B: per-rank) from probed tooltips.
- New `pipeline/deploy.py`: gate-then-copy deploy to the live install (release-train
  binding); verified: 20 files deployed to `_classic_beta_` AddOns.
- Stats panel reskinned: dark translucent card, class-color accents/title/top-strip,
  zebra rows, hover highlight, green/red colored what-if deltas - all code-drawn.
- Selftest grows to 30 checks (serialize, headless verify persistence).

*Features:* QA-collector, QA-verify-command, QA-harvester, QA-deploy, UI-export-window,
UI-stats-panel, CORE-bootstrap

## 0.2.0 - 2026-10-10

ECS-inspired stats panel + marginal stat conversions (UI pattern scan: Extended
Character Stats lineage - toggle button, collapsible-category side panel, per-character
state; mockup and mapping in DESIGN.md "UI map").

- New `ui/panel_model.lua` (pure, selftest-covered) + `ui/stats_panel.lua` (renderer):
  side panel docked to CharacterFrame with HM toggle button; sections Dimensions /
  Regen / Mechanics / What-if; collapse state persists per character; presumed-formula
  values marked `(p)`; secret/unavailable values render "-".
- What-if section is the differentiator vs ECS: live "+10 stat -> human terms" rows.
- Classic per-class primary-stat conversions added to the formula registry (AP per
  Str/Agi, Agi per crit%, Int per spell-crit%), applied as MARGINAL rates around the
  snapshot so game-reported AP/crit is never double-counted. Str/Agi/Int now move
  dimensions (Shaman demo: +10 Str = +6.45% melee DPS, +10 Sta = +5.56% tankability).
- Selftest grows to 28 checks.

*Features:* UI-stats-panel, DATA-formula-registry, MODEL-impact-diff, QA-selftest-harness

## 0.1.2 - 2026-10-10

- `/helpme talent` now accepts names (case-insensitive, partial match lists candidates)
  via new `HM.findTalents`; selftest grows to 21 checks.
- Shaman verified end-to-end in generated data (46 talents across 3 trees; Forever
  additions like Lava Burst present and mapped).
- Rank-scaling rule downgraded to `disputed-mixed-evidence`: classic-value comparison
  shows some talents store per-rank values, others max totals. Four named probe
  talents added to the S3 beta checklist.

*Features:* CORE-bootstrap, QA-selftest-harness, DATA-formula-registry

## 0.1.1 - 2026-10-10

Compliance audit + permanent gate (incident-to-gate: class = "a code change introduces
an automation call, protected-API use, or sandbox escape risking the account").

- Audited the full addon: zero automation/protected calls, zero sandbox escapes.
- New `pipeline/check_compliance.py`: static scan banning ~40 casting/targeting/
  movement/item-use/macro APIs and os/io/require/loadstring escapes; documented
  `-- compliance-allow:` mechanism for justified exceptions; TOC sanity checks.
- Wired into `run_tests.py` as the FIRST step of the ship gate (red blocks everything).
- Gate proven: planted CastSpellByName violation detected (exit 1), clean run green.
- Hardened gate output for BOM/cp1252 consoles (utf-8-sig reads, replace-errors stdout).

*Features:* QA-compliance-gate

## 0.1.0 - 2026-10-10

Foundation release: data pipeline, impact graph, character modelling, test harness.

- Data pipeline: fetch 14 Forever DB2 tables (build 1.60.1.70338) from wago.tools;
  generator computes talent->affected-spells via spell-family class masks (246/432
  talents auto-mapped, 186 flagged for curation) and emits Lua data tables
  (432 talents, 27 tabs, 3,448 player spells with cast/cost/tick/cooldown data).
- Discovered + encoded Forever client data layout: multi-rank talent values stored
  only on the rank-1 spell as max-rank totals; rank scaling shipped as
  "linearToMax-presumed" pending beta verification.
- Impact graph engine: typed modifier DAG (flat/pctAdd/pctMult/override), stacking
  groups, per-value breakdowns, cycle detection.
- Formula registry with confidence tags (classic regen formulas, swing time, armor
  mitigation, spell coefficients, talent rank rule).
- Loadout modelling: snapshot + what-if deltas (talents, stat changes), dimension
  scoring (7 lenses), diffing, and the "+2 Spirit -> human terms" explainer.
- Core addon: TOC (Interface 16001), secret-value guard layer, versioned SavedVariables,
  /helpme talent|stat|selftest commands.
- Headless test harness (lupa Lua VM): 19/19 selftest checks pass.

*Features:* DATA-pipeline-fetch, DATA-pipeline-generate, DATA-generated-tables,
DATA-formula-registry, DATA-overrides, GRAPH-impact-engine, GRAPH-dimensions,
MODEL-snapshot, MODEL-loadout-whatif, MODEL-impact-diff, MODEL-talent-summary,
CORE-bootstrap, CORE-guards, CORE-saveddb, QA-selftest-harness
