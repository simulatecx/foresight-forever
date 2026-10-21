-- Foresight what-if plan (WHATIF-planner): a persistent, user-composed "future build" -
-- an ordered list of typed deltas (gear stats to hunt, talents to take, buffs to run,
-- a race to compare) evaluated against the CURRENT character. Pure composition over the
-- one loadout delta stack (model/loadout.lua) - this module adds no value math.
-- SavedVariables are user-editable: every read passes validate() (untrusted-input law);
-- garbage entries are dropped, never errored on.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Plan = {}
HM.Plan = Plan

-- Stats a plan delta may move: the base graph nodes withStatDelta can target.
-- S25: the six school pools are first-class plan stats.
local PLAN_STATS = {
    Strength = true, Agility = true, Stamina = true, Intellect = true, Spirit = true,
    spellDamage = true, spellPower = true, healingPower = true, armor = true,
    ["school.holy"] = true, ["school.fire"] = true, ["school.nature"] = true,
    ["school.frost"] = true, ["school.shadow"] = true, ["school.arcane"] = true,
}
Plan.stats = PLAN_STATS

-- S28b: plan GOAL abilities (validated on read like everything else; cap 3; only
-- decoded spells qualify - a goal must be judgeable).
function Plan.goals()
    local db = HM.charDb and HM.charDb()
    local g = db and db.settings and db.settings.planGoals
    local out = {}
    if type(g) == "table" then
        for _, sid in ipairs(g) do
            sid = tonumber(sid)
            local sp = sid and HM.gen and HM.gen.spells and HM.gen.spells[sid]
            if sp and (sp.dmg or sp.heal or sp.wpn) and #out < 3 then
                out[#out + 1] = sid
            end
        end
    end
    return out
end

local MAX_DELTAS = 20
local MAX_AMOUNT = 1000
local MAX_LABEL = 40

local function cleanAmount(v)
    local n = tonumber(v)
    if not n or n ~= n or n == 0 or n < -MAX_AMOUNT or n > MAX_AMOUNT then return nil end
    return n
end

-- Validate ONE raw delta -> clean copy or nil. Existence checks go against the
-- generated data so a stale/tampered plan can never reference unknown content.
function Plan.validateDelta(d)
    if type(d) ~= "table" or type(d.type) ~= "string" then return nil end
    local gen = HM.gen or {}
    if d.type == "stat" then
        local amount = cleanAmount(d.amount)
        if PLAN_STATS[d.stat] and amount then
            return { type = "stat", stat = d.stat, amount = amount }
        end
    elseif d.type == "item" then
        if type(d.stats) ~= "table" then return nil end
        local stats, any = {}, false
        for stat, amount in pairs(d.stats) do
            local n = cleanAmount(amount)
            if PLAN_STATS[stat] and n then stats[stat] = n; any = true end
        end
        local label = type(d.label) == "string" and d.label:sub(1, MAX_LABEL) or "item"
        if any then return { type = "item", label = label, stats = stats } end
    elseif d.type == "trait" then
        local node = HM.formulas.impactNodes()[d.nodeId]
        if node then
            local maxRank = node.maxRank or 1
            local rank = tonumber(d.rank) or maxRank
            if rank >= 1 and rank <= maxRank then
                return { type = "trait", nodeId = d.nodeId, rank = math.floor(rank) }
            end
        end
    elseif d.type == "buff" then
        if gen.consumables and (gen.consumables[d.id]
                or (gen.buffsBySpell and gen.buffsBySpell[d.id])) then
            return { type = "buff", id = d.id }
        end
    elseif d.type == "racial" then
        if gen.racialsBySpell and gen.racialsBySpell[d.spellID] then
            return { type = "racial", spellID = d.spellID }
        end
    elseif d.type == "race" then
        if gen.racials and gen.racials[d.raceId] then
            return { type = "race", raceId = d.raceId }
        end
    end
    return nil
end

-- Validate a whole raw plan -> clean list (+ count of dropped entries).
function Plan.validate(raw)
    local clean, dropped = {}, 0
    if type(raw) ~= "table" then return clean, type(raw) ~= "nil" and 1 or 0 end
    for _, d in ipairs(raw) do
        local ok = #clean < MAX_DELTAS and Plan.validateDelta(d) or nil
        if ok then clean[#clean + 1] = ok else dropped = dropped + 1 end
    end
    return clean, dropped
end

-- The persisted plan for this character (validated on every read; writes store the
-- cleaned list so tampering heals on first touch).
function Plan.store()
    if not (HM.charDb) then return {} end
    local db = HM.charDb()
    local clean = Plan.validate(db.plan)
    db.plan = clean
    return clean
end

function Plan.save(list)
    if not (HM.charDb) then return end
    HM.charDb().plan = Plan.validate(list)
end

-- Human label for a delta (used by the panel rows, /foresight plan, and sources).
function Plan.describe(d)
    local gen = HM.gen or {}
    if d.type == "stat" then
        return ("%+g %s"):format(d.amount, d.stat)
    elseif d.type == "item" then
        local parts = {}
        for stat, amount in pairs(d.stats) do
            parts[#parts + 1] = ("%+g %s"):format(amount, stat)
        end
        table.sort(parts)
        return ("%s (%s)"):format(d.label, table.concat(parts, ", "))
    elseif d.type == "trait" then
        local node = HM.formulas.impactNodes()[d.nodeId]
        local maxRank = node and node.maxRank or 1
        local name = node and node.name or ("node " .. tostring(d.nodeId))
        if maxRank > 1 then return ("%s %d/%d"):format(name, d.rank, maxRank) end
        return name
    elseif d.type == "buff" then
        local entry = gen.consumables and (gen.consumables[d.id]
            or (gen.buffsBySpell and gen.consumables[gen.buffsBySpell[d.id]]))
        return entry and entry.name or ("buff " .. tostring(d.id))
    elseif d.type == "racial" then
        local sp = HM.Racials and HM.Racials.bySpell(d.spellID)
        return (sp and sp.name or tostring(d.spellID)) .. " (racial)"
    elseif d.type == "race" then
        local race = gen.racials and gen.racials[d.raceId]
        return "as " .. (race and race.name or ("race " .. tostring(d.raceId)))
    end
    return "?"
end

-- Compose the plan onto a loadout through the ONE delta stack. No new math.
function Plan.apply(loadout, list)
    local modeled = loadout
    for _, d in ipairs(list or {}) do
        if d.type == "stat" then
            modeled = modeled:withStatDelta(d.stat, d.amount, Plan.describe(d))
        elseif d.type == "item" then
            for stat, amount in pairs(d.stats) do
                modeled = modeled:withStatDelta(stat, amount, d.label)
            end
        elseif d.type == "trait" then
            modeled = modeled:withTraitNode(d.nodeId, d.rank)
        elseif d.type == "buff" then
            modeled = modeled:withBuff(d.id)
        elseif d.type == "racial" then
            modeled = modeled:withRacial(d.spellID)
        elseif d.type == "race" then
            modeled = modeled:withRace(d.raceId)
        end
    end
    return modeled
end

-- Net effect of the plan: dimension changes + the derived stat chain, one diff.
function Plan.summary(loadout, list)
    local modeled = Plan.apply(loadout, list)
    local changes = HM.Impact.diff(loadout, modeled)
    local chain = HM.Impact.chainLines(loadout, modeled)
    return changes, chain
end

-- Find a trait node by (case-insensitive) name or substring; exact match wins.
function Plan.findTraitNode(name)
    if type(name) ~= "string" or name == "" then return nil end
    local q = name:lower()
    local nodes = HM.formulas.impactNodes()
    local partial
    for nid, node in pairs(nodes) do
        local n = (node.name or ""):lower()
        if n == q then return nid, node end
        if not partial and n:find(q, 1, true) then partial = nid end
    end
    return partial, partial and nodes[partial] or nil
end

-- Find a consumable by (case-insensitive) name substring or itemId.
function Plan.findConsumable(query)
    local gen = HM.gen or {}
    if not gen.consumables then return nil end
    local id = tonumber(query)
    if id and gen.consumables[id] then return id, gen.consumables[id] end
    if type(query) ~= "string" or query == "" then return nil end
    local q = query:lower()
    local bestId
    for iid, entry in pairs(gen.consumables) do
        local n = (entry.name or ""):lower()
        if n == q then return iid, entry end
        if n:find(q, 1, true) and (not bestId or iid < bestId) then bestId = iid end
    end
    return bestId, bestId and gen.consumables[bestId] or nil
end

return Plan
