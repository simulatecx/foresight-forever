-- Foresight stats-panel model: builds the section/row structure the panel renders.
-- Pure Lua (no frames) so the whole thing is selftest-covered headless; the renderer
-- (ui/stats_panel.lua) just walks this model. ECS-style: sections with label/value
-- rows, plus the Foresight differentiator - what-if rows showing what MORE stat would do.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

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

local WHATIF_STATS = { "Spirit", "Intellect", "Stamina", "Agility", "Strength" }

-- UI-playstyle-label: one-line "what IS my build" from dimension scores. v0 heuristic.
-- Archetype = the top output lens; the offense/survival lean compares the archetype's
-- key stat against Stamina (a within-character, scale-stable signal).
local ARCHETYPE = {
    spellcasting = { word = "Caster", stat = "intellect" },
    healing      = { word = "Healer", stat = "intellect" },
    meleeDps     = { word = "Melee",  stat = "strength" },
    rangedDps    = { word = "Ranged", stat = "agility" },
}

function PanelModel.playstyleLabel(results, snapshot)
    local bestId, bestScore
    for id in pairs(ARCHETYPE) do
        local r = results[id]
        if r and r.score and (not bestScore or r.score > bestScore) then
            bestId, bestScore = id, r.score
        end
    end
    local arch = ARCHETYPE[bestId] or ARCHETYPE.spellcasting
    local lean = ""
    local stats = snapshot and snapshot.stats
    if stats then
        local off = stats[arch.stat] or 0
        local sta = stats.stamina or 0
        if sta > off * 1.15 then lean = " - survival-focused"
        elseif off > sta * 1.15 then lean = " - offense-focused"
        else lean = " - balanced" end
    end
    return ("%s-leaning%s (v0 heuristic)"):format(arch.word, lean)
end

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
            { label = "Mana/tick (no cast 5s+)", value = fmt(get("mech.manaPerTick")) .. F.presumedMark(F.manaRegenTick),
              tooltip = F.manaRegenTick.unit },
            { label = "Mana/min (downtime)", value = fmt((get("mech.manaPerTick") or 0) * 30) .. F.presumedMark(F.manaRegenTick) },
            { label = "Health/tick (o.o.c.)", value = fmt(get("mech.healthPerTick")) .. F.presumedMark(F.healthRegenTick),
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
            { label = "Armor mitigation", value = mitigation and (fmt(mitigation * 100) .. "%" .. F.presumedMark(F.armorMitigation)) or "-",
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

    -- Stat value: each stat's strongest impact per +1 point (MODEL-stat-advisor).
    local statRows = {}
    local ok, ranked = pcall(HM.Impact.rankStats, loadout)
    for _, r in ipairs(ok and ranked or {}) do
        statRows[#statRows + 1] = {
            label = r.stat,
            value = r.bestLabel and ("%+.1f%% %s"):format(r.bestPct, r.bestLabel)
                or "no modeled effect",
            wide = true,
        }
    end
    sections[#sections + 1] = { id = "statvalue", title = "Stat value (per +1)", rows = statRows }

    return {
        sections = sections,
        notes = built.notes,
        playstyle = PanelModel.playstyleLabel(results, loadout.snapshot),
    }
end

return PanelModel
