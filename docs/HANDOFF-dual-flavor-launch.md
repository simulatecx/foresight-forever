# HANDOFF - Dual-flavor development + the Forever launch runbook

Written 2026-10-22 at v0.53.0 (main 4b4bb7c). Supersedes `HANDOFF-next-build-wave.md`
(that wave shipped in v0.48.x) as the active handoff. Two jobs:

1. **Streamline how Classic and Forever are developed together** - the laws that keep one
   codebase serving two games without forking or silently breaking either.
2. **The launch process for Forever going live 2026-11-04** - what must land before, what
   happens on the day, and what the first weeks look like.

Authority order: `SPRINTS.md` > this doc > memory. If they disagree, SPRINTS wins.

---

## Part 1 - The dual-flavor relationship

### 1.1 The architecture in one paragraph

ONE repo, ONE CurseForge project (1744126), TWO TOCs - never a branch, never a second
repo. `Foresight/Foresight.toc` (Interface 16001) loads `data/generated/`;
`Foresight/Foresight_Vanilla.toc` (Interface 11509) loads `data/generated_classic/` and
deliberately skips Forever-only files (forever_talents, tf_talents, verified_rules - an
empty-but-truthy table would defeat runtime fallbacks). The BigWigs packager auto-detects
both TOCs and ships one zip whose release.json marks both flavors; CF lists both games
from the one upload. Both TOCs carry the same `X-Curse-Project-ID`.

### 1.2 The flavor laws (what keeps this from rotting)

- **Branch on `gen.flavor`, never on build strings or table presence.** `build.lua`
  stamps `flavor = "forever"|"classic"`; runtime code asks `HM.gen.flavor`. The one
  lesson behind this: classic shipped 9 junk stub TraitNode rows that made "any trait
  nodes present?" lie - now generate.py scrubs classic traits AND code checks the stamp.
- **Cross-flavor features walk `HM.formulas.impactNodes()`** (trait nodes on Forever, a
  talent view keyed by talentId on classic). Synergy, chains, catalog, mapping, and plan
  all ride it. A new feature that iterates "impact sources" uses impactNodes(), not
  `gen.traits.nodes` directly.
- **Flavor-semantic decodes live in generate.py behind the module-global `FLAVOR`**
  (set from `--flavor`). Current examples: vanilla magnitudes are bp+DieSides
  (`eff_magnitude`), classic ships NO spell coefficient (the 1.15 column is wrong;
  runtime derives castTime/3.5, (p)-tagged), and vanilla hardcodes auras 174/175 to
  Spirit (the 0.53.0 Spiritual Guidance fix). When a classic decode disagrees with the
  modern shape, pin the VANILLA truth and comment why.
- **Forever-only surfaces degrade honestly on classic, never error**: no tf text, no
  verified_rules, no trait overlay (PlayerSpellsFrame absent so hooks never engage).
  The pattern is nil-guard + skip, with the feature's absence invisible, not broken.
- **Id spaces don't mix.** A classic talentId and a Forever trait nodeId can collide
  numerically - never pass one into the other flavor's index (the talentLines synergy
  block is flavor-gated for exactly this reason).

### 1.3 The test contract (how both flavors stay green)

`python pipeline/run_tests.py` IS the ship gate and runs BOTH flavors - a fresh Lua VM
per TOC, loading exactly what that TOC lists. Current counts: Forever 304, Classic 259.

- **Forever data pins** (counts, names, ids that only exist in the Forever dataset) are
  wrapped `if not isClassic then -- Forever data pin (S43 classic-gated)`.
- **Every gated pin should prompt the question: is there a classic TRUTH to dual-pin?**
  The duals are where classic correctness actually lives: 8 races exactly, Mongoose = 1
  hour, Fireball 14-22 with no stored coef, FT1 plain prefix, Divine Spirit chaining
  through Spiritual Guidance. A gated pin with no dual means classic is untested there.
- `version_sync_check` enforces both TOCs == `core/init.lua` HM.version. **A version
  bump touches exactly 3 files** (both TOCs + init.lua); the gate refuses otherwise.
- `pipeline/deploy.py` verifies BOTH TOC layouts post-copy (vanilla optional if absent).

### 1.4 Data refresh - the asymmetry to fix

Forever is automated; classic is manual. This is the main streamlining gap.

| | Forever | Classic Era |
|---|---|---|
| Source product | wago.tools, prefix `1.60.` | wago.tools `wow_classic_era`, prefix `1.15.` |
| Current build | 1.60.1.70450 (DEFAULT_BUILD) | 1.15.9.70003 (manual `--build`) |
| New-build detection | `check_updates.py` + daily `data-freshness.yml` -> review PR | **NONE** (zero classic coverage in CI) |
| Regenerate | `python pipeline/fetch.py && python pipeline/generate.py` | `python pipeline/fetch.py --build 1.15.9.70003` then `python pipeline/generate.py --build 1.15.9.70003 --flavor classic` |

