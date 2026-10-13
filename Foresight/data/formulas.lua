-- Foresight formula registry: the conversion math client data doesn't express.
-- Every formula carries source + confidence; the probe module upgrades confidence to
-- "verified@<build>" when in-game measurement matches, or flags a mismatch report.
-- Confidence levels: "classic-presumed" (classic-era community formula, unverified on
-- Forever) | "verified@<build>" | "disputed".

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local F = {}
HM.formulas = F

-- Mana regen per 2s tick outside the five-second rule, by class token.
-- Classic-era community formulas (zugzugdb.com/formulas, Warcraft Tavern).
F.manaRegenTick = {
    unit = "mana per 2s tick, outside the five-second rule",
    source = "classic community formulas / zugzugdb",
    confidence = "classic-presumed",
    byClass = {
        MAGE    = function(spirit) return 13 + spirit / 4 end,
        PRIEST  = function(spirit) return 13 + spirit / 4 end,
        WARLOCK = function(spirit) return 8 + spirit / 4 end,
        DRUID   = function(spirit) return 15 + spirit / 5 end,
        SHAMAN  = function(spirit) return 15 + spirit / 5 end,
        PALADIN = function(spirit) return 15 + spirit / 5 end,
        HUNTER  = function(spirit) return 15 + spirit / 5 end,
    },
}

-- Health regen per 2s tick while out of combat (classic per-class spirit weights).
F.healthRegenTick = {
    unit = "health per 2s tick, out of combat",
    source = "classic community formulas",
    confidence = "classic-presumed",
    byClass = {
        WARRIOR = function(spirit) return spirit * 1.26 end,
        PALADIN = function(spirit) return spirit * 0.25 end,
        HUNTER  = function(spirit) return spirit * 0.43 end,
        ROGUE   = function(spirit) return spirit * 0.84 end,
        PRIEST  = function(spirit) return spirit * 0.41 end,
        SHAMAN  = function(spirit) return spirit * 1.1 end,
        MAGE    = function(spirit) return spirit * 0.38 end,
        WARLOCK = function(spirit) return spirit * 0.45 end,
        DRUID   = function(spirit) return spirit * 0.34 end,
    },
}

-- Weapon swing time in seconds.
F.swingTime = {
    unit = "seconds per swing",
    source = "universal WoW mechanic",
    confidence = "classic-presumed",
    fn = function(weaponSpeed, hastePct) return weaponSpeed / (1 + (hastePct or 0) / 100) end,
}

-- Spell damage coefficient for direct-damage spells (base cast time / 3.5, clamped).
F.spellCoefficient = {
    unit = "fraction of +spell damage applied",
    source = "classic community theorycraft",
    confidence = "classic-presumed",
    fn = function(baseCastSeconds)
        local c = baseCastSeconds / 3.5
        if c > 1 then c = 1 end
        if c < 0.1 then c = 0.1 end
        return c
    end,
}

-- Base spell/heal magnitude from the decoded SpellEffect fields: min/max from
-- bp +/- variance/2; level term bp + ppl * (clampedLevel - baseLevel), where
-- clampedLevel = min(playerLevel, maxLevel when set). The decoded VALUES carry the
-- generated-data channel provenance; this entry tags the composition LAW.
F.spellBaseDamage = {
    unit = "min, max base points at the player's level",
    source = "Forever client SpellEffect layout (build 1.60.1.70338); min/max law cross-checked vs classic rank-1 Fireball 14-22; display envelope verified vs the LIVE Lightning Bolt r2 tooltip 2026-10-12 (raw 25.4-29.4 renders as 25 to 30)",
    confidence = "datamined-presumed",
    fn = function(base, var, ppl, baseLevel, maxLevel, playerLevel)
        local bp = base or 0
        if ppl and ppl > 0 and playerLevel then
            local lvl = playerLevel
            if maxLevel and maxLevel > 0 and lvl > maxLevel then lvl = maxLevel end
            local term = lvl - (baseLevel or lvl)
            if term > 0 then bp = bp + ppl * term end
        end
        local spread = (var or 0) / 2
        return bp * (1 - spread), bp * (1 + spread)
    end,
    -- Blizzard renders the WIDEST integer envelope (floor min, ceil max) - first live
    -- verification caught our round-half showing 25-29 where the game says 25 to 30.
    -- The epsilon guards float noise (Fireball's stored variance puts the raw max at
    -- 22.0000001; naive ceil would claim 23).
    display = function(minv, maxv)
        return math.floor((minv or 0) + 0.0005), math.ceil((maxv or 0) - 0.0005)
    end,
}

