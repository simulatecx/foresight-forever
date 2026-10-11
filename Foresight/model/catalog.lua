-- Foresight content catalog: ONE normalized table over every impact source Foresight
-- ships - talents, trait nodes, racials, consumables (potion/elixir/flask/food/scroll),
-- and weapon imbues. The reference spine the synergy view, the planner, search, and the
-- future crowd-validation all query, so adding a new source to the pipeline makes it
-- appear everywhere for free. Pure Lua, selftest-covered; reads only generated data.
--
-- Entry shape (uniform across kinds):
--   { key = "<kind>:<id>", kind, name, confidence, ops, ref = <native id> }
-- `key` is globally unique; `ref` is the id within its own table (talentId / nodeId /
-- racial spellID / consumable itemId / imbue spellID).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Catalog = {}
HM.Catalog = Catalog

local cache

local function add(list, entry)
    list[#list + 1] = entry
end

-- Build the flat entry list once from HM.gen (rebuilds only after _reset).
function Catalog.all()
    if cache then return cache end
    cache = {}
    local gen = HM.gen or {}

    for id, t in pairs(gen.talents or {}) do
        local imp = gen.talentImpacts and gen.talentImpacts[id]
        add(cache, { key = "talent:" .. id, kind = "talent", name = t.name,
                     ref = id, ops = imp and imp.ops or {},
                     needsCuration = imp and imp.needsCuration or nil })
    end
    for nid, node in pairs((gen.traits and gen.traits.nodes) or {}) do
        add(cache, { key = "trait:" .. nid, kind = "trait", name = node.name,
                     ref = nid, ops = node.ops or {}, needsCuration = node.needsCuration })
    end
    for raceId, race in pairs(gen.racials or {}) do
        for _, sp in ipairs(race.spells or {}) do
            add(cache, { key = "racial:" .. sp.spellID, kind = "racial",
                         name = sp.name .. " (" .. (race.token or raceId) .. ")",
                         ref = sp.spellID, ops = sp.ops or {},
                         confidence = sp.confidence, passive = sp.passive,
                         needsCuration = sp.needsCuration })
        end
    end
    for itemId, c in pairs(gen.consumables or {}) do
        add(cache, { key = "buff:" .. itemId, kind = c.type or "consumable",
                     name = c.name, ref = itemId, ops = c.ops or {},
                     confidence = c.confidence })
    end
    for sid, e in pairs(gen.imbues or {}) do
        add(cache, { key = "imbue:" .. sid, kind = "imbue", name = e.name,
                     ref = sid, ops = e.ops or {}, confidence = e.confidence,
                     speedDamage = e.speedDamage, procs = e.procs, flatDamage = e.flatDamage })
    end
    -- Gear (the in-client item seed): stat TYPES only; live GetItemStats fills amounts.
    -- Empty ops keeps them out of the talent/build synergy index while fully browsable.
    for itemId, it in pairs(gen.items or {}) do
        add(cache, { key = "item:" .. itemId, kind = "item", name = it.name,
                     ref = itemId, ops = {}, stats = it.stats, slot = it.slot,
                     ilvl = it.ilvl, reqLevel = it.reqLevel, quality = it.quality })
    end
    return cache
end

function Catalog._reset() cache = nil end

-- The reference TABLE: how many of each content kind are catalogued, how many carry
-- decoded impact ops, and how many still need curation. This is the growth scoreboard -
-- it expands cleanly as the pipeline (and the crowd) surface more content.
function Catalog.stats()
    local out, order = {}, {}
    for _, e in ipairs(Catalog.all()) do
        local row = out[e.kind]
        if not row then
            row = { kind = e.kind, count = 0, withOps = 0, needsCuration = 0 }
            out[e.kind] = row
            order[#order + 1] = row
        end
        row.count = row.count + 1
        if e.ops and #e.ops > 0 then row.withOps = row.withOps + 1 end
        if e.needsCuration then row.needsCuration = row.needsCuration + 1 end
    end
    table.sort(order, function(a, b) return a.count > b.count end)
    return order
end

-- Case-insensitive name search across every kind (optionally filtered to one kind).
function Catalog.search(query, kind)
    local q = (query or ""):lower()
    local hits = {}
    for _, e in ipairs(Catalog.all()) do
        if (kind == nil or e.kind == kind)
                and (q == "" or e.name:lower():find(q, 1, true)) then
            hits[#hits + 1] = e
        end
    end
    table.sort(hits, function(a, b) return a.name < b.name end)
    return hits
end

-- Every entry whose ops include a kind (e.g. "statConvert", "critChance") - the data
-- backbone for the synergy relationship graph.
function Catalog.withOpKind(opKind)
    local hits = {}
    for _, e in ipairs(Catalog.all()) do
        for _, op in ipairs(e.ops or {}) do
            if op.kind == opKind then hits[#hits + 1] = e; break end
        end
    end
    return hits
end

-- Gear that carries a given stat (case-insensitive, substring) - "what has Dodge /
-- Frost Resistance / Attack Power". Sorted by required level so the nearest upgrades
-- surface first. The browse answer the item seed exists for.
function Catalog.itemsWithStat(statQuery, limit)
    local q = (statQuery or ""):lower()
    local hits = {}
    for _, e in ipairs(Catalog.all()) do
        if e.kind == "item" then
            for _, s in ipairs(e.stats or {}) do
                if s:lower():find(q, 1, true) then hits[#hits + 1] = e; break end
            end
        end
    end
    table.sort(hits, function(a, b) return (a.reqLevel or 0) < (b.reqLevel or 0) end)
    if limit and #hits > limit then
        local out = {}
        for i = 1, limit do out[i] = hits[i] end
        return out, #hits
    end
    return hits, #hits
end

return Catalog
