# Retail Validation Fork - Handoff (written 2026-10-12, base v0.36.0)

GOAL (user directive): fork Foresight onto live WoW RETAIL, where every number is
public and verifiable TODAY, to validate the calculation engine against real data -
then port the verified fixes back to the Forever fork so the Nov 4 launch starts
with proven math and the crowdsourcing loop opens on day one.

WHY THIS FORK IS CHEAP: Forever already runs the Mainline 12.x addon API. The entire
adapter layer (C_Traits talent walk, C_Item shims, tooltip hooks, taint isolation,
combat gates) was built FOR this API family. A retail fork swaps DATA and formula
VALUES, not architecture. Read `docs/ARCHITECTURE-AUDIT-2026-10-12.md` first - the
layer map and coupling census there define what moves and what must not.

## What retail CAN validate (the point of the fork)

1. The DECODE LAWS: modern SpellEffect layout (bp/Variance/EffectBonusCoefficient/
   ppl/MaxLevel), weapon effects 17/31/58/121, the totem grants chase - retail uses
   the SAME DB2 format, and retail tooltips are ground truth at every level.
2. The COMPOSITION: Sim.abilityHit (base + power x coef, normalization substitution,
   spellmod folds), Sim.weaponSwap (white-DPS law + AP-equivalent netting), the
   floor/ceil display envelope - all verifiable via `/foresight audit` (scans the
   game's OWN rendered tooltips for every known decoded spell and verdicts base vs
   gear-composed envelopes; it also settles whether tooltips fold gear per client).
3. The PLUMBING: item mapper key coverage (unknownItemStats journal), itemKey
   identity, baseline/swap-relative laws, tooltip injection, overlay taint isolation
   (retail talent UI = same PlayerSpellsFrame family), the harvest loop end to end.
4. The HARNESS: gate, selftests, apiWatch drift detection on a fast-patching client.

## What retail CANNOT validate (do not port these back)

- Classic-era formula VALUES: manaRegenTick/healthRegenTick (retail regen is a
  different system), statConversions (retail has no classic AP-per-Str rates),
  weaponNormalization constants, critMultiplier (retail crit laws differ by spec),
  armorMitigation K-values, the talent rank-rule system semantics (retail has no
  classic Talent.csv ranks). On the retail fork either swap in retail laws or set
  confidence tags honestly ("not-modeled-on-retail") - NEVER let a retail value flow
  back into the Forever fork's data or formulas.
- data/: generated tables, overrides.lua, loops.lua are per-game. Never cross.

## Fork procedure (step by step)

1. Fork the repo (new remote, e.g. foresight-retail). Keep the name/brand; set
   `## Interface:` from retail's `select(4, GetBuildInfo())` and update
   `DEFAULT_BUILD`/`DEFAULT_CHANNEL="retail"` in pipeline/fetch.py + generate.py.
2. `python pipeline/fetch.py --build <retail build>` - wago.tools hosts retail; the
   table list is identical. Then `generate.py`. EXPECTED DELTAS: classic Talent.csv
   is legacy/empty on retail -> talents_out ~0 (fine: traits.lua carries everything;
   the C_Traits adapter is the live path already); racial/consumable/imbue decodes
   should populate; spell decode counts will be much larger.
3. Run the gate. Selftest data gates pinned to Forever values (Fireball 14-22, SoE
   8075, LB 529 etc.) will RED - re-pin them to retail ground truth (same checks,
   retail constants). This re-pinning IS part of the validation: if a gate can't be
   satisfied by retail data, the decode law was Forever-specific and we learned
   something.
4. Formula values: swap or honestly tag per the cannot-validate list above. The
   registry structure, resolution paths, and (p) machinery stay untouched.
5. data/loops.lua: either curate 2-3 retail loops or ship empty (the Matrix degrades
   honestly).
6. In-game validation protocol, in order: `/foresight verify` (apiWatch absences
   first - fix shims) -> `/foresight audit` (the mass tooltip compare; iterate until
   mismatch=0 or every mismatch is understood) -> `/foresight hit` on 5+ abilities
   across two classes -> weapon-swap hovers vs the game's own comparison numbers ->
   `/foresight focus` + Matrix render -> logout -> `python pipeline/harvest.py`
   (reports/taints/drift all surface there).

## Port-back protocol (retail -> Forever)

- PORT: engine fixes (model/, graph/, pure ui models), pipeline decode fixes,
  adapter fixes (client.lua shims, scan patterns, hook correctness), new selftest
  checks (re-pinned to Forever constants when data-bound), harness improvements.
- NEVER PORT: anything under data/, formula VALUES, re-pinned gate constants.
- Mechanics: cherry-pick commits touching engine/pipeline files only; both forks keep
  the same gate so a clean cherry-pick is provable (`run_tests.py` green on both).
- Timeline: fork + validate before 2026-11-04; on Forever launch day, fetch the live
  build, regenerate, run the (already-validated) audit in-game, flip
  DEFAULT_CHANNEL="live", and open crowdsourcing (the harvest loop is already
  multi-account; contributors run harvest.py and submit JSON - the addon never
  networks).

## Known traps for the forking agent

- Lua 5.1 only even though retail's client is newer-Lua-tolerant in places - keep
  the dialect lint green so the Forever port-back never breaks.
- pcall does NOT contain protected-API blocks: presence-check, never call, anything
  possibly protected (the apiWatch pattern).
- Never compare item links by raw string (use Tooltips.itemKey).
- Trained talent-tooltip captures are ground truth - the no-downgrade law must
  survive any capture changes.
- The compliance gate + taint isolation laws are non-negotiable on BOTH forks: no
  frame parented into Blizzard trees, no key written onto Blizzard objects, all
  talent-UI touches combat-gated.