-- School damage pools (S25, doc-entry law - no fn, the identity IS the claim):
-- GetSpellBonusDamage(school) returns the TOTAL bonus for that school - generic
-- "+spell damage" and school-specific "+Frost damage" already combined by the client.
-- The graph's six stat.school.* pools and the generic-feeds-all-six folding law rest
-- on this; the in-game check compares the pools against the character sheet.
F.schoolPoolLaw = {
    unit = "total bonus spell damage per school",
    source = "classic GetSpellBonusDamage semantics (community-documented); per-school reads retained since v0.37.0",
    confidence = "classic-presumed",
}

-- Crit damage multipliers (classic laws): melee/ranged crits land 2x, spell and heal
-- crits 1.5x. Used for the crit FRAMING line only - the headline hit range never
-- bakes crit in.
F.critMultiplier = {
    unit = "damage multiplier on a critical hit",
    source = "classic combat rules (community-documented)",
    confidence = "classic-presumed",
    melee = 2, spell = 1.5,
}

-- Effective health against physical: HP / (1 - mitigation). Armor mitigation vs a
-- level L attacker (classic): armor / (armor + 400 + 85 * L), capped at 75%.
F.armorMitigation = {
    unit = "fraction of physical damage mitigated",
    source = "classic community formulas",
    confidence = "classic-presumed",
    fn = function(armor, attackerLevel)
        local m = armor / (armor + 400 + 85 * (attackerLevel or 60))
        if m > 0.75 then m = 0.75 end
        return m
    end,
}

-- Talent rank scaling: effect values exist ONLY on the rank-1 spell. Whether the
-- stored value is the max-rank TOTAL (hypothesis A: rank N = value * N / maxRank) or
-- the PER-RANK value (hypothesis B: rank N = value * N) is UNRESOLVED - classic-value
-- comparisons give mixed evidence (A fits Improved Fireball id 26 and Ancestral
-- Knowledge; B fits Concussion and Improved Reincarnation), suggesting Forever
-- re-authored values. Default is A; the S3 beta pass checks those four talents'
-- in-game tooltips and settles the rule (or makes it per-talent data).
F.talentRankValue = {
    unit = "effect value at a given rank",
    source = "Forever client data layout analysis (build 1.60.1.70338)",
    confidence = "disputed-mixed-evidence",
    fn = function(maxValue, rank, maxRank)
        if maxRank <= 0 then return 0 end
        return maxValue * rank / maxRank
    end,
}

-- PER-TALENT rank value - THE one resolution path (S11 + S21), in order:
--   (1) op.values[rank] - datamined per-rank spell decode (S21), the truth, no rule;
--   (2) overrides.rankRules[talentId] - crowd-verified rule ("maxTotal" = value*N/maxRank,
--       "perRank" = value*N); entries arrive ONLY from the harvest draft
--       (collected/rank_rules_draft.lua) after human review;
--   (3) the global presumed default above, still tagged (p).
-- `values` is the generated per-op array (present only where every rank spell carried
-- aligned effect rows); callers pass op.values through - never a second math path.
function F.talentRankValueFor(talentId, maxValue, rank, maxRank, values)
    if type(values) == "table" then
        local v = values[rank or 0]
        if type(v) == "number" then return v end
    end
    local rules = HM.overrides and HM.overrides.rankRules
    local rule = talentId and rules and rules[talentId]
    if rule == "perRank" then
        return (maxValue or 0) * (rank or 0)
    end
    return F.talentRankValue.fn(maxValue or 0, rank or 0, maxRank or 1)
end

-- The honesty mark for a specific talent's rank scaling: datamined per-rank values
-- (every op carries a values array) drop the (p), crowd-verified talents drop it too;
-- everything else keeps the global presumed mark. ops optional (the generated op list
-- for this talent/node).
function F.rankRuleMark(talentId, ops)
    if type(ops) == "table" and #ops > 0 then
        local all = true
        for _, op in ipairs(ops) do
            if type(op) ~= "table" or not op.values then all = false end
        end
        if all then return "" end
    end
    local rules = HM.overrides and HM.overrides.rankRules
    if talentId and rules and rules[talentId] then return "" end
    return F.presumedMark(F.talentRankValue)
