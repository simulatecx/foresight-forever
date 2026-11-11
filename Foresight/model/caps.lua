-- Foresight/model/caps.lua - chance caps & the boss frame (S56, SinStats-inspired).
-- The classic chance mechanics as ONE data-located table + pure functions: how often
-- you miss vs a same-level target and vs a +3 "boss", how far you are from the hit
-- caps, the weapon-skill miss penalty, and the white-swing crit ceiling. Design
-- record: docs/SINSTATS-ANALYSIS.md (mechanism learned from SinStats' shipped
-- Forever build - game facts re-implemented, zero code reuse; their addon is ARR).
--
-- EVERY number here is classic mechanics lore, confidence-tagged: all output lines
-- carry the house "(p)" until the owner's in-game pass verifies them on Forever
-- (the beta-probe doctrine). Pure above the harness guard - fixture-tested headless.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Caps = {}
HM.Caps = Caps

-- ---- the tables (classic-presumed; one home) ---------------------------------

-- Melee/ranged white-hit miss vs defense (defense = targetLevel * 5):
--   skillDiff = defense - weaponSkill
--   diff <= 10:  base + diff * slope
--   diff  > 10:  breakBase + (diff - 10) * steep   <- the weapon-skill breakpoint
-- Dual-wield white swings add the off-hand penalty (the 24/26 bases).
Caps.MELEE = {
    base = 5, breakBase = 7,
    dualBase = 24, dualBreakBase = 26,
    slope = 0.1, steep = 0.4, breakAt = 10,
}

-- Spell miss floors: 3% vs same-level, 16% vs +3 boss (so +hit caps at those).
Caps.SPELL = { same = 3, boss = 16 }

-- Crit vs a higher-level target: crit - levelDiff - aura (the 1.8% suppression
-- that kicks in at +3). Applies to melee/ranged/spell crit alike.
Caps.CRIT_BOSS = { perLevel = 1, aura = 1.8, auraAt = 3 }

-- White-swing crit ceiling vs a +3 boss: the hit table fills with miss + dodge +
-- glancing (40% of white swings) before crit; extra weapon skill over the level
-- cap claws a little back.
Caps.WHITE = { glancing = 40, dodgeBase = 5, dodgeSlope = 0.1, critSupp = 4.8,
               extraSkillSlope = 0.04 }

local function clampPct(v)
    if v < 0 then return 0 elseif v > 100 then return 100 end
    return v
end

-- ---- pure math ----------------------------------------------------------------

-- White miss chance. weaponSkill/defense in skill points; hitPct = +hit from
-- gear/talents; dual = off-hand weapon equipped (white swings only).
function Caps.meleeMiss(weaponSkill, defense, dual, hitPct)
    local diff = (tonumber(defense) or 0) - (tonumber(weaponSkill) or 0)
    local T = Caps.MELEE
    local miss
    if diff > T.breakAt then
        miss = (dual and T.dualBreakBase or T.breakBase) + (diff - T.breakAt) * T.steep
    else
        miss = (dual and T.dualBase or T.base) + diff * T.slope
    end
    return clampPct(miss - (tonumber(hitPct) or 0))
end

-- Spell miss for the two frames ("same" | "boss").
function Caps.spellMiss(frame, spellHitPct)
    local floor = (frame == "boss") and Caps.SPELL.boss or Caps.SPELL.same
    return clampPct(floor - (tonumber(spellHitPct) or 0))
end

-- Crit as it lands on a +diff target.
function Caps.critVs(critPct, levelDiff)
    local d = math.max(0, tonumber(levelDiff) or 0)
    local aura = (d >= Caps.CRIT_BOSS.auraAt) and Caps.CRIT_BOSS.aura or 0
    local c = (tonumber(critPct) or 0) - d * Caps.CRIT_BOSS.perLevel - aura
    return c < 0 and 0 or c
end

-- The white-swing crit ceiling vs a +3 boss at player level `level`.
function Caps.whiteCritCap(level, weaponSkill, dual, hitPct)
    level = tonumber(level) or 60
    local skill = tonumber(weaponSkill) or level * 5
    local defense = (level + 3) * 5
    local missBoss = Caps.meleeMiss(skill, defense, dual, hitPct)
    local diff = defense - skill
    local dodge = Caps.WHITE.dodgeBase + diff * Caps.WHITE.dodgeSlope
    local extra = math.max(0, skill - level * 5)
    local cap = 100 - missBoss - dodge - Caps.WHITE.glancing
        + Caps.WHITE.critSupp + extra * Caps.WHITE.extraSkillSlope
    return clampPct(cap)
