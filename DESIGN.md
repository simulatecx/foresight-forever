# Foresight - Addon Design (WoW: Forever)

Product spec and technical design. Research date: 2026-10-10. Target: official WoW: Forever
(modern retail client, classic-era Azeroth, level 60 cap, Midnight 12.0 "secret values" API).
See `FEASIBILITY.md` for the platform research this builds on.

## Product summary

**Foresight** - the hardcore player's safety net. Three pillars:

1. **Panic Advisor** - knows your class's escape toolkit; when you're in a bind it flashes the
   right buttons on screen, ranked, with keybinds. Fully user-modifiable per character.
2. **What-to-press** - on-screen highlight of the next recommended ability, powered by
   Blizzard's own assisted-combat engine (compliant by construction).
3. **Talent Impact Map** - pick a talent, see exactly which of your skills it changes and how
   it shapes your build. The same data spine later powers "which skills does this item impact".

Positioning: Forever ships with its own hardcore mode ("level 60 on one life"). Deaths are
permanent, most deaths happen while leveling in the open world - exactly where the addon API is
unrestricted. The Forever addon ecosystem is nearly empty at launch (most classic addons need
rewrites). A death-prevention addon is arguably the highest-value niche on this platform.

## Feature 1: Panic Advisor ("in a bind - what do I press")

### Trigger engine (own-state only, secret-safe)
- Inputs: own health % and rate of drop, own active CC (stunned/feared/rooted), combat state,
  usable consumables in bags (healthstone, potions, bandages), ability cooldown readiness.
- Own data is readable in open-world content under the 12.0 rules; every read goes through a
  guard layer (`issecretvalue()` + `pcall`) so in dungeons/raids the advisor degrades
  gracefully (display-only or disabled) instead of erroring.
- Tiered alerts, user-tunable: e.g. caution at 50% HP, danger at 35%, PANIC at 20% or when
  HP is dropping faster than X%/sec.

### Escape registry (character-specific)
Per-class prioritized "get out of trouble" lists, seeded with sensible defaults, filtered by
level/known spells, learned-at-runtime. Examples of registry entries:
- Immunities/bail-outs: Divine Shield, Ice Block, Feign Death, Vanish
- Gap-makers: Blink, Frost Nova + run, Hamstring-and-go, travel forms
- Emergency heals: Lay on Hands, Nature's Swiftness combos, Healthstone, potions, bandage
- CC breaks + racials: Stoneform, Will of the Forsaken, Escape Artist, PvP trinket
- Generic consumables: health potion, swiftness potion
Forever adds 115 new talents and new abilities; registry is data-driven (one table per class)
so additions are cheap. Users can reorder, add, remove, and set per-entry conditions in config.

### Display
- **Button flash**: locate the action-bar buttons holding the registry abilities (scan action
  slots by spell/item ID) and apply a pulsing glow overlay (LibCustomGlow-style). Purely
  cosmetic frame drawing - explicitly allowed; addons that restyle Blizzard's own Assisted
  Highlight glow exist on CurseForge today.
- **Panic panel**: optional central strip showing the top 3 ranked options as icon + keybind,
  ordered by the registry priority and current availability.
- Escalation styling: colors/pulse rate by tier; optional sound; optional screen-edge vignette.
- Everything suggest-only. Addons can never press buttons - that's a hard platform rule
  (protected functions require real hardware events).

## Feature 2: What-to-press (rotation highlight)

Blizzard's 12.0 client exposes its assisted-combat engine to addons:
- `C_AssistedCombat.GetNextCastSpell()` - the spell the game itself recommends next
- `C_AssistedCombat.IsAvailable()`, `C_Spell.GetSpellCooldown()` for state
The Knickili addon on CurseForge proves this pattern is compliant: display the recommended
spell icon + keybind in a HUD element, no secret-value inspection needed. Foresight wraps the
same API and optionally also glows the matching action button.

**Assumption to verify in beta**: `C_AssistedCombat` is present and populated on the Forever
client (it is a 12.x retail client, so expected yes; needs a 10-minute beta check).

## Feature 3: Talent Impact Map

Forever's talent system: classic structure (3 trees/class, 51 points at 60, 7 rows) with a 4th
one-point "gold" talent per tree at 16 points. Beta has 466 talents: 115 new, 46 removed, 15 new
31-pointers. Key buffs (Kings, Divine Spirit, etc.) moved out of trees to baseline.

### Data model: the "effects graph"
```
source (talent | item) -> modifier (damage %, cast time, cooldown, resource, proc) -> target (spell | school)
```
- **Primary data source - runtime tooltip parsing**: classic-style talent text almost always
  names what it affects ("Reduces the cast time of your Fireball spell by 0.5 sec"). Parse
  talent descriptions at runtime, match referenced spell names/schools against the player's
  spellbook, and auto-build the mapping. Zero shipping-data staleness.
