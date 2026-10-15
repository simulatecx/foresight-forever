## 0.49.1

A hardening pass from a full code review - no new features, just making a solid build sturdier.

- **Shared talent builds can't misbehave.** A corrupted or hand-edited build code now always
  reports cleanly as invalid instead of risking an error while reading it.
- **`/foresight oom`** shows a clean whole-second estimate again.
- **Exact numbers where it matters.** A few advisory lines (weapon-enchant proc chance,
  Windfury bonus Attack Power, the threat-standing percent) now show their true value rather
  than quietly rounding down.

Everything from 0.49.0 (the Talent Planner and the per-item "Best for your spells" tooltip)
is included.
