# Foresight - Work Tracker

Single source of truth for work. Status glyphs: ☐ todo · ◐ in progress · ☑ done · ⚑ superseded.

## Status index

| Story | Status |
|---|---|
| S1 Foundation: data pipeline + impact graph + modelling core | ☑ |
| S2 Talent Impact Map in-game MVP (tooltip + /foresight talent) | ◐ |
| S3 Beta verification pass (API shapes, rank rule, snapshot) | ◐ |
| S4 Report/feedback export strings | ☐ |
| S5 ECS-style stats panel (code-complete, render pending beta) | ◐ |
| S6 Crowd data-collection loop (pilot scale) | ☑ |

## Active work

### S2 - Talent Impact Map in-game MVP ◐
Hover a talent in the talent frame -> injected "Affects: ..." lines + per-rank values;
`/foresight talent <id>` already works. **Features:** UI-talent-tooltip.
AC: tooltip lines render on Forever beta client without taint errors; needs-curation
talents say so honestly; mobile check N/A (game UI).
Fit & Overlap: enhances MODEL-talent-summary (same data path, new surface). No overlap -
nothing else renders talent impacts.
Built 2026-10-10 (v0.5.0): shared injection module `ui/tooltips.lua` (the ONE hook
system UI-spell-tooltip must reuse), position+name talent resolver, next-point marginal
values, "for you now" dimension delta, needs-curation + (p) honesty lines; 8 selftest
checks; /foresight verify now reports hook status. Remaining: in-game verify (no taint,
lines render, resolver matches live positions) - fold into the S3 beta session, then ☑.

### S3 - Beta verification pass ◐
On the Forever beta client, verify: talent API shape (Snapshot.captureTalents),
UnitStat/crit/haste API indices, `C_AssistedCombat` presence, SavedVariables
persistence bug status, and THE RANK-SCALING RULE - evidence is mixed (see
formulas.talentRankValue): compare in-game rank 1 vs max tooltips for Improved
Fireball (26), Concussion, Improved Reincarnation, Ancestral Knowledge; outcome is
either one rule or a per-talent field in generated data. Pilot class: Shaman.
**Features:** MODEL-snapshot, DATA-formula-registry. Beta window closes 2026-10-21.
Initial pass 2026-10-10 (v0.5.1): in-game verify ran green on the level-9 pilot
(0.5.0 login line confirmed). Harvest dry-run exposed + fixed two latent pipeline
bugs, both now gated: lua_to_py flattened sparse-id tables to lists (rank-rule voting
would have crashed on first real probe; analyze_selfcheck added to run_tests), and
stat auras decoded MiscValue_0 as index when modern data uses a MiscValue_1 BITMASK -
six talents (incl. probe talent Ancestral Knowledge) said "Strength" instead of
Int/Sta/Agi; generator fixed, data regenerated, selftest pins the decode. Harvester
now also votes on untrained rank-1 tooltip text (separate presumed tally) so the
level-9 probe gives rank-rule signal before any point is spent. Remaining: pilot
logs out/reloads -> harvest verify+probe read-back; trained votes + S2 hover check
at level 10+; snapshot stat-index verification against the live journal.
First harvest read-back (2026-10-10 20:45, build 70338, v0.5.2 shipped fixes):
- VERIFIED LIVE: SavedVariables persistence under ForesightDB; UnitStat indices
  (str/agi/sta/int/spi all sane); crit/haste/weapon-speed APIs; C_SpecializationInfo,
  C_AssistedCombat WITH GetNextCastSpell (ASSIST-hud feasible), secret-values system,
  C_TooltipInfo all present.
- CLASSIC TALENT API ABSENT (GetTalentInfo/GetNumTalentTabs nil): captureTalents, the
  tooltip probe, and the S2 hook all degraded as designed. Verify now runs a 16-
  candidate talent-API shape discovery (C_SpecializationInfo.*, C_ClassTalents,
  C_Traits, C_TooltipInfo.GetTalent, TooltipDataProcessor, GameTooltip.SetTalent);
  next harvest decides what S2 hooks instead. Talent frame itself unlocks at level 10
  - the pilot is level 9, so the UI surface is also still unconfirmed.
