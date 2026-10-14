-- Foresight outcome dimensions: the lenses a loadout is scored through.
-- v0 heuristics - directional scores with honest breakdowns, refined as the probe
-- verifies formulas. Each dimension reads graph nodes built by model/loadout.lua.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local D = {}
HM.dimensions = D

-- Each entry: { id, label, nodes = {graph node ids}, score = function(get) -> number, unit }
-- get(id) returns the evaluated graph value for the loadout being scored.
D.list = {
    {
        id = "spellcasting",
        label = "Spellcasting",
        unit = "throughput index",
        score = function(get)
            local sp = get("stat.spellDamage")
            local crit = get("stat.spellCritPct")
            local throughput = get("agg.spellThroughputPct")
            return (100 + sp / 10) * (1 + crit / 100) * (1 + throughput / 100)
        end,
    },
    {
        id = "meleeDps",
        label = "Melee DPS",
        unit = "white-DPS index: score/10 = your real swing DPS incl. crit (p)",
        score = function(get)
            -- v0.34.0 lens fix (live catch: the old (100 + AP)/swing index INVERTED
            -- weapon swaps - a better-but-slower weapon scored LOWER because weapon
            -- damage wasn't in the formula at all). Now rides mech.whiteDps: the real
            -- sheet range per hasted swing, marginal what-if AP folded by the one
            -- substitution law. x10 keeps the index in the cross-lens display band.
            local white = get("mech.whiteDps")
            local crit = get("stat.meleeCritPct")
            local throughput = get("agg.meleeThroughputPct")
            return white * 10 * (1 + crit / 100) * (1 + throughput / 100)
        end,
    },
    {
        id = "rangedDps",
        label = "Ranged DPS",
        unit = "throughput index",
        score = function(get)
            local rap = get("stat.rangedAttackPower")
            local crit = get("stat.rangedCritPct")
            local throughput = get("agg.rangedThroughputPct")
            return (100 + rap / 14 * 10) * (1 + crit / 100) * (1 + throughput / 100)
        end,
    },
    {
        id = "healing",
        label = "Healing",
        unit = "throughput index",
        score = function(get)
            local hp = get("stat.healingPower")
            local crit = get("stat.spellCritPct")
            local throughput = get("agg.healingThroughputPct")
            return (100 + hp / 10) * (1 + crit / 200) * (1 + throughput / 100)
        end,
    },
    {
        id = "tankability",
        label = "Tankability",
        unit = "effective HP vs lv60 physical",
        score = function(get)
            return get("outcome.effectiveHealth")
        end,
    },
    {
        id = "survivability",
        label = "Survivability",
        unit = "composite index",
        score = function(get)
            -- Effective HP plus recovery: how big a hole you can survive and refill.
            local ehp = get("outcome.effectiveHealth")
            local regen = get("mech.healthPerTick") * 30 -- per minute o.o.c.
            local avoid = get("agg.avoidancePct")
            return ehp * (1 + avoid / 100) + regen
        end,
    },
    {
        id = "sustain",
        label = "Mana sustain",
        unit = "mana per minute (outside FSR)",
        score = function(get)
            return get("mech.manaPerTick") * 30
        end,
    },
    {
        id = "threat",
        label = "Threat modifier",
        unit = "% of normal threat from your talents (p; stance + per-ability pending)",
        -- Own-state only: 100% baseline plus the summed talent threat modifiers. Below
        -- 100 = you pull less (good for non-tanks); above = more. A lens, not an absolute.
        score = function(get)
            return 100 + get("agg.threatModPct")
        end,
    },
}

function D.byId(id)
    for _, d in ipairs(D.list) do
        if d.id == id then return d end
    end
end

-- The featured-challenge rotation for the crowd daily trial (CROWD-share). KEEP IN SYNC
-- with web/app.js FEATURED - same order and keys - so the in-game daily trial and the
-- website pick the same challenge for a given day-of-year.
D.featured = {
    { label = "Most Armor", key = "stat.armor" },
    { label = "Biggest Earth Shock", key = "ability:Earth Shock" },
    { label = "Most Frost Spell Damage", key = "school.frost" },
    { label = "Most Health", key = "stat.maxHealth" },
    { label = "Biggest Fireball", key = "ability:Fireball" },
    { label = "Most Fire Spell Damage", key = "school.fire" },
    { label = "Biggest Greater Heal", key = "ability:Greater Heal" },
}

-- Human label for a crowd metric key (mirrors web/app.js metricLabel): the stat.* /
-- school.* / ability:* families, else a generic fallback.
local METRIC_LABELS = {
    ["stat.armor"] = "Most Armor", ["stat.maxHealth"] = "Most Health",
    ["stat.spellDamage"] = "Most Spell Power",
}
local function capFirst(s)
    return s:sub(1, 1):upper() .. s:sub(2)
end
function D.metricLabel(key)
    if type(key) ~= "string" then return "?" end
    if METRIC_LABELS[key] then return METRIC_LABELS[key] end
    if key:sub(1, 8) == "ability:" then return "Biggest " .. key:sub(9) end
    if key:sub(1, 7) == "school." then return "Most " .. capFirst(key:sub(8)) .. " Spell Damage" end
    if key:sub(1, 5) == "stat." then return "Most " .. capFirst(key:sub(6)) end
    return "Most " .. key
end

-- THE ONE DISPLAY LAW for lens values (user catch 2026-10-12: a summary mixing real
-- units and raw indices read as broken). Real-unit lenses say their unit; the
-- 100-floor output indices show "+X% vs base" (score minus the no-gear floor);
-- survivability stays the one composite index (tooltip carries its definition).
local HUNDRED_FLOOR = { spellcasting = true, rangedDps = true, healing = true }

-- (number, unitSuffix, isRealUnit) - what-if lines show before -> after only for
-- real units; index lenses read as a bare % change.
function D.humanValue(id, score)
    if type(score) ~= "number" then return score, "", false end
    if id == "meleeDps" then return score / 10, " DPS", true end
    if id == "tankability" then return score, " EHP", true end
    if id == "sustain" then return score, "/min", true end
    if id == "threat" then return score, "%", true end
    return score, "", false
end

-- The full display string every value surface uses (panel dims, Matrix bars).
-- GROWTH VIEW (user call 2026-10-13): the "+X% vs base" framing compares to a no-gear
-- floor, which climbs as you gear and reads oddly - so it's now an opt-in toggle
-- (settings.growthView), OFF by default. Off shows the plain current index; the
-- decision numbers people act on are always diffs from the current character anyway.
-- (The real "vs others in your spec" comparison is the planned crowd-data build.)
function D.display(id, score)
    if type(score) ~= "number" then return "-" end
    if HUNDRED_FLOOR[id] then
        local growth = HM.Settings and HM.Settings.get and HM.Settings.get("growthView")
        if growth then
            return ("%+.1f%% vs base"):format(score - 100)
        end
        return ("%.0f"):format(score) -- plain current index (tooltip carries the unit)
    end
    local v, unit = D.humanValue(id, score)
    local body
    if v >= 1000 then body = ("%.1fk"):format(v / 1000)
    elseif v >= 100 then body = ("%.0f"):format(v)
    else body = ("%.1f"):format(v) end
    return body .. unit
end

return D
