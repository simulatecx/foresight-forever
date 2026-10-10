-- HelpMe outcome dimensions: the lenses a loadout is scored through.
-- v0 heuristics - directional scores with honest breakdowns, refined as the probe
-- verifies formulas. Each dimension reads graph nodes built by model/loadout.lua.

local _, HM = ...
if not HM then HM = _G.HelpMe or {}; _G.HelpMe = HM end

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
        unit = "throughput index",
        score = function(get)
            local ap = get("stat.attackPower")
            local crit = get("stat.meleeCritPct")
            local swing = get("mech.swingTime")
            local throughput = get("agg.meleeThroughputPct")
            if swing <= 0 then swing = 2.0 end
            return (100 + ap / 14 * 10) / swing * (1 + crit / 100) * (1 + throughput / 100)
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
}

function D.byId(id)
    for _, d in ipairs(D.list) do
        if d.id == id then return d end
    end
end

return D
