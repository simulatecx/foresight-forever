# Polestar analysis -> Foresight upgrade presentation (2026-11-12)

Owner: "run an audit of how Polestar presents upgrades - take some inspiration from
theirs for upgrade - also our character sheet FS stayed static with Arms after we
respecced to Protection; it should provide prot guidance."

Analyzed from the installed addon family (Polestar + Polestar_ItemDB etc., the
leveling-guide suite). Mechanism inspiration only - our verdicts stay model-driven
(the real net-swap impact graph), never static stat weights.

## How Polestar presents upgrades (the mechanisms)

1. **The spec-labeled one-liner.** Every item tooltip gets ONE compact branded line:
   "Polestar - Arms   +12.4% upgrade - Head" - the SPEC it judged for, the signed
   percent, the slot it replaces. Their spec comes from the character's TALENTS
   (`Gear.GetSpec` source "talents") - the presentation is spec-reactive by
   construction.
2. **Quest-reward "Best pick".** `Gear.RankChoices` ranks every offered reward;
   the pick is the upgrade with the largest gain, else the highest-scoring usable
   choice. DETERMINISTIC ties: higher score, then LOWER item id, then the earlier
   choice - stable across clients.
3. **Bag upgrade arrows + step-item glow.** At-a-glance overlays on bag item
   buttons (an arrow for upgrades, a pulsing border for the current guide step's
   item), with explicit Baganator coexistence (corner widgets) and strict
   layer discipline (OVERLAY sublevels documented per texture).
4. **Replace-aware comparison.** vs what it would actually REPLACE: rings/trinkets
   take the weaker of the two, a two-hander weighs against MH+OH together, an
   off-hand candidate pairs with the best bag match, dual-wielders try the OH.
5. **Cache invalidation on GEAR_UPDATED = spec, level, equipment, item data.**
   Their caches treat a SPEC CHANGE as a first-class invalidation signal.

## What Foresight took (S57) vs recorded follow-ups

Taken (enhance `ui/tooltips.lua` + the model):
- **The spec-labeled header** (mechanism 1, minus the slot - the player is hovering
  the item): the Foresight tooltip header now reads "(p) for your Protection
  (0/5/41)" from the live spec profile. A respec re-brands every tooltip on the
  next hover - visible proof the guidance follows the talents.
- **Quest-reward Best pick** (mechanism 2): all choices judged through OUR
  `Impact.itemVerdict` (net-swap, spec-aware goal), the Polestar tie law kept
  verbatim (pct > lower id > earlier choice), selftest-pinned.
- **Spec-reactivity as a law** (mechanisms 1+5) - fixed at the MODEL: the owner's
  Prot respec kept Arms guidance because (a) no Protection loop existed (the
  Matrix fell back to loops[1]=Arms with only a footnote) and (b) the auto goal
  always chased the loudest OUTPUT lens. Fixes: the Shield Wall Engine loop
  (data/loops.lua, specTab Protection) and `Impact.goalDimension` (auto goal =
  tankability when the dominant tree is a tank tree; warrior+paladin Protection
  mapped, Feral deliberately not - dual-role).

Recorded follow-ups (SPRINTS S57), not built:
- **Bag upgrade glyphs / reward-panel marks** (mechanism 3): overlay UI on other
  addons' bag frames needs the ElvUI/Bagnon/Baganator coexistence pass (wow-ui-ux
  skill) and an in-game verify sweep - not a gate-green-only ship.
- **Replace-aware ring/trinket pairing** (mechanism 4): our compare takes the
  hovered slot's equipped item; weaker-of-two ring/trinket selection is a real
  correctness upgrade for `equippedCompareStats` - its own story.

## The honesty difference (why ours is not a Polestar clone)

Polestar scores items with authored per-spec WEIGHT BANDS (SpecData.lua, Pawn
scales importable). Foresight judges with the live impact model - the same
net-swap fold the rest of the addon uses - so the verdict, the chance check, the
Matrix, and the Best pick can never disagree with each other. Their presentation
grammar, our numbers.
