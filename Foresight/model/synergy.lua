-- Foresight synergy engine: which talents work together. Every trait node's effects are
-- already decoded (stat boosts, affected spells, school damage, mechanics) in the
-- generated trait data, so a "synergy" is just a group of nodes that push the same lever.
-- Pick a theme - "Intellect", "Lightning Bolt", "crit" - and see every node that feeds it
-- (the Diablo-paragon "show me everything Intelligence" selection). Chained synergies
-- (A boosts Int -> B converts Int to AP) are a later layer; this is the direct grouping.
-- Pure Lua, selftest-covered; reads only generated data.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Synergy = {}
HM.Synergy = Synergy

local cache

local function addTo(group, key, nodeId)
    local list = group[key]
    if not list then list = {}; group[key] = list end
    for _, n in ipairs(list) do if n == nodeId then return end end
    list[#list + 1] = nodeId
end

-- Mechanic lever a spellmod property maps to (coarse buckets players think in).
local function mechanicOf(property)
    if not property then return nil end
    if property:find("crit") then return "crit" end
    if property:find("cost") then return "cost" end
    if property == "cast time" then return "cast time" end
    if property == "cooldown" then return "cooldown" end
    if property:find("threat") then return "threat" end
    return nil
end

-- Build the theme index once: { stat={[stat]=nodes}, spell={[name]=nodes},
-- school={[school]=nodes}, mechanic={[lever]=nodes} }.
function Synergy.build()
    if cache then return cache end
    cache = { stat = {}, spell = {}, school = {}, mechanic = {} }
    local nodes = (HM.gen and HM.gen.traits and HM.gen.traits.nodes) or {}
    local spells = (HM.gen and HM.gen.spells) or {}
    for nid, node in pairs(nodes) do
        for _, op in ipairs(node.ops or {}) do
            if op.kind == "stat" and op.stat then
                addTo(cache.stat, op.stat, nid)
            elseif op.kind == "schoolDamage" and op.school then
                addTo(cache.school, op.school, nid)
            elseif op.kind == "threat" then
                addTo(cache.mechanic, "threat", nid)
            elseif op.kind == "spellmod" then
                local lever = mechanicOf(op.property)
                if lever then addTo(cache.mechanic, lever, nid) end
                for _, sid in ipairs(op.affected or {}) do
                    local sp = spells[sid]
                    if sp and sp.name then addTo(cache.spell, sp.name, nid) end
                end
            end
        end
    end
    return cache
end

function Synergy._reset() cache = nil end -- test hook

local function nodeName(nid)
    local node = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nid]
    return node and node.name or ("node:" .. tostring(nid))
end

-- The concise themes a node belongs to (stat/school/mechanic only - not its many spell
-- themes), each with how many OTHER nodes share it. Feeds the tooltip "Synergy:" line.
function Synergy.themesFor(nodeId)
    local c = Synergy.build()
    local out = {}
    for _, group in ipairs({ { c.stat, "" }, { c.school, " damage" }, { c.mechanic, "" } }) do
        for key, list in pairs(group[1]) do
            local has, others = false, 0
            for _, n in ipairs(list) do
                if n == nodeId then has = true else others = others + 1 end
            end
            if has and others > 0 then
                out[#out + 1] = { label = key .. group[2], key = key, others = others }
            end
        end
    end
    table.sort(out, function(a, b) return a.others > b.others end)
    return out
end

-- Resolve a free-text query to a theme and return the member node names (sorted).
-- Matches a stat, a mechanic lever, a school, or a spell-name substring (in that order).
function Synergy.query(q)
    local c = Synergy.build()
    q = (q or ""):lower()
    if q == "" then return nil end
    local function names(list)
        local ns = {}
        for _, nid in ipairs(list or {}) do ns[#ns + 1] = nodeName(nid) end
        table.sort(ns)
        return ns
    end
    for key, list in pairs(c.stat) do
        if key:lower() == q then return { label = key, nodes = names(list) } end
    end
    for key, list in pairs(c.mechanic) do
        if key:lower() == q or (q == "mana" and key == "cost") then
            return { label = key, nodes = names(list) }
        end
    end
    for key, list in pairs(c.school) do
        if key:lower():find(q, 1, true) then return { label = key .. " damage", nodes = names(list) } end
    end
    -- Spell-name substring (e.g. "lightning").
    local matchKey, matchList, best
    for key, list in pairs(c.spell) do
        if key:lower():find(q, 1, true) then
            if not best or #list > best then best = #list; matchKey = key; matchList = list end
        end
    end
    if matchKey then return { label = matchKey, nodes = names(matchList) } end
    return nil
end

-- The themes available to browse (for a no-argument listing).
function Synergy.themes()
    local c = Synergy.build()
    local out = {}
    for key, list in pairs(c.stat) do out[#out + 1] = key .. " (" .. #list .. ")" end
    for key, list in pairs(c.mechanic) do out[#out + 1] = key .. " (" .. #list .. ")" end
    for key, list in pairs(c.school) do out[#out + 1] = key .. " damage (" .. #list .. ")" end
    table.sort(out)
    return out
end

return Synergy
