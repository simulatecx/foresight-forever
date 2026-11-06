## 0.65.0 - under-the-hood cleanup

No visible changes - this release consolidates internals so everything stays consistent:
every green-up/red-down number now runs through one shared color helper, and the
"compare this item against what you're wearing" math runs through one shared fold used by
the verdict, the dimension rows, the per-spell lines, and the plan line alike - so they
can never drift apart.

Ship gate: Forever 322 checks, Classic 276. Display-and-advice only, official APIs only.
