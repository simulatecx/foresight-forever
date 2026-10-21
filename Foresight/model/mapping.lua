-- Foresight impact MAP (S7b): the bidirectional talent<->ability index. Forward: "which
-- of my abilities does this talent touch?" Inverse: "which talents/effects modify THIS
-- spell?" Both read the same affected-spell edges the catalog already carries (a spellmod
-- op lists the spells it changes), so the two directions are one data source, never out of
-- sync. Pure Lua, selftest-covered; the renderer/commands sit on top.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Mapping = {}
HM.Mapping = Mapping

local cache

-- Human one-liner for what an op does to an ability (magnitude + property).
local MS_PROPS = { ["cast time"] = true, ["cooldown"] = true, ["global cooldown"] = true }
function Mapping.describeOp(op)
    local v = op.maxValue or 0
    local prop = op.property or op.stat or op.label or op.kind
    local val
    if op.isPct then
        val = ("%+g%%"):format(v)
    elseif prop and MS_PROPS[prop] then
        val = ("%+gs"):format(v / 1000)
    else
        val = ("%+g"):format(v)
    end
    return ("%s %s"):format(val, prop)
end

-- Build the inverse index once: spellName -> { {name, kind, key, op} } over every catalog
-- entry whose ops affect that spell. (Talents/traits carry the affected edges; other kinds
-- join automatically if they ever gain them - one source of truth.)
function Mapping.build()
    if cache then return cache end
    cache = { bySpell = {} }
    local spells = (HM.gen and HM.gen.spells) or {}
    for _, e in ipairs((HM.Catalog and HM.Catalog.all()) or {}) do
        local seen = {}
        for _, op in ipairs(e.ops or {}) do
            for _, sid in ipairs(op.affected or {}) do
                local sp = spells[sid]
                local name = sp and sp.name
                if name and not seen[name .. (op.property or "")] then
                    seen[name .. (op.property or "")] = true
                    local list = cache.bySpell[name]
                    if not list then list = {}; cache.bySpell[name] = list end
                    list[#list + 1] = { name = e.name, kind = e.kind, key = e.key, op = op }
                end
            end
        end
    end
    return cache
end

function Mapping._reset() cache = nil end

-- INVERSE: everything that modifies a spell (resolved by exact name, else substring -
-- the ability with the most modifiers wins a tie, so "fireball" finds the main nuke).
-- Returns { spell = <resolved name>, sources = { {name, kind, key, op} } } or nil.
function Mapping.forSpell(query)
    local c = Mapping.build()
    local q = (query or ""):lower()
    if q == "" then return nil end
    if c.bySpell[query] then
        return { spell = query, sources = c.bySpell[query] }
    end
    local bestName, bestList
    for name, list in pairs(c.bySpell) do
        local nl = name:lower()
        if nl == q then bestName, bestList = name, list; break end
        if nl:find(q, 1, true) and (not bestList or #list > #bestList) then
            bestName, bestList = name, list
        end
    end
    if bestName then
        local sorted = {}
        for _, s in ipairs(bestList) do sorted[#sorted + 1] = s end
        table.sort(sorted, function(a, b) return a.name < b.name end)
        return { spell = bestName, sources = sorted }
    end
    return nil
end

-- School mask legend (client SchoolMask bits; generated op.school labels come from the
-- same legend in generate.py's school_label).
local SCHOOL_BITS = {
    [1] = "Physical", [2] = "Holy", [4] = "Fire", [8] = "Nature",
    [16] = "Frost", [32] = "Shadow", [64] = "Arcane",
}

-- S22a: classified reverse lookup - the three modifier classes for ONE ability.
--   direct:      tree nodes with an op whose affected list contains this spell
--                (the existing forSpell edges, reused).
--   school:      pct schoolDamage ops whose school matches the spell's school mask.
--   statFeeders: character-level ops whose LEVERS feed the spell's scaling input -
--                AP/melee-crit (+ Str/Agi where the class conversion is nonzero) for
--                weapon instants; spell damage/healing/crit (+ Int where
--                intPerSpellCrit exists) for casters. Rides Levers.of - never a
--                second stat-chain walker.
-- ctx (optional): { classToken } gates the primary-stat feeders; absent -> those are
-- honestly skipped. Pure; returns nil for an unknown spell (no false claims).
-- Priority dedupe: direct > school > statFeeders (a node lands in ONE bucket).
function Mapping.classifiedForSpell(spellId, ctx)
    local spells = (HM.gen and HM.gen.spells) or {}
    local spell = spells[spellId]
    if not spell then return nil end
    local nodes = HM.formulas.impactNodes() -- traits (forever) or talents (classic)
    local conv = (ctx and ctx.classToken and HM.formulas
        and (HM.formulas.statConversions.byClass or {})[ctx.classToken]) or {}
    local isWeapon = spell.wpn ~= nil
    local isHeal = (not isWeapon) and spell.heal ~= nil

    local schoolSet = {}
    for bit, sname in pairs(SCHOOL_BITS) do
        if spell.school and math.floor(spell.school / bit) % 2 == 1 then
            schoolSet[sname] = true
        end
    end
    local function schoolMatches(label)
        if type(label) ~= "string" then return false end
        for sname in label:gmatch("[^/]+") do
            if schoolSet[sname] then return true end
        end
        return false
    end

    -- Does this character-level op feed the spell's scaling input? (Spellmods are
    -- ability-targeted and belong to direct, never here.)
    local function feeds(op)
        if op.kind == "spellmod" then return false end
        for _, lever in ipairs((HM.Levers and HM.Levers.of(op, spells)) or {}) do
            if isWeapon then
                if lever.axis == "mechanic"
                        and (lever.key == "attack power" or lever.key == "crit") then
                    return true
                end
                if lever.axis == "stat"
                        and ((lever.key == "Strength" and (conv.apPerStr or 0) ~= 0)
                          or (lever.key == "Agility" and (conv.apPerAgi or 0) ~= 0)) then
                    return true
                end
            else
                if lever.axis == "mechanic"
                        and (lever.key == "crit"
                          or (isHeal and lever.key == "healing")
                          or (not isHeal and lever.key == "spell damage")) then
                    return true
                end
                if lever.axis == "stat" and lever.key == "Intellect"
                        and conv.intPerSpellCrit then
                    return true
                end
            end
        end
        return false
    end

    local out = { spell = spell.name, direct = {}, school = {}, statFeeders = {} }
    for nid, node in pairs(nodes) do
        local bucket
        for _, op in ipairs(node.ops or {}) do
            for _, sid in ipairs(op.affected or {}) do
                if sid == spellId then bucket = "direct" break end
            end
            if bucket == "direct" then break end
            if op.kind == "schoolDamage" and op.isPct and schoolMatches(op.school) then
                bucket = "school"
            elseif not bucket and feeds(op) then
                bucket = "statFeeders"
            end
        end
        if bucket then
            out[bucket][#out[bucket] + 1] = { nodeId = nid, name = node.name }
        end
    end
    for _, list in pairs({ out.direct, out.school, out.statFeeders }) do
        table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    end
    return out
end

-- FORWARD: the abilities a catalog entry (talent/trait node) touches, each with the op.
-- Accepts a numeric trait nodeId or a catalog key ("talent:26").
function Mapping.forEntry(ref)
    local spells = (HM.gen and HM.gen.spells) or {}
    local entry
    for _, e in ipairs((HM.Catalog and HM.Catalog.all()) or {}) do
        if e.key == ref or e.ref == ref then entry = e; break end
    end
    if not entry then return nil end
    local out, seen = {}, {}
    for _, op in ipairs(entry.ops or {}) do
        for _, sid in ipairs(op.affected or {}) do
            local sp = spells[sid]
            if sp and sp.name and not seen[sp.name] then
                seen[sp.name] = true
                out[#out + 1] = { spell = sp.name, op = op }
            end
        end
    end
    table.sort(out, function(a, b) return a.spell < b.spell end)
    return { name = entry.name, kind = entry.kind, abilities = out }
end

return Mapping
