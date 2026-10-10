# WoW Overlay Addon - Feasibility Research

Research date: 2026-10-10. Target assumed to be **World of Warcraft: Forever** (official Blizzard
version, beta since 2026-09-17, launches 2026-11-04) based on this project's folder name.

## TL;DR

- The right way to build this is an **in-game addon written in Lua**. Addons natively draw UI
  frames on top of the 3D game world - that IS the overlay. No screen capture or external
  process is needed, and the game pushes events to you (quest accepted, health changed, zone
  changed, level up, death, loot) instead of you having to "watch the screen".
- An **external desktop overlay that monitors the screen or memory is the wrong path**: memory
  reading violates the EULA (Warden anti-cheat, bannable), and screen-scraping to drive combat
  decisions is the "pixel bot" category Blizzard actively bans. Passive overlays (Discord,
  Overwolf) are tolerated but have no legitimate access to live game data anyway.
- 3 of the 4 desired features are fully feasible. The 4th ("tell you what to press") is feasible
  in reduced, suggest-only form, mostly in open-world content - see the matrix below.

## Platform context (important, recent)

Blizzard's **Midnight expansion (patch 12.0, 2025/2026) introduced "Addon Disarmament"**:
combat-state data becomes **"secret values"** in restricted contexts. Addons can *display*
secret values (pass them to a status bar or text widget) but cannot *inspect, compare, or do
arithmetic* on them. Consequences:

- **WeakAuras ceased development** for Midnight; **Hekili and all rotation helpers are dead**.
  Blizzard replaced them with built-in Assisted Highlights / one-button assist, a Cooldown
  Manager, boss warnings, and a native damage meter.
- **WoW: Forever adopts the same Midnight API restrictions** (modern retail client, classic-era
  content, level cap 60).
- Scope of restrictions: they key off **map type (instances/raids), combat state, PvP matches,
  and unit relationship**. Enemy health/power/auras/cooldowns become secret; **your own data
  generally remains accessible**, especially in open-world content. Open-world questing/leveling
  addons work as before (Questie already has a Forever-specific release; DBM is being ported).
- Dev note: restrictions can be force-enabled for testing via console variables
  (e.g. `addonCombatRestrictionsForced`). Guard any possibly-secret value with
  `issecretvalue()` before branching on it.
- Known Forever beta issue: SavedVariables (addon persistence) don't persist across client
  restarts. Bug, expected fixed by launch - but plan defensive persistence anyway.

If the actual target is a *private* server (several "ForeverWoW"-branded 3.3.5a servers exist),
everything flips: old 3.3.5 API, no secret values, but a much older addon API. This doc assumes
official WoW: Forever.

## How addons are built (the standard stack)

- **Language**: Lua 5.1 (game-embedded), optional XML for frame layout (most modern addons do
  UI in pure Lua). No OS access, no network, no arbitrary file I/O - fully sandboxed.
- **Structure**: a folder in `<WoW flavor>\Interface\AddOns\<AddonName>\` containing:
  - `<AddonName>.toc` - manifest: Interface version, title, SavedVariables names, file list.
  - `.lua` files - event-driven logic.
- **Programming model**: create a Frame, `RegisterEvent("QUEST_ACCEPTED")` etc., react in an
  `OnEvent` handler, query API namespaces (`C_QuestLog`, `UnitHealth`, `C_Map`, ...), render
  via `CreateFrame`, `FontString`, `Texture`, `StatusBar`.
- **Persistence**: `SavedVariables` tables, written to disk by the client on logout/reload.
- **Hard limits (always, everywhere)**: addons can never cast spells, move the character, or
  press buttons - protected functions require a hardware event (a real user click/keypress).
  An addon may *suggest* an action; the player must press it.
- **Tooling**: VS Code + WoW API extensions (annotations/completion), Ace3 library suite,
  in-game iteration via `/reload`, BugSack/BugGrabber for errors. Distribution via
  CurseForge/Wago, installed through WowUp or the CurseForge app.

## Feature feasibility matrix

| # | Feature | Verdict | Notes |
|---|---------|---------|-------|
| 1 | Context on what the player is doing | **Feasible** | Events cover zone changes, quest accept/progress/turn-in, level-ups, combat enter/exit, deaths, loot, rested state. A context HUD panel is straightforward. |
| 2 | Journey stats tracking (what you've done) | **Feasible** | SavedVariables journal: quests completed, deaths (where/what killed you), XP/hour, gold curve, time played per zone, dungeons run, milestones. Beta persistence bug noted above. |
| 3 | Open quests / current objectives dashboard | **Feasible** | `C_QuestLog` APIs; Questie's Forever release proves the category works. Can enrich with objective progress, suggested next quest by proximity/level. |
| 4 | "In trouble - tell you what to press" | **Partial** | Suggest-only (never auto-press). Own health/resources are readable in open world, so a leveling "panic advisor" (low HP -> flash Healthstone/potion/defensive/run away) is feasible for the 1-60 journey. Inside dungeons/raids, combat values go secret and decision logic dies by design - degrade to displaying, not advising. Full rotation helpers are dead platform-wide; Blizzard's built-in Assisted Highlights covers that niche. |
| 5 | External screen-monitoring overlay | **Rejected** | Memory reading = bannable; pixel-reading for decisions = bot category; and it's unnecessary - the addon API provides the same data legitimately with an in-game overlay. |

## Recommended architecture (single Lua addon)

```
overlay/
  Overlay.toc
  core/        -- event bus, saved-variables DB, secret-value guards
  journal/     -- journey tracker (deaths, quests, XP rate, zone time)
  hud/         -- the overlay frames: context panel, movable/lockable
  quests/      -- quest dashboard module
  advisor/     -- open-world-only "in trouble" rules engine (issecretvalue-guarded)
```

MVP order: (1) journal + SavedVariables, (2) HUD context panel, (3) quest dashboard,
(4) advisor. Each module ships independently useful.

## Key sources

- Blizzard: [Combat Philosophy and Addon Disarmament in Midnight](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight)
- [Secret values - Warcraft Wiki](https://warcraft.wiki.gg/wiki/Secret_values)
- [Patch 12.0.0 API changes - Warcraft Wiki](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes)
- [World of Warcraft API - Warcraft Wiki](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [Restricted API functions - Warcraft Wiki](https://warcraft.wiki.gg/wiki/Category:API_functions/restricted)
- [WoW Forever addons: what works and what is blocked](https://wowforeverclassic.com/guides/addons)
- [World of Warcraft: Forever - Wikipedia](https://en.wikipedia.org/wiki/World_of_Warcraft:_Forever)
- [WoW Forever reveal (BlizzCon 2026)](https://wccftech.com/world-of-warcraft-forever-blizzcon-2026-release-date/)
- [WeakAuras: no addon support planned for Midnight](https://www.mmo-champion.com/threads/2665749-WeakAuras-Update-Still-No-Addon-Support-Planned-for-Midnight)
- [Getting started with writing AddOns](https://wowwiki-archive.fandom.com/wiki/Getting_started_with_writing_AddOns)
