-- HelpMe impact evaluation: score a loadout across all dimensions, diff two loadouts,
-- and explain deltas in human terms. This is the engine behind "model this talent" and
-- "what does +2 Spirit actually do for me".

local _, HM = ...
if not HM then HM = _G.HelpMe or {}; _G.HelpMe = HM end

local Impact = {}
HM.Impact = Impact

-- Evaluate every dimension for a loadout. Returns { [dimId] = { score, label, unit } }.
function Impact.evaluate(loadout)
    local built = loadout:build()
    local cache = {}
    local get = function(id) return built.graph:value(id, built.ctx, cache) end
    local out = {}
    for _, dim in ipairs(HM.dimensions.list) do
        local ok, score = pcall(dim.score, get)
        out[dim.id] = {
            label = dim.label,
            unit = dim.unit,
            score = ok and score or nil,
            error = not ok and tostring(score) or nil,
        }
    end
    out._notes = built.notes
    return out
end

-- Diff two loadouts (e.g. current vs modeled). Returns ordered list of
-- { id, label, before, after, delta, pct } for dimensions that changed.
function Impact.diff(baseLoadout, modeledLoadout)
    local before = Impact.evaluate(baseLoadout)
    local after = Impact.evaluate(modeledLoadout)
    local changes = {}
    for _, dim in ipairs(HM.dimensions.list) do
        local b, a = before[dim.id], after[dim.id]
        if b.score and a.score then
            local delta = a.score - b.score
            if math.abs(delta) > 1e-9 then
                changes[#changes + 1] = {
                    id = dim.id, label = dim.label, unit = dim.unit,
                    before = b.score, after = a.score, delta = delta,
                    pct = b.score ~= 0 and (delta / b.score * 100) or nil,
                }
            end
        end
    end
    table.sort(changes, function(x, y) return math.abs(x.pct or 0) > math.abs(y.pct or 0) end)
    return changes, before, after
end

local function round(x, places)
    local mult = 10 ^ (places or 1)
    return math.floor(x * mult + 0.5) / mult
end

-- The "+2 Spirit, so what?" answer: human-terms explanation of a stat delta.
-- Returns a list of plain-language lines.
function Impact.explainStatDelta(loadout, stat, amount)
    local modeled = loadout:withStatDelta(stat, amount, "+" .. amount .. " " .. stat)
    local changes = Impact.diff(loadout, modeled)
    local s = loadout.snapshot
    local lines = {}
    for _, c in ipairs(changes) do
        if c.id == "sustain" then
            local perMin = c.delta
            lines[#lines + 1] = ("+%s mana/min while not casting for 5s+"):format(round(perMin))
            -- Translate to casts of the player's reference spell if we know one.
            local ref = s.referenceSpell
            local spell = ref and HM.gen and HM.gen.spells and HM.gen.spells[ref]
            if spell and spell.cost and perMin > 0 then
                local minutesPerCast = spell.cost / perMin
                lines[#lines + 1] = ("~1 extra %s every %s min of downtime regen")
                    :format(spell.name, round(minutesPerCast))
            end
        elseif c.id == "survivability" then
            lines[#lines + 1] = ("survivability index %s -> %s (%s%%)")
                :format(round(c.before), round(c.after), round(c.pct or 0, 2))
        else
            lines[#lines + 1] = ("%s: %s -> %s (%+.2f%%)")
                :format(c.label, round(c.before), round(c.after), c.pct or 0)
        end
    end
    if #lines == 0 then
        lines[1] = ("+%s %s has no modeled effect for a %s yet (v0 dimensions)")
            :format(amount, stat, s.classToken or "?")
    end
    return lines, changes
end

-- Talent summary for tooltips: what a talent touches, from precise generated data.
-- Returns { name, affectedNames = {...}, property, valueAtRank, isPct, needsCuration }.
function Impact.talentSummary(talentId, rank)
    local talent = HM.gen and HM.gen.talents and HM.gen.talents[talentId]
    local impacts = HM.gen and HM.gen.talentImpacts and HM.gen.talentImpacts[talentId]
    if not talent then return nil end
    rank = rank or talent.maxRank
    local summary = {
        name = talent.name, maxRank = talent.maxRank, rank = rank,
        needsCuration = impacts and impacts.needsCuration or false,
        ops = {},
    }
    local seen = {}
    for _, op in ipairs(impacts and impacts.ops or {}) do
        local entry = {
            kind = op.kind, property = op.property or op.label or op.stat or op.school,
            isPct = op.isPct,
            value = HM.formulas.talentRankValue.fn(op.maxValue or 0, rank, talent.maxRank),
            rankRule = op.rankRule,
            affectedNames = {},
        }
        for _, sid in ipairs(op.affected or {}) do
            local spell = HM.gen.spells and HM.gen.spells[sid]
            local name = spell and spell.name
            if name and not seen[name] then
                seen[name] = true
                entry.affectedNames[#entry.affectedNames + 1] = name
            end
        end
        table.sort(entry.affectedNames)
        summary.ops[#summary.ops + 1] = entry
    end
    return summary
end

return Impact
