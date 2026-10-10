-- Foresight tooltip injection: THE one shared injection module (triage law: the future
-- spell-tooltip surface, UI-spell-tooltip, must reuse this core - never a second hook
-- system). S2 ships the talent provider: hovering a talent appends an honest Foresight
-- block - what the talent affects, what the next point is worth, and what that does to
-- your dimension scores - matching the approved design in mockups/foresight-ui.html.
--
-- Split: the resolver and line builders are pure Lua (selftest-covered headless); only
-- attach() and the hook install touch frames. Degrade law: any failure - secret values,
-- API-shape surprises, unresolvable talents - means NO injected lines, never an error.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Tooltips = {}
HM.Tooltips = Tooltips
Tooltips.installed = false

local BRAND = { r = 0.2, g = 1, b = 0.6 }
local GREY = { r = 0.62, g = 0.62, b = 0.62 }
local BODY = { r = 0.9, g = 0.9, b = 0.9 }
local MAX_AFFECTED_NAMES = 8

-- Talent resolver: classic-API position (1-based tab/tier/column) -> generated talent id ---

local CLASS_MASKS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local classIndexCache

-- Per-class lookup tables built once from generated data: tab ids sorted by their
-- in-game order, talents keyed by "tabIndex:tier:column" (0-based, as generated)
-- and by lowercase name for the fallback path.
local function classIndex()
    if classIndexCache then return classIndexCache end
    local tabs = HM.gen and HM.gen.talentTabs
    local talents = HM.gen and HM.gen.talents
    if not (tabs and talents) then return nil end

    local perMask, maskToToken = {}, {}
    for tabId, tab in pairs(tabs) do
        perMask[tab.classMask] = perMask[tab.classMask] or {}
        local list = perMask[tab.classMask]
        list[#list + 1] = { id = tabId, order = tab.order }
    end
    classIndexCache = {}
    for token, mask in pairs(CLASS_MASKS) do
        maskToToken[mask] = token
        local list = perMask[mask] or {}
        table.sort(list, function(a, b) return a.order < b.order end)
        local tabIndexOf = {}
        for i, t in ipairs(list) do tabIndexOf[t.id] = i end
        classIndexCache[token] = { tabIndexOf = tabIndexOf, byPos = {}, byName = {} }
    end
    for id, t in pairs(talents) do
        local tab = tabs[t.tab]
        local entry = tab and classIndexCache[maskToToken[tab.classMask]]
        local tabIndex = entry and entry.tabIndexOf[t.tab]
        if tabIndex then
            entry.byPos[tabIndex .. ":" .. (t.tier or 0) .. ":" .. (t.column or 0)] = id
            entry.byName[(t.name or ""):lower()] = id
        end
    end
    return classIndexCache
end

-- Resolve a hovered talent to its generated id. Position (what the classic talent API
-- reports, 1-based) is primary; the displayed name arbitrates when they disagree.
function Tooltips.resolveTalent(classToken, tabIndex, tier, column, name)
    local idx = classIndex()
    local entry = idx and idx[classToken]
    if not entry then return nil end
    local id = entry.byPos[tabIndex .. ":" .. ((tier or 1) - 1) .. ":" .. ((column or 1) - 1)]
    if id and name and HM.gen.talents[id].name ~= name then
        id = nil -- position and displayed name disagree: trust the name the user sees
    end
    if not id and name then
        id = entry.byName[name:lower()]
    end
    return id
end

-- Line builders (pure) ---------------------------------------------------------

-- Generated time-type properties carry milliseconds; everything else is a plain
-- number or (isPct) a percentage.
local MS_PROPS = {
    ["cast time"] = true, ["cooldown"] = true, ["duration"] = true,
    ["global cooldown"] = true, ["activation time"] = true,
}

local function fmtValue(value, isPct, property)
    if isPct then return ("%+g%%"):format(value) end
    if property and MS_PROPS[property] then return ("%+gs"):format(value / 1000) end
    return ("%+g"):format(value)
end

-- "What does the next point do to my scores?" - diff one-more-rank against the current
-- rank. The snapshot's baked-in talent effects cancel out of the diff, so only the
-- marginal point shows. Returns nil when no dimension moves (cast time, cost and
-- cooldown ops don't fold into dimensions yet - see GRAPH-rotation-weights backlog).
local function dimFragment(loadout, talentId, rank, maxRank)
    if not loadout or rank >= maxRank then return nil end
    local ok, changes = pcall(function()
        return (HM.Impact.diff(loadout:withTalent(talentId, rank),
                               loadout:withTalent(talentId, rank + 1)))
    end)
    if not ok or type(changes) ~= "table" or #changes == 0 then return nil end
    local top = changes[1]
    local color = top.delta >= 0 and "|cff4ade80" or "|cfff87171"
    return ("-> for you now: %s%+.1f|r %s"):format(color, top.delta, top.label)
end

-- Build the injected block for a talent at the player's current rank. Returns a list
-- of { text, r, g, b, wrap } lines ({ kind = "double", left, right, ... } for the
-- header) or nil when there is nothing honest to say.
function Tooltips.talentLines(talentId, currentRank, loadout)
    local summary = HM.Impact.talentSummary(talentId)
    if not summary then return nil end
    local F = HM.formulas
    local rank = currentRank or 0
    local maxRank = summary.maxRank or 1
    local lines = {}

    local presumed = F.presumedMark(F.talentRankValue) ~= ""
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = presumed and "(p) rank rule presumed" or nil,
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }

    local affected = {}
    for _, op in ipairs(summary.ops) do
        for _, n in ipairs(op.affectedNames) do affected[#affected + 1] = n end
    end
    if #affected > 0 then
        local shown = {}
        for i = 1, math.min(#affected, MAX_AFFECTED_NAMES) do shown[i] = affected[i] end
        local more = #affected - #shown
        lines[#lines + 1] = {
            text = "|cff9d9d9dAffects:|r " .. table.concat(shown, ", ")
                .. (more > 0 and (" (+%d more)"):format(more) or ""),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
    end

    for _, op in ipairs(summary.ops) do
        if op.property and op.maxValue then
            local valueAt = function(r) return F.talentRankValue.fn(op.maxValue, r, maxRank) end
            local text
            if maxRank <= 1 then
                text = ("%s %s"):format(fmtValue(valueAt(1), op.isPct, op.property), op.property)
            elseif rank >= maxRank then
                text = ("Maxed: %s %s"):format(
                    fmtValue(valueAt(maxRank), op.isPct, op.property), op.property)
            else
                local marginal = fmtValue(valueAt(rank + 1) - valueAt(rank), op.isPct, op.property)
                local maxPart = fmtValue(valueAt(maxRank), op.isPct, op.property)
                if rank == 0 then
                    text = ("Next point: %s %s (max %s)"):format(marginal, op.property, maxPart)
                else
                    text = ("Next point: %s %s (now %s, max %s)"):format(
                        marginal, op.property,
                        fmtValue(valueAt(rank), op.isPct, op.property), maxPart)
                end
            end
            lines[#lines + 1] = { text = text, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
        end
    end

    local dim = dimFragment(loadout, talentId, rank, maxRank)
    if dim then
        lines[#lines + 1] = { text = dim, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
    end

    if summary.needsCuration then
        lines[#lines + 1] = {
            text = "Some effects aren't mapped yet - shown values may be incomplete (needs curation).",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end

    if #lines <= 1 then return nil end -- nothing beyond the header: inject nothing
    return lines
end

-- In-game wiring ---------------------------------------------------------------

local function attach(tip, lines)
    tip:AddLine(" ")
    for _, L in ipairs(lines) do
        if L.kind == "double" and L.right then
            tip:AddDoubleLine(L.left, L.right, L.r, L.g, L.b, L.r2, L.g2, L.b2)
        else
            tip:AddLine(L.text or L.left, L.r, L.g, L.b, L.wrap)
        end
    end
    tip:Show() -- recalculate tooltip height for the appended block
end

local function injectTalent(tip, tab, index)
    local name, _, tier, column, rank = _G.GetTalentInfo(tab, index)
    if not name then return end
    local _, classToken = _G.UnitClass("player")
    if not classToken then return end
    local talentId = Tooltips.resolveTalent(classToken, tab, tier, column, name)
    if not talentId then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local lines = Tooltips.talentLines(talentId, rank, loadout)
    if lines then attach(tip, lines) end
end

local function onSetTalent(tip, tab, index, inspect)
    if inspect then return end -- we model the player, never an inspected unit
    pcall(injectTalent, tip, tab, index)
end

function Tooltips.install()
    if Tooltips.installed then return true end
    local tip = _G.GameTooltip
    if not (tip and _G.hooksecurefunc and _G.GetTalentInfo
            and type(tip.SetTalent) == "function") then
        return false -- headless, or API moved: degrade to no injection (S3 verify surfaces it)
    end
    -- Post-hook on THIS tooltip object only - never the shared template metatable - so
    -- the hidden ForesightScanTooltip probe keeps capturing clean, uninjected text.
    _G.hooksecurefunc(tip, "SetTalent", onSetTalent)
    Tooltips.installed = true
    return true
end

if _G.CreateFrame then Tooltips.install() end

return Tooltips
