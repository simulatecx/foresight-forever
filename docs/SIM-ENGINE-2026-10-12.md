# SIM-engine design record (S18, 2026-10-12)

Source: three user PRDs - "Synergy & Simulation Engine", "Demystification & Class
Synergies", "Comprehensive Class Formulas & Synergy Matrix". This file maps each PRD
claim to what shipped, what the client data corrected, and what is deferred. One home
per fact: status lives in SPRINTS.md S18; this is the design rationale.

## PRD -> built (v0.25.0)

| PRD ask | Where it landed |
|---|---|
| Tier 1 class scalars (1 Str = 2 AP, Agility trap, 14 AP = 1 DPS) | already shipped: `data/formulas.lua` statConversions + AP_PER_DPS law |
| Weapon normalization constants (1.7 / 2.4 / 3.3) | `F.weaponNormalization` (+2.8 ranged), classic-presumed; snapshot now captures `weaponType` |
| Proc loops: crit -> Flurry uptime -> eff. speed -> Windfury -> burst | `model/sim.lua` meleeCascade; Flurry uptime = 1-(1-c)^N steady-state (`F.flurryUptime`) |
| Windfury formula (extra attacks, bonus AP, actual speed) | pipeline decode `extraAttacks` (tooltip-macro chase, 20% / 2 attacks / +46..333 AP by rank); `Sim.windfuryBurst`; EV folded into `Imbues.compare` |
| Time-to-OOM (chain-cast drain vs pool, FSR) | `Sim.timeToOOM` + `/foresight oom` + ability-tooltip "Chain-cast" line; FSR = regen 0 while chaining, downtime tick quoted |
| Archetype standings (Glass Bruiser, Endurance Brawler...) | `Sim.standing` - honest ratio basis (see corrections); panel subtitle + `/foresight sim` |
| Archetype-shift flag on item hover | `Sim.standingShift` -> "Shifts your build: X -> Y" tooltip line |
| "Pro highlight": slow weapon raises Windfury burst | gear DB now carries `speedMs`; `Tooltips.windfuryWeaponLine` (AP-term delta, honest about unknown base damage) |
| Enabler -> Engine -> Payoff ecosystems (Shatter loop etc.) | `data/loops.lua` curated registry (Shatter / Windfury / Flurry), selftest-gated name resolution, `/foresight loop` with live computed lines |
| Goal-oriented pathway highlighting | `Sim.goalPathways` + `/foresight path [dimension]` - ranks unspent trait steps by marginal goal impact |
| Flurry values | pipeline decode `critHaste`: the $Nn macro names the trigger buff; aura 319 bp (+10% Shaman r1 buff, +30% Warrior buff) x ProcCharges (3) |

## PRD corrections (client data + known limits win)

1. **Instant Poison is NOT PPM.** PRD 3 claims a hidden PPM system; the Forever client
   carries a flat 20% proc chance on the enchant. We ship the data's number.
2. **Intellect does not change spell coefficients.** PRD 1 derives a
   "Spell_Damage_Coefficient" from Int; coefficients are cast-time based (castMs/3.5).
   Int feeds max mana + spell crit only - as already modeled.
3. **Windfury extra attacks keep ACTUAL weapon speed.** PRD 1 wants normalization on
   everything; normalization governs instant yellow abilities. WF extra attacks are
   auto-attack swings (PRD 3 agrees). `windfuryBurst` uses actual speed; the
   normalization formula exists for future ability math (Stormstrike).
4. **%-threshold archetypes are dishonest on our indices.** The dimension scores are
   per-lens indices on different scales (SPRINTS fill-basis note), so "Melee > 80%"
   is meaningless. Standings pick the top output WORD from scores but make all ratio
   calls in same-unit stat space (Strength vs Intellect vs Stamina) - comparable
   within one character by construction. (Caught live: a near-zero-investment Ranged
   lens sat at 109 vs Spellcasting 110 purely from the shared baseline.)
5. **Flurry per-rank scaling is UNRESOLVED in the data.** The talent spell carries a
   dummy aura (bp=1, maxRank 5); the triggered buff carries the real haste (Shaman
   16257: +10%, 3 charges). We decode the buff and tag forever-new-unverified; the
   talent-tooltip hover capture upgrades or corrects it. Nothing is invented.
6. **Shatter's damage numbers can't be claimed yet.** "Ice Lance hits for 840" needs
   base spell damage per rank - not in the shipped tables (backlog). The loop ships
   the crit math (+50% vs frozen, (p)) and says the damage gap out loud.

## Deferred (groomed, not dropped)

- **Matrix side-panel UI** (PRD 1 §4, PRD 3 §4): the Talent-window Summary View with
  three-color ecosystem highlighting. The data layer is DONE (loops registry, mapping
  inverse/forward, pathways, synergy highlight glow plumbing); the renderer folds into
  the S7b visual panel work next build.
- **Rogue poison PPM / off-hand advice** (PRD 3 §3.3): poison procs are flat-chance in
  data; per-hand EV advice lands with the imbue surfaces when a rogue pilot exists.
- **Warrior rage economy** (PRD 3 §3.4): needs the classic rage formula
  (damage-and-speed based, level-dependent constant) as a tagged formula entry +
  crit-doubles-rage. Groomed for the next math pass.
- **Priest MP5/FSR gear insight** (PRD 3 §3.5): the OOM model covers chain-cast FSR;
  the "% of combat inside FSR" and MP5-bypass lines need combat-log timing (S11
  regen/GCD measurement).
- **Soft warning icons on underperforming talents** (PRD 2 §4.3, e.g. fast dagger +
  Windfury spec): the check exists implicitly via windfuryWeaponLine; a passive talent
  -frame badge waits for the Matrix UI.
