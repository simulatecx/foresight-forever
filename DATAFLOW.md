# HelpMe - Data Flow & Impact Graph Design

Date: 2026-10-10. Priority #1 deliverable: the **Talent Impact Map**, built on a general
**Character Impact Graph** that models how everything in WoW affects everything else - so the
same engine later answers items, professions, and "what does +2 Spirit actually do for me".
Supersedes the build order in `DESIGN.md` (talents now come first).

## 1. The core idea: one impact graph, many askers

Model the character as a directed graph of typed nodes and modifier edges:

```
SOURCES          STATS                MECHANICS                 ABILITIES         OUTCOMES
talents     -->  primary (Str/Agi/    mana regen tick (2s)      Frostbolt R4  --> sustained DPS
items       -->   Sta/Int/Spirit)     health regen tick         Corruption    --> casts per minute
buffs       -->  secondary (+spell    weapon swing timer        Auto-attack   --> effective HP
professions -->   dmg, +healing, mp5, DoT/HoT tick period       Fireball      --> survival margin
consumables -->   crit%, hit%, haste, GCD, cast time                              (hardcore!)
                  defense, wpn skill) school lockout (interrupt)
                                      attack table (miss/dodge/
                                       parry/glance/crit)
```

**Edges are typed modifiers**: `flat add`, `% multiplier`, `formula` (class-specific
conversion), `conditional` (stance/form, five-second rule, in-combat), `cap`. Stacking rules
(additive groups vs multiplicative) live on the edge type, which is how "talents multiply with
weapon/inventory changes" is handled correctly instead of hand-waved.

Every query is a graph walk: a talent's impact = everything downstream of it; a stat's meaning
= the formula edges leaving it; an item's impact = its stat deltas pushed through the walk.

### The anchor example: "+2 Spirit on a Mage - so what?"

```
+2 Spirit
  -> [formula: mage mana tick = 13 + Spirit/4, every 2s outside the five-second rule]
  -> +0.5 mana per tick  ->  +1.5 MP5 (while not casting for 5s+)
  -> [fight model: your measured casting uptime, e.g. 60%]
  -> ~ +18 mana per minute of combat
  -> [÷ Frostbolt R4 cost]
  -> "~1 extra Frostbolt every ~9 minutes; +X HP/5 out-of-combat regen -> ~Y sec faster
      recovery between pulls"
```

The presentation layer always ends in human terms: extra casts, seconds saved, effective HP -
never just a number relabeled. Same walk handles weapon swing (speed / (1+haste%)), DoT tick
counts (duration / period, both in client data), and interrupt cost (school lockout seconds x
your cast mix in that school).

## 2. Data sources - where we pull from, ranked by impact

| Priority | Source | What it gives | How |
|----------|--------|---------------|-----|
| 1 | **Client DB2 tables via wago.tools** (Forever builds `1.60.1.x` are served today; current build 70338) | Ground truth: every spell, rank, coefficient, **tick period (SpellEffect aura period)**, cast time, power cost, duration, talents, items, profession recipes | Offline pipeline: fetch CSVs per build -> generate `data/generated/*.lua` shipped with the addon. Community repos (e.g. `alcaras/forever-ref`) already prove this works for Forever |
| 2 | **Runtime in-game APIs** | Current post-talent values on the live character: `C_TooltipInfo` structured tooltips, spellbook, `GetItemStats`, `UnitStat`, mana regen APIs, combat log | Always correct for "this character right now"; no staleness; catches hotfixes |
| 3 | **Formula registry** (classic-era community formulas + Forever-specific sources like zugzugdb.com/formulas) | The conversion math DB2 doesn't express: per-class Spirit regen (Mage/Priest `13 + Spirit/4`, Warlock `8 + Spirit/4`, Druid/Shaman/Paladin/Hunter `15 + Spirit/5` per 2s tick), five-second rule, attack table, weapon-skill effects | Curated Lua table; every formula carries `source` + `confidence` + `verified_build` fields |
| 4 | **Empirical probe (us - the pilot case)** | Validation that Forever didn't silently change classic math | We play; the addon measures (see below) |

