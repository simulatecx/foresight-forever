## 0.54.0 - launch day

Forever is live, and Foresight is tuned to the launch client (build 1.60.1.70790). This
is the day-1 patch: the data matches what you're playing, with one real decode fix and a
new way to start a talent plan.

**Tuned to the launch balance pass**
Paladin and Rogue tree reworks, Druid Starfire/Shred buffs, Hunter Serpent Sting, Shaman
Riptide - the shipped talent, spell, and item data all match the live client, so your
hover numbers and gear comparisons are right for launch. Classic Era players: your build
is refreshed too (1.15.9.70576), no content changes.

**Example builds in the planner**
New "Examples" button in the talent planner: a ready-made deep build for every spec, for
all nine classes - load one as a starting point and tweak it however you like. Like
everything in the planner, it's advice only; nothing is applied to your character. The
builds are generated straight from the live talent tree, so they're always legal and
always current.

**A launch-day fix**
The launch reworks shipped the first talents that convert Intellect into *only* spell
damage or *only* healing (Champion of the Light, Arcane Blast, Natural Instinct), which
let us catch and fix a spot where those two were labeled backwards. Champion of the Light
now correctly shows Intellect -> spell damage, and the chains it feeds are right.

As always: every release passes the full test suite on both flavors before it ships
(Forever 305 checks, Classic 260), display-and-advice only, official APIs only.
