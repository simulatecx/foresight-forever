# Foresight - Model Validation One-Pager (hand to an external reviewer)

v0.33.0, build 1.60.1.70338, selftest 219/219. Repo: github.com/simulatecx/foresight-forever.
Scope of this check: HOW the model claims WoW skills / talents / items impact a character -
find anything missed or mis-chained. Rules for the reviewer: cite file:line for every claim;
if you cannot see the file, say "not verified" instead of confirming; do not credit
remediations you cannot point at (prior review hallucinated three).

## The impact chains (what moves what)

1. ITEM -> stats -> graph -> outcomes. `GetItemStats` keys map to model stats
   (`ui/tooltips.lua` ITEM_STAT_MAP: primaries, spell/healing power, AP/ranged AP,
   mana/health, armor). Unmapped keys are JOURNALED, never silently dropped. Each stat is
   a graph node (`model/loadout.lua`); dimension lenses read nodes (`graph/dimensions.lua`);
   verdict = diff of equip-vs-equipped (`model/impact.lua itemVerdict` - the ONE judge).
   WEAPONS additionally compare BASE damage/speed scanned off both rendered tooltips:
   white DPS = baseAvg/speed + AP/14, both items' AP-equivalent stats netted
   (`model/sim.lua weaponSwap`/`apFromStats`); for melee goals this replaces the stat-only
   lens pct. Known limits: main-hand only; crit/haste/hit RATINGS deferred (no conversion
   law yet); offline item damage needs unfetched ItemDamage* DB2s.
2. TALENT -> ops -> rank value -> graph + abilities. Pipeline decodes SpellEffect rows of
   talent spells into typed ops (`pipeline/generate.py build_ops`): stat/schoolDamage/
   spellmod(+affected spell edges via class masks)/statConvert/threat/crit/etc. Rank
   magnitude resolves through ONE path (`data/formulas.lua talentRankValueFor`):
   datamined per-rank values (31 talents whose rank spells all carry aligned rows) >
   crowd-verified rule from captured tooltips (overrides.rankRules, 11 promoted, all
   trained-capture-backed) > presumed global rule, tagged (p). Live talents are C_Traits
   nodes; classic-overlap nodes bridge by spellID.
3. SKILL -> decoded base -> composed hit. Per-spell dmg/heal {base, var, lvl, maxLvl,
   coef} + wpn {pct, flat, norm} + dotTick decoded from SpellEffect (modern layout: NO
   EffectDieSides; spread = Variance; real coefficients in EffectBonusCoefficient on
   Effect 2/10 rows only). `Sim.abilityHit` composes: (base range at level + power x
   coefficient) x (1 + selected %dmg spellmods) + flat mods; weapon instants ride the
   LIVE weapon range with the snapshot-AP term substituted at normalized speed (Effect
   121) or marginal-AP at actual speed (17/58). Display = widest integer envelope
   (floor min / ceil max - live-verified vs Lightning Bolt r2 "25 to 30").
4. BUFFS / RACIALS / IMBUES fold through the same op shapes; live snapshot already
   contains own racials + active buffs, so folds are marginal-only (double-count law).

## Confidence + verification machinery

Every number is (a) datamined (generated tables, channel-stamped), (b) live-read
(snapshot), or (c) a tagged law in `data/formulas.lua` {fn, confidence, source} with (p)
shown until verified. Verification loops: 219-check headless selftest incl. classic
ground-truth data gates (gate = compliance scan + Lua 5.1 dialect lint + version sync +
sandboxed harvest selfchecks); `/foresight audit` scans the game's OWN rendered spell
tooltips for every known decoded spell and auto-verdicts each vs base and vs
gear-composed envelopes (also settles whether Forever folds gear into tooltips); captured
talent tooltips vote per-talent rank rules (trained captures = ground truth, no-downgrade
law); observed buff impacts auto-compare vs generated. Promotions into overrides are
k-of-n + human-reviewed, never automatic.

## Micro-check questions (answer each with file:line or "not verified")

1. Chain completeness: name any way an ITEM changes a classic-era character that the
   item chain above cannot represent (procs/use-effects/set bonuses/weapon skill...)
   and whether we DEGRADE honestly (no claim) or MIS-claim for it.
2. Same for TALENTS: op kinds in `build_ops` vs reality - what passive effect types are
   missing, and do they land as "unmapped" (honest) or wrong-bucket?
3. Is the spellmod composition order (base + power*coef, then %mods, then flat) the
   server's order? Any known classic case where flat mods apply before coefficients?
4. Weapon math: any AP double-count or omission in weaponSwap/abilityHit given UnitDamage
   already folds AP at actual speed?
5. Rank resolution: any path where a surface could show a rank value NOT routed through
   talentRankValueFor?
6. The audit's "base vs gear" discriminator: is tooltip-folds-gear plausibly per-spell
   rather than global on Mainline-API clients? What would that do to our verdicts?
7. What single missing conversion law most limits item verdicts today? (Our answer:
   combat ratings. Challenge it.)
8. Anything in the chains that contradicts classic-era mechanics we have marked
   verified rather than (p)?
