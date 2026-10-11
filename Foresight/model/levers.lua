-- Foresight lever taxonomy: the ONE declarative map from an impact op to the canonical
-- "levers" it pushes. Every surface that reasons about relationships - synergy grouping,
-- the catalog, tooltips - asks THIS module, so "what axis does this effect belong to" is
-- defined once. Adding a generator op kind means adding one entry here (or declaring it
-- label-only); the completeness gate (run_tests) reds if an op kind is ever unclassified,
-- so new content can never silently drop out of synergies.
--
-- A lever = { axis, key, label }. axis names the relationship plane and maps 1:1 to a
-- synergy index table (stat / school / spell / mechanic). Attack Power, Spell Power,
-- Healing, crit, defense, resource and tempo are DISTINCT keys on the mechanic axis, so
-- "attacks" (attack power / melee crit) never blur into "spells" (spell power / spell crit).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Levers = {}
HM.Levers = Levers

-- Op kinds that intentionally carry NO lever (surfaced as tooltip text only, never a
-- synergy bucket). Listed explicitly so the gate distinguishes "label-only by design"
-- from "unclassified - someone forgot to categorize it".
Levers.LABEL_ONLY = {
    aura = true,       -- misc character auras we show verbatim (dodge, hit, resist...)
    unmapped = true,   -- effect we could not decode; honesty line, no relationship claim
}

-- mechanic sub-lever a spellmod PROPERTY maps to (the coarse buckets players think in).
function Levers.mechanicOfProperty(property)
    if not property then return nil end
    if property:find("crit") then return "crit" end
    if property:find("cost") then return "cost" end
    if property == "cast time" then return "cast time" end
    if property == "cooldown" then return "cooldown" end
    if property:find("threat") then return "threat" end
    if property:find("damage") or property:find("healing") then return "ability damage" end
    return nil
end

-- statConvert output -> the mechanic key it feeds (so a converter groups with the direct
-- sources of that output - Mental Dexterity lands under "attack power" beside Flurry).
Levers.CONVERT_KEY = {
    attackPower = "attack power", spellDamage = "spell damage", healingPower = "healing",
}

-- The canonical levers an op pushes. Returns a list (statConvert pushes two: its source
-- STAT and its output MECHANIC - the chained-synergy bridge). `spells` is HM.gen.spells
-- for resolving affected spell ids to the ability axis. An op kind absent here AND absent
-- from LABEL_ONLY is a classification gap the gate will catch.
function Levers.of(op, spells)
    local k = op.kind
    if k == "stat" then
        if op.stat == "all stats" then
            local out = {}
            for _, s in ipairs({ "Strength", "Agility", "Stamina", "Intellect", "Spirit" }) do
                out[#out + 1] = { axis = "stat", key = s, label = s }
            end
            return out
        end
        return op.stat and { { axis = "stat", key = op.stat, label = op.stat } } or {}
    elseif k == "schoolDamage" then
        return op.school and { { axis = "school", key = op.school, label = op.school .. " damage" } } or {}
    elseif k == "statConvert" then
        local out = {}
        if op.from then out[#out + 1] = { axis = "stat", key = op.from, label = op.from } end
        local mk = Levers.CONVERT_KEY[op.to]
        if mk then out[#out + 1] = { axis = "mechanic", key = mk, label = mk } end
        return out
    elseif k == "critChance" then
        return { { axis = "mechanic", key = "crit", label = "crit" } }
    elseif k == "maxHealth" then
        return { { axis = "mechanic", key = "health", label = "max health" } }
    elseif k == "maxPower" then
        return (op.powerType == 0) and { { axis = "mechanic", key = "max mana", label = "max mana" } } or {}
    elseif k == "armor" then
        return { { axis = "mechanic", key = "armor", label = "armor" } }
    elseif k == "attackPower" or k == "rangedAttackPower" then
        return { { axis = "mechanic", key = "attack power", label = "attack power" } }
    elseif k == "threat" then
        return { { axis = "mechanic", key = "threat", label = "threat" } }
    elseif k == "spellmod" then
        local out = {}
        local lever = Levers.mechanicOfProperty(op.property)
        if lever then out[#out + 1] = { axis = "mechanic", key = lever, label = lever } end
        -- The ability axis ("attacks themselves"): each affected spell is a relationship
        -- node, so modifiers of the same ability synergize and the inverse ("what touches
        -- this skill") falls out for free.
        for _, sid in ipairs(op.affected or {}) do
            local sp = spells and spells[sid]
            if sp and sp.name then
                out[#out + 1] = { axis = "spell", key = sp.name, label = sp.name }
            end
        end
        return out
    end
    return nil -- unknown kind: nil signals the gate (distinct from {} = "no lever")
end

-- Is an op kind accounted for (has levers OR declared label-only)? The gate's predicate.
function Levers.classified(opKind)
    if Levers.LABEL_ONLY[opKind] then return true end
    -- A representative probe op per kind; Levers.of returns non-nil for known kinds.
    return Levers.of({ kind = opKind }, nil) ~= nil
end

return Levers
