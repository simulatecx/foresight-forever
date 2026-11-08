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

> The layman's oracle for WoW: Forever - see, in plain terms, what every talent, stat,
> and item actually does for YOUR character, built on a crowd-sourced Forever database.

## Listing description (marketing copy)

Positioning (user, 2026-10-14): NOT hardcore (Panic isn't built), NOT "simplify the
game" - it's an INSIGHT tool and a community-built Forever DB. Keep the founder voice.

> **The layman's oracle for WoW: Forever.**
>
> I've played since 2007 and still can't always tell what a new piece of gear really
> does for my character - is this trinket an upgrade? what is "+2 Spirit" actually worth?
> Foresight is the tool I always wanted: it reads the game's own numbers and answers in
> plain language - extra casts per fight, seconds of regen saved, damage per swing, how
> far a single talent point moves the needle.
>
> It isn't here to simplify the game or play it for you. It's here to give you
> **insight** - so you understand your choices and make them yourself.
>
> **What it shows you**
> - **Talent Impact Map** - hover any talent and see which of your abilities it changes,
>   and what it does for your character right now.
> - **Stat & gear clarity** - what +Agility, a new weapon, or a flask is really worth,
>   measured against what you already have equipped.
> - **Synergies** - "show me everything that scales with Intellect," including the chains
>   (Intellect -> Attack Power via Mental Dexterity).
> - **Weapon imbue sim** - Rockbiter vs Flametongue on your actual weapon, as numbers.
> - **Future-build planner** - plan the gear and talents you're chasing and see the net
>   impact before you earn them.
>
> **Built on a crowd-sourced Forever database.** Forever is new, and much about it isn't
> documented yet. Foresight learns from the people who use it: opt in and your anonymous
> game data helps build an open, live-verified database of what gear, talents, and
> consumables truly do - never guessed. Then compare your build against others of your
> spec, chase the daily challenges, and climb the ladders at wow-foresight.web.app. The
> more players who use it, the sharper it gets - and we'll keep expanding it, for
> ourselves and everyone who uses it.
>
> **Account-safe by construction.** Display-and-advice only - it never casts, targets,
> moves, uses items, or automates anything, never reads memory, and never touches the
> network. Every number comes straight from the live Forever client data. The full
> source is public and a static compliance gate blocks any release that could break
> those promises.
>
> *In-game: `/foresight` (or `/fore`). `/foresight selftest` runs the built-in checks.*

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
6. Rewrite `.github/RELEASE_NOTES.md` with this version's PLAYER-FACING notes (short,
   human, "what's new for you" - not the dev CHANGELOG). This file, not CHANGELOG.md,
   becomes the CurseForge + GitHub release notes.
7. Tag a release: `git tag v0.22.0 && git push --tags` -> CI gates, packages, uploads.
8. Upload the logo + this description on the CurseForge/Wago project pages.

## License & distribution (owner-confirmed 2026-10-14)

- **License: MIT** on both GitHub and the CurseForge project page - match the repo; do
  NOT use CurseForge's "All Rights Reserved" default (it would contradict the already-
  MIT public source and protect nothing, since the moat is the crowd DATA - gitignored,
  in Firebase - never the code).
- **Distribution: allow third-party distribution** (WowUp etc. may fetch via the API).
  Reach feeds the crowd database, we already publish to Wago + GitHub Releases too, and
  it's a free open addon with nothing to gate. Opt in to the broadest distribution.
- If commercial cloning ever becomes a concern, that's a repo license change (to a
  source-available / non-commercial license) applied to GitHub + CurseForge together -
  a deliberate decision, not CurseForge's dropdown. For now MIT + open stays.

License file: MIT (`LICENSE`). Swap to GPL etc. via a one-line `## X-License` change.

---

## Listing description (drafted 2026-11-06, v0.65.0 - owner reviews/pastes to CurseForge)

NOTE: the license note above is STALE (repo moved to All Rights Reserved 2026-10-15);
the TOC `## X-License: All Rights Reserved` is current. Kept for history.

# Foresight - know what every choice actually does

**The layman's oracle for WoW: Forever.** Every talent point, stat, item, and buff -
explained in plain terms, with your character's real numbers. Built for players who want
to understand their character, and hardcore players who can't afford to guess.

## Understand your character

Log in and Foresight reads your character back to you: your archetype and strongest
lens, your biggest hits, what your talent build actually stacks (and the capstone it
pays off into), the hidden synergy your class can exploit, and one coaching nudge.
Re-run it anytime: `/foresight insights`.

