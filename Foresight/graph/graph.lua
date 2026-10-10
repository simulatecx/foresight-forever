-- Foresight impact graph: nodes with base values or formulas, typed modifier edges,
-- deterministic stacking. Pure Lua 5.1, no WoW API - testable headless.
--
-- Stacking model (per target node):
--   value = (base + sum(flat)) * (1 + sum(pctAdd in group)/100 for each group) * prod(1 + pctMult/100)
--   "override" (highest priority wins) short-circuits the above.
-- Every value() call can also return a breakdown table explaining each contribution,
-- because Foresight's contract is human-readable answers, not bare numbers.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Graph = {}
Graph.__index = Graph
HM.Graph = Graph

function Graph.new()
    return setmetatable({ nodes = {}, modifiers = {} }, Graph)
end

-- node = { id, kind = "stat"|"mechanic"|"ability"|"outcome", base = number?,
--          formula = function(get, ctx) -> number?, label = string? }
function Graph:addNode(node)
    assert(node and node.id, "node requires id")
    assert(not self.nodes[node.id], "duplicate node: " .. tostring(node.id))
    self.nodes[node.id] = node
    return node
end

function Graph:getNode(id)
    return self.nodes[id]
end

-- mod = { target, op = "flat"|"pctAdd"|"pctMult"|"override", value = number,
--         group = string? (pctAdd stacking group, default "default"),
--         source = string (e.g. "talent:1234", "item:5678"),
--         priority = number? (override resolution), enabled = function(ctx)->bool? }
function Graph:addModifier(mod)
    assert(mod and mod.target and mod.op and mod.value ~= nil, "modifier requires target/op/value")
    assert(mod.source, "modifier requires a source for explainability")
    local list = self.modifiers[mod.target]
    if not list then
        list = {}
        self.modifiers[mod.target] = list
    end
    list[#list + 1] = mod
    return mod
end

function Graph:removeModifiersBySource(source)
    local removed = 0
    for _, list in pairs(self.modifiers) do
        for i = #list, 1, -1 do
            if list[i].source == source then
                table.remove(list, i)
                removed = removed + 1
            end
        end
    end
    return removed
end

local function applyModifiers(self, id, base, ctx, breakdown)
    local list = self.modifiers[id]
    if not list then
        return base
    end
    local flat, pctMult = 0, 1
    local pctGroups = {}
    local override, overridePrio
    for i = 1, #list do
        local m = list[i]
        if not m.enabled or m.enabled(ctx) then
            if m.op == "override" then
                local prio = m.priority or 0
                if not override or prio >= overridePrio then
                    override, overridePrio = m, prio
                end
            elseif m.op == "flat" then
                flat = flat + m.value
            elseif m.op == "pctAdd" then
                local g = m.group or "default"
                pctGroups[g] = (pctGroups[g] or 0) + m.value
            elseif m.op == "pctMult" then
                pctMult = pctMult * (1 + m.value / 100)
            else
                error("unknown modifier op: " .. tostring(m.op))
            end
            if breakdown then
                breakdown[#breakdown + 1] = { source = m.source, op = m.op, value = m.value, group = m.group }
            end
        end
    end
    if override then
        if breakdown then
            breakdown[#breakdown + 1] = { source = override.source, op = "override", value = override.value }
        end
        return override.value
    end
    local value = base + flat
    for _, pct in pairs(pctGroups) do
        value = value * (1 + pct / 100)
    end
    return value * pctMult
end

-- Evaluate a node. ctx = { base = {id -> number}, ... caller state }.
-- Returns value, breakdown. Memoized per-call via an internal cache table;
-- formulas receive get(id) so derived nodes compose. Cycles are an error.
function Graph:value(id, ctx, _cache, _visiting)
    ctx = ctx or {}
    _cache = _cache or {}
    _visiting = _visiting or {}
    if _cache[id] ~= nil then
        return _cache[id].value, _cache[id].breakdown
    end
    assert(not _visiting[id], "cycle detected at node: " .. tostring(id))
    local node = self.nodes[id]
    assert(node, "unknown node: " .. tostring(id))
    _visiting[id] = true

    local breakdown = {}
    local base
    if ctx.base and ctx.base[id] ~= nil then
        base = ctx.base[id]
        breakdown[#breakdown + 1] = { source = "snapshot", op = "base", value = base }
    elseif node.formula then
        local get = function(depId)
            local v = self:value(depId, ctx, _cache, _visiting)
            return v
        end
        base = node.formula(get, ctx)
        breakdown[#breakdown + 1] = { source = "formula", op = "base", value = base }
    else
        base = node.base or 0
        breakdown[#breakdown + 1] = { source = "default", op = "base", value = base }
    end

    local value = applyModifiers(self, id, base, ctx, breakdown)
    _visiting[id] = nil
    _cache[id] = { value = value, breakdown = breakdown }
    return value, breakdown
end

return Graph
