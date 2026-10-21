## 0.52.0

FORESIGHT COMES TO CLASSIC ERA. One addon, two games: alongside the WoW: Forever build,
this release installs a Classic Era (1.15) flavor of Foresight - the same talent planner,
honest tooltips, Matrix, and ladders, running on data generated from the classic client's
own files.

**Classic, done faithfully**
- The planner uses the real classic talent trees (432 talents, all nine classes, with
  prerequisite arrows) - and **321 of them carry exact datamined per-rank values**.
- Vanilla math is vanilla: Fireball rank 1 really is 14-22, Arcane Intellect rank 1 really
  is +2, and spell coefficients follow the classic cast-time law (the data column modern
  tools trust is wrong in the 1.15 export - we checked, and don't use it).
- Vanilla item truths preserved: Elixir of the Mongoose is a 1-hour elixir here, your 8
  classic races are exactly that, and anything only verified on Forever honestly starts
  as "(p) presumed" on Classic until your own scans confirm it.
- Synergies, chains, the catalog, and the ability map all work on classic talents.

**Quality gate, doubled**: every release now has to pass the full test suite on BOTH
flavors before it can ship.

Forever players: everything from 0.51.0 and earlier is unchanged in this release.
