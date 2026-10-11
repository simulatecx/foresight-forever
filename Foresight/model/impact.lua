-- Foresight impact evaluation: score a loadout across all dimensions, diff two loadouts,
-- and explain deltas in human terms. This is the engine behind "model this talent" and
-- "what does +2 Spirit actually do for me".

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

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

-- Combined stat-delta explanation for an item (or any bundle of stats): apply every
-- delta at once, diff against the base loadout, describe the dimension moves. Reuses the
-- diff path - the one marginal-value computation, never a second. statDeltas is keyed by
-- snapshot stat name ({ Agility = 4, Stamina = 6, spellDamage = 10 }).
function Impact.explainItemDelta(loadout, statDeltas)
    local modeled, any = loadout, false
    for stat, amount in pairs(statDeltas or {}) do
        if type(amount) == "number" and amount ~= 0 then
            modeled = modeled:withStatDelta(stat, amount, ("+%g %s"):format(amount, stat))
            any = true
        end
    end
    if not any then return {}, {} end
    local changes = Impact.diff(loadout, modeled)
    local lines = {}
    for _, c in ipairs(changes) do
        lines[#lines + 1] = ("%s: %+.1f%%"):format(c.label, c.pct or 0)
    end
    return lines, changes
end

-- Gear compare (DATA-items v0): net per-dimension impact of equipping item A instead of
-- item B. Both are mapped stat bundles ({ Agility=4, Stamina=6, ... }). Reuses
-- explainItemDelta (the diff path) - no forked value math. net > 0 means A wins that
-- dimension. Returns rows sorted by |net|, biggest swing first.
function Impact.compareItems(loadout, statsA, statsB)
    local _, changesA = Impact.explainItemDelta(loadout, statsA)
    local _, changesB = Impact.explainItemDelta(loadout, statsB)
    local byId = {}
    for _, c in ipairs(changesA or {}) do
        byId[c.id] = { id = c.id, label = c.label, a = c.pct or 0, b = 0 }
    end
    for _, c in ipairs(changesB or {}) do
        local r = byId[c.id] or { id = c.id, label = c.label, a = 0, b = 0 }
        r.b = c.pct or 0
        byId[c.id] = r
    end
    local rows = {}
    for _, r in pairs(byId) do
        local net = r.a - r.b
        if math.abs(net) > 1e-9 then
            rows[#rows + 1] = { id = r.id, label = r.label, net = net }
        end
    end
    table.sort(rows, function(x, y) return math.abs(x.net) > math.abs(y.net) end)
    return rows
end

-- Gear VERDICT (Pawn-style headline, but honest): the one-line answer - is this item an
-- upgrade for the dimension you're gearing for? Uses the real diff (net swap vs equipped,
-- or marginal add when there's nothing to compare), never a one-directional stat weight.
-- goalId = a dimension id, or "auto"/nil to use the build's primary output lens.
function Impact.itemVerdict(loadout, mapped, comparedStats, goalId)
    local goal = goalId
    if not goal or goal == "auto" then goal = Impact.primaryDimension(loadout) end
    local pct
    if comparedStats then
        for _, r in ipairs(Impact.compareItems(loadout, mapped, comparedStats)) do
            if r.id == goal then pct = r.net end
        end
    else
        local _, changes = Impact.explainItemDelta(loadout, mapped)
        for _, c in ipairs(changes or {}) do
            if c.id == goal then pct = c.pct end
        end
    end
    pct = pct or 0
    local dim = HM.dimensions.byId(goal)
    local direction = (pct > 0.05 and "upgrade")
        or (pct < -0.05 and "downgrade") or "sidegrade"
    return { dim = goal, label = dim and dim.label or goal, pct = pct,
             direction = direction, compared = comparedStats ~= nil }
end

-- MODEL-stat-advisor: rank stats by marginal value for THIS build, so gear/drop choices
-- are obvious. Built entirely on explainStatDelta (no second value path). v0 heuristic:
-- "value" is each stat's strongest dimension move per +1 point; the headline orders by
-- the build's primary output lens, the per-stat breakdown shows each stat's best use.
local OUTPUT_DIMS = { "spellcasting", "meleeDps", "rangedDps", "healing" }
local DEFAULT_STATS = { "Strength", "Agility", "Stamina", "Intellect", "Spirit" }

-- The build's primary output lens: highest-scoring of the throughput dimensions.
function Impact.primaryDimension(loadout)
    local results = Impact.evaluate(loadout)
    local bestId, bestScore
    for _, id in ipairs(OUTPUT_DIMS) do
        local r = results[id]
        if r and r.score and (not bestScore or r.score > bestScore) then
            bestId, bestScore = id, r.score
        end
    end
    return bestId or "spellcasting", results
end

-- Rank stats for a loadout. Returns ordered list of
-- { stat, focusPct, bestPct, bestLabel } plus the focus dimension id.
function Impact.rankStats(loadout, stats, focusDimId)
    stats = stats or DEFAULT_STATS
    local focus = focusDimId or Impact.primaryDimension(loadout)
    local ranked = {}
    for _, stat in ipairs(stats) do
        local _, changes = Impact.explainStatDelta(loadout, stat, 1)
        local focusPct, bestPct, bestLabel = 0, 0, nil
        for _, c in ipairs(changes or {}) do
            if c.id == focus then focusPct = c.pct or 0 end
            if math.abs(c.pct or 0) > math.abs(bestPct) then
                bestPct, bestLabel = c.pct or 0, c.label
            end
        end
        ranked[#ranked + 1] = { stat = stat, focusPct = focusPct,
                                bestPct = bestPct, bestLabel = bestLabel }
    end
    table.sort(ranked, function(a, b)
        if a.focusPct ~= b.focusPct then return a.focusPct > b.focusPct end
        return math.abs(a.bestPct) > math.abs(b.bestPct)
    end)
    return ranked, focus
end

-- One human sentence: "For your Spellcasting right now: Intellect > Spirit per point".
function Impact.statPrioritySentence(loadout, stats)
    local ranked, focus = Impact.rankStats(loadout, stats)
    local dim = HM.dimensions.byId(focus)
    local names = {}
    for _, r in ipairs(ranked) do
        if r.focusPct > 0 then names[#names + 1] = r.stat end
    end
    if #names == 0 then -- nothing moves the focus lens; fall back to best-overall order
        for _, r in ipairs(ranked) do names[#names + 1] = r.stat end
    end
    return ("For your %s right now: %s per point (v0 heuristic)"):format(
        dim and dim.label or "build", table.concat(names, " > ")), ranked, focus
end

-- The CHAIN view (shared): given a base loadout and a modeled one (one stat added, or one
-- talent taken), describe the derived stats it moves (AP + per-swing damage, crit%, mana)
-- and the net dimension deltas - reading the graph's intermediate nodes, not just the
-- final dimensions. This is the "+2 AP -> ~+0.5 dmg per main-hand swing" answer.
local function derivedChainLines(base, modeled, statsOnly)
    local bb, ab = base:build(), modeled:build()
    local function delta(id)
        local okb, vb = pcall(function() return bb.graph:value(id, bb.ctx, {}) end)
        local oka, va = pcall(function() return ab.graph:value(id, ab.ctx, {}) end)
        if okb and oka and vb and va then return va - vb end
    end
    local s = base.snapshot
    local ws = s.weaponSpeed or 2
    local lines = {}

    local ap = delta("stat.attackPower")
    if ap and math.abs(ap) > 0.05 then
        lines[#lines + 1] = ("%+.0f Attack Power"):format(ap)
        lines[#lines + 1] = ("  ~%+.1f damage per main-hand swing (%.1fs weapon)"):format(
            ap / 14 * ws, ws)
    end
    local rap = delta("stat.rangedAttackPower")
    if rap and math.abs(rap) > 0.05 then
        lines[#lines + 1] = ("%+.0f Ranged Attack Power"):format(rap)
    end
    local mc = delta("stat.meleeCritPct")
    if mc and math.abs(mc) > 0.004 then
        lines[#lines + 1] = ("%+.2f%% melee crit (your swings + special attacks)"):format(mc)
    end
    local sc = delta("stat.spellCritPct")
    if sc and math.abs(sc) > 0.004 then
        lines[#lines + 1] = ("%+.2f%% spell crit (your damage/healing spells)"):format(sc)
    end
    local mana = delta("stat.maxMana")
    if mana and math.abs(mana) > 0.5 then lines[#lines + 1] = ("%+.0f max mana"):format(mana) end
    local hp = delta("stat.maxHealth")
    if hp and math.abs(hp) > 0.5 then lines[#lines + 1] = ("%+.0f max health"):format(hp) end
    local regen = delta("mech.manaPerTick")
    if regen and math.abs(regen) > 0.02 then
        lines[#lines + 1] = ("%+.1f mana/tick while regenerating"):format(regen)
    end

    if not statsOnly then
        for _, c in ipairs(Impact.diff(base, modeled) or {}) do
            if math.abs(c.pct or 0) > 0.009 then
                lines[#lines + 1] = ("-> %s %+.2f%%"):format(c.label, c.pct)
            end
        end
    end
    return lines
end

-- The derived stats a bundle of item stats grants (crit%, AP + per-swing, mana) - the
-- concrete "what +1 Agility actually gives you" for an item tooltip. No dimension lines.
function Impact.itemDerivedLines(loadout, statDeltas)
    local modeled, any = loadout, false
    for stat, amount in pairs(statDeltas or {}) do
        if type(amount) == "number" and amount ~= 0 then
            modeled = modeled:withStatDelta(stat, amount, ("+%g %s"):format(amount, stat))
            any = true
        end
    end
    if not any then return {} end
    return derivedChainLines(loadout, modeled, true)
end

-- What a raw stat change does, step by step (the /foresight stat answer).
function Impact.statImpactDetail(loadout, stat, amount)
    local modeled = loadout:withStatDelta(stat, amount, ("+%s %s"):format(amount, stat))
    local lines = derivedChainLines(loadout, modeled)
    if #lines == 0 then
        lines[1] = ("+%s %s has no modeled effect for a %s yet"):format(
            amount, stat, loadout.snapshot.classToken or "?")
    end
    return lines
end

-- What taking a trait node (classic talent or new Forever node) does for the character.
function Impact.talentChainLines(loadout, nodeId, rank)
    return derivedChainLines(loadout, loadout:withTraitNode(nodeId, rank))
end

-- The derived-stat chain between any two loadouts (WHATIF-planner surface; stats
-- only - dimension changes come from diff so callers never show them twice).
function Impact.chainLines(base, modeled)
    return derivedChainLines(base, modeled, true)
end

-- CONSUME-buffs: what a consumable buff is worth while active - and, sign-flipped,
-- what expires with it. One diff through the shared path; no forked math.
-- Returns derived chain lines (incl. dimension moves) + the raw changes.
function Impact.buffDelta(loadout, id)
    local modeled = loadout:withBuff(id)
    local lines = derivedChainLines(loadout, modeled)
    local changes = Impact.diff(loadout, modeled)
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
            isPct = op.isPct, maxValue = op.maxValue,
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
