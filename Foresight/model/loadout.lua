-- Foresight loadout: a character snapshot plus a stack of what-if deltas (talents, stat
-- tweaks, items later). build() produces an impact graph ready for dimension scoring,
-- so "current self" and "modeled self" are the same machinery with different deltas.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Loadout = {}
Loadout.__index = Loadout
HM.Loadout = Loadout

-- snapshot = { classToken = "MAGE", level = 60, stats = { spirit=100, intellect=120,
--   stamina=80, strength=40, agility=50, spellDamage=0, healingPower=0, attackPower=0,
--   rangedAttackPower=0, spellCritPct=0, meleeCritPct=0, rangedCritPct=0, hastePct=0,
--   armor=0, avoidancePct=0 }, weaponSpeed = 2.0, talents = { [talentId]=rank } }
function Loadout.fromSnapshot(snapshot)
    assert(snapshot and snapshot.classToken and snapshot.stats, "snapshot requires classToken and stats")
    return setmetatable({ snapshot = snapshot, deltas = {} }, Loadout)
end

local function copyDeltas(self, extra)
    local l = Loadout.fromSnapshot(self.snapshot)
    for i, d in ipairs(self.deltas) do l.deltas[i] = d end
    l.deltas[#l.deltas + 1] = extra
    return l
end

-- Model taking (or changing) a talent: returns a NEW loadout, original untouched.
function Loadout:withTalent(talentId, rank)
    return copyDeltas(self, { type = "talent", talentId = talentId, rank = rank })
end

-- Model a raw stat change ("what does +2 Spirit do?"): stat key as in snapshot.stats.
function Loadout:withStatDelta(stat, amount, label)
    return copyDeltas(self, { type = "stat", stat = stat, amount = amount, label = label })
end

local STAT_NODE = {
    Strength = "stat.strength", Agility = "stat.agility", Stamina = "stat.stamina",
    Intellect = "stat.intellect", Spirit = "stat.spirit",
}

local function addTalentModifiers(graph, talentId, rank, source)
    local impacts = HM.gen and HM.gen.talentImpacts and HM.gen.talentImpacts[talentId]
    local talent = HM.gen and HM.gen.talents and HM.gen.talents[talentId]
    if not impacts or not talent then return false end
    local rankValue = HM.formulas.talentRankValue.fn
    for _, op in ipairs(impacts.ops or {}) do
        local value = rankValue(op.maxValue or 0, rank, talent.maxRank)
        if op.kind == "stat" and STAT_NODE[op.stat] then
            graph:addModifier{
                target = STAT_NODE[op.stat],
                op = op.isPct and "pctAdd" or "flat",
                value = value, source = source,
            }
        elseif op.kind == "stat" and op.stat == "all stats" then
            for _, node in pairs(STAT_NODE) do
                graph:addModifier{ target = node, op = op.isPct and "pctAdd" or "flat",
                                   value = value, source = source }
            end
        elseif op.kind == "schoolDamage" and op.isPct then
            graph:addModifier{ target = "agg.spellThroughputPct", op = "flat",
                               value = value, source = source }
        elseif op.kind == "spellmod" and op.property == "damage/healing" and op.isPct then
            -- v0: percent damage/healing on specific spells feeds the throughput
            -- aggregate; the precise affected-spell list stays available for tooltips.
            graph:addModifier{ target = "agg.spellThroughputPct", op = "flat",
                               value = value, source = source }
        elseif op.kind == "spellmod" and op.property == "crit chance" then
            graph:addModifier{ target = "stat.spellCritPct", op = "flat",
                               value = value, source = source }
        elseif op.kind == "threat" then
            -- Threat % modifier (own-state): sums into the threat lens. A -20 op means
            -- 20% less threat. Per-ability threat + stance stay future (overrides k-of-n).
            graph:addModifier{ target = "agg.threatModPct", op = "flat",
                               value = value, source = source }
        end
        -- Other ops (cast time, cost, cooldown...) surface via tooltip/explain for now;
        -- folding them into throughput needs per-spell rotation weights (post-beta).
    end
    return true
end

-- Build the evaluated graph: base nodes seeded from the snapshot, modifiers from deltas.
function Loadout:build()
    local g = HM.Graph.new()
    local s = self.snapshot
    local F = HM.formulas

    -- Stat nodes (base values from snapshot).
    local baseStats = {
        ["stat.strength"] = s.stats.strength or 0,
        ["stat.agility"] = s.stats.agility or 0,
        ["stat.stamina"] = s.stats.stamina or 0,
        ["stat.intellect"] = s.stats.intellect or 0,
        ["stat.spirit"] = s.stats.spirit or 0,
        ["stat.spellDamage"] = s.stats.spellDamage or 0,
        ["stat.healingPower"] = s.stats.healingPower or 0,
        ["stat.rangedCritPct"] = s.stats.rangedCritPct or 0,
        ["stat.hastePct"] = s.stats.hastePct or 0,
        ["stat.armor"] = s.stats.armor or 0,
        ["agg.avoidancePct"] = s.stats.avoidancePct or 0,
        ["agg.spellThroughputPct"] = 0,
        ["agg.healingThroughputPct"] = 0,
        ["agg.meleeThroughputPct"] = 0,
        ["agg.rangedThroughputPct"] = 0,
        ["agg.threatModPct"] = 0, -- talent threat modifiers sum here (negative = less threat)
    }
    for id in pairs(baseStats) do
        g:addNode{ id = id, kind = id:find("^agg") and "aggregate" or "stat" }
    end

    -- Derived combat stats: the game's reported AP/crit already INCLUDES primary-stat
    -- contributions, so these nodes apply classic conversion rates only to the
    -- MARGINAL stat change vs the snapshot (what-if deltas, talent stat boosts).
    local conv = (F.statConversions.byClass or {})[s.classToken] or {}
    local snapStr, snapAgi, snapInt =
        s.stats.strength or 0, s.stats.agility or 0, s.stats.intellect or 0
    g:addNode{ id = "stat.attackPower", kind = "stat",
               formula = function(get)
                   return (s.stats.attackPower or 0)
                       + (get("stat.strength") - snapStr) * (conv.apPerStr or 0)
                       + (get("stat.agility") - snapAgi) * (conv.apPerAgi or 0)
               end }
    g:addNode{ id = "stat.rangedAttackPower", kind = "stat",
               formula = function(get)
                   return (s.stats.rangedAttackPower or 0)
                       + (get("stat.agility") - snapAgi) * (conv.rapPerAgi or 0)
               end }
    g:addNode{ id = "stat.meleeCritPct", kind = "stat",
               formula = function(get)
                   local perCrit = conv.agiPerCrit
                   return (s.stats.meleeCritPct or 0)
                       + (perCrit and (get("stat.agility") - snapAgi) / perCrit or 0)
               end }
    g:addNode{ id = "stat.spellCritPct", kind = "stat",
               formula = function(get)
                   local perCrit = conv.intPerSpellCrit
                   return (s.stats.spellCritPct or 0)
                       + (perCrit and (get("stat.intellect") - snapInt) / perCrit or 0)
               end }

    -- Mechanic + outcome nodes (formula-driven).
    local manaFn = (F.manaRegenTick.byClass or {})[s.classToken]
    g:addNode{ id = "mech.manaPerTick", kind = "mechanic",
               formula = function(get) return manaFn and manaFn(get("stat.spirit")) or 0 end }
    local healthFn = (F.healthRegenTick.byClass or {})[s.classToken]
    g:addNode{ id = "mech.healthPerTick", kind = "mechanic",
               formula = function(get) return healthFn and healthFn(get("stat.spirit")) or 0 end }
    g:addNode{ id = "mech.swingTime", kind = "mechanic",
               formula = function(get) return F.swingTime.fn(s.weaponSpeed or 2.0, get("stat.hastePct")) end }
    g:addNode{ id = "stat.maxHealth", kind = "stat",
               formula = function(get) return (s.stats.baseHealth or 0) + get("stat.stamina") * 10 end }
    g:addNode{ id = "stat.maxMana", kind = "stat",
               formula = function(get) return (s.stats.baseMana or 0) + get("stat.intellect") * 15 end }
    g:addNode{ id = "mech.armorMitigation", kind = "mechanic",
               formula = function(get) return F.armorMitigation.fn(get("stat.armor"), s.level or 60) end }
    g:addNode{ id = "outcome.effectiveHealth", kind = "outcome",
               formula = function(get)
                   return get("stat.maxHealth") / (1 - get("mech.armorMitigation"))
               end }

    -- Apply deltas.
    local notes = {}
    for i, d in ipairs(self.deltas) do
        if d.type == "talent" then
            local ok = addTalentModifiers(g, d.talentId, d.rank, "talent:" .. d.talentId)
            if not ok then
                notes[#notes + 1] = "unknown talent " .. tostring(d.talentId)
            end
        elseif d.type == "stat" then
            local node = STAT_NODE[d.stat] or ("stat." .. d.stat)
            if g:getNode(node) then
                g:addModifier{ target = node, op = "flat", value = d.amount,
                               source = d.label or ("delta:" .. d.stat) }
            else
                notes[#notes + 1] = "unknown stat node " .. node
            end
        end
    end

    return { graph = g, ctx = { base = baseStats, snapshot = s }, notes = notes }
end

return Loadout
