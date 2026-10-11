# Foresight - Release Notes

Player-facing summary of where Foresight stands: what works, what's being verified, and
what's known-broken or not-yet-built. For the full engineering log see `../CHANGELOG.md`
(the source of truth; this file is the plain-language companion).

Foresight is the hardcore player's safety net for **WoW: Forever**: it tells you what a
talent point, a stat, or an item actually does for *your* character - before you commit.

---

## v0.8.2 - 2026-10-11 (beta / pilot: Orc Shaman)

### Working now (confirmed live on the Forever beta client)
- **Character read**: stats, weapon speed, crit/haste, armor, mana/health pools -
  all captured correctly through the secret-value guard layer.
- **Talent capture**: reads the talents you've actually selected from Forever's trait
  trees (the modern `C_Traits` system), and matches them to Foresight's data.
- **Full talent data**: Foresight now ships data for every node in the trait trees
  (555 nodes), not just the ones carried over from the classic talent trees.
- **Stat advisor** (`/foresight advisor`): ranks your stats by what each is worth for
  your build right now, with a per-stat "what it's best for" breakdown.
- **Build label** (`/foresight build`): a one-line read of your build
  (e.g. "Caster-leaning - offense-focused").
- **Data collection**: `/foresight verify` runs automatically on login and saves a
  snapshot; persistence across sessions is confirmed working.

### Built, awaiting your in-game eyeball (hooks are installed and their APIs confirmed present)
- **Item tooltips**: hover an item and see what its stats do for you
  ("+4 Agility -> +X% melee DPS").
- **Spell tooltips**: hover an ability and see how much of your Spell/Healing Power
  lands on it per cast.
- **Talent tooltips**: hover a talent node for its affected spells, the value of the
  next point, and what it does to your dimension scores.
- **Stats panel**: the character-sheet side panel (Dimensions / Regen / Mechanics /
  What-if / Stat value), now **movable** - drag it anywhere; position saves per
  character; `/foresight panel reset` re-docks it.

### Known issues / not fixed yet
- **Talent tooltips on Forever** use a best-effort hook (`TraitEntry` tooltip). If it
  doesn't show, the next data capture will tell us the exact hook to use. Talent *data*
  capture already works regardless.
- **New Forever-only talents** (not present in classic) are recognized by name but their
  effects don't yet feed the "what-if" model and dimension scores (that's the next step).
- **Rank-scaling rule** for multi-rank talents is still a best-guess (shown as "(p)")
  until the in-game probe confirms it. Numbers tagged "(p)" are classic-presumed.
- **Threat** is shown from your own talents only; per-ability threat and stance/form
  effects aren't modeled yet.
- **Not started**: the Panic Advisor and the what-to-press HUD (the other two pillars);
  item/profession stats in the offline pipeline; public release packaging.

### Notable fixes on the road to 0.8.2
- Discovered Forever's talents are the modern trait system (the classic talent API is
  gone) and repointed the whole talent read path to it.
- Fixed six talents that were reading the wrong stat (a data-decoding bug).
- Fixed the data harvester silently reading stale captures, plus several first-login
  display bugs (armor reading 0, the data-build line showing "?").

---

*Confidence tags you'll see:* `(p)` = classic-presumed, not yet verified on Forever;
plain = read live from your character or the client database.