**Three-way reconciliation** is the quality mechanism: DB2 says *base*, runtime says *current*,
probe says *actual*. Disagreement -> flag the entry, lower its confidence, surface it in the
dev panel. Shipped data is stamped with the client build it was generated from; the addon warns
when the game build is newer than the data build.

## 3. Empirical probe module (why being the pilot matters)

Forever's formulas are classic-*like* but unconfirmed (115 new talents, modern client). The
probe watches our own gameplay - own-unit data, open world, fully readable - and measures:

- **Mana/health regen**: sample own power every tick window, segmented by inside/outside the
  five-second rule -> fit against the formula registry per class/level/Spirit.
- **Weapon swings**: own swing event timestamps from the combat log -> actual swing timer vs
  `weapon speed / (1+haste)`.
- **DoT/HoT ticks**: own periodic aura events -> actual tick period vs DB2 aura period.
- **GCD / cast times**: spellcast event deltas.

Each measurement either *verifies* a formula (confidence -> `verified@build`) or *flags* it
(mismatch report auto-drafted). This converts "we play the beta" into dataset QA for free.

## 4. User feedback: "this doesn't work for X reason"

Addons have no network access, so the proven pattern is export strings (how WeakAuras shares):

1. Every HelpMe tooltip/panel has a small **"report" affordance** (and `/helpme report`).
2. It captures a structured payload: the disputed entry (talent/formula/mapping id), expected
   vs observed, character class/level/race, talent snapshot, addon version + game build,
   optional free-text reason.
3. Payload is serialized + compressed into a copyable string; user pastes it into Discord or a
   GitHub issue template with a paste box.
4. Our side: a small decoder script turns pasted strings into triage rows; fixes land in the
   curated overrides table and ship next data build.
5. **Later upgrade**: a tiny companion desktop app that reads the addon's SavedVariables file
   and uploads reports automatically (reading our own addon's output file outside the game is
   the same legitimate pattern WowUp and Warcraft Logs use). No pasting, same data.

The probe module (sec. 3) feeds the same pipeline: auto-drafted mismatch reports are
pre-filled, the user just confirms sending.

## 4b. Publishing & infrastructure plan (decided 2026-10-10)

Clarity first: the shipped database (talents/spells/formulas) is BAKED INTO the addon -
players need no server for HelpMe to work. Infrastructure exists for exactly two jobs:
distribution/updates, and the crowd-data return channel.

### Distribution + automated updates (phase 1 - free, standard ecosystem tooling)

```
GitHub repo (source of truth)
  -> tag vX.Y.Z -> GitHub Action (BigWigsMods/packager) -> zips addon, stamps .toc
       -> auto-uploads to CurseForge + Wago Addons + GitHub Releases
            -> players' addon managers (CurseForge app / WowUp) auto-update
```

- Players get "automated addon updates" for free: their manager sees the new version.
- Our side is one `git tag` push; the packager action handles CurseForge/Wago API
  uploads via repo-secret tokens. `.pkgmeta` controls packaging.
- DATA FRESHNESS automation (our special case): a scheduled GitHub Action polls
  wago.tools for a new Forever build; on change it runs fetch -> generate -> ship gate,
  and opens a release PR. Every game patch = refreshed shipped database with zero
  manual work. The compliance gate runs in CI on every push (same run_tests.py).

### Crowd-data return channel (phased - start free, add a server only when volume asks)

- **Phase A (launch): zero infra.** In-game report/export strings (users paste into a
  GitHub issue template or Discord); pilot harvesting stays local (harvest.py). Free,
  no PII custody, enough for early curation.
- **Phase B (traction): companion uploader + tiny ingestion endpoint.** The companion
  app runs harvest.py logic locally and POSTs the JSON. Endpoint options, either fine:
  Firebase (Cloud Function -> Firestore/Storage) or Cloudflare Worker -> R2/D1. Shape
  is append-only telemetry ingestion + offline weekly aggregation into
  `data/overrides.lua` for the next release - NOT a live database the addon reads.
  Privacy pass required before Phase B ships (privacy-by-design): opt-in consent in
  the companion app, strip/hash account ids, character name optional, no chat/social
  data ever; retention policy documented.
