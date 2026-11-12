-- Foresight/ui/bag_arrows.lua - bag upgrade arrows + the worth-wearing nudge
-- (S58, Polestar-inspired; design record docs/POLESTAR-ANALYSIS.md). The arrow
-- is the tooltip verdict at a glance: an item in your bags that upgrades your
-- CURRENT GOAL (spec-aware via Impact.goalDimension - a Protection build marks
-- tank upgrades) gets a small arrow on its bag slot. Verdict source is the ONE
-- pipeline the hover uses (Tooltips._resolveItemStats/_equippedCompareStats ->
-- Impact.itemVerdict) so the arrow can never disagree with the tooltip.
--
-- LAWS (from the Polestar deep read, reshaped to our doctrine):
--   * Wearable-now: an item above your level NEVER gets the arrow (its tooltip
--     still shows the impact, with the "too high for you yet" line).
--   * Taint-clean: nothing is written into Blizzard's buttons - arrows live in
--     our own weak by-button map; hooks are hooksecurefunc only.
--   * Spec-change is a first-class invalidation: talent/equip/level events
--     clear the verdict cache, so a respec re-marks the bags.
--   * The nudge is ADVICE ONLY: when a NEW copy of an upgrade reaches your
--     bags, ONE chat line says so (per item, remembered in the account DB).
--     Items you already held at login never nudge; Foresight never equips.
--   * Display toggles: bagArrows / wearNudge (core/settings.lua), both on.
--
-- Coverage: the stock bags on BOTH flavors (Forever's Mainline container
-- frames via per-frame UpdateItems hooks - the mixin's functions are COPIED
-- onto each frame, so a mixin hook would miss; classic era via the old
-- ContainerFrame_Update). Bagnon/Baganator/ElvUI bag replacements are a
-- recorded follow-up - absent support degrades to no arrows, never an error.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Arrows = {}
HM.BagArrows = Arrows

-- ---- pure core (headless-tested) ----------------------------------------------

-- One judged answer for a bag item: upgrade (arrow-worthy: an upgrade for the
-- spec-aware goal AND wearable now), tooHigh, and the verdict's pct/label.
function Arrows.judge(loadout, mapped, compared, minLevel, playerLevel)
    local tooHigh = (tonumber(minLevel) or 0) > (tonumber(playerLevel) or 0)
    local okv, v = pcall(HM.Impact.itemVerdict, loadout, mapped, compared, "auto")
    local up = (okv and v and v.direction == "upgrade") or false
    return {
        upgrade = (up and not tooHigh) or false,
        tooHigh = tooHigh,
        pct = (okv and v and v.pct) or 0,
        label = okv and v and v.label or nil,
    }
end

-- The nudge's new-copy law: only itemIds whose COUNT ROSE since the last look
-- qualify (held-at-login and unchanged stacks never nudge).
function Arrows.newCopies(prev, cur)
    local fresh = {}
    for id, n in pairs(cur or {}) do
        if n > ((prev or {})[id] or 0) then fresh[id] = true end
    end
    return fresh
end

if not _G.CreateFrame then return Arrows end

-- ---- live state -----------------------------------------------------------------

local function say(msg)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Foresight|r: " .. msg)
    end
end

local verdictCache = {}      -- link -> bool (arrow?) until the next invalidation
local cachedLoadout = nil

local function invalidate()
    verdictCache = {}
    cachedLoadout = nil
end

local function liveLoadout()
    if cachedLoadout then return cachedLoadout end
    local snap = HM.Snapshot and HM.Snapshot.capture and HM.Snapshot.capture()
    cachedLoadout = (snap and HM.Loadout and HM.Loadout.fromSnapshot(snap)) or nil
    return cachedLoadout
end

local function judgeLink(link)
    local lo = liveLoadout()
    local T = HM.Tooltips
    if not (lo and T and T._resolveItemStats and T._equippedCompareStats) then return nil end
    local ok, res = pcall(function()
        local mapped = T.mapItemStats(T._resolveItemStats(link))
        if type(mapped) ~= "table" or not next(mapped) then return nil end
        local compared = T._equippedCompareStats(link)
        local gi = (HM.Client and HM.Client.getItemInfo) or _G.GetItemInfo
        local minLevel = gi and (select(5, gi(link)))
        return Arrows.judge(lo, mapped, compared, minLevel,
            lo.snapshot and lo.snapshot.level)
    end)
    return ok and res or nil
end

function Arrows.isUpgrade(link)
    if type(link) ~= "string" then return false end
    if HM.showSetting and not HM.showSetting("bagArrows") then return false end
    local hit = verdictCache[link]
    if hit ~= nil then return hit end
    local res = judgeLink(link)
    local up = (res and res.upgrade) or false
    verdictCache[link] = up
    return up
end

-- ---- the arrow texture (by-button, never IN the button) --------------------------

local arrows = setmetatable({}, { __mode = "k" })

local function arrowFor(btn)
    local t = arrows[btn]
    if not t then
        -- The client's own unused UpgradeIcon spot (top-left), OVERLAY sublevel 3:
        -- over the icon overlays, under the search overlay so a bag search dims it
        -- with the item (the Polestar layer discipline).
        t = btn:CreateTexture(nil, "OVERLAY", nil, 3)
        t:SetSize(13, 13)
        t:SetPoint("TOPLEFT", 2, -2)
        local okA = pcall(t.SetAtlas, t, "bags-greenarrow")
        if not (okA and t.GetAtlas and t:GetAtlas()) then
            t:SetTexture("Interface\\Buttons\\Arrow-Up-Up") -- classic-safe fallback
        end
        arrows[btn] = t
    end
    return t
end

