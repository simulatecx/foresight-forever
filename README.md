# Foresight

The hardcore player's safety net for official **WoW: Forever**. Foresight answers the
question every talent point and every stat on gear raises: *"+2 Spirit - so what?"*
Answers always end in human terms: extra casts per fight, seconds of regen saved,
hits you can survive.

Three pillars:

1. **Talent Impact Map** - what each talent actually does to *your* character, with
   what-if modelling before you commit a point (it matters when respecs are expensive
   and deaths are permanent).
2. **Panic Advisor** - what to press when things go wrong (planned).
3. **What-to-press HUD** - suggest-only rotation help (planned).

Status: pre-release, built against the Forever beta (Interface 16001, data build
1.60.1.70338). Forever launches 2026-11-04.

## Official download channels

When released, Foresight will be distributed **only** through:

- CurseForge
- Wago Addons
- GitHub Releases on this repository

Anything obtained anywhere else is unofficial and may have been tampered with. The
login message prints the addon version plus the game data build it was generated
from; if yours does not match a release on this page, you are not running our build.

## Account safety, by construction

Foresight is a normal `Interface\AddOns` addon using official APIs only, and it is
**display-and-advice only**: it never casts, targets, moves, uses items, or automates
any protected action. There is no memory reading, no input injection, no game-file
modification, and the addon never talks to the network.

This is enforced, not just promised: `pipeline/check_compliance.py` statically bans
every automation/protected API and sandbox escape, runs as the first step of the ship
gate, and a red result blocks any release. The full source is public so you can check.

## Installing from source (beta)

Copy the `Foresight/` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\`
(or your flavor's `Interface\AddOns\`). Then `/foresight` in-game; `/foresight selftest`
runs the built-in checks.

## Development

- `python pipeline/fetch.py` - download Forever DB2 CSVs from wago.tools
- `python pipeline/generate.py` - regenerate `Foresight/data/generated/*.lua`
- `python pipeline/run_tests.py` - compliance gate + headless selftest; THE ship gate
- `python pipeline/deploy.py` - gate-then-copy to a live install

Docs: `DESIGN.md` (product), `DATAFLOW.md` (architecture, threat model, publishing),
`FEASIBILITY.md` (platform research), `SPRINTS.md` / `FEATURES.md` / `CHANGELOG.md`
(work tracker / capability inventory / release history).