end

-- ---- the snapshot read (one bundle for every surface) --------------------------

-- forSnapshot(snap) -> {
--   melee = { same, boss, dual, skill, skillMax, skillGapPct, toCapSame, toCapBoss },
--   spell = { same, boss, toCapSame, toCapBoss },
--   critCap = pct or nil,
-- } - nil when there is no snapshot. All percentages, boss frame = +3 levels.
function Caps.forSnapshot(snap)
    if type(snap) ~= "table" then return nil end
    local stats = snap.stats or {}
    local level = tonumber(snap.level) or 60
    local hit = tonumber(stats.hitPct) or 0
    local spellHit = tonumber(stats.spellHitPct) or 0
    local skillMax = level * 5
    local skill = tonumber(snap.weaponSkill) or skillMax
    local dual = snap.dualWield and true or false

    local defSame, defBoss = level * 5, (level + 3) * 5
    local melee = {
        same = Caps.meleeMiss(skill, defSame, dual, hit),
        boss = Caps.meleeMiss(skill, defBoss, dual, hit),
        dual = dual,
        skill = skill,
        skillMax = skillMax,
        -- What the skill shortfall ALONE costs you (miss now vs miss at full skill).
        skillGapPct = Caps.meleeMiss(skill, defSame, dual, hit)
            - Caps.meleeMiss(skillMax, defSame, dual, hit),
    }
    melee.toCapSame = melee.same -- +hit needed to zero the frame
    melee.toCapBoss = melee.boss
    local spell = {
        same = Caps.spellMiss("same", spellHit),
        boss = Caps.spellMiss("boss", spellHit),
    }
    spell.toCapSame = spell.same
    spell.toCapBoss = spell.boss
    return {
        melee = melee,
        spell = spell,
        critCap = Caps.whiteCritCap(level, skill, dual, hit),
    }
end

-- ---- the insight lines (consumed by Insights.forCharacter) ---------------------

-- Lane from the primary dimension id; healing has no miss story (heals don't miss).
local LANE = { meleeDps = "melee", rangedDps = "melee", spellcasting = "spell" }

-- linesFor(loadout, primaryId) -> array of { text, tone } or nil. ONE chance-check
-- head line + at most two muted follow-ups - insight, not a stats dump (the
-- "don't lose what Foresight is" law: we interpret, SinStats displays).
function Caps.linesFor(loadout, primaryId)
    local snap = loadout and loadout.snapshot
    local c = Caps.forSnapshot(snap)
    local lane = LANE[primaryId or ""]
    if not (c and lane) then return nil end
    local out = {}
    local function add(text, tone) out[#out + 1] = { text = text, tone = tone } end

    if lane == "melee" then
        local m = c.melee
        if m.same <= 0 then
            add(("Chance check: hit-capped vs same-level - +hit only helps vs bosses now (%.1f%% miss there) (p)")
                :format(m.boss), "body")
        else
            add(("Chance check: your swings miss ~%.1f%% vs same-level, ~%.1f%% vs +3 bosses%s - +%.1f%% hit caps same-level (p)")
                :format(m.same, m.boss, m.dual and " (dual-wield white swings)" or "",
                    m.toCapSame), "body")
        end
        -- The train-your-weapon callout: only when the skill shortfall itself bites.
        if m.skill < m.skillMax and (m.skillGapPct or 0) >= 1 then
            add(("  Weapon skill %d/%d costs you ~%.1f%% extra miss - it trains by attacking; the cheapest hit you own (p)")
                :format(m.skill, m.skillMax, m.skillGapPct), "muted")
        end
        -- White crit ceiling: context only when the player's crit is near/past it.
        local crit = snap.stats and tonumber(snap.stats.meleeCritPct)
        if crit and c.critCap and crit >= c.critCap - 5 then
            add(("  White-swing crit ceiling vs bosses ~%.1f%% (you: %.1f%%) - crit past it only helps specials (p)")
                :format(c.critCap, crit), "muted")
        end
    else -- spell lane
        local s = c.spell
        if s.same <= 0 then
            add(("Chance check: spell-hit capped vs same-level - bosses still resist %.1f%% (cap +%d%%) (p)")
                :format(s.boss, Caps.SPELL.boss), "body")
        else
            add(("Chance check: your spells miss ~%.1f%% vs same-level, ~%.1f%% vs +3 bosses - +%.1f%% spell hit caps same-level (p)")
                :format(s.same, s.boss, s.toCapSame), "body")
        end
    end
    return out
end

return Caps
