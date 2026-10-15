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
    -- Blizzard's rendering is KIND-SPLIT (three live verifications, 2026-10-12):
    -- DAMAGE renders the widest integer envelope (floor min, ceil max - Lightning
    -- Bolt raw 25.4-29.4 -> "25 to 30"); HEALS render ROUND-HALF on both ends
    -- (Healing Wave r1 raw 36.4-47.2 -> "36 to 47", r2 raw 68.5-83.5 -> "69 to 83" -
    -- the /foresight audit mismatches that taught us this). The epsilon guards float
    -- noise (Fireball's stored variance puts the raw max at 22.0000001; naive ceil
    -- would claim 23).
    display = function(minv, maxv, kind)
        if kind == "heal" then
            return math.floor((minv or 0) + 0.5), math.floor((maxv or 0) + 0.5)
        end
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

-- LIVE SELF-VERIFY (S33) - the player's OWN captured talent tooltips are ground truth
-- for THIS client. A trained capture (rank>0) is scored against two hypotheses exactly
-- the way the offline harvest does (pipeline/harvest.py analyze_rank_rule), ported to
-- Lua: maxTotal => tooltip at rank R shows |maxValue|*R/maxRank; perRank => |maxValue|*R
-- (each with a /1000 ms->s variant). Whichever prediction appears among the tooltip's own
-- numbers wins. When a talent's captures settle a single, non-conflicting rule, that rule
-- drives this client's value path and the (p) mark flips to "verified from your scan".
-- Ambiguous or conflicting votes record nothing and the shipped/presumed rule stands - a
-- scan can only confirm or correct, never make the display worse.
local selfVerifyCache, selfVerifyStamp = nil, nil

