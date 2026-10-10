-- HelpMe stats-panel model: builds the section/row structure the panel renders.
-- Pure Lua (no frames) so the whole thing is selftest-covered headless; the renderer
-- (ui/stats_panel.lua) just walks this model. ECS-style: sections with label/value
-- rows, plus the HelpMe differentiator - what-if rows showing what MORE stat would do.

local _, HM = ...
if not HM then HM = _G.HelpMe or {}; _G.HelpMe = HM end

local PanelModel = {}
HM.PanelModel = PanelModel

local function round(x, places)
    local mult = 10 ^ (places or 1)
    return math.floor(x * mult + 0.5) / mult
end

local function fmt(value, places)
    if value == nil then return "-" end
    if value >= 1000 then return tostring(round(value / 1000, 1)) .. "k" end
    return tostring(round(value, places or 1))
end

-- Marks values computed from classic-presumed (unverified on Forever) formulas.
local function presumedMark(formulaEntry)
    local c = formulaEntry and formulaEntry.confidence or ""
    if c:find("^verified") then return "" end
    return " (p)"
end

local WHATIF_STATS = { "Spirit", "Intellect", "Stamina", "Agility", "Strength" }

-- Build the full panel model for a loadout.
-- Returns { sections = { { id, title, rows = { { label, value, tooltip? } } } } }
function PanelModel.build(loadout)
    local results = HM.Impact.evaluate(loadout)
    local built = loadout:build()
    local cache = {}
    local get = function(id)
        local ok, v = pcall(function() return built.graph:value(id, built.ctx, cache) end)
        return ok and v or nil
    end
    local F = HM.formulas

    local sections = {}

    -- Dimensions: the seven outcome lenses.
    local dimRows = {}
    for _, dim in ipairs(HM.dimensions.list) do
        local r = results[dim.id]
        dimRows[#dimRows + 1] = {
            label = dim.label,
            value = r and fmt(r.score) or "-",
            tooltip = dim.unit,
        }
    end
    sections[#sections + 1] = { id = "dimensions", title = "Dimensions", rows = dimRows }

    -- Regen: the "+2 Spirit actually matters" numbers, FSR-annotated.
    sections[#sections + 1] = {
        id = "regen",
        title = "Regen",
        rows = {
            { label = "Mana/tick (no cast 5s+)", value = fmt(get("mech.manaPerTick")) .. presumedMark(F.manaRegenTick),
              tooltip = F.manaRegenTick.unit },
            { label = "Mana/min (downtime)", value = fmt((get("mech.manaPerTick") or 0) * 30) .. presumedMark(F.manaRegenTick) },
            { label = "Health/tick (o.o.c.)", value = fmt(get("mech.healthPerTick")) .. presumedMark(F.healthRegenTick),
              tooltip = F.healthRegenTick.unit },
        },
    }

    -- Mechanics: swing/mitigation/EHP.
    local mitigation = get("mech.armorMitigation")
    sections[#sections + 1] = {
        id = "mechanics",
        title = "Mechanics",
        rows = {
            { label = "Swing time", value = fmt(get("mech.swingTime"), 2) .. "s" },
            { label = "Armor mitigation", value = mitigation and (fmt(mitigation * 100) .. "%" .. presumedMark(F.armorMitigation)) or "-",
              tooltip = "vs level " .. (loadout.snapshot.level or 60) .. " attacker" },
            { label = "Effective HP", value = fmt(get("outcome.effectiveHealth")) },
            { label = "Max health", value = fmt(get("stat.maxHealth")) },
            { label = "Max mana", value = fmt(get("stat.maxMana")) },
        },
    }

    -- What-if: what MORE would do, in human terms (top line per stat).
    local whatifRows = {}
    for _, stat in ipairs(WHATIF_STATS) do
        local ok, lines = pcall(HM.Impact.explainStatDelta, loadout, stat, 10)
        whatifRows[#whatifRows + 1] = {
            label = "+10 " .. stat,
            value = (ok and lines and lines[1]) or "no modeled effect",
            wide = true, -- renderer hint: value needs the full row width
        }
    end
    sections[#sections + 1] = { id = "whatif", title = "What-if", rows = whatifRows }

    return { sections = sections, notes = built.notes }
end

return PanelModel