- FIXED from live data: armor read 0 (UnitArmor return #3 is classic-only; now #2,
  effectiveArmor, via new Guards.select); dataBuild journaled "?" and login line
  printed "data build ?" (HM.gen.build is a string, was indexed as a table).
Shape discovery verdict (2026-10-10 20:53, v0.5.3 shipped the response): FOUND
C_SpecializationInfo.GetTalentInfo/GetSpecialization(Info), C_ClassTalents,
C_Traits, C_TooltipInfo.GetTalent, TooltipDataProcessor, and GameTooltip.SetTalent
(the S2 hook method EXISTS - only the install guard requiring the classic global
blocked it). ABSENT: all classic globals, C_SpecializationInfo.GetNum*/GetTalentTabInfo
enumerators, Enum.TooltipDataType.Talent. Response: new `core/talent_api.lua` adapter -
pcall-probes known GetTalentInfo conventions (classic / spec-table / spec-positional),
locks the first that answers, normalizes to classic shape; enumeration brute-probes
coordinates (no GetNum* needed); snapshot capture, tooltip probe, and the S2 hook all
rerouted through it; verify gained "talent API adapter returns data" (reports locked
mode + sample). Next read-back confirms which convention Forever answers - possibly
only at level 10+ if talent data is level-gated.
Level-10 read-back (2026-10-10 21:21, v0.5.4 response): adapter STILL mode=none-answered,
probe 0 talents, even after allocating a point - none of the three guessed GetTalentInfo
conventions returns data; the S2 hook installs but injects nothing (nothing on hover
before OR after allocation). STOPPED GUESSING: v0.5.4 adds `Collect.probeTalentApiShape`,
recording the literal return (table keys / scalars / error string) of 5 GetTalentInfo
call shapes + spec/trait/config calls + a GameTooltip:SetTalent(1,1) render test into
SavedVariables; harvester prints it. Next read-back gives the real signature -> write
the adapter convention against ground truth. Also: `/foresight verify` now auto-runs
once per login (silent, C_Timer-deferred 1s) so a reload alone gathers data; discovery
expanded to item/spell tooltip surfaces. THIS IS THE S3 BLOCKER - needs one more pilot
reload + harvest to unblock S2/snapshot-talents.
BREAKTHROUGH (2026-10-10, v0.7.1): scanned Thunderz96/forever-addon-kit (a working
Forever addon kit). Forever talents are RETAIL'S C_Traits NODE TREES - the classic
GetTalentInfo/GetNumTalentTabs globals are gone (its dumpTraits confirms; forever_api.json
lists the full C_Traits + C_ClassTalents set). This invalidated both the Google AI
Overview (which described the classic global signature) AND the adapter's three
C_SpecializationInfo.GetTalentInfo guesses - all aimed at the wrong SYSTEM, which is why
it returned none-answered. REPOINTED: talent_api.lua now walks C_Traits exactly like the
kit (GetActiveConfigID -> GetConfigInfo -> GetTreeNodes -> GetNodeInfo -> GetEntryInfo ->
GetDefinitionInfo.spellID; ranksPurchased = rank), and maps that spellID back to our
generated talent via spellRanks (the capture bridge, no tab/tier/column needed). The
shape probe now runs the same walk and records nodes/purchased/mapped-to-generated + a
sample, so the next harvest CONFIRMS the path live and proves the spellID bridge.
S2 TRAIT-TOOLTIP HOOK (v0.8.2): SetTalent is dead on the trait UI (confirmed, 0 lines),
so added a TraitEntry-tooltip hook - TooltipDataProcessor.AddTooltipPostCall(
Enum.TooltipDataType.TraitEntry) -> resolve data.id (entryID) -> GetEntryInfo ->
GetDefinitionInfo.spellID -> our classic talent -> talentLines. Activates only if the
TraitEntry type is exposed (discovery now probes Enum.TooltipDataType.TraitEntry,
GameTooltip.SetTraitEntry, C_TooltipInfo.GetTraitEntry, ClassTalentFrame,
PlayerSpellsFrame); if not exposed, the next harvest names the real hook. Best-effort
pending live confirmation. (New Forever nodes with no classic talent still fall through;
the spell-tooltip hook may already cover those on hover.)

