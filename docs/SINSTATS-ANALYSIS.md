# SinStats analysis -> Foresight cap & boss-frame insights (2026-11-10)

Owner: "we downloaded SinStats (character stats) - don't explore all their code,
but understand if we can take inspiration from their tips/recommendations
relevant to the character, and build a plan to incorporate."

Analyzed from the installed addon (v7.1000 by Sinba, CurseForge 389802,
multi-flavor incl. a native **Forever TOC at Interface 16001** and Classic Era
11509). License: **All Rights Reserved** - mechanism inspiration only, zero code
reuse (the same posture as the QuestieTrace analysis in the RUN repo).

## What SinStats actually does (the finding)

Their "tips/recommendations" are NOT coaching text. The product is **derived,
actionable stat readouts** the stock UI hides, delivered as an always-on
configurable HUD (fonts/bars/profiles). The advisory value is three mechanisms:

1. **The boss frame.** Every chance stat (crit, hit, miss) renders against TWO
   reference targets - **same-level** and **boss-level (+3)** - selectable per
   stat (`Level_Same_Boss` in their stat defs). When a real target exists, its
   actual level replaces the assumption. One stat, two truths: "crit 7.2% /
   vs boss 5.9%".
2. **Cap distance.** Chance stats display as progress-toward-cap with bars
   (`Cap_Percent`, a dedicated `CritCap` row, expertise cap). The readout IS
   the recommendation: how far from capped, visually.
3. **Weapon-skill-aware miss math.** The classic miss tables computed honestly:
   target defense (level x 5) vs the ACTUAL equipped-weapon skill
   (`C_SkillInfo.GetSkillLineInfoByID`, feral-combat special case), the >10
   skill-diff breakpoint (miss grows 0.4/point instead of 0.1), the dual-wield
   base-miss penalty (26 vs 24 base with an off-hand weapon), hit% folded in.

Secondary patterns worth noting:
- **Secret-value cache**: `GetHitModifier()` can be secret in restricted
  content; they cache the last READABLE value so the display degrades to
  stale-but-valid instead of blank. (Our Guards doctrine degrades to omission;
  their pattern is a candidate Guards enhancement but is a doctrine change -
  owner call, not part of this story.)
- **Their Forever port is API-shape evidence**: `C_SkillInfo`, `GetHitModifier`,
  `Enum.ItemWeaponSubclass` all presence-confirmed on 16001 by a live shipped
  addon (corroboration like forever-addon-kit - evidence, never a source).

## What Foresight has vs what's missing (duplication check, confirmed in code)

Already ours (do NOT rebuild): crit percentages in the snapshot
(`model/snapshot.lua` GetCritChance/GetSpellCritChance/GetRangedCritChance),
stat marginals (`Impact.rankStats` "+0.5%/pt"), the insights engine
(`model/insights.lua` archetype/gear-alignment/coaching), ability-level crit
folding (formulas), spec profile, the stats panel + Matrix surfaces.

Missing (the gap this fills): **no hit%, no miss model, no weapon skill, and no
cap concept anywhere in the model.** Verified: no capDistance/hit-cap/
weapon-skill hits in `Foresight/` outside incidental words. SPRINTS S54's
insight roadmap item (1) "cap/threshold distance" is the groomed placeholder -
this analysis turns it into a story (S56).

## What we take, reframed for Foresight's altitude

SinStats SHOWS numbers; the S54 research verdict was that the vacant layer is
WHY/SO-WHAT interpretation. So we do not clone readouts - we fold caps into the
impact graph so every existing surface gets smarter:

1. **Cap-distance insight** (their mechanism 2 + our WHY): "You're 2% short of
   the boss spell-hit cap - +Hit is your best Frostbolt stat until then"
   (Insights line + first-run; the which-stat half comes free from rankStats).
2. **The boss frame** (their mechanism 1): chance stats and ability-hit lines
   framed vs same-level AND vs +3 boss on the existing panel/tooltip surfaces.
3. **Cap-aware marginals** (the differentiation NOBODY has): `Impact.rankStats`
   zeroes/flags a stat's marginal PAST its cap - "+1% hit does nothing, you're
   capped" - which also powers the dead-investment story (roadmap item 2) later.
4. **Weapon-skill truth** (their mechanism 3): weapon skill as a first-class
   stat node with the breakpoint math, so the marginals can say "1 weapon-skill
   rank beats 1% crit right now" for melee.

Explicitly NOT taken: their always-on stat HUD (their niche; our surfaces are
the character-sheet panel, Matrix, planner, insights), fonts/profiles/layout
engine, any code (ARR).

## Confidence & verification plan

Every formula ships confidence-tagged `classic-presumed` (the miss tables and
cap values are classic mechanics lore). Verification on Forever: the owner's
in-game character-sheet values vs our computed miss/hit lines on a live
character (the beta-probe doctrine); SinStats' shipped Forever build is
corroborating evidence that the mechanics survived the port, never the cited
source. Selftests pin the MATH on fixed fixtures (rename-proof law - no live
names/numbers).

The story: SPRINTS **S56**. Record loop on ship: S56 ☑ + CHANGELOG version +
FEATURES.md (MODEL- + UI- entries) in the same change.
