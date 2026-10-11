# Changelog

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
