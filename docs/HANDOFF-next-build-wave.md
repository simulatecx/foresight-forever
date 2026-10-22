# Handoff - next build wave (verified pipeline, show-off tier, coverage, zero-click verify)

> SUPERSEDED: this wave shipped in v0.48.x. The ACTIVE handoff is
> `docs/HANDOFF-dual-flavor-launch.md` (dual-flavor process + the 2026-11-04 launch
> runbook). Kept for the A-G story detail and decisions of record.

A self-contained spec for a fresh session with none of this conversation's context. Read
every rule; the anchors are quoted strings (search for them - line numbers drift). Written
2026-10-14 by the planning session. Companion to `docs/S13-CROWD-BACKEND.md` (crowd
backend) and `docs/COMPANION-APP.md` (the always-on uploader - a parallel track).

---

## 0. Header - environment, gates, laws

- **Repo:** `E:\Development_Related\development_projects\wowforever_addons\overlay`
  (public: github.com/simulatecx/foresight-forever). **Branch:** `main`.
- **Baseline commit:** `504893f` (the web tally fix). **Version at baseline:** `0.47.1`
  (TOC `## Version:` + `HM.version` in `Foresight/core/init.lua` - keep them equal).
- **Next version:** bump to **"next"** per change size (a feature wave = a minor, e.g.
  `0.48.0`; a lone fix = a patch). Don't hardcode a number from this doc - read the
  current TOC first and increment.
- **Ship gate (THE gate for any addon-logic change):** `python pipeline/run_tests.py`
  - runs compliance -> version-sync -> harvest selfcheck -> selftest. At baseline it is
  **285/285**. Every story adds tests; the target is **+N over whatever the count is when
  you start** (re-pin it - see §1).
- **Deploy addon to the live test client:** `python pipeline/deploy.py` (gate + copy to
  `_classic_beta_`). **Deploy web:** `firebase deploy --only hosting,firestore:rules
  --project wow-foresight`. **Deploy functions:** `firebase deploy --only functions
  --project wow-foresight`.
- **CurseForge release:** tag `vX.Y.Z` and push the tag -> `.github/workflows/release.yml`
  packages + uploads (CurseForge/Wago/GitHub Releases). Only tag after an in-game confirm.
- **House laws that bind every story here (from `CLAUDE.md`):**
  - **The addon NEVER networks.** Official `Interface\AddOns` APIs only; display/advice
    only; no casting/targeting/movement/item-use/macro/automation. Enforced by
    `pipeline/check_compliance.py` (first gate step). Never weaken the banned list to fit
    a feature - redesign the feature. Justified false positives: `-- compliance-allow: <reason>`.
  - **Lua 5.1 dialect** in addon code (no goto, no `//`, no bit ops) - the harness Lua is
    newer, so avoid constructs that differ.
  - **Untrusted-input law:** anything parsing someone else's SavedVariables MUST use the
    neutered Lua sandbox in `pipeline/harvest.py` (gated by `sandbox_selfcheck()`).
  - **overrides.lua changes only via k-of-n confirmation + human-reviewed PR.** The OWNER
    is the exception (trusted fast lane - Story B).
  - **No PII, ever, in the anonymous tier:** no name/realm/account/guild/IP/timestamps/
    free-text. The identifying tier (Story C) is a separate, explicit, off-by-default opt-in.
  - **Confidence tags:** every formula/assumption carries one; unverified-on-Forever says so.
  - **Commits:** plain dash only (no em-dash), NO AI co-author trailers.
  - **Doc spine:** on ship, flip the `SPRINTS.md` story to `☑` + sync the status index,
    add a dated `CHANGELOG.md` entry with a `*Features:*` line, update `FEATURES.md`. All
    three in the same change. No new top-level `.md` without retiring one (docs/ is fine).
- **Launch context (not a hard per-story deadline):** WoW: Forever launches
  **2026-11-04** (Interface 16001). Beta probing happens before then.

## 1. Reconcile BEFORE building (executor's first step)

Re-pin the baseline: read the TOC `## Version:`, run `python pipeline/run_tests.py`, note
the selftest count. If the repo moved since `504893f`, append a dated **BASELINE
RECONCILIATION** block at the TOP of this doc: shift the "+N tests" targets, re-anchor any
quoted string that changed, and mark any story content that shipped in the interim
("already built - do not rebuild" + what remains). Never silently edit the stories below.

