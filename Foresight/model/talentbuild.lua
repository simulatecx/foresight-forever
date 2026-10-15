-- Talent build engine (S35 UI-talent-planner): the PURE rules + build-string codec behind
-- the interactive talent planner. No frames here - ui/talent_tree.lua renders + drives this.
-- A "build" is a plain map { [talentId] = rank }. All reads are defensive (untrusted-input
-- law: imported strings + inspected players are hostile data). DISPLAY/ADVICE ONLY - this
-- plans and validates; it NEVER spends points (no LearnTalent/PurchaseRank/CommitConfig).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local TB = {}
HM.TalentBuild = TB

TB.MAX_LEVEL = 60          -- classic cap; talent points = level - 9 (1 per level from 10)
TB.POINTS_PER_TIER = 5     -- points in LOWER tiers needed to unlock a tier (0-based tiers)

local function gen() return HM.gen or {} end

-- classToken ("SHAMAN") -> classId (the ChrClasses id), from the generated class roster.
function TB.classIdFor(token)
    token = tostring(token or ""):upper()
    local classes = gen().classes
    if type(classes) == "table" then
        for id, c in pairs(classes) do
            if type(c) == "table" and tostring(c.token or ""):upper() == token then return id end
        end
    end
    for id, name in pairs(gen().classNames or {}) do
        if type(name) == "string" and name:upper() == token then return id end
    end
    return nil
end

function TB.classToken(classId)
    local c = gen().classes and gen().classes[classId]
    if c and c.token then return c.token end
    local n = gen().classNames and gen().classNames[classId]
    return n and n:upper() or nil
end

