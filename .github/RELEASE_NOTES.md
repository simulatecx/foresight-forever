## 0.46.8

Fixes a case where using `/foresight share` (or opening the Matrix) could trip WoW's
"action blocked" protection. Sharing and the crowd comparison are safe to use again.
Comparisons now group by class and level; per-spec grouping returns once we can read it
without tripping that protection.
