## 0.49.1

**If you installed 0.49.0 from CurseForge, update now**: the 0.49.0 package had a broken
folder layout that stopped the addon loading its data (talent hovers errored). 0.49.1 fixes
the packaging - plus everything below.

**The planner shows Forever's real talents - with real numbers**
- The talent planner now renders Forever's actual talent trees (all nine classes, with real
  prerequisite arrows), not the old vanilla table.
- Hover any talent for its **per-rank text** (credited to **talentsforever.com**, read from the
  Forever beta client's data), the modeled impact of the next point, and the **Affects /
  At-max / Synergy** breakdown - what it changes and which talents push the same lever.
- **Plan for a future level**: Lv - / Lv + sets the level you're planning toward (20 points at
  30, or 25 with the **legacy talent** toggle), so you can design a build before you're there.

**Plan from the talent frame**
- A **Foresight button on the talent UI**: your own tree opens the planner; while inspecting a
  player it becomes **Copy to Foresight** and saves their build as a named, deletable snapshot.
  Right-click toggles **plan mode** (ghost highlights on the live tree).
- **Load my current build** (`/foresight planner current`) seeds the planner from your real
  allocation so you can plan by removing and moving points - entirely on paper. Foresight
  never spends or unlearns a point.

**Make the UI yours**
- Drag the **Matrix** by its title bar; collapse the stats table independently; panels clamp
  on-screen. **Options** are reorganized (Character first, plus a Layout tab with scale,
  opacity, and reset actions) and the options window is resizable and remembers its size.

**Safety + honesty hardening** (from a full code audit): corrupt or out-of-date build codes
always refuse with a clear message instead of loading the wrong talents; saved window sizes
and snapshots are validated against tampering; every modeled number keeps its confidence tag.