## Talents that explain themselves

- Hover any talent - in the talent frame or our planner - and see what it affects,
  what the next point does to YOUR abilities ("Fireball: ~141 -> ~148 per hit"), and
  the synergies it joins. Hold Shift for the full breakdown.
- **Chains**: see where a point really pays out - "Intellect -> spell damage via
  Mental Quickness." Hidden synergies too: when one stat scales several lanes for
  your class (the Int-stacked Shaman that powers melee, casting, AND totems), we say so.
- **The planner**: click-to-allocate talent trees usable at ANY level (even before 10),
  with example builds for every spec ("why it works" on hover), import/export codes,
  saved builds, a live overlay that glows your planned path on the real talent tree,
  and plan-for-a-future-level. Suggest-only: you always spend your own points.

## Gear verdicts that tell the whole story

- Pawn-style one-line verdicts ("Upgrade for Melee DPS +2.8%") - but from a real
  net-swap model of your character, not static weights.
- Weapon swaps account for the whole configuration: hover a two-hander while wearing
  a shield and Foresight shows the survivability you'd lose with it.
- "Best for your spells" - which of YOUR abilities an item lifts the most.
- Bleeds count: Rend-style damage shows per-tick and total, not a mystery.

## The Foresight Matrix

A dashboard of your character's engine: honest dimension bars, your class's
Enabler -> Engine -> Payoff loop (spec-aware - Arms warriors see the bleed engine,
Fury sees Flurry; hybrids are named hybrids), best-next-points for your goal, and
crowd comparisons ("Among your spec") with daily featured challenges.

## Honesty is the feature

Numbers come from the game client's own data. Anything not yet verified on Forever is
tagged **(p)** presumed - and your own talent scans verify rank rules live, flipping
tags green with "verified from your scan." No invented numbers, ever: when we can't
model something (a proc rate, a trinket effect), we say so out loud.

## Account safety

Display and advice ONLY. No automation, no casting, no targeting, no memory reading -
a normal addon using official APIs, enforced by an automated compliance gate on every
release. Crowd features are opt-in, anonymous by default, and the addon never
networks: sharing happens by a link YOU copy.

**Classic Era too:** the same addon works on Classic Era (1.15) with faithful classic
data - one install, both games.

Per-rank talent text credit: **talentsforever.com** (fan-made Forever talent calculator).
Web armory + ladders: **wow-foresight.web.app**

---

### Also from us: RUN - Immersive Enemy Builder

Foresight tells you about YOUR character; **RUN** makes the world's enemies worth
fearing. A living-world danger advisor: combat odds before you pull ("your chances vs
this creature"), rare hunts, and a Nemesis system where the enemies that kill you gain
notoriety and titles. Pairs with Foresight automatically - RUN reads a light combat
profile through our addon-to-addon bridge (nothing leaves your client) so its odds
sharpen when both are installed.

---

## Wago Addons automation (added 2026-11-08; LIVE since v0.65.1 - id nKWwP4KE in both TOCs, secret set)

The release workflow ALREADY passes `WAGO_API_TOKEN` to the BigWigs packager
(`.github/workflows/release.yml:44`) and the packager auto-detects both flavors - so Wago
publishing needs exactly TWO one-time inputs, then every `git tag vX.Y.Z` ships to
CurseForge + Wago + GitHub together (missing token/id = packager skips Wago silently,
which is why past releases never failed):

1. **The Foresight Wago project id** (owner): on addons.wago.io, create/import the
   project from the GitHub repo (same flow as RUN, whose id is `ANz7Dw64` in its TOCs),
   then copy the ID from the project's developer page. Paste it to the agent -> it lands
   `## X-Wago-ID: <id>` in BOTH TOCs (Foresight.toc + Foresight_Vanilla.toc, same id -
   one Wago project, multi-flavor, exactly like CurseForge project 1744126).
2. **The repo secret** (owner, token must never appear in chat/commits): copy the Wago
   API token (wago.io account -> API keys - same account token RUN uses) to the
   clipboard, then run:
   `powershell -c "Get-Clipboard | gh secret set WAGO_API_TOKEN -R simulatecx/foresight-forever"`
   (the clipboard pipe keeps the value out of the terminal history and the chat).

Verify on the next tag: the Release run's package log shows
"Uploading Foresight-vX.Y.Z.zip ... to Wago" + Success, same as the CurseForge line.
