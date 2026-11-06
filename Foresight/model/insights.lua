-- Foresight/model/insights.lua - "understand your character" (INSIGHTS, S51).
-- A plain-language read of the player's OWN character, for first-run onboarding and
-- /foresight insights: the archetype it leans to, its biggest hits, what its talent build
-- actually stacks (and the capstone it pays off into), the hidden cross-tree synergy its
-- class can exploit, and ONE coaching nudge. Pure + defensive - every piece is nil-guarded
-- so it degrades to whatever the live data supports (headless = the structural pieces only).
-- Reuses the existing engines (Impact / Sim / Synergy); it introduces no new analysis math.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Insights = {}
HM.Insights = Insights

-- The planner-shaped build table (id -> rank) from a snapshot's talents: nodeId on Forever,
-- talentId on classic - the same key space Synergy.analyzeBuild expects.
local function buildFromSnapshot(snap)
    local b, n = {}, 0
    for _, t in ipairs((snap and snap.talents) or {}) do
        local id = t.nodeId or t.talentId
        if id and (tonumber(t.rank) or 0) > 0 then b[id] = t.rank; n = n + 1 end
    end
    return b, n
end

-- forCharacter(loadout) -> { lines = {{text, tone}...}, archetype, primary, hasBuild }
-- tone is "head"|"body"|"muted" so the caller can color without re-deciding anything.
function Insights.forCharacter(loadout)
    if not loadout then return nil end
    local snap = loadout.snapshot or {}
    local stats = snap.stats or {}
    local classToken = snap.classToken
    local lines = {}
    local function add(text, tone) lines[#lines + 1] = { text = text, tone = tone or "body" } end

    -- 1) Archetype + primary output lens (the one-line "who you are").
    local results = HM.Impact and HM.Impact.evaluate and HM.Impact.evaluate(loadout)
    local primary = HM.Impact and HM.Impact.primaryDimension and HM.Impact.primaryDimension(loadout)
    local standing = results and HM.Sim and HM.Sim.standing and HM.Sim.standing(results, stats)
    local archName = standing and standing.name ~= "Unmeasured" and standing.name or nil
    local primaryLabel = primary and results and results[primary] and results[primary].label or nil
    if archName or primaryLabel then
        local who = archName or "Your character"
        if primaryLabel then who = who .. (", strongest at " .. primaryLabel) end
        add(who .. ((classToken and (" (" .. classToken:lower() .. ")")) or "") .. ".", "head")
        if standing and standing.detail and standing.detail ~= "" then add(standing.detail, "muted") end
    else
        add("Here's your character.", "head")
    end

    -- 2) Biggest hits (what your buttons do now), when the spellbook is readable.
    local tops = HM.PanelModel and HM.PanelModel._topHits and HM.PanelModel._topHits(loadout, 3)
    if tops and #tops > 0 then
        local parts = {}
        for _, e in ipairs(tops) do parts[#parts + 1] = ("%s ~%d"):format(e.name, math.floor(e.avg + 0.5)) end
        add("Your biggest hits: " .. table.concat(parts, ", ") .. ".", "body")
    end

    -- 3) What your BUILD stacks + its payoff (the synergy rationale on your own talents).
    local build, allocated = buildFromSnapshot(snap)
    local hasBuild = allocated > 0
    if hasBuild and HM.Synergy and HM.Synergy.analyzeBuild then
        local an = HM.Synergy.analyzeBuild(build, { classToken = classToken,
            raceId = snap.raceId })
        if an and an.headline then
            add("Your build: " .. an.headline .. ".", "body")
            for _, line in ipairs((an.chains and { an.chains[1] }) or {}) do
                if line then add("  Chains: " .. line, "muted") end
            end
        end
    elseif not hasBuild then
        add("No talent points spent yet - open your talents, or try /foresight planner.", "muted")
    end

    -- 4) The hidden cross-tree synergy your class can exploit (the off-meta lever).
    if HM.Synergy and HM.Synergy.crossTreeInsights then
        local ins = HM.Synergy.crossTreeInsights({ classToken = classToken, raceId = snap.raceId })
        if ins and ins[1] then add("Hidden synergy: " .. ins[1].text .. ".", "body") end
    end

    -- 5) ONE coaching nudge (a mechanism-dead stat for your build), reusing the S20 line.
    if HM.Impact and HM.Impact.coachingLine and HM.Impact.rankStats then
        local ranked, focus = HM.Impact.rankStats(loadout, nil, primary)
        local ok, coach = pcall(HM.Impact.coachingLine, loadout, ranked, focus)
        if ok and coach then add(coach, "muted") end
    end

    return { lines = lines, archetype = archName, primary = primary, hasBuild = hasBuild }
end

-- Flatten to plain strings (slash output / chat), honesty tags intact.
function Insights.textLines(loadout)
    local r = Insights.forCharacter(loadout)
    if not r then return {} end
    local out = {}
    for _, l in ipairs(r.lines) do out[#out + 1] = l.text end
    return out
end

return Insights