**Backlog item (S43 follow-up, do before launch if time allows, after launch otherwise):**
extend `check_updates.py` with a classic mode (scan `1.15.` prefix, separate
DEFAULT_BUILD constant or a `CLASSIC_BUILD` pair in fetch/generate) and add a second job
to `data-freshness.yml` mirroring the Forever one (detect -> fetch+generate --flavor
classic -> git-diff gate -> dual ship gate -> review PR). Nothing auto-ships either way;
the owner reviews and tags. Classic patches rarely (1.15.x is stable), so this is a
safety net, not a treadmill.

### 1.5 Feature development process (the per-feature checklist)

Run feature-triage as always (FEATURES.md category -> overlap -> enhance-over-net-new),
plus the flavor questions:

1. **Which flavors get it?** Default BOTH via impactNodes()/shared models. Forever-only
   (trait UI, tf text, verified rules) must nil-degrade on classic. Classic-only is rare
   (vanilla-truth decodes).
2. **Where does its data come from per flavor?** Shared generated tables, or does
   generate.py need a FLAVOR branch? If the classic column differs in MEANING (not just
   name), pin vanilla truth with a comment + a dual test.
3. **Does it add selftest pins?** Gate Forever-dataset pins; write the classic dual if a
   classic truth exists.
4. **UI surfaces follow the wow-ui-ux skill** (window taxonomy, measured rows, wrap laws,
   taint isolation) - both clients, same code; the classic client is also modern-engine
   so the frame API is shared.
5. **Ship**: dual gate green -> deploy.py -> doc spine (SPRINTS ☑ + CHANGELOG with
   *Features:* IDs + FEATURES entry) -> RELEASE_NOTES rewrite PRE-tag -> bump 3 files ->
   tag -> verify the shipped zip (both TOCs, no leaks, release.json both flavors).

### 1.6 Crowd data - the one place flavors MUST NOT mix (pre-launch blocker)

The `/foresight share` payload already carries `build` (32-char client build string), so
flavor is derivable server-side (`1.60.` vs `1.15.`). But the Cloud Function aggregation
(functions/index.js) buckets by class/spec/level only - **classic contributions would mix
into Forever brackets** and poison percentiles both ways. Before classic users contribute
at any real scale (realistically: before launch-week publicity):

- Aggregation keys gain a flavor dimension (derive from the build prefix; unknown ->
  reject or bucket "other", never merge).
- `fetch_baselines.py` bake + `peer_baselines.lua` + the in-game peer readout carry the
  flavor key through (the addon knows its own flavor from gen.flavor).
- firestore.rules unchanged (build is already in the allow-list shape).

This is backend + bake only - no addon payload change. It is the ONE hard technical
gate in Part 2's pre-launch list.

---

## Part 2 - The Forever launch process (2026-11-04)

### 2.0 The shape of the window

Beta ENDED 2026-10-21. From now until launch there is NO live Forever client to verify
against - but **Classic Era is live today**, and the classic flavor can be verified
in-game on anniversary realms right now. Use the dark window for classic verification,
backend work, and launch prep; expect a NEW Forever client build on or near launch day.

### 2.1 Pre-launch (now -> Nov 3), in priority order

1. ☐ **Crowd flavor-bucketing** (1.6 above) - the only hard blocker.
2. ☐ **Owner in-game verify of the 0.53.0 UI wave** on either client: Matrix collapse
   chevron, close-both/pin flow, forge chrome, Shift-gated hover depth (built blind
   against the gate).
3. ☐ **Classic live-verification pass** (Classic Era realms are up NOW): planner trees,
   talent hovers (Synergy/Chains lines), item verdicts, `/foresight selftest` in-game,
   scans upgrading (p) tags. Every classic-presumed formula verified now is one fewer
   launch-day unknown.
4. ☐ **Classic build watch in CI** (1.4) - nice-to-have before launch.
5. ☐ Owner account items: CF listing description + talentsforever credit text, logo,
   X-Wago-ID (needs a Wago project + WAGO_API_TOKEN), App Check `&& appChecked()`
   restore check (was pending backend token propagation), reddit app creds (parked).
