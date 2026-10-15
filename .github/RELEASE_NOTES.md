## 0.49.0

Plan a build before you spend a point, and see what any item does to the spells you actually cast.

**The Talent Planner.** A full interactive talent tree you can open and click to allocate - and it works before level 10, so you can plan from your very first level. As you build, Foresight shows what the whole plan does for you in plain terms ("This build: Spellcasting +4.2, Melee DPS +1.8"), folding every planned point through the same impact engine the rest of the addon uses. When you have a plan, your real talent tree glows the path - blue where points remain, gold once you've spent them - and the glow updates live as you allocate in Blizzard's own UI. Share a plan as a code and a friend gets the exact same overlay to follow. You can also copy the build off a player you inspect. Nothing is ever auto-applied - Foresight shows you the path, you spend the points. Commands: `/foresight planner`, and `/foresight set plannerOverlay off` to hide the tree glow.

**Gear → your spells.** Hover any item and, right under the upgrade/downgrade verdict, Foresight now names the few of *your* top abilities it changes the most - "Best for your spells: Frostbolt +3.2%, Frost Nova +1.1%". It works for every kind of item: a Strength or Attack Power piece ranks your melee strikes, a +spell-damage piece ranks your casts, a healing piece ranks your heals. The per-spell numbers use the exact same honest math as the headline verdict (what you'd gain over the item you're replacing - never a double-count on gear you already wear), so they can never disagree with the call above them. Hide it with `/foresight set spellImpact off`.

Plus more datamined talent rank values baked in, and a sturdier install path under the hood.
