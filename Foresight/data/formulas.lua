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

-- Registry-wide helpers -------------------------------------------------------

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