-- Collect the description numbers from a captured tooltip for the vote. WoW escape codes
-- (colour |cAARRGGBB..|r, textures |T..|t, hyperlinks |H..|h) are stripped first so their
-- hex digits can't pollute the numbers; the name line and the "Rank N/M" line are skipped
-- exactly as the offline harvest's clean_tip_text does (their numbers aren't effect values).
local function tooltipNumbers(text)
    local s = tostring(text or "")
    s = s:gsub("|[cC]%x%x%x%x%x%x%x%x", ""):gsub("|[rR]", "")
    s = s:gsub("|[tT].-|[tT]", ""):gsub("|[hH].-|[hH]", ""):gsub("|[hH]", "")
    local nums, first = {}, true
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        local skip = first
        first = false
        if line:find("Rank", 1, true) and line:match("%d+%s*/%s*%d+") then skip = true end
        if line:find("Press F6", 1, true) then skip = true end
        if not skip then
            for n in line:gmatch("%d+%.?%d*") do nums[#nums + 1] = tonumber(n) end
        end
    end
    return nums
end

local function approxIn(nums, target)
    for i = 1, #nums do
        if math.abs(nums[i] - target) < 0.01 then return true end
    end
    return false
end

local function buildSelfVerified()
    local rules = {}
    local collect = HM.db and HM.db.collect
    local tips = collect and collect.talentTooltips
    local gen = HM.gen
    if type(tips) ~= "table" or not gen or type(gen.talents) ~= "table" then
        return rules
    end
    local byName = {} -- talent name -> id (mirrors harvest talents_by_name; first wins)
    for tid, t in pairs(gen.talents) do
        if type(t) == "table" and t.name and byName[t.name] == nil then
            byName[t.name] = tid
        end
    end
    local impactsAll = gen.talentImpacts or {}
    for _, e in pairs(tips) do
        if type(e) == "table" and type(e.rank) == "number" and e.rank > 0 then
            local rank = e.rank
            local name = e.name or (e.text and tostring(e.text):match("^([^\n]+)"))
            -- Resolve the capture to a talentId by name (classic) OR by the spell bridge
            -- (Forever trait nodes carry a spellID; node names needn't match talent names).
            local tid = name and byName[name]
            if tid == nil and e.spellID and HM.TalentAPI and HM.TalentAPI.talentForSpell then
                tid = tonumber(HM.TalentAPI.talentForSpell(e.spellID))
            end
            local talent = tid and gen.talents[tid]
            local impacts = tid and impactsAll[tid]
            if talent and type(impacts) == "table" and type(impacts.ops) == "table" then
                local maxRank = talent.maxRank or 1
                local nums = tooltipNumbers(e.text)
                local verdict = nil -- "maxTotal" | "perRank" | false (conflict)
                if maxRank > 0 and #nums > 0 then
                    for _, op in ipairs(impacts.ops) do
                        local v = math.abs(op.maxValue or 0)
                        if v > 0 then
                            local hitA = approxIn(nums, v * rank / maxRank)
                                or approxIn(nums, v / 1000 * rank / maxRank)
                            local hitB = approxIn(nums, v * rank)
                                or approxIn(nums, v / 1000 * rank)
                            local this = (hitA and not hitB and "maxTotal")
                                or (hitB and not hitA and "perRank") or nil
                            if this then
                                if verdict == nil then verdict = this
                                elseif verdict ~= this then verdict = false end
                            end
                        end
                    end
                end
                if verdict and verdict ~= false then rules[tid] = verdict end
            end
        end
    end
    return rules
end

-- Lazy, cached map of talentId -> player-verified rule. A cheap signature (capture count
-- plus the sum of ranks) rebuilds it when a new tooltip is captured OR an untrained
-- capture is upgraded to a trained one (the no-downgrade replace), without rebuilding on
-- every op lookup.
function F.selfVerifiedRules()
    local collect = HM.db and HM.db.collect
    local tips = collect and collect.talentTooltips
    -- Signature folds in each capture's KEY and rank (order-independent sum), not just the
    -- count+ranksum: adding talent A rank 2 and later a DIFFERENT talent B rank 2 to the
    -- same base would otherwise collide and return a stale map.
    local n, sig = 0, 0
    if type(tips) == "table" then
        for k, e in pairs(tips) do
            n = n + 1
            local kn = tonumber(k) or 0
            local rk = (type(e) == "table" and type(e.rank) == "number" and e.rank) or 0
            sig = sig + kn * 31 + rk
        end
    end
    local stamp = n * 1000000007 + sig
    if selfVerifyCache == nil or selfVerifyStamp ~= stamp then
        selfVerifyCache = buildSelfVerified()
        selfVerifyStamp = stamp
    end
    return selfVerifyCache
end

function F.selfVerifiedRule(talentId)
    if talentId == nil then return nil end
    return F.selfVerifiedRules()[talentId]
end

-- PER-TALENT rank value - THE one resolution path (S11 + S21 + S33), in order:
--   (1) op.values[rank] - datamined per-rank spell decode (S21), the truth, no rule;
--   (2) selfVerifiedRule(talentId) - the PLAYER'S OWN scanned rule (S33); local ground
--       truth outranks the shipped crowd rule;
--   (3) overrides.rankRules[talentId] - crowd-verified rule ("maxTotal" = value*N/maxRank,
--       "perRank" = value*N); entries arrive ONLY from the harvest draft
--       (collected/rank_rules_draft.lua) after human review;
--   (4) the global presumed default above, still tagged (p).
-- `values` is the generated per-op array (present only where every rank spell carried
-- aligned effect rows); callers pass op.values through - never a second math path.
-- Both "maxTotal" and the presumed default compute value*rank/maxRank, so only "perRank"
-- branches; everything else falls through to the one fn.
function F.talentRankValueFor(talentId, maxValue, rank, maxRank, values)
    if type(values) == "table" then
        local v = values[rank or 0]
        if type(v) == "number" then return v end
    end
    local rules = HM.overrides and HM.overrides.rankRules
    local rule = F.selfVerifiedRule(talentId)
        or (talentId and rules and rules[talentId])
    if rule == "perRank" then
        return (maxValue or 0) * (rank or 0)
    end
    return F.talentRankValue.fn(maxValue or 0, rank or 0, maxRank or 1)
end

-- The honesty mark for a specific talent's rank scaling: datamined per-rank values
-- (every op carries a values array) drop the (p), the player's own scan drops it, and
-- crowd-verified talents drop it too; everything else keeps the global presumed mark.
-- ops optional (the generated op list for this talent/node).
function F.rankRuleMark(talentId, ops)
    if type(ops) == "table" and #ops > 0 then
        local all = true
        for _, op in ipairs(ops) do
            if type(op) ~= "table" or not op.values then all = false end
        end
        if all then return "" end
    end
    if talentId and F.selfVerifiedRule(talentId) then return "" end
    local rules = HM.overrides and HM.overrides.rankRules
    if talentId and rules and rules[talentId] then return "" end
    return F.presumedMark(F.talentRankValue)
end

-- Which source settles this talent's rank scaling, for the honesty header:
-- "datamined" | "scan" (the player's own capture) | "crowd" | "presumed".
function F.rankRuleSource(talentId, ops)
    if type(ops) == "table" and #ops > 0 then
        local all = true
        for _, op in ipairs(ops) do
            if type(op) ~= "table" or not op.values then all = false end
        end
        if all then return "datamined" end
    end
    if talentId and F.selfVerifiedRule(talentId) then return "scan" end
    local rules = HM.overrides and HM.overrides.rankRules
    if talentId and rules and rules[talentId] then return "crowd" end
    return "presumed"
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