- The addon NEVER networks in any phase (compliance invariant).

## 4c. Threat model - abuse of the addon / our name (decided 2026-10-10)

Who can be penalized for what: Blizzard actions accounts for what THEY run; our
sandboxed display-only addon cannot harm its users' accounts, and a stranger's
tampered fork is the tamperer's problem account-wise. What CAN hurt us: our brand
(malicious repackaging), our machines (hostile data submissions), and our database
(poisoned crowd data). Defenses per vector:

| Vector | Defense | Status |
|---|---|---|
| Hostile SavedVariables submissions executing code in our harvester | Lua sandbox (os/io/python/load/require neutered, size cap) + `sandbox_selfcheck()` wired into the ship gate | ☑ shipped + gated |
| Tampered/corrupted SavedVariables breaking the addon on a user's machine | Type-validated defensive load; malformed fields reset to defaults | ☑ shipped + tested |
| Poisoned crowd data corrupting the shipped database | Phase B rule: aggregation requires k-of-n independent confirmations before any curated change; one submission can never alter `overrides.lua`; human review on the PR | ☐ binds Phase B |
| Malicious "HelpMe" repackaging / brand abuse | Official channels only (CurseForge + Wago + GitHub Releases), stated in README; source fully visible (policy requires it anyway); login line prints version + data build so users can spot fakes; CurseForge takedown process for impersonations | ☐ binds publish step |
| Supply-chain: compromised repo/CI shipping bad code | Branch protection, CI actions pinned by SHA, upload tokens as repo secrets, compliance gate runs in CI on every push (a malicious PR adding automation calls goes RED) | ☐ binds publish step |
| Future import strings executing code (the WeakAuras custom-code attack class) | INVARIANT: HelpMe never executes imported content; any future import is data-only parsing with shape validation, never loadstring | law in CLAUDE.md |

## 5. Build order (talent map first)

1. **Data pipeline** (separate `pipeline/` tooling, Python or Node): pull Forever DB2 CSVs from
   wago.tools for a pinned build -> emit `data/generated/` Lua tables (spells incl. tick
   periods and coefficients, talents, talent->spell effect links, items later).
2. **Graph core** (`graph/` in-addon): node/edge store, modifier ops with stacking rules,
   query API: `impactsOf(talent)`, `explain(statDelta, character)`, `affectedBy(spell)`.
3. **Formula registry** (`data/formulas.lua`): classic-era seeds, confidence-tagged.
4. **Talent Impact Map MVP**: tooltip injection on talent hover - "Affects: [spells]" from DB2
   links (text-parse fallback for indirect talents) + human-terms deltas via the graph.
5. **Probe module**: regen/swing/tick measurement while we play; verification statuses.
6. **Report affordance + export string**; decoder script in `pipeline/`.
7. Then: mapping panel UI, item impact (same graph, item stat deltas), professions
   (recipes/consumables from DB2 SkillLine tables -> modifier sources like everything else).

## 6. Sources

- [wago.tools DB2 export for Forever builds](https://wago.tools/) (e.g. `db2/<table>/csv?build=1.60.1.x`; [helper tooling](https://github.com/p3lim/dbc-helper), [forever-ref example consumer](https://github.com/alcaras/forever-ref))
- [ForeverDB - full Forever client database](https://foreverdb.net/) · [TheWoWDB Forever](https://thewowdb.com/wow-forever/) · [wow-forever.gg](https://wow-forever.gg/) · [WCLBox Forever DB with Classic-era diffs](https://wowforever.wclbox.com/en)
- [Forever mana regeneration formulas - ZugZugDB](https://zugzugdb.com/formulas/mana-regeneration)
- [Classic mana/Spirit mechanics & five-second rule - Warcraft Tavern](https://www.warcrafttavern.com/wow-classic/guides/mana-management-optimization/)
- [Spirit regen per-class formulas discussion](https://us.forums.blizzard.com/en/wow/t/is-my-maths-right-for-this-mana-5-vs-spirit/321047)