-- The 3 tab ids for a class, in display order (talentTabs.order).
function TB.tabsForClass(classId)
    local g = gen()
    local seen, tabs = {}, {}
    for _, t in pairs(g.talents or {}) do
        if type(t) == "table" and t.classId == classId and t.tab and not seen[t.tab] then
            seen[t.tab] = true
            tabs[#tabs + 1] = t.tab
        end
    end
    table.sort(tabs, function(a, b)
        local oa = (g.talentTabs and g.talentTabs[a] and g.talentTabs[a].order) or 0
        local ob = (g.talentTabs and g.talentTabs[b] and g.talentTabs[b].order) or 0
        if oa ~= ob then return oa < ob end
        return a < b
    end)
    return tabs
end

-- Talents in a tab, canonical order by (tier, column) - used for layout AND the build-string
-- slot order, so encode/decode agree on both ends (deterministic from generated data).
function TB.talentsInTab(tabId)
    local g = gen()
    local list = {}
    for tid, t in pairs(g.talents or {}) do
        if type(t) == "table" and t.tab == tabId then list[#list + 1] = tid end
    end
    table.sort(list, function(a, b)
        local ta, tb = g.talents[a], g.talents[b]
        if (ta.tier or 0) ~= (tb.tier or 0) then return (ta.tier or 0) < (tb.tier or 0) end
        if (ta.column or 0) ~= (tb.column or 0) then return (ta.column or 0) < (tb.column or 0) end
        return a < b
    end)
    return list
end

function TB.pointsInTab(build, tabId)
    local g, n = gen(), 0
    for tid, rank in pairs(build or {}) do
        local t = g.talents and g.talents[tid]
        if t and t.tab == tabId then n = n + (tonumber(rank) or 0) end
    end
    return n
end

-- Points in tiers STRICTLY BELOW `tier` within a tab (the classic tier-unlock basis).
function TB.pointsBelowTier(build, tabId, tier)
    local g, n = gen(), 0
    for tid, rank in pairs(build or {}) do
        local t = g.talents and g.talents[tid]
        if t and t.tab == tabId and (t.tier or 0) < tier then n = n + (tonumber(rank) or 0) end
    end
    return n
end

function TB.totalPoints(build)
    local n = 0
    for _, rank in pairs(build or {}) do n = n + (tonumber(rank) or 0) end
    return n
end

-- Points available at a character level (for display; planning itself is unbounded up to max).
function TB.budget(level) return math.max(0, (tonumber(level) or 0) - 9) end

-- Why a talent is locked, purely from the build (nil = allocatable). Does NOT check maxRank.
function TB.lockReason(build, talentId)
    local t = gen().talents and gen().talents[talentId]
    if not t then return "unknown talent" end
    local need = TB.POINTS_PER_TIER * (t.tier or 0)
    if TB.pointsBelowTier(build, t.tab, t.tier or 0) < need then
        return ("Requires %d points in this tree"):format(need)
    end
    for _, pr in ipairs(t.prereqs or {}) do
        if (tonumber(build[pr.talent]) or 0) < (pr.rank or 1) then
            local pt = gen().talents and gen().talents[pr.talent]
            return ("Requires %d/%d %s"):format(pr.rank or 1,
                (pt and pt.maxRank) or (pr.rank or 1), (pt and pt.name) or "prerequisite")
        end
    end
    return nil
end

function TB.canAdd(build, talentId)
    local t = gen().talents and gen().talents[talentId]
    if not t then return false, "unknown talent" end
    if (tonumber(build[talentId]) or 0) >= (t.maxRank or 1) then return false, "At max rank" end
    local locked = TB.lockReason(build, talentId)
    if locked then return false, locked end
    return true
end

-- Can we remove a point without making any OTHER allocated talent illegal (tier or prereq)?
function TB.canRemove(build, talentId)
    local g = gen()
    local cur = tonumber(build and build[talentId]) or 0
    if cur <= 0 then return false, "No point to remove" end
    local sim = {}
    for k, v in pairs(build) do sim[k] = v end
    sim[talentId] = cur - 1
    for otid, orank in pairs(sim) do
        if (tonumber(orank) or 0) > 0 then
            local ot = g.talents and g.talents[otid]
            if ot then
                if TB.pointsBelowTier(sim, ot.tab, ot.tier or 0) < TB.POINTS_PER_TIER * (ot.tier or 0) then
                    return false, "Other talents depend on these points"
                end
                for _, pr in ipairs(ot.prereqs or {}) do
                    if pr.talent == talentId and (tonumber(sim[talentId]) or 0) < (pr.rank or 1) then
                        return false, "A dependent talent needs this rank"
                    end
                end
            end
        end
    end
    return true
end

local function copy(build)
    local out = {}
    for k, v in pairs(build or {}) do out[k] = v end
    return out
end

function TB.add(build, talentId)
    if not TB.canAdd(build, talentId) then return build, false end
    local out = copy(build)
    out[talentId] = (tonumber(out[talentId]) or 0) + 1
    return out, true
end

function TB.remove(build, talentId)
    if not TB.canRemove(build, talentId) then return build, false end
    local out = copy(build)
    local nv = (tonumber(out[talentId]) or 0) - 1
    out[talentId] = nv > 0 and nv or nil
    return out, true
end

-- Is a whole build legal: every allocated talent within rank, tier-unlocked, prereqs met, and
-- the total within the classic maximum. These constraints together guarantee the build is
-- reachable by bottom-up allocation, so a decoded/imported build that passes is trustworthy.
function TB.isLegal(classToken, build)
    local g = gen()
    if TB.totalPoints(build) > TB.budget(TB.MAX_LEVEL) then return false, "too many points" end
    local classId = TB.classIdFor(classToken)
    for tid, rank in pairs(build or {}) do
        rank = tonumber(rank) or 0
        local t = g.talents and g.talents[tid]
        if not t then return false, "unknown talent" end
        if classId and t.classId ~= classId then return false, "wrong class" end
        if rank < 1 or rank > (t.maxRank or 1) then return false, "bad rank" end
        if TB.pointsBelowTier(build, t.tab, t.tier or 0) < TB.POINTS_PER_TIER * (t.tier or 0) then
            return false, "tier not unlocked"
        end
        for _, pr in ipairs(t.prereqs or {}) do
            if (tonumber(build[pr.talent]) or 0) < (pr.rank or 1) then return false, "prereq unmet" end
        end
    end
    return true
end

-- Compact, versioned, URL-safe build string: "FT1-<CLASS>-<t1>-<t2>-<t3>", each tN the ranks
-- (single digit 0..maxRank<=5) of that tab's talents in canonical order, trailing zeros
-- trimmed. DATA ONLY; decode re-validates with isLegal and never executes anything.
function TB.encode(classToken, build)
    local classId = TB.classIdFor(classToken)
    if not classId then return nil end
    local parts = {}
    for _, tabId in ipairs(TB.tabsForClass(classId)) do
        local digits = {}
        for _, tid in ipairs(TB.talentsInTab(tabId)) do
            digits[#digits + 1] = tostring(math.min(9, tonumber(build and build[tid]) or 0))
        end
        parts[#parts + 1] = (table.concat(digits)):gsub("0+$", "")
    end
    return ("FT1-%s-%s"):format(tostring(classToken):upper(), table.concat(parts, "-"))
end

function TB.decode(str)
    if type(str) ~= "string" then return nil, "not a string" end
    local classToken, rest = str:match("^FT1%-(%u+)%-(.*)$")
    if not classToken then return nil, "not a Foresight build string (FT1-...)" end
    local classId = TB.classIdFor(classToken)
    if not classId then return nil, "unknown class" end
    local tabStrings = {}
    for s in (rest .. "-"):gmatch("([^%-]*)%-") do tabStrings[#tabStrings + 1] = s end
    local build = {}
    local tabs = TB.tabsForClass(classId)
    for i, tabId in ipairs(tabs) do
        local digits = tabStrings[i] or ""
        if digits:find("[^0-9]") then return nil, "malformed string" end
        local talents = TB.talentsInTab(tabId)
        for j = 1, #talents do
            local r = tonumber(digits:sub(j, j)) or 0
            if r > 0 then
                local t = gen().talents[talents[j]]
                if not t or r > (t.maxRank or 1) then return nil, "rank over max" end
                build[talents[j]] = r
            end
        end
    end
    local ok, why = TB.isLegal(classToken, build)
    if not ok then return nil, "illegal build (" .. tostring(why) .. ")" end
    return build, classToken
end

-- Map a classic-talent build (talentId->rank) to a C_Traits NODE plan (nodeId->rank), via
-- the shared spellID bridge (gen.traits.bySpell). This is what drives the live overlay on
-- the real tree. Only classic-overlap talents map (Forever-new nodes aren't in the classic
-- grid - those are planned on the live tree directly, a future step). Pure + defensive.
function TB.toNodePlan(build)
    local g = gen()
    local bySpell = g.traits and g.traits.bySpell
    local out = {}
    if type(bySpell) ~= "table" then return out end
    for tid, rank in pairs(build or {}) do
        rank = tonumber(rank) or 0
        local t = g.talents and g.talents[tid]
        if t and rank > 0 and type(t.spellRanks) == "table" then
            for _, sid in ipairs(t.spellRanks) do
                local nodeId = bySpell[sid]
                if nodeId then
                    if rank > (out[nodeId] or 0) then out[nodeId] = rank end
                    break
                end
            end
        end
    end
    return out
end

-- The set of C_Traits node ids any classic talent maps to (the classic-overlap nodes). The
-- grid "owns" these; everything else in a node plan (Forever-new nodes from inspect/FT2/the
-- edit overlay) is owned outside the grid and must survive a grid edit. Cached-free + pure.
function TB.classicNodeSet()
    local g = gen()
    local bySpell = g.traits and g.traits.bySpell
    local set = {}
    if type(bySpell) ~= "table" or type(g.talents) ~= "table" then return set end
    for _, t in pairs(g.talents) do
        if type(t) == "table" and type(t.spellRanks) == "table" then
            for _, sid in ipairs(t.spellRanks) do
                local nid = bySpell[sid]
                if nid then set[nid] = true; break end
            end
        end
    end
    return set
end

-- Map a C_Traits node plan (nodeId->rank) back to a classic-talent build for the grid view.
-- Only classic-overlap nodes map (via the node's spellID -> the talent that owns it); Forever-
-- new nodes have no classic talent and are left to the live overlay. Pure.
function TB.fromNodePlan(nodePlan)
    local g = gen()
    local nodes = g.traits and g.traits.nodes
    local out = {}
    if type(nodePlan) ~= "table" or type(nodes) ~= "table" or type(g.talents) ~= "table" then return out end
    local byRankSpell = {}
    for tid, t in pairs(g.talents) do
        if type(t.spellRanks) == "table" then
            for _, s in ipairs(t.spellRanks) do if byRankSpell[s] == nil then byRankSpell[s] = tid end end
        end
    end
    for nid, rank in pairs(nodePlan) do
        local node = nodes[nid]
        local sid = node and node.spellID
        local tid = sid and byRankSpell[sid]
        if tid and g.talents[tid] then
            local mr = g.talents[tid].maxRank or 1
            local r = math.min(mr, tonumber(rank) or 0)
            if r > (out[tid] or 0) then out[tid] = r end
        end
    end
    return out
end

return TB
