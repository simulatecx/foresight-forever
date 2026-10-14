---
name: feature-triage
description: Foresight repo bindings for the global feature-triage gate. Use BEFORE building any new feature or sprint story in this repo - categorizes against FEATURES.md, runs the duplication check, and drafts the story for SPRINTS.md.
---

Follow the global `feature-triage` and `engineering-governance` skills for the method.
This file adds the Foresight repo bindings.

## Categories (FEATURES.md)

`DATA-` pipeline & shipped data · `GRAPH-` impact engine & dimensions · `MODEL-`
snapshot/loadout/impact · `CORE-` addon plumbing · `UI-` in-game surfaces · `QA-`
verification & feedback · `CROWD-` crowd data: share contract, backend, aggregation
(the addon never networks; data leaves only by user-initiated share) · `PANIC-` panic
advisor · `ASSIST-` what-to-press HUD.

## Shared spines (change these, update every consumer)

- Generated-data shape (`HM.gen.*`): produced by `pipeline/generate.py`, consumed by
  `model/impact.lua`, `model/loadout.lua`, `data/overrides.lua`, selftest. A shape
  change requires regenerating data AND updating all consumers in the same change.
- Graph node ids (`stat.*`, `mech.*`, `agg.*`, `outcome.*`): defined in
  `model/loadout.lua`, consumed by `graph/dimensions.lua`.
- Formula registry entries: consumed by loadout, impact, and the future probe module;
  renaming an entry breaks probe verification mapping.
- Guard layer: any new game-state read MUST route through `core/guards.lua`.

## Repo-specific triage questions

1. Does it read game state that can be secret? -> name the degraded behavior.
2. Does it need new client data? -> extend the pipeline, never hand-copy values.
3. Is the fact verified on Forever or classic-presumed? -> tag it.
4. "Mobile" check here = readable at 1280x720 with 0.65 UI scale.
5. **Compliance (account safety)**: could any part be construed as automation or a
   sandbox escape? The feature must keep `pipeline/check_compliance.py` green without
   weakening the banned list. If it can't, the design is wrong - the addon is
   display-and-advice only, always.