CONFIRMED LIVE (2026-10-11 07:12, v0.7.2 after a clean logout/login flush - the prior
"we ran it" was STALE 0.5.3 data; harvester now warns on version mismatch): the C_Traits
walk WORKS. Shaman config 13926795, tree 1082, 77 nodes, 7 selected, adapter mode=traits.
The spellID->talent bridge is proven: 38/77 nodes map to our generated talents (e.g.
16178->592, 29206->1648). All 3 tooltip hooks install; discovery confirms their APIs are
present (Enum.TooltipDataType.Item/Spell, C_Item.GetItemStats, GameTooltip.GetItem) so
item/spell tooltips should render live. GameTooltip:SetTalent(1,1) renders 0 lines ->
S2 talent-tooltip injection via SetTalent is dead (data capture fine; injection needs
another hook). C_SpecializationInfo.GetTalentInfo needs a {tier=} query (vestigial 7-row
system, returns empty) - dead end, ruled out.
GAP FOUND -> `DATA-traits` (triaged): only 1 of the pilot's 7 selections maps, because
Forever trait trees include NEW nodes (ids 408xxx/1223xxx) + baseline passives absent
from our classic-Talent-derived data (fetch.py pulls Talent/TalentTab, not the Trait DB2
tables). Full coverage needs generating from TraitTree/TraitNode/TraitNodeEntry/
TraitDefinition. This is the honest next build for talent-capture completeness.

### S5 - ECS-style stats panel ◐
Side panel on CharacterFrame (pattern: Extended Character Stats; mockup in DESIGN.md
"UI map"). Model built + selftest-covered headless; renderer written. Remaining: verify
render/anchoring/toggle on the Forever beta client (fold into the S3 session), then ☑.
**Features:** UI-stats-panel. Fit & Overlap: net-new surface (no prior UI); complements
MODEL-impact-diff (same evaluate path). Mobile: default font templates, 230px panel -
check readability at 1280x720 / 0.65 UI scale during the beta pass.
v0.8.1: panel is now DRAGGABLE (it docks beside the character sheet by default, which can
overlap other panels) - drag to move, position saved per character and restored,
`/foresight panel reset` re-docks. Saved pos is validated (untrusted-input law) so a
tampered value can't fling it off-screen. Drag/anchor behavior folds into the S3 render check.

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
- ◐ DATA-traits (built v0.8.0, 2026-10-11): pull the Retail Trait DB2 and generate full
  node coverage. As a Forever player, I want Foresight to recognize EVERY talent I pick,
  not just the ones that overlap the classic trees. Verdict: enhance the pipeline +
  DATA-generated-tables (no new math path - reuses build_ops for node impacts). fetch.py
  now pulls TraitNode/TraitNodeEntry/TraitNodeXTraitNodeEntry/TraitDefinition/
  SkillLineXTraitTree; generate.py emits traits.lua (555 nodes keyed by nodeID:
  spellID/name/maxRank/ops + bySpell index + tree->class skill line). The C_Traits
  adapter resolves every selected node by nodeID (name/maxRank/traitKnown), so coverage
  is no longer limited to classic-overlap. Selftest: trait load, the 16178->Purification
  bridge, ops present, 50+ non-classic nodes covered. Phase 2: feed new-node ops into the
  what-if model/dimensions (classic-mapped nodes already model via talentImpacts); verify
  live coverage on the next harvest (adapter line now reports resolved vs classic-mapped).

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

