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

-- Model taking a Retail trait node (Forever's live talents) - same what-if as withTalent
-- but keyed by the C_Traits node id, so new Forever nodes (no classic talent) model too.
function Loadout:withTraitNode(nodeId, rank)
    return copyDeltas(self, { type = "trait", nodeId = nodeId, rank = rank })
end

-- Model a raw stat change ("what does +2 Spirit do?"): stat key as in snapshot.stats.
function Loadout:withStatDelta(stat, amount, label)
    return copyDeltas(self, { type = "stat", stat = stat, amount = amount, label = label })
end

-- Model one racial passive (what-if). NOTE: a live snapshot already contains your own
-- race's passives inside its stat reads - these deltas exist for cross-race questions
-- and synthetic snapshots, never as an unconditional fold of the current race.
function Loadout:withRacial(spellID)
    return copyDeltas(self, { type = "racial", spellID = spellID })
end

-- Model a whole race's passive kit (class-gated), e.g. "what would a Gnome get?".
function Loadout:withRace(raceId)
    return copyDeltas(self, { type = "race", raceId = raceId })
end

-- Model a consumable buff being active (CONSUME-buffs). Accepts the itemId from the
-- generated consumables table or the buff's spellId (what a live aura read returns).
-- Diffing base vs withBuff gives "while active +X"; the same numbers sign-flipped are
-- the expiry loss. (An ALREADY-active buff is inside your live snapshot stats - the
-- delta answers "what is this worth / what do I lose", not "add it twice".)
function Loadout:withBuff(id)
    return copyDeltas(self, { type = "buff", id = id })
end

local STAT_NODE = {
    Strength = "stat.strength", Agility = "stat.agility", Stamina = "stat.stamina",
    Intellect = "stat.intellect", Spirit = "stat.spirit",
}
local STAT_KEY = { -- display stat name -> snapshot.stats key (conversion source)
    Strength = "strength", Agility = "agility", Stamina = "stamina",
    Intellect = "intellect", Spirit = "spirit",
}
local CONVERT_NODE = { -- statConvert target -> graph node it adds into
    attackPower = "stat.attackPower", spellDamage = "stat.spellDamage",
    healingPower = "stat.healingPower",
}

-- Fold a list of impact ops (classic talent OR trait node - identical op shape) into the
-- graph at the given rank. The one place talent/trait effects become modifiers.
-- snapStats (the snapshot's live stats) backs statConvert ops - "AP = N% of Intellect"
-- folds as a flat amount off the player's current source stat.
local function applyOps(graph, ops, rank, maxRank, source, snapStats, talentId)
    -- talentId (optional) routes through the PER-TALENT rank rule when the crowd has
    -- verified one (overrides.rankRules); op.values (S21 datamined per-rank decode)
    -- outranks both; nil falls back to the global default.
    for _, op in ipairs(ops or {}) do
        local value = HM.formulas.talentRankValueFor(talentId, op.maxValue or 0, rank,
            maxRank, op.values)
        if op.kind == "statConvert" and CONVERT_NODE[op.to] then
            local srcVal = (snapStats and STAT_KEY[op.from] and snapStats[STAT_KEY[op.from]]) or 0
            graph:addModifier{ target = CONVERT_NODE[op.to], op = "flat",
                               value = srcVal * value / 100, source = source }
        elseif op.kind == "stat" and STAT_NODE[op.stat] then
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
        elseif op.kind == "maxHealth" then
            -- "Total Health increased by X%" (Tauren Endurance) or flat +X (Flask
            -- of the Titans).
            graph:addModifier{ target = "stat.maxHealth",
                               op = op.isPct and "pctAdd" or "flat",
                               value = value, source = source }
        elseif op.kind == "maxPower" and op.isPct and op.powerType == 0 then
            -- "Maximum Mana increased by X%" (e.g. Expansive Mind). Rage/energy
            -- variants have no graph node yet and stay tooltip-only.
            graph:addModifier{ target = "stat.maxMana", op = "pctAdd",
                               value = value, source = source }
        elseif op.kind == "critChance" then
            -- Unconditional crit % (Elixir of the Mongoose): all three crit stats.
            graph:addModifier{ target = "stat.meleeCritPct", op = "flat",
                               value = value, source = source }
            graph:addModifier{ target = "stat.spellCritPct", op = "flat",
                               value = value, source = source }
            graph:addModifier{ target = "stat.rangedCritPct", op = "flat",
                               value = value, source = source }
        elseif op.kind == "armor" then
            graph:addModifier{ target = "stat.armor", op = "flat",
                               value = value, source = source }
        elseif op.kind == "attackPower" then
            graph:addModifier{ target = "stat.attackPower", op = "flat",
                               value = value, source = source }
        elseif op.kind == "rangedAttackPower" then
            graph:addModifier{ target = "stat.rangedAttackPower", op = "flat",
                               value = value, source = source }
        end
        -- Other ops (cast time, cost, cooldown...) surface via tooltip/explain for now;
        -- folding them into throughput needs per-spell rotation weights (post-beta).
    end
end

local function addTalentModifiers(graph, talentId, rank, source, snapStats)
    local impacts = HM.gen and HM.gen.talentImpacts and HM.gen.talentImpacts[talentId]
    local talent = HM.gen and HM.gen.talents and HM.gen.talents[talentId]
    if not impacts or not talent then return false end
    applyOps(graph, impacts.ops, rank, talent.maxRank, source, snapStats, talentId)
    return true
end

-- Trait-node modifiers (Forever's live talents, incl. new nodes with no classic talent).
local function addTraitModifiers(graph, nodeId, rank, source, snapStats)
    local node = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nodeId]
    if not node then return false end
    -- Bridge to the classic talent id (when one exists) so a crowd-verified per-talent
    -- rank rule applies to the trait-node what-if path too.
    local talentId = HM.TalentAPI and HM.TalentAPI.talentForSpell
        and node.spellID and HM.TalentAPI.talentForSpell(node.spellID) or nil
    applyOps(graph, node.ops, rank, node.maxRank or 1, source, snapStats,
        tonumber(talentId))
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
    local snapStr, snapAgi, snapInt, snapSta =
        s.stats.strength or 0, s.stats.agility or 0, s.stats.intellect or 0,
        s.stats.stamina or 0

    -- Marginal crit-per-point: DERIVE it from the character's own live crit and stat
    -- (critPct / stat), which auto-scales to level and gear - far more accurate than a
    -- fixed level-60 constant (which badly understated crit from Agility while leveling).
    -- Falls back to the classic constant when live crit is unavailable (e.g. tests).
    local liveAgiPerCrit = (snapAgi > 0 and (s.stats.meleeCritPct or 0) > 0)
        and (snapAgi / s.stats.meleeCritPct) or conv.agiPerCrit
    local liveIntPerCrit = (snapInt > 0 and (s.stats.spellCritPct or 0) > 0)
        and (snapInt / s.stats.spellCritPct) or conv.intPerSpellCrit
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
                   return (s.stats.meleeCritPct or 0)
                       + (liveAgiPerCrit and (get("stat.agility") - snapAgi) / liveAgiPerCrit or 0)
               end }
    g:addNode{ id = "stat.spellCritPct", kind = "stat",
               formula = function(get)
                   return (s.stats.spellCritPct or 0)
                       + (liveIntPerCrit and (get("stat.intellect") - snapInt) / liveIntPerCrit or 0)
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
    -- Pool maxima: the LIVE sheet value is the base (it already contains every rule
    -- the server applies - the classic per-point formulas overstate low levels); only
    -- the MARGINAL stat change converts at 10 hp/stamina and 15 mana/int ((p)).
    g:addNode{ id = "stat.maxHealth", kind = "stat",
               formula = function(get)
                   return (s.stats.maxHealth or 0) + (get("stat.stamina") - snapSta) * 10
               end }
    g:addNode{ id = "stat.maxMana", kind = "stat",
               formula = function(get)
                   return (s.stats.maxMana or 0) + (get("stat.intellect") - snapInt) * 15
               end }
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
            local ok = addTalentModifiers(g, d.talentId, d.rank, "talent:" .. d.talentId, s.stats)
            if not ok then
                notes[#notes + 1] = "unknown talent " .. tostring(d.talentId)
            end
        elseif d.type == "trait" then
            local ok = addTraitModifiers(g, d.nodeId, d.rank, "trait:" .. tostring(d.nodeId), s.stats)
            if not ok then
                notes[#notes + 1] = "unknown trait node " .. tostring(d.nodeId)
            end
        elseif d.type == "racial" then
            local sp = HM.Racials and HM.Racials.bySpell(d.spellID)
            if not sp then
                notes[#notes + 1] = "unknown racial " .. tostring(d.spellID)
            elseif not HM.Racials.classMatches(sp.classMask, s.classToken) then
                notes[#notes + 1] = sp.name .. " does not apply to your class"
            else
                applyOps(g, sp.ops, 1, 1, "racial:" .. tostring(d.spellID), s.stats)
            end
        elseif d.type == "buff" then
            local gen = HM.gen
            local entry = gen and gen.consumables and gen.consumables[d.id]
            if not entry and gen and gen.buffsBySpell and gen.buffsBySpell[d.id] then
                entry = gen.consumables[gen.buffsBySpell[d.id]]
            end
            if entry then
                applyOps(g, entry.ops, 1, 1, "buff:" .. tostring(d.id), s.stats)
            else
                notes[#notes + 1] = "unknown buff " .. tostring(d.id)
            end
        elseif d.type == "race" then
            local kit = HM.Racials and HM.Racials.forRace(d.raceId, s.classToken, true) or {}
            for _, sp in ipairs(kit) do
                applyOps(g, sp.ops, 1, 1, "racial:" .. tostring(sp.spellID), s.stats)
            end
            if s.raceId then
                -- Honest-compare caveat: your own race's passives stay baked into the
                -- live snapshot stats; this delta only ADDS the modeled race's kit.
                notes[#notes + 1] = "race what-if adds the modeled race's passives; your current racials remain in your stats"
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
