## 0.53.0

ORGANIZED COMPLEXITY. We audited the big character-stat addons (ExtendedCharacterStats,
DejaCharacterStats, Details!, Pawn, ElvUI, Titan Panel) and applied the conventions they
converged on: keep every number, put the depth one gesture away.

**Less space, your call**
- **Collapse the Matrix**: a new title-bar chevron shrinks the Foresight Matrix down to
  just its title bar - the Details!-style minimize. Remembered per character.
- **Both windows close together**: closing the character menu now closes the Matrix with
  it, by default. Want it to stay? Turn on the new "Pin the Matrix open" option.
- **Forged chrome**: gold corner brackets and studs on the panels - drawn in code, in
  your class color, so they match any UI skin (ElvUI included).

**Hold Shift for the full breakdown**
Talent hovers now lead with the verdict: the at-max value, what the next point does to
your actual abilities, and the Synergy/Chains lines. The depth - the full affected-spell
list, the stat-fold context, your crit baseline - appears while you hold Shift, and it
appends live mid-hover. Works on the talent frame and the planner, both flavors.

**Classic synergy truth**
Vanilla hardcodes its stat-conversion auras to Spirit - our classic decode now honors
that, so Spiritual Guidance correctly chains Spirit into spell damage and healing (the
modern-shaped column had it misread as Strength). Classic talent hovers now carry the
same Synergy: and Chains: lines Forever gets, and `/foresight synergy` reads like a
report: grouped by talents / racials / buffs instead of one long dump.

Every release still passes the full test suite on BOTH flavors before it ships
(Forever 304 checks, Classic 259).
