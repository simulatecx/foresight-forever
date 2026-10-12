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

-- Validate a saved panel position (SavedVariables are user-editable - untrusted-input
-- law). Returns a clean { point, relPoint, x, y } or nil if malformed/out of range, so a
-- tampered value can never fling the panel off-screen or error the renderer.
local ANCHORS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
function PanelModel.normalizePanelPos(pos)
    if type(pos) ~= "table" then return nil end
    local x, y = tonumber(pos.x), tonumber(pos.y)
    if not (x and y) then return nil end
    if x < -5000 or x > 5000 or y < -5000 or y > 5000 then return nil end
    local point = ANCHORS[pos.point] and pos.point or "TOPLEFT"
    local relPoint = ANCHORS[pos.relPoint] and pos.relPoint or point
    return { point = point, relPoint = relPoint, x = x, y = y }
end

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
    -- SIM-engine standing: the plain-English name leads, the lean detail follows.
    local standing = HM.Sim and HM.Sim.standing(results, stats)
    local prefix = (standing and standing.name and standing.name ~= "Unmeasured")
        and (standing.name .. " | ") or ""
    return ("%s%s-leaning%s (v0 heuristic)"):format(prefix, arch.word, lean)
end

-- Matrix opacity setting (untrusted-input law): clamp to a readable range, garbage
-- falls back to the default. Pure so the selftest covers it.
local OPACITY_DEFAULT, OPACITY_MIN, OPACITY_MAX = 0.92, 0.2, 1.0
function PanelModel.normalizeOpacity(v)
    local a = tonumber(v)
    if not a then return OPACITY_DEFAULT end
    if a < OPACITY_MIN then return OPACITY_MIN end
    if a > OPACITY_MAX then return OPACITY_MAX end
    return a
end

-- The Matrix panel model (S7b, mockups/foresight-matrix-2026-10-12.html): header with
-- the plain-English standing badge, dimension BARS, and the class's Enabler -> Engine
-- -> Payoff loops. Pure - the renderer draws, this decides.
-- FILL-BASIS LAW (the honest-bars decision): dimension scores are per-lens indices on
-- different scales, so each bar fills RELATIVE WITHIN ITS GROUP (your strongest output
-- lens = full bar; defensive/economy lenses scale within their own group) and the
-- basis is stated on the panel. Never fake absolutes.
local OUTPUT_IDS = { spellcasting = true, meleeDps = true, rangedDps = true, healing = true }