- **Curated overrides**: a hand-maintained table for talents whose text is indirect (procs,
  "your next spell..."), layered over the parser output.
- Non-combat feature: no secret-value exposure at all.

### UX
- **Tooltip injection**: hovering a talent appends "Affects: [spell icons/names]" and a build
  note ("core to Fire leveling", "survival talent - hardcore value: high").
- **Mapping panel**: per-build view - left column talents taken, right column your skills,
  lines/greying showing impact; invert it to answer "which talents touch Fireball?".
- **Future (feature 3b)**: same parser on item tooltips ("Increases damage done by Shadow
  spells by up to 23") feeds the same graph -> "these skills are most impacted by this item",
  and at equip-compare time, "this upgrade mostly benefits: [skills]".

## UI map (added 2026-10-10, inspired by the most popular stat/UI addons)

Pattern source: Extended Character Stats / CharacterStatsClassic lineage - toggle button
on the character frame, collapsible-category side panel, label/value rows, per-character
expand-state memory. Forever's #1 UI addon (ClassicUI Forever) is a classic-look reskin,
so Foresight uses stock Blizzard templates to blend with both classic and default skins.

```
+--------------------------+  +----------------------+
|                          |  | Foresight        [gear] |
|   CharacterFrame         |  |----------------------|
|   (Blizzard)             |  | [-] Dimensions       |
|                          |  |   Spellcasting  312  |
|                          |  |   Melee DPS      88  |
|                          |  |   Survivability 3.1k |
|                          |  | [-] Regen            |
|                          |  |   Mana/tick  38 (p)  |
|                          |  |   Health/tick 41 (p) |
|                   [HM] <-+--+ toggle button        |
|                          |  | [-] What-if          |
+--------------------------+  |   +10 Spirit -> ...  |
                              |   +10 Int    -> ...  |
                              +----------------------+
```

- **Sections** (collapsible, state saved per character): Dimensions (7 outcome scores),
  Regen (mana/health per tick, five-second-rule annotated), Mechanics (swing time,
  armor mitigation, effective HP), What-if (quick stat deltas in human terms - the
  differentiator: ECS shows what you have, Foresight shows what more would do).
- `(p)` marks classic-presumed formula values until the probe verifies them; secret or
  unavailable values render as "-", never errors.
- Separation for testability: `ui/panel_model.lua` builds the section/row model from a
  loadout (pure Lua, selftest-covered); `ui/stats_panel.lua` renders frames (in-game only).
- Later surfaces reuse the same split: talent tooltip injection, mapping panel.

## Architecture

```
Foresight/
  Foresight.toc
  core/      -- event bus, SavedVariables DB (per-character profiles), config UI, secret-value guard layer
  data/      -- class escape registries, talent/item parser, curated overrides
  panic/     -- trigger engine, button-flash overlay, panic panel
  assist/    -- C_AssistedCombat HUD wrapper
  talents/   -- tooltip injection + mapping panel
  items/     -- (future) item impact module, reuses data/ parser
```

Build order: **superseded by `DATAFLOW.md` (2026-10-10)** - the Talent Impact Map and its
underlying Character Impact Graph come first (we are piloting on live Forever gameplay);
panic advisor and assist HUD follow on top of the same data layer.

## Risks / beta-verification checklist

| Item | Risk | Check |
|------|------|-------|
| Own health/buffs readable in open-world combat | Low (documented design intent) | Read `UnitHealth("player")` in combat in beta |
| `C_AssistedCombat` on Forever client | Low-medium | `/dump C_AssistedCombat.GetNextCastSpell()` in beta |
| Talent API shape (classic trees on modern client) | Medium - new hybrid, API surface undocumented | Inspect `C_SpecializationInfo`/talent frame in beta |
| SavedVariables don't persist (known beta bug) | Temporary | Expected fixed by launch; keep DB layer defensive |
| Instanced content: advisor data goes secret | By design | Guard layer degrades to display-only; hardcore leveling (core audience) unaffected |

## Sources

- [Secret values - Warcraft Wiki](https://warcraft.wiki.gg/wiki/Secret_values)
- [Blizzard: Combat Philosophy and Addon Disarmament](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [Knickili - Midnight rotation helper via C_AssistedCombat](https://www.curseforge.com/wow/addons/knickili)
- [Assisted Circle Highlight - restyling Blizzard's glow is allowed](https://www.curseforge.com/wow/addons/assisted-circle-highlight)
- [WoW Forever talent calculator guide - 51 points, 4 gold talents](https://lfcarry.com/guides/wow-forever-talent-calculator)
- [WoW Forever class changes - new talents](https://expcarry.com/wow-forever-class-changes)
- [WoW Forever addons: what works](https://wowforeverclassic.com/guides/addons)
