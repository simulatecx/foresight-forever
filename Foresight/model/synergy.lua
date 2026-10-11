-- Foresight synergy engine: which impact sources work together. Every source's effects
-- are already decoded into the ONE op shape (trait nodes, racials, consumable buffs),
-- so a "synergy" is just a group of sources that push the same lever. Pick a theme -
-- "Intellect", "Lightning Bolt", "crit" - and see everything that feeds it (the
-- Diablo-paragon "show me everything Intelligence" selection). Members are trait
-- nodeIds (numbers) plus typed refs ("racial:<spellID>", "buff:<itemId>") when player
-- context (race/class/active buffs) is supplied; with no context the index is the
-- static trait-only view. Chained synergies (A boosts Int -> B converts Int to AP) are
-- a later layer. Pure Lua, selftest-covered; reads only generated data.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Synergy = {}
HM.Synergy = Synergy

local cache, cacheKey

local function addTo(group, key, member)
    local list = group[key]
    if not list then list = {}; group[key] = list end
    for _, n in ipairs(list) do if n == member then return end end
    list[#list + 1] = member
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

-- player (optional): { raceId, classToken, buffs = captureActiveBuffs() shape or
-- plain itemIds }. The cache rebuilds when this context changes.
local function playerKey(player)
    if not player then return "static" end
    local ids = {}
    for _, b in ipairs(player.buffs or {}) do
        ids[#ids + 1] = type(b) == "table" and b.itemId or b
    end
    table.sort(ids)
    return tostring(player.raceId or "") .. ":" .. tostring(player.classToken or "")
        .. ":" .. table.concat(ids, ",")
end

-- statConvert output -> the mechanic theme it feeds (so converters group with the
-- direct sources of that output; "spell damage"/"healing" join "attack power").
local CONVERT_THEME = {
    attackPower = "attack power", spellDamage = "spell damage", healingPower = "healing",
}

-- Build the theme index: { stat={[stat]=members}, spell={[name]=members},
-- school={[school]=members}, mechanic={[lever]=members}, converts={bridges} }.
function Synergy.build(player)
    local key = playerKey(player)
    if cache and cacheKey == key then return cache end
    cache = { stat = {}, spell = {}, school = {}, mechanic = {}, converts = {} }
    cacheKey = key
    local spells = (HM.gen and HM.gen.spells) or {}

    -- ONE op-walker for every source kind - the whole point of the shared op shape.
    local function ingest(member, ops)
        for _, op in ipairs(ops or {}) do
            if op.kind == "stat" and op.stat then
                addTo(cache.stat, op.stat, member)
            elseif op.kind == "schoolDamage" and op.school then
                addTo(cache.school, op.school, member)
            elseif op.kind == "threat" then
                addTo(cache.mechanic, "threat", member)
            elseif op.kind == "critChance" then
                addTo(cache.mechanic, "crit", member)
            elseif op.kind == "maxHealth" then
                addTo(cache.mechanic, "health", member)
            elseif op.kind == "maxPower" and op.powerType == 0 then
                addTo(cache.mechanic, "max mana", member)
            elseif op.kind == "armor" then
                addTo(cache.mechanic, "armor", member)
            elseif op.kind == "attackPower" or op.kind == "rangedAttackPower" then
                addTo(cache.mechanic, "attack power", member)
            elseif op.kind == "statConvert" then
                -- The chained-synergy bridge: a converter scales an OUTPUT from a
                -- primary stat. It belongs to BOTH the source-stat theme (it rewards
                -- stacking that stat) and the output theme (it is an output source) -
                -- and we record the bridge so a query can explain the chain.
                local outTheme = CONVERT_THEME[op.to] or op.to
                if op.from then addTo(cache.stat, op.from, member) end
                addTo(cache.mechanic, outTheme, member)
                cache.converts[#cache.converts + 1] =
                    { member = member, from = op.from, to = outTheme }
            elseif op.kind == "spellmod" then
                local lever = mechanicOf(op.property)
                if lever then addTo(cache.mechanic, lever, member) end
                for _, sid in ipairs(op.affected or {}) do
                    local sp = spells[sid]
                    if sp and sp.name then addTo(cache.spell, sp.name, member) end
                end
            end
        end
    end

    for nid, node in pairs((HM.gen and HM.gen.traits and HM.gen.traits.nodes) or {}) do
        ingest(nid, node.ops)
    end
    if player and player.raceId and HM.Racials then
        for _, sp in ipairs(HM.Racials.forRace(player.raceId, player.classToken, true)) do
            ingest("racial:" .. sp.spellID, sp.ops)
        end
    end
    if player then
        for _, b in ipairs(player.buffs or {}) do
            local itemId = type(b) == "table" and b.itemId or b
            local entry = itemId and HM.gen and HM.gen.consumables
                and HM.gen.consumables[itemId]
            if entry then ingest("buff:" .. itemId, entry.ops) end
        end
    end
    return cache
end

function Synergy._reset() cache, cacheKey = nil, nil end -- test hook

local function nodeName(nid)
    local node = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nid]
    return node and node.name or ("node:" .. tostring(nid))
end

-- Display name for any member kind: trait node, racial, or consumable buff.
local function memberName(m)
    if type(m) == "number" then return nodeName(m) end
    local kind, id = m:match("^(%a+):(%d+)$")
    id = tonumber(id)
    if kind == "racial" and HM.Racials then
        local sp = HM.Racials.bySpell(id)
        if sp then return sp.name .. " (racial)" end
    elseif kind == "buff" then
        local e = HM.gen and HM.gen.consumables and HM.gen.consumables[id]
        if e then return e.name .. " (" .. (e.type or "buff") .. ")" end
    end
    return tostring(m)
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

-- Resolve a free-text query to a theme and return the member names (sorted). player
-- context (optional) folds the player's racials + active buffs into the themes.
-- Matches a stat, a mechanic lever, a school, or a spell-name substring (in that order).
-- Chained-synergy lines for a resolved theme: converters that bridge INTO this theme
-- (fed by a stat) and OUT of it (this stat feeds an output). e.g. querying "Attack
-- Power" -> "Mental Dexterity: Intellect -> attack power"; querying "Intellect" ->
-- the same bridge from the other side. This is the Diablo-style "what connects".
local function chainsFor(c, label)
    local key = (label or ""):lower()
    local chains = {}
    for _, b in ipairs(c.converts or {}) do
        local fromMatch = b.from and b.from:lower() == key
        local toMatch = b.to and b.to:lower() == key
        if fromMatch or toMatch then
            chains[#chains + 1] = ("%s: %s -> %s"):format(memberName(b.member), b.from, b.to)
        end
    end
    table.sort(chains)
    return chains
end

function Synergy.query(q, player)
    local c = Synergy.build(player)
    q = (q or ""):lower()
    if q == "" then return nil end
    local function names(list)
        local ns = {}
        for _, m in ipairs(list or {}) do ns[#ns + 1] = memberName(m) end
        table.sort(ns)
        return ns
    end
    local function result(label, list)
        return { label = label, nodes = names(list), members = list,
                 chains = chainsFor(c, label) }
    end
    for key, list in pairs(c.stat) do
        if key:lower() == q then return result(key, list) end
    end
    for key, list in pairs(c.mechanic) do
        if key:lower() == q or (q == "mana" and key == "cost") then
            return result(key, list)
        end
    end
    for key, list in pairs(c.school) do
        if key:lower():find(q, 1, true) then
            return result(key .. " damage", list)
        end
    end
    -- Spell-name substring (e.g. "lightning").
    local matchKey, matchList, best
    for key, list in pairs(c.spell) do
        if key:lower():find(q, 1, true) then
            if not best or #list > best then best = #list; matchKey = key; matchList = list end
        end
    end
    if matchKey then return result(matchKey, matchList) end
    return nil
end

-- The themes available to browse (for a no-argument listing).
function Synergy.themes(player)
    local c = Synergy.build(player)
    local out = {}
    for key, list in pairs(c.stat) do out[#out + 1] = key .. " (" .. #list .. ")" end
    for key, list in pairs(c.mechanic) do out[#out + 1] = key .. " (" .. #list .. ")" end
    for key, list in pairs(c.school) do out[#out + 1] = key .. " damage (" .. #list .. ")" end
    table.sort(out)
    return out
end

return Synergy