-- S22b: the cascade, visualized - breadcrumb segments from EXISTING computed data
-- (graph deltas + Sim.abilityHit), each link emitted ONLY when its number actually
-- computed (nil-degrade per link; a middle step is never invented). The probe is a
-- round +10 of the spell's scaling input so the chips read as rates. Pure.
function PanelModel.pathwayModel(loadout, spellId)
    local spell = HM.gen and HM.gen.spells and HM.gen.spells[spellId]
    if not (spell and loadout and HM.Sim and HM.Sim.abilityHit) then return nil end
    local snap = loadout.snapshot or {}
    local conv = ((HM.formulas.statConversions.byClass or {})[snap.classToken]) or {}
    local isWeapon = spell.wpn ~= nil
    local statKey
    if isWeapon then
        if (conv.apPerStr or 0) > 0 then statKey = "Strength"
        elseif (conv.apPerAgi or 0) > 0 then statKey = "Agility" end
    else
        statKey = spell.heal and "healingPower" or "spellDamage"
    end
    if not statKey then return nil end -- no feeding stat for this class: no cascade claim
    local before = HM.Sim.abilityHit(loadout, spellId, { selected = snap.talents })
    if not before then return nil end
    local probe = 10
    local modeled = loadout:withStatDelta(statKey, probe, "+10 " .. statKey)
    local after = HM.Sim.abilityHit(modeled, spellId, { selected = snap.talents })
    if not after then return nil end
    local hitDelta = after.avg - before.avg
    if math.abs(hitDelta) < 0.05 then return nil end -- the chain never reaches the hit
    local DISPLAY = { spellDamage = "Spell Power", healingPower = "Healing Power" }
    local segments = { ("+%d %s"):format(probe, DISPLAY[statKey] or statKey) }
    if isWeapon then
        -- The AP link, read off the same graphs the hit used (never re-derived).
        local okAp, apDelta = pcall(function()
            local bb, ab = loadout:build(), modeled:build()
            return ab.graph:value("stat.attackPower", ab.ctx, {})
                - bb.graph:value("stat.attackPower", bb.ctx, {})
        end)
        if okAp and type(apDelta) == "number" and math.abs(apDelta) > 0.05 then
            segments[#segments + 1] = ("%+.0f Attack Power"):format(apDelta)
            -- per-swing via the classic 14 AP = 1 DPS law (same as impact.lua's chain)
            segments[#segments + 1] = ("%+.1f per swing"):format(
                apDelta / 14 * (snap.weaponSpeed or 2.0))
        end
    end
    segments[#segments + 1] = ("%+.1f %s per %s"):format(hitDelta, spell.name,
        before.kind == "heal" and "cast" or "hit")
    return { spell = spell.name, segments = segments, hitDelta = hitDelta,
             presumed = (before.presumed or after.presumed) and true or false }
end

-- S22a Matrix integration: everything the insight area needs for a focused skill -
-- the three modifier classes (names capped per row) + the S22b pathway. Pure.
function PanelModel.focusModel(loadout, name)
    if not (HM.Sim and HM.Sim.resolveSpellLevelCapped and HM.Mapping
            and HM.Mapping.classifiedForSpell) then return nil end
    local snap = loadout.snapshot or {}
    local sid = HM.Sim.resolveSpellLevelCapped(name, snap.level)
    local c = sid and HM.Mapping.classifiedForSpell(sid, { classToken = snap.classToken })
    if not c then return nil end
    local function joined(list, cap)
        local out = {}
        for i = 1, math.min(#list, cap or 4) do out[i] = list[i].name end
        local more = #list - #out
        return table.concat(out, ", ") .. (more > 0 and (" (+%d)"):format(more) or "")
    end
    local classes = {}
    if #c.direct > 0 then
        classes[#classes + 1] = { tag = "Direct", color = "gold", text = joined(c.direct) }
    end
    if #c.school > 0 then
        classes[#classes + 1] = { tag = "School", color = "blue", text = joined(c.school) }
    end
    if #c.statFeeders > 0 then
        classes[#classes + 1] = { tag = "Feeds it", color = "blue", text = joined(c.statFeeders) }
    end
    return { spell = c.spell, classes = classes,
             pathway = PanelModel.pathwayModel(loadout, sid) }
end

-- pathways (optional): a Sim.goalPathways result - the renderer computes it on talent
-- changes only (one evaluate per open node is too heavy for every aura tick) and
-- passes it through; the model stays pure. focus (optional): a PanelModel.focusModel
-- result - same passthrough contract.
function PanelModel.matrixModel(loadout, activeLoopId, pathways, focus)
    local results = HM.Impact.evaluate(loadout)
    local snapshot = loadout.snapshot or {}
    local stats = snapshot.stats or {}
    local standing = HM.Sim and HM.Sim.standing(results, stats)
        or { name = "?", detail = "" }

    -- Dimension bars, grouped for an honest relative fill.
    local groupMax = { output = 0, defense = 0 }
    local rows = {}
    for _, dim in ipairs(HM.dimensions.list) do
        local r = results[dim.id]
        if r and r.score then
            local group = OUTPUT_IDS[dim.id] and "output" or "defense"
            if r.score > groupMax[group] then groupMax[group] = r.score end
            rows[#rows + 1] = { id = dim.id, label = dim.label, score = r.score,
                                group = group }
        end
    end
    local bars = {}
    for _, row in ipairs(rows) do
        local max = groupMax[row.group]
        local fill = (max > 0) and (row.score / max) or 0
        bars[#bars + 1] = {
            id = row.id, label = row.label, group = row.group,
            value = (row.score >= 100) and ("%.0f"):format(row.score)
                or ("%.1f"):format(row.score),
            fill = fill, top = fill >= 0.999,
        }
    end

    -- Class loops (the ecosystem map). The active one feeds the card list; the rest
    -- are cycle targets for the goal row.
    local loops = HM.loopsForClass and HM.loopsForClass(snapshot.classToken) or {}
    local active
    for _, l in ipairs(loops) do
        if l.id == activeLoopId then active = l end
    end
    active = active or loops[1]
    local eco
    if active then
        local okc, computed = pcall(active.compute, loadout)
        eco = {
            id = active.id, name = active.name, insight = active.insight,
            confidence = active.confidence,
            computed = okc and computed or {},
            nodes = {
                { tag = "Enabler", title = table.concat(active.enablers, " / "),
                  desc = "Turns the engine on - without this the loop is off." },
                { tag = "Engine", title = table.concat(active.engine, " / "),
                  desc = "The multiplier this loop exists for." },
                { tag = "Payoff", title = table.concat(active.payoffs, " / "),
                  desc = "Cash it in right after an enabler lands." },
            },
        }
    end

    return {
        header = {
            name = snapshot.name, classToken = snapshot.classToken,
            level = snapshot.level, raceToken = snapshot.raceToken,
            standing = standing,
        },
        bars = {
            basis = "bars relative to your strongest lens per group (p)",
            rows = bars,
        },
        path = (pathways and pathways.rows and #pathways.rows > 0) and
            { label = pathways.label, rows = pathways.rows } or nil,
        focus = focus or nil,
        eco = eco,
        loopCount = #loops,
    }
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

    -- Future build (WHATIF-planner): the user's composed plan + its net impact.
    local planRows = {}
    local plan = HM.Plan and HM.Plan.store() or {}
    if #plan == 0 then
        planRows[1] = { label = "empty", value = "/foresight plan add stat Agility 5",
                        wide = true }
    else
        for i, d in ipairs(plan) do
            planRows[#planRows + 1] = { label = i .. ".", value = HM.Plan.describe(d), wide = true }
        end
        local okp, changes, chain = pcall(HM.Plan.summary, loadout, plan)
        for _, l in ipairs(okp and chain or {}) do
            planRows[#planRows + 1] = { label = "", value = l, wide = true }
        end
        local shown = 0
        for _, c in ipairs(okp and changes or {}) do
            if shown >= 4 then break end
            shown = shown + 1
            planRows[#planRows + 1] = {
                label = "", value = ("-> %s %+.1f%%"):format(c.label, c.pct or 0), wide = true,
            }
        end
        if okp and #changes == 0 and #chain == 0 then
            planRows[#planRows + 1] = { label = "", value = "no modeled change yet", wide = true }
        end
    end
    sections[#sections + 1] = { id = "plan", title = "Future build", rows = planRows }

    -- Stat value: each stat's strongest impact per +1 point (MODEL-stat-advisor).
    local statRows = {}
    local ok, ranked, focus = pcall(HM.Impact.rankStats, loadout)
    for _, r in ipairs(ok and ranked or {}) do
        statRows[#statRows + 1] = {
            label = r.stat,
            value = r.bestLabel and ("%+.1f%% %s"):format(r.bestPct, r.bestLabel)
                or "no modeled effect",
            wide = true,
        }
    end
    -- S20 coaching footer: one derived mechanism line when a stat is dead for the
    -- focus lens (attribution, never judgment - the verdict logic is untouched).
    if ok then
        local okc, coach = pcall(HM.Impact.coachingLine, loadout, ranked, focus)
        if okc and coach then
            statRows[#statRows + 1] = { label = "", value = coach, wide = true }
        end
    end
    sections[#sections + 1] = { id = "statvalue", title = "Stat value (per +1)", rows = statRows }

    return {
        sections = sections,
        notes = built.notes,
        playstyle = PanelModel.playstyleLabel(results, loadout.snapshot),
    }
end

return PanelModel