local function mark(btn, show)
    if show then
        arrowFor(btn):Show()
    elseif arrows[btn] then
        arrows[btn]:Hide()
    end
end

-- ---- painting the two stock bag UIs -----------------------------------------------

local getNumSlots = (_G.C_Container and _G.C_Container.GetContainerNumSlots)
    or _G.GetContainerNumSlots
local getLink = (_G.C_Container and _G.C_Container.GetContainerItemLink)
    or _G.GetContainerItemLink

-- Forever / Mainline container frames: items enumerate on frame.Items.
local function paintMainline(frame)
    if not (frame and frame.Items) then return end
    for _, btn in ipairs(frame.Items) do
        local bag = btn.GetBagID and btn:GetBagID()
        local slot = btn.GetID and btn:GetID()
        local link = bag and slot and getLink and getLink(bag, slot)
        mark(btn, (link and Arrows.isUpgrade(link)) or false)
    end
end

local hookedFrames = {}
local function hookMainlineFrames()
    local holder = _G.ContainerFrameContainer
    local all = {}
    for _, f in ipairs((holder and holder.ContainerFrames) or {}) do all[#all + 1] = f end
    if _G.ContainerFrameCombinedBags then all[#all + 1] = _G.ContainerFrameCombinedBags end
    for _, f in ipairs(all) do
        -- Hook PER FRAME: the mixin's functions are copied onto each frame as it
        -- is made - a hook on the mixin itself would miss them (the deep-read trap).
        if not hookedFrames[f] and type(f.UpdateItems) == "function" then
            hookedFrames[f] = true
            _G.hooksecurefunc(f, "UpdateItems", function(frame) pcall(paintMainline, frame) end)
            if f:IsShown() then pcall(paintMainline, f) end
        end
    end
end

-- Classic era: the old global ContainerFrame_Update(frame) path.
local classicHooked
local function paintClassic(frame)
    local name = frame and frame.GetName and frame:GetName()
    if not name then return end
    local bag = frame:GetID()
    local size = (getNumSlots and getNumSlots(bag)) or 0
    for i = 1, size do
        local btn = _G[name .. "Item" .. i]
        if btn and btn.GetID then
            local link = getLink and getLink(bag, btn:GetID())
            mark(btn, (link and Arrows.isUpgrade(link)) or false)
        end
    end
end

local function hookClassic()
    if classicHooked or type(_G.ContainerFrame_Update) ~= "function" then return end
    classicHooked = true
    _G.hooksecurefunc("ContainerFrame_Update", function(frame) pcall(paintClassic, frame) end)
end

function Arrows.redraw()
    hookMainlineFrames()
    hookClassic()
    local holder = _G.ContainerFrameContainer
    for _, f in ipairs((holder and holder.ContainerFrames) or {}) do
        if f:IsShown() then pcall(paintMainline, f) end
    end
    if _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags:IsShown() then
        pcall(paintMainline, _G.ContainerFrameCombinedBags)
    end
    if classicHooked then
        for i = 1, 13 do
            local f = _G["ContainerFrame" .. i]
            if f and f:IsShown() then pcall(paintClassic, f) end
        end
    end
end

-- ---- the worth-wearing nudge (advice only) -----------------------------------------

local prevCounts   -- itemId -> count at the last look (nil until PLAYER_LOGIN seeds it)
local linkOf = {}  -- itemId -> a live link seen this scan (for the judged chat line)

local function bagCounts()
    local counts = {}
    if not (getNumSlots and getLink) then return counts end
    for bag = 0, 4 do
        for slot = 1, (getNumSlots(bag) or 0) do
            local link = getLink(bag, slot)
            local id = link and tonumber(link:match("item:(%d+)"))
            if id then
                counts[id] = (counts[id] or 0) + 1
                linkOf[id] = link
            end
        end
    end
    return counts
end

local function nudgeScan()
    local cur = bagCounts()
    if prevCounts == nil then
        -- First look (a bag event raced PLAYER_LOGIN): seed only - what you
        -- already hold never nudges (the held-at-login law).
        prevCounts = cur
        return
    end
    local fresh = Arrows.newCopies(prevCounts, cur)
    prevCounts = cur
    if not next(fresh) then return end
    if HM.showSetting and not HM.showSetting("wearNudge") then return end
    local db = HM.db
    if db and type(db.wearNoted) ~= "table" then db.wearNoted = {} end
    local noted = (db and db.wearNoted) or {}
    for id in pairs(fresh) do
        local link = linkOf[id]
        if link and not noted[id] then
            local res = judgeLink(link)
            if res and res.upgrade then
                noted[id] = true
                say(("worth wearing: %s beats what you have on (%+.1f%% %s) - it's in your bags (p)")
                    :format(link, res.pct, res.label or "for your goal"))
                break -- one nudge per scan, never a burst
            end
        end
    end
end

-- ---- events ------------------------------------------------------------------------

local pending
local function queue(fn)
    if pending then return end
    pending = true
    local function run() pending = nil; pcall(fn) end
    if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.25, run) else run() end
end

local f = _G.CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
                      "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
                      "CHARACTER_POINTS_CHANGED", "PLAYER_LEVEL_UP" }) do
    pcall(f.RegisterEvent, f, ev)
end
f:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        hookMainlineFrames()
        hookClassic()
        prevCounts = bagCounts() -- held-at-login items never nudge
        return
    end
    if event ~= "BAG_UPDATE_DELAYED" then
        invalidate() -- spec/gear/level changed: the verdicts are stale (Polestar law)
    end
    queue(function()
        Arrows.redraw()
        if event == "BAG_UPDATE_DELAYED" then nudgeScan() end
    end)
end)

return Arrows
