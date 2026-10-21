## 0.50.1

Plays nice with your UI - a full pass on window behavior and text layout, matched to how
the big addons behave (ElvUI, WeakAuras, Details!).

- **ESC closes Foresight windows** (planner, options, export) instead of opening the game
  menu over them. The Matrix stays pinned like a Details! window - close it with its X.
- **Windows behave like windows**: the one you click comes to the front, nothing can be
  dragged off-screen, the Matrix no longer hides underneath other addons' frames, and the
  options window remembers where you put it.
- **One scale slider for everything**: the Layout panel-scale setting now sizes the planner,
  options, and export windows too - the lever for fitting Foresight beside a scaled ElvUI.
- **Text stays organized at any size**: the planner header can't overlap its controls
  anymore, a long build summary pushes the trees down instead of running under the buttons,
  saved builds page neatly instead of spilling off the frame, options descriptions grow
  their row instead of covering the next setting, and tooltips wrap instead of going
  mile-wide. Larger fonts (ElvUI font settings) grow the layout instead of clipping it.
- Talent-tree glows now respect window layering instead of drawing over everything.

All of 0.50.0 (the talent-tree planner look, prerequisite arrows, cross-impact tooltips,
and the 1.60.1.70450 patch data) is included.