- ◐ GRAPH-threat (built v0.7.0, 2026-10-10): threat as the 8th outcome lens, own-state.
  As a hardcore dungeon leveler, I want to see how gear/talents shift my threat so I
  don't rip aggro and die. Shipped: discovered + mapped SPELL_AURA_MOD_THREAT (aura 10,
  misc0 = school mask) to a real "threat" op - ground-truthed vs tooltips (Subtlety 72 =
  Nature/Arcane, Silent Resolve 2 = Holy, Frost Channeling 16 = Frost), which also moved
  4 talents OUT of needsCuration (186->182). Threat ops fold through a new
  agg.threatModPct graph node (never a second math path); the lens scores 100% baseline
  + own talent threat %, (p) classic-presumed. The talent tooltip (S2) now surfaces
  threat lines for free. Per-ability base threat + stance multipliers are future
  (overrides.abilityThreat, k-of-n crowd rule; secret-safe stance read). Selftest covers
  op mapping, the lens baseline, and a modeled Suppression lowering it to 80%.
  Remaining: live signal depends on the S3 talent-read unblock (base shows 100% until
  talents are readable); panel 8th row readability at mobile baseline folds into S3.
  Fit & Overlap - GRAPH (-> DATA): enhanced dimensions.lua + formula registry, no new
  math path. Complements tankability/survivability.

- ◐ UI-spell-tooltip (built v0.6.2, 2026-10-10): ability-tooltip injection with layman
  lines. As a leveler comparing buttons, I want each ability's tooltip to say what it
  does for MY character. Shipped honestly: rather than invent a flat hit number (base
  spell damage per rank isn't in the shipped tables), it uses the client cast time +
  the (p) coefficient formula to translate live Spell/Healing Power into "+N to this
  spell per cast". Shares the ONE injection module (Tooltips.spellLines + spell hook,
  TooltipDataProcessor(Spell) with OnTooltipSetSpell fallback). Logic selftest-covered;
  in-game hook + "does the flat-hit number need base data" fold into the S3 pass.
  Fit & Overlap - UI (-> MODEL): no second hook system; the duplicate avoided. When
  DATA-items/probe later ship base damage per rank, upgrade the line to an absolute
  estimate.

- ☑ UI-playstyle-label (shipped v0.6.0, 2026-10-10): one-line build profile
  ("Caster-leaning - offense-focused (v0 heuristic)") from the top output dimension +
  a within-character offense/survival stat lean; pure in panel_model.playstyleLabel,
  surfaced in the panel subtitle and `/foresight build`. Selftest-covered. Remaining:
  in-game subtitle fit check at mobile baseline (fold into S3).

- ☑ MODEL-stat-advisor (shipped v0.6.0, 2026-10-10): Impact.rankStats /
  statPrioritySentence built entirely on explainStatDelta (no forked value path).
  Headline orders stats by the build's primary output lens; the per-stat breakdown
  names each stat's strongest dimension move. `/foresight advisor` + panel "Stat value
  (per +1)" rows. v0 heuristic, selftest-covered. Feeds the future DATA-items gear
  compare.

- ◐ UI-item-tooltip (triaged + built v0.6.1, 2026-10-10): user ask - "+1 Agility"
  gear should say what it does for MY character. As a leveler comparing drops, I want
  each item's tooltip to translate its stats into dimension impact. AC: injected lines
  append without taint; reads degrade to no-injection; conversion values (p)-tagged;
  compliance green. Fit & Overlap - UI (-> MODEL). Verdict: Net-new SURFACE but shares
  the ONE injection module (ui/tooltips.lua) and reuses explainItemDelta over the diff
  path - the duplicate to avoid is any second marginal-value math. Complements
  MODEL-stat-advisor + future DATA-items. Touches: tooltips.lua, impact.lua. Built:
  GetItemStats -> mapItemStats -> explainItemDelta -> injected block; primaries + spell/
  healing power in v0 (gear ratings wait for rating conversion); TooltipDataProcessor
  path with legacy OnTooltipSetItem fallback. Logic selftest-covered; in-game hook
  pending S3 verify (no taint, GetItemStats returns expected keys on Forever).