end

-- Threat model (GRAPH-threat). v0 is own-state only: a 100% baseline modified by the
-- character's own talent threat % effects (mapped from SPELL_AURA_MOD_THREAT in client
-- data). Stance/form multipliers (Defensive Stance, Bear, Righteous Fury) and per-ability
-- base threat are NOT here yet - those arrive as curated overrides (k-of-n crowd rule)
-- and a secret-safe stance read. Everything the lens shows is classic-presumed until the
-- probe/crowd verifies it.
F.threatModel = {
    unit = "percent of normal threat (own talents only in v0)",
    source = "classic threat mechanics; talent values from Forever client DB2",
    confidence = "classic-presumed",
    base = 100,
}

-- Primary-stat conversions (classic-era per-class values). Used as MARGINAL rates
-- around the live snapshot (the game's reported AP/crit already includes stats, so
-- the graph adds conversion * (stat - snapshotStat), never the absolute).
F.statConversions = {
    unit = "attack power per point / points of stat per 1% crit",
    source = "classic community theorycraft (vanilla values)",
    confidence = "classic-presumed",
    byClass = {
        WARRIOR = { apPerStr = 2, apPerAgi = 0, rapPerAgi = 1, agiPerCrit = 20, intPerSpellCrit = nil },
        PALADIN = { apPerStr = 2, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 25, intPerSpellCrit = 54 },
        HUNTER  = { apPerStr = 1, apPerAgi = 1, rapPerAgi = 2, agiPerCrit = 53, intPerSpellCrit = nil },
        ROGUE   = { apPerStr = 1, apPerAgi = 1, rapPerAgi = 1, agiPerCrit = 29, intPerSpellCrit = nil },
        PRIEST  = { apPerStr = 1, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 25, intPerSpellCrit = 59 },
        SHAMAN  = { apPerStr = 2, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 25, intPerSpellCrit = 59 },
        MAGE    = { apPerStr = 1, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 25, intPerSpellCrit = 59 },
        WARLOCK = { apPerStr = 1, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 25, intPerSpellCrit = 60 },
        DRUID   = { apPerStr = 2, apPerAgi = 0, rapPerAgi = 0, agiPerCrit = 20, intPerSpellCrit = 60 },
    },
}

-- Weapon normalization (classic 1.8+ combat rule): instant yellow attacks apply
-- Attack Power at a NORMALIZED weapon speed so ultra-slow weapons don't scale
-- infinitely. White swings - and Windfury extra attacks - keep the ACTUAL speed.
F.weaponNormalization = {
    unit = "bonus damage an instant attack gains from Attack Power",
    source = "classic 1.8 combat change (community-documented constants)",
    confidence = "classic-presumed",
    constants = { dagger = 1.7, oneHand = 2.4, twoHand = 3.3, ranged = 2.8 },
    fn = function(ap, weaponType)
        local c = F.weaponNormalization.constants[weaponType or "oneHand"] or 2.4
        return (ap or 0) / 14 * c
    end,
}

-- Flurry-family steady-state uptime: with crit chance c per swing and a buff that
-- lasts N swings, the chance any given swing is hasted ~ 1 - (1-c)^N. First-order
-- model (ignores refresh overlap and proc-of-proc crits) - tagged, never silent.
F.flurryUptime = {
    unit = "fraction of swings under the crit-triggered haste buff",
    source = "steady-state model over per-swing crit chance",
    confidence = "model-presumed",
    fn = function(critPct, swings)
        local c = (critPct or 0) / 100
        if c < 0 then c = 0 elseif c > 1 then c = 1 end
        local miss = 1
        for _ = 1, (swings or 3) do miss = miss * (1 - c) end
        return 1 - miss
    end,
}

-- Registry-wide helpers -------------------------------------------------------

-- The honesty mark: " (p)" for any formula not yet verified on Forever. One definition
-- so every surface (stats panel, tooltips) tags presumed values identically.
function F.presumedMark(entry)
    local c = entry and entry.confidence or ""
    if c:find("^verified") then return "" end
    return " (p)"
end

function F.get(name, classToken)
    local entry = F[name]
    if not entry then return nil end
    if entry.byClass then
        return classToken and entry.byClass[classToken] or nil, entry
    end
    return entry.fn, entry
end

function F.setConfidence(name, confidence)
    if F[name] then F[name].confidence = confidence end
end

return F