6. ☑ **Dry-run of the launch-day runbook: RAN FOR REAL 2026-10-29.** The live `wowf`
   client (1.60.1.70685) installed to `_forever_` and Classic Era 1.15.9.70576 to
   `_classic_era_`; check_updates --apply, both flavors refetched+regenerated, tf
   refreshed, dual gate green with ZERO fixture re-pins, deploy.py retargeted to both
   live installs (beta retired) and deployed layout-verified. Diff of record: Frost Mage
   rework (Piercing Ice removed, Winter's Chill -> Fingers of Frost, Ice Barrier
   redesigned+decoded, Frost Blast coef 0.343 -> 0.271), warlock curse consolidation,
   itemization polish; classic content unchanged. TAG HELD for the owner's in-game verify.
7. ☐ RUN addon (separate track, ARR, shares the Firebase): launch-gated; its kickoff is
   its own plan ([[run-addon-plan]] in memory / SPRINTS S35-RUN). Don't let it steal
   launch week.

### 2.2 Launch-day runbook (Nov 4, in order)

The S41 patch-day playbook, hardened. Expect a new client build + balance changes +
possibly renamed/moved APIs.

1. **Detect**: `python pipeline/check_updates.py` - it scans ALL wago.tools products for
   the `1.60.` prefix (builds have MOVED between products before; never assume the old
   product). If a new build: `--apply` bumps DEFAULT_BUILD in fetch/generate/audit.
2. **Refresh**: `python pipeline/fetch.py` -> `python pipeline/generate.py`. Classic is
   UNAFFECTED by the Forever launch (different product); do not touch it unless 1.15
   also shipped.
3. **Review the generated diff like a hawk** (git diff of data/generated/). The S41
   lessons: aura ids can SPLIT (22 -> 674 armor), spells get renamed/rebalanced, and
   selftest fixtures pinned on live spells break on balance changes - re-pin fixtures to
   surviving carriers, never loosen the assertion.
4. **tf refresh**: `fetch_talentsforever.py --force` - but client data is the real patch
   signal; tf re-exports lag (S41: zero content change on patch day).
5. **Gate**: dual gate green. Red = fix before anything ships; the gate catching a
   decode break on patch day is it working.
6. **Deploy + live verify on the LAUNCH client** (first non-beta session):
   `deploy.py`, then in-game `/foresight selftest`, `/foresight verify`,
   `/foresight audit` (rendered-tooltip sweep vs our envelopes), a talent hover pass,
   an item hover pass. Watch two journals specifically: **apiWatch drift** (launch
   client may rename C_ paths - the GetItemInfo ambush class) and the **taint sentinel**
   (any ADDON_ACTION_BLOCKED naming Foresight).
7. **Scan to upgrade (p)**: trained talent hovers + the auto-verify pass settle rank
   rules against the LAUNCH client; harvest -> promote -> `push_verified.py --write`
   (gcloud re-auth first - tokens last ~1h) -> `fetch_verified.py` bake.
8. **Ship**: RELEASE_NOTES rewrite -> bump 3 files -> CHANGELOG/SPRINTS/FEATURES ->
   dual gate -> tag `vX.Y.Z` -> push -> watch release.yml -> **download the zip and
   layout-verify it** (both TOCs, no leaks, release.json both flavors). This last step
   is law (the v0.49.0 broken-zip incident).

### 2.3 Launch week + after

- **data-freshness.yml daily** keeps catching Forever hotfix builds -> review PRs;
  launch week will likely produce several. Same diff-review discipline each time.
- **Crowd watch**: first real contribution volume. Watch bucket counts, small-bucket
  suppression behavior, and that flavor bucketing holds. First real
  `fetch_baselines.py` bake -> peer_baselines.lua ships in the next tag -> the in-game
  "Among your spec" readout goes live for real.
- **User reports**: `/foresight report` journals + harvest surface them; triage into
  SPRINTS. Expect the launch population to find what the two-pilot beta couldn't.
- **Hardcore kickoff ~2026-12-04** is the second wave (and the RUN addon's seasonal
  reset moment) - keep the launch-week fixes flowing so the codebase is calm by then.

### 2.4 Standing constraints (unchanged by launch, listed so nobody relearns them)

- Suggest-only / no automation; account-safety doctrine; taint laws (anchor, never
  parent; no key writes on Blizzard objects; no CSI calls; no math.random). The
  compliance gate enforces all of it - never weaken the banned list.
- Untrusted-input laws: SavedVariables type-validated; imports are data-only parsing.
- Crowd data: no PII, no real names; named ladders are the separate opt-in tier.
- Credit talentsforever.com while shipping their JSON.
- `.pkgmeta`: no inline comments in the ignore list; repo-root `data/` stays ignored.
- Nothing ships without the dual gate + a tag; deploy.py is the ONLY local installer.
