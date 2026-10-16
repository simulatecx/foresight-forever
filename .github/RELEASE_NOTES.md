## 0.49.1 (beta)

Make the UI yours, and plan talents straight from the talent frame.

**Move and size everything**
- Drag the **Foresight Matrix** by its title bar (clicking it still switches the view). All
  panels stay clamped on-screen - handy with a full UI overhaul loaded.
- The **stats table** gets its own collapse/expand button - shrink it to the title bar
  without hiding the Matrix.
- **Options are reorganized**: a **Character** tab (your ladder handle / armory) comes first,
  then General, Tooltips, Synergy Matrix, and a **Layout** tab (panel scale, opacity, motion,
  and one-click Reset-positions / Reset-Matrix-width). The options window is now **resizable**
  and remembers its size.

**Plan from the talent frame**
- A **Foresight button right on the talent UI**. Your own tree: it opens the planner. While
  **inspecting** another player: it becomes **Copy to Foresight** and saves their build as a
  snapshot you can follow or delete. Right-click it to toggle **plan mode** - the ghost
  highlights you follow on the live tree.
- **Copying an inspected player** now saves a **named, deletable snapshot** (loadable any time),
  not a one-off highlight.
- **Load my current build** (the Current button, or `/foresight planner current`) drops your
  real allocation into the planner so you can **plan by removing and moving points around** -
  entirely on paper. Foresight never spends or unlearns a point; you apply changes yourself.
- **Plan for a future level.** Use **Lv - / Lv +** to set the level you're planning toward
  (defaults to 30 for the beta) and you get the points you'd have then - 20 at level 30, or
  **25 with the legacy talent** toggled. Build a future spec before you're even there.

**Also** (from a full code-verification pass): corrupt/foreign talent codes always fail safely,
`/foresight oom` shows clean whole seconds, and a few advisory numbers show their exact value
instead of rounding down.

Beta note: lots of new on-screen furniture here - if a panel or button lands oddly in your UI,
that's what this beta is for.
