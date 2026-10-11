# CurseForge / Wago project kit

Listing copy, the product lineup, a logo prompt, and the deploy checklist. Keep this in
sync with the pillars as they ship.

## Product lineup (the "3 downloads")

DECIDED 2026-10-11 (user): ship as THREE SEPARATE CurseForge/Wago projects, not one
modular addon - players install exactly the problem they want solved (no bloat; the
account-safety and "specific addon" doctrine). The three share the generated data layer
(and may share a small common lib later) but each is its own project + repo/TOC:

1. **Foresight** - *Talent, Item & Consumable Impact Map.* The theorycraft core (shipped):
   what every talent point, stat, item, buff, and weapon imbue actually does for YOUR
   character, in human terms, with synergies and a future-build planner. Data is
   Forever-verified from the live client.
2. **Foresight: Assist** - *What-to-Press Overlay.* A movable, suggest-only HUD showing
   your recommended next ability + keybind (`C_AssistedCombat`). Display-only, never
   automates. (Pillar 2 - next build.)
3. **Foresight: Panic** - *Hardcore Safety Net.* Flashes your best escape when you're in
   danger (HP%/incoming-damage triggers), per-class escape registry. The headline
   hardcore feature. (Pillar 1.)

## Short summary (CurseForge tagline, ~1 sentence)

> Foresight shows what every talent point, stat, item, and buff actually does for YOUR
> character on WoW: Forever - in plain terms, before you commit.

## Listing description (marketing copy)

> **Know before you commit.** On a hardcore realm a wasted talent point or the wrong
> trinket can end a character. Foresight answers the question every choice raises -
> *"+2 Spirit, so what?"* - in human terms: extra casts per fight, seconds of regen
> saved, damage per swing, hits you can survive.
>
> - **Talent Impact Map** - hover any talent and see exactly which of your abilities it
>   changes and what it does for your character right now.
> - **Stat & gear clarity** - what +Agility, a new weapon, or a flask is really worth,
>   compared against what you have equipped.
> - **Synergies** - the Diablo-style "show me everything that scales with Intellect",
>   including the chains (Intellect -> Attack Power via Mental Dexterity).
> - **Weapon imbue sim** - Rockbiter vs Flametongue on your actual weapon, as numbers.
> - **Future-build planner** - plan the gear and talents you're hunting and see the net
>   impact before you get them.
>
> Every number comes straight from the live Forever client data (Forever-verified, with
> the patch shown), never guessed. **Account-safe by construction:** display-and-advice
> only - it never casts, targets, moves, or automates anything, never reads memory, and
> never touches the network. The full source is public and a static compliance gate
> blocks any release that could break those promises.

## Logo - FINALIZED 2026-10-11

The icon is chosen: an all-seeing eye fused with a shield, emerald-green + gold on dark
slate, encircled by arcane runes (matches the brand green ~#33FF99). Save the PNG into the
repo at `media/logo.png` (and a square 512x512 for CurseForge/Wago project avatars + the
README header). Keep the transparent-background master for resizes. This same mark skins
all three products, tinted per module (core = green, Assist = gold, Panic = red) so the
suite reads as one family.

## Logo prompt (the brief that produced it; kept for variations/resizes)

> A minimalist game-addon app icon for "Foresight", a World of Warcraft addon. A single
> stylized all-seeing eye fused with a protective shield/rune, suggesting foresight and
> hardcore safety. Dark slate background, emerald-green and warm-gold accents (addon
> brand green ~#33FF99), subtle arcane etching, soft inner glow. Clean, iconic,
> high-contrast, instantly readable at 64x64 as an addon icon; centered, no text, no
> letters. Fantasy-UI aesthetic, not cartoonish.

Variations to try: swap the shield for a compass rose (planning), or the eye for a
branching talent-tree node (the impact map).

## Deploy checklist (your decisions - CI is already scaffolded in .github/workflows/)

1. Create the GitHub remote; push `main` (public recommended - the audit-first trust
   story IS the marketing). `git remote add origin <url> && git push -u origin main`.
2. Register the CurseForge project (and Wago) for **Foresight**; note the project ID +
   slug. Set the CurseForge category to a theorycraft/combat category; mark the game as
   WoW: Forever / Classic.
3. Add repo secrets: `CF_API_TOKEN`, `WAGO_API_TOKEN` (optional `WOWI_API_TOKEN`).
4. Put the CurseForge id in the TOC: `## X-Curse-Project-ID: <id>` (and `## X-Wago-ID:`).
5. SHA-pin the action refs in the three workflows; enable branch protection on `main`.
6. Tag a release: `git tag v0.22.0 && git push --tags` -> CI gates, packages, uploads.
7. Upload the logo + this description on the CurseForge/Wago project pages.

License: MIT (`LICENSE`) - permissive, which an open/audit-first addon wants. Swap if you
prefer GPL (one-line change + `## X-License`).