## 2. The data model these stories share

The crowd payload is built by an **allow-list** in three mirrors today:
`Crowd.buildPayload` (search `function Crowd.buildPayload` in `Foresight/core/crowd.lua`),
`sanitize` in `web/app.js`, and `validContribution` in `web/firestore.rules`. The rank-rule
display resolves per talent in this order (already built - search `function
F.talentRankValueFor` and `function F.rankRuleSource` in `Foresight/data/formulas.lua`):
datamined `op.values` -> the player's OWN scan (`F.selfVerifiedRule`) -> the shipped
crowd/verified rule (`HM.overrides.rankRules`) -> presumed `(p)`. Captures live at
`HM.db.collect.talentTooltips` (written by `journalTalentTooltip` in
`Foresight/ui/tooltips.lua`); item/buff journals at `HM.db.collect.itemSightings` /
`observedImpacts` (written by `Collect.scanItems` / `Collect.observe` in
`Foresight/core/collect.lua`).

---

## Story A - Single-source the payload allow-list  (PREREQUISITE; do first)

**Goal.** Collapse the 3 (soon 4-5) hand-synced copies of the crowd allow-list into ONE
declarative schema that all consumers derive from, so adding a field (Story C adds
name/armory/buffs) can't drift into a PII leak.

**Fit & Overlap - Category CORE/DATA. Verdict: Enhance** (refactor the existing contract,
don't add a parallel one). Complements CROWD-share + the companion spec. Touches:
`Foresight/core/crowd.lua`, `web/app.js`, `web/firestore.rules`, a new
`data/crowd-schema.json`, `pipeline/`. **Avoid duplicating:** do NOT leave a 4th hand-copy
for the companion/Story C - that's the whole point. Data: no new data, re-expresses the
existing contract. Abuse: n/a (build-time). Mobile/Languages: no UI surface.

**Decisions (final).**
- The schema is **`data/crowd-schema.json`**: allowed keys, types, clamps, caps, and a
  `tier` per field (`anon` | `identifying`). It is the single source.
- The **Firestore rules fragment** (`validContribution` body) is GENERATED from the schema
  by a `pipeline/gen_rules.py` step and written into `web/firestore.rules` between marker
  comments (`// BEGIN generated validContribution` / `// END`). The gate fails if the
  committed rules don't match a fresh generation (drift guard).
- The addon keeps `Crowd.buildPayload` but drives its allow-list from a generated
  `Foresight/data/generated/crowd_schema.lua` (emitted by `pipeline/generate.py` from the
  JSON). `web/app.js` `sanitize` imports a generated `web/crowd-schema.js`.
- One schema edit -> regenerate -> 3 consumers update. Selftest + a rules-parity check gate it.

**Acceptance criteria.**
- ☐ Adding a throwaway field to `crowd-schema.json`, regenerating, and running the gate
  shows it reflected in all three consumers; removing it reverts cleanly.
- ☐ `pipeline/run_tests.py` gains a parity test: the committed `firestore.rules` generated
  block == a fresh generation (fails on drift). +~2 selftest/gate checks.
- ☐ No behavioral change to the shipped payload (same keys as `504893f`); the existing
  crowd selftests (`search "crowd payload: allow-list build"`) still pass unchanged.

**Out of scope.** Changing WHAT is collected (that's Story C). Touching the aggregator.

---

## Story B - Verified table + owner push tool + bake-back  (the core ask)

**Goal.** Make "the owner scans by playing -> every user gets it in-game-ready" real. One
Firebase table holds confirmed rank-rules; the owner pushes to it with their own creds; the
addon ships a bake of it so end users never have to scan.

**Fit & Overlap - Category CROWD -> DATA. Verdict: Enhance** the existing bake pattern
(`pipeline/fetch_baselines.py` -> `peer_baselines.lua`), do not invent a parallel pipeline.
Complements `overrides.rankRules` (hand-curated) - the baked table is the *crowd/owner*
layer beneath it. Touches: `functions/` or `firestore.rules` (new collection), a new
`pipeline/push_verified.py`, `pipeline/fetch_baselines.py` (extend), a new generated
`Foresight/data/generated/verified_rules.lua` + TOC load order, `Foresight/data/formulas.lua`
(consult it). Data: non-identifying rank-rules only (no PII) - classify in the story.
Abuse: table is NOT client-writable (owner/admin only, like `aggregates`).

**Decisions (final).**
- New Firestore collection **`verifiedRules`**, doc id = `talentId`, body
  `{ rule: "perRank"|"maxTotal", n: <votes>, basis: "owner"|"crowd", build: <str> }`.
  Rules: `allow read: if true; allow write: if false;` (written only by the owner's
  gcloud-authed tool / a Cloud Function, never a client - mirror the `aggregates` rule).
- **`pipeline/push_verified.py`:** reads the owner's `ForesightDB.lua` via the harvest
  neutered sandbox (reuse `pipeline/harvest.py`), runs the existing `analyze_rank_rule` +
  `decide_rank_rule` on the owner's captures, and writes confirmed rules to `verifiedRules`
  via Firestore REST with the maintainer's `gcloud auth print-access-token` (the exact
  pattern in `pipeline/fetch_baselines.py` - reuse `access_token()` / `shutil.which("gcloud")`).
  NO service-account creds in the repo.
- **Bake-back:** extend `pipeline/fetch_baselines.py` (or add `fetch_verified.py`) to pull
  `verifiedRules` -> **`Foresight/data/generated/verified_rules.lua`**
  (`HM.gen.verifiedRules = { [talentId] = "perRank", ... }`), added to `Foresight.toc` load
  order near `peer_baselines.lua`. GENERATED - DO NOT EDIT.
- **Consumption:** `F.talentRankValueFor` + `F.rankRuleSource` treat `HM.gen.verifiedRules`
  as the "crowd" tier ALONGSIDE `HM.overrides.rankRules` (overrides wins ties - it's
  hand-curated). Insert the lookup where they currently read `HM.overrides.rankRules`
  (search `HM.overrides.rankRules` in `formulas.lua`). The player's own `selfVerifiedRule`
  still outranks both (local truth). No display-source changes needed beyond "crowd"
  already existing.

**Acceptance criteria.**
- ☐ Running `push_verified.py` against a captured real `ForesightDB.lua` populates
  `verifiedRules` (dry-run flag first, per `safe-data-ops`).
- ☐ The bake writes `verified_rules.lua`; a FRESH character (no local captures) hovering a
  talent the owner verified shows green "rank rule crowd-verified", not "(p)".
- ☐ Resolution order test (extend `selftest.lua`, search `"resolution order: values beat
  override beats default"`): self-scan > overrides > verified_rules > presumed; verified_rules
  > presumed. +~3 selftest checks.
- ☐ Gate green; `verified_rules.lua` ships empty-safe (missing/empty table = today's behavior).

**Out of scope.** Item/buff verification (Story F). Auto-promoting CROWD votes to the table
without review (owner-push only for now; crowd promotion stays the reviewed harvest path).

---

## Story C - Identifying "show-off" tier: named leaderboards + buff provenance  (items #2+#3)

**Goal.** Let players who want the spotlight appear by a chosen handle on per-metric
leaderboards (e.g. "Biggest Armor"), with the buffs they had at submission shown so records
are honest ("buffed send"). Everyone else stays anonymous, unchanged.

**Fit & Overlap - Category CROWD. Verdict: Enhance** CROWD-share (new tier on the same
contract). Touches: `crowd-schema.json` (Story A - new `identifying`-tier fields),
`Foresight/core/crowd.lua` + settings (capture handle/armory/buffs), `web/firestore.rules`
(conditional allow), `functions/index.js` (named top-N), `web/` (leaderboard UI + consent),
`privacy.html` (same change). **Data (classify):** `name`/`armory` = direct PII, identifying
tier, opt-in off-by-default; `buffs` = non-identifying game data. **Abuse:** named writes
could be spoofed/spammed -> per-clientId rate limit + length caps + the handle is display-only
(never trusted as identity). **Mobile:** leaderboard must read at 1280x720 / 0.65 UI scale.
**Languages:** all strings in DOM text nodes, full sentences.

**Decisions (final).**
- **Handle, not real name (DEFAULT).** Collect a user-chosen `name` (handle) + optional
  `armory` URL. OWNER DECISION PENDING (planner asked; not answered): if the owner wants the
  real character name/realm instead, it rides the SAME opt-in gate - do not change the
  gating, only the field source. Default to handle+armory until the owner says otherwise.
- **Gating:** new payload field `named: true` unlocks `name`/`armory`. Rules: `name`/`armory`
  allowed ONLY when `named == true` (else `hasOnly` forbids them). `buffs` is allowed in the
  anon tier too (it's game data) - a list of spellIds (or `{id,name}`), capped (<= 40).
  Caps: `name` <= 32 chars, `armory` <= 200 chars + must match an allow-listed host pattern.
- **Backend:** `functions/index.js` keeps a `leaderboards/<metricKey>` doc with top-N
  (N=25) entries `{ value, class, level, name, armory, buffs }` drawn ONLY from `named`
  submissions; anonymous submissions still feed the quantiles but never a named row.
- **Web:** a new "Champions" / general leaderboard section per featured metric showing
  name + class color + value + a buff row; anonymous records (the quantile max) show as
  "Anonymous". Reuse `metricLabel`, `classColor`, the `.ladder-card` styles.
- **Consent:** the in-game opt-in (settings toggle, default OFF) and the web consent line
  both say plainly "your handle and build will be shown publicly on the ladders." Revocable.
  Update `web/privacy.html` in the same change (policy-practice sync law).

**Acceptance criteria.**
- ☐ Default (no opt-in): payload carries NO name/armory; rules REJECT a forged named write
  without `named==true` (add a rules/selftest fixture - search `"crowd payload: allow-list
  build"` for the pattern). The anonymous promise is provably intact.
- ☐ Opt-in: a `named` submission appears on the web leaderboard with handle + buffs; an
  anonymous one never shows a name but still counts.
- ☐ Buff provenance renders for a record ("with: Flask of ..., Blessing of ...").
- ☐ Mobile check at 1280x720 / 0.65 UI scale (addon) and a narrow viewport (web).
- ☐ `privacy.html` updated. Gate green. +~4 selftest/rules checks.

**Out of scope.** Real-name/realm unless the owner opts in (default handle). Auth'd user
accounts. Editing/claiming past anonymous entries.

---

## Story D - `/foresight coverage` + inspect-scan readout

**Goal.** Show the owner how much of the all-class talent roster they've captured/verified,
so they can target the gaps (by inspecting other-class players, which already captures).

**Fit & Overlap - Category UI/QA. Verdict: Enhance** the slash dispatcher (search
`elseif cmd == "verify"` in `Foresight/core/init.lua`) + `Collect`. No UI frame needed
(chat output). Touches: `Foresight/core/init.lua` (new `coverage` subcommand),
`Foresight/core/collect.lua` (a coverage tally helper), `Foresight/ui/tooltips.lua`
(inspect-capture already fires via the `SetOwner` hook - add a once-per-target print).

**Decisions (final).**
- `/foresight coverage` prints: `<captured>/<total multi-rank talents> captured across
  <classes> classes; <verified> verified (own scan + shipped); missing classes: <list>`.
  Total roster from `HM.gen.talents` (multi-rank only); captured from
  `HM.db.collect.talentTooltips`; verified from `F.selfVerifiedRules()` + the shipped tables.
- Inspect-scan: when `journalTalentTooltip` writes a capture whose owner is an INSPECT
  frame (not the player's own tree), emit at most one throttled line per inspected unit:
  "captured N talents from an inspected <class>." (Capture already happens; this is just the
  readout.) Must not spam or touch any protected path.

**Acceptance criteria.**
- ☐ `/foresight coverage` prints a correct tally against a known capture store (selftest with
  a fixture store). ☐ Inspecting another class increases the count. +~2 checks. Gate green.

**Out of scope.** A coverage UI panel (chat line is enough for v1).

---

## Story E - Zero-click self-verify (auto-probe on talent frame open)

**Goal.** "Nobody wants to scan" - so verify everything trained the moment the talent/spec
frame opens, no hover, no command.

**Fit & Overlap - Category CORE. Verdict: Enhance** (`Collect.probeTalentTooltips` already
exists - just auto-trigger it). Touches: `Foresight/ui/tooltips.lua` or `core/collect.lua`
(hook the talent/spec frame `OnShow`). **Account-safety:** `probeTalentTooltips` is a
read-only tooltip scan (`tip:SetTalent`) - confirm it carries no taint before auto-firing
(it runs today on `/foresight verify`). Throttle: once per frame-open, debounced; never
while in combat.

**Decisions (final).** Hook the Blizzard talent/spec frame `OnShow` (resolve by the frame
names already referenced - search `"PlayerSpellsFrame"` / `"ClassTalentFrame"` in
`Foresight/core/collect.lua`). On open (debounced, out of combat) call
`Collect.probeTalentTooltips`. A setting `autoVerify` (default ON) gates it.

**Acceptance criteria.**
- ☐ Opening the talent frame flips trained talents to "verified from your scan" with no hover
  and no command. ☐ No taint / no protected-action error on a controller (in-game check).
  ☐ `autoVerify=false` restores manual-only. Gate green; +~1 check.

**Out of scope.** Auto-probing on login (frame-open is enough; avoid a login hitch).

---

## Story F - Backend aggregation of items + observed buffs

**Goal.** Turn the raw `items`/`observed` rows (already arriving since v0.47.0) into
something usable: item popularity + crowd-verified buff values (the data that corrects
presumed values).

**Fit & Overlap - Category CROWD. Verdict: Enhance** `functions/index.js`. Touches:
`functions/index.js`, possibly `verifiedRules` (Story B) for buff values. **Data:** item ids
+ counts, buff spellId + stat values - non-identifying. k-of-n before any observed buff value
is treated as verified.

**Decisions (final).** Aggregate `items` into `aggregates`/`itemPopularity` (counts per
item per class/level). Aggregate `observed` into candidate buff-value records; a value with
`n >= K` (K=5) and low variance becomes a verified buff value (feeds overrides via the
reviewed harvest, NOT auto-shipped). Document the k-of-n in `docs/S13-CROWD-BACKEND.md`.

**Acceptance criteria.** ☐ Contributed items/observed produce the new aggregates (emulator
or a test write). ☐ Suppression + dedup-by-clientId preserved. ☐ No PII. Gate (functions
have their own checks; at minimum lint + a local run).

**Out of scope.** Auto-promoting observed values into shipped overrides without review.

---

## Story G - Restore App Check on writes  (when unblocked)

Small. When Firebase App Check backend validation is fixed (it currently won't set
`request.app` on writes - see the comment block in `web/firestore.rules`, search
`appChecked()`), restore `&& appChecked()` on the `contributions` + `feedback` create rules
and remove the "temporarily relaxed" comments. AC: a write with a valid token succeeds, one
without fails; re-verify in a browser. No addon change.

---

## Global out-of-scope (do NOT build)

- Any network/automation/memory/input path in the ADDON - ever (the companion app in
  `docs/COMPANION-APP.md` is the only networked piece, and it's a separate process).
- Service-account / Admin SDK credentials in the repo.
- Real-name/realm collection unless the owner explicitly opts into it (Story C default is a
  handle).
- Weakening `check_compliance.py`'s banned list or the `hasOnly` shape-lock to fit a feature.
- Auto-promoting crowd votes into `overrides.lua` without k-of-n + human review.

## Done criteria (whole wave)

- Gate green at each story; selftest count up by the per-story deltas.
- In-product verification per story (the ☐ in-game / in-browser checks above), not just unit
  tests.
- Doc spine closed per story: `SPRINTS.md` story -> `☑` + status index, dated `CHANGELOG.md`
  entry with `*Features:*`, `FEATURES.md` entry. Same change as the code.
- CurseForge: tag only after an in-game confirm of that version.

## Coverage / roster declaration

All stories serve **all 9 Forever classes**. Story B's verified data and Story C's
leaderboards are class-agnostic (keyed by class/metric). Honest degrade: a class/talent with
no verified rule shows `(p)` presumed and self-verifies locally when that player trains it
(the existing fallback). No story narrows class parity.

## Paste-ready doc-spine snippets (executor pastes on ship)

CHANGELOG entry skeleton (fill version/date/IDs):
```
## X.Y.Z - 2026-MM-DD

<player-facing summary of the stories shipped in this version>

*Features:* <IDs, e.g. CROWD-share, DATA-formula-registry, CROWD-companion>
```

FEATURES: enhance the existing `CROWD-share` + `DATA-formula-registry` + `DATA-overrides`
entries (Stories B/C/F) and add `☑ UI-coverage` under `## UI` (Story D) and a note on
`CORE` auto-verify (Story E). Do NOT add net-new top-level docs.

SPRINTS: one story block per Story above, in the house format (`As a <role>, I want ... so
that ...` + AC + the Fit & Overlap line already written in each story here), flipped `☑` on
ship with the status index synced.
