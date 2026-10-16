-- Interactive talent planner (S35 UI-talent-planner): renders the three class talent trees
-- from OUR generated data (HM.gen.talents) so it works at ANY level - including before 10,
-- when the Blizzard C_Traits frame is gated. Click to allocate a PLANNED build; the engine
-- (model/talentbuild.lua) enforces tier unlocks + prerequisites. Save/load named builds,
-- export/import compact strings, see each talent's impact.
--
-- ACCOUNT-SAFETY: display + advice ONLY. This NEVER spends points (no LearnTalent /
-- C_Traits.PurchaseRank / CommitConfig). You apply the plan yourself in-game. All visuals
-- live on OUR UIParent-layer frame - never a child of, nor a write onto, a Blizzard frame.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end
if not _G.CreateFrame then return end

local TT = {}
HM.TalentTree = TT

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local BTN = 36          -- talent button size
local COL_GAP, ROW_GAP = 12, 10
local TREE_W = 4 * BTN + 3 * COL_GAP + 24   -- 4 columns + padding
local PAD = 14

local frame, treeHost
local state = { class = nil, build = {}, name = nil, planLevel = nil, legacy = false }
local trees = {}        -- [i] = { box, header, buttons = { [talentId] = button }, lines = {} }
local chips = {}        -- saved-build chip buttons

-- ---- data + persistence ----------------------------------------------------------------
local function TB() return HM.TalentBuild end

-- The planner's talent definitions: Forever trait nodes (keyed by nodeID) when present, else
-- the classic table. `forever()` = those keys are trait nodeIDs (so impact folds via the node).
local function talentDefs()
    local tb = TB()
    return (tb and tb.talents and tb.talents()) or (HM.gen and HM.gen.talents) or {}
end
local function forever() return HM.gen and HM.gen.foreverTalents ~= nil end
-- Fold one planned talent's impact onto a loadout: Forever talents ARE trait nodes (ops fold
-- via withTraitNode(nodeID)); classic talents fold via withTalent(talentId). nil-safe caller.
local function foldTalent(lo, id, rank)
    if forever() and lo.withTraitNode then return lo:withTraitNode(id, rank) end
    return lo:withTalent(id, rank)
end

local function planDb()
    local db = HM.charDb and HM.charDb()
    if not db then return { builds = {} } end
    db.settings = db.settings or {}
    local p = db.settings.planner
    if type(p) ~= "table" then p = { builds = {} }; db.settings.planner = p end
    if type(p.builds) ~= "table" then p.builds = {} end
    return p
end

local function classColor(token)
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 0.78, 0.64, 0.30
end

local function spellIcon(spellId)
    if not spellId then return QUESTION end
    local tex
    if _G.C_Spell and _G.C_Spell.GetSpellTexture then
        local ok, t = pcall(_G.C_Spell.GetSpellTexture, spellId); if ok then tex = t end
    end
    if not tex and _G.GetSpellTexture then
        local ok, t = pcall(_G.GetSpellTexture, spellId); if ok then tex = t end
    end
    return tex or QUESTION
end

local function playerClass()
    local _, token = _G.UnitClass("player")
    return token
end

-- The level you're PLANNING toward: you get the points you'd have at this level, to pretend-
-- allocate a future build (display-only). Defaults to 30 for the beta - or your own level if
-- higher - so even a low-level beta character has points to play with. Clamped to the cap.
local function planLevel()
    if not state.planLevel then
        local lv = (_G.UnitLevel and _G.UnitLevel("player")) or 0
        local maxL = (TB() and TB().MAX_LEVEL) or 60
        state.planLevel = math.min(maxL, math.max(lv, 30))
    end
    return state.planLevel
end

-- Best-effort live impact for a talent at a rank (nil-degrades; never errors into the UI).
local function impactLine(talentId, rank)
    if not (HM.Snapshot and HM.Loadout and HM.Impact and HM.Impact.evaluate) then return nil end
    local ok, snap = pcall(HM.Snapshot.capture)
    if not ok or type(snap) ~= "table" then return nil end
    local base = HM.Loadout.fromSnapshot(snap)
    if not base or not base.withTalent then return nil end
    local okd, before = pcall(HM.Impact.evaluate, base)
    local after = foldTalent(base, talentId, rank)
    local oka, aft = pcall(HM.Impact.evaluate, after)
    if not (okd and oka and type(before) == "table" and type(aft) == "table") then return nil end
    -- surface the single biggest moved lens
    local best
    for id, r in pairs(aft) do
        local b = before[id]
        if type(r) == "table" and type(b) == "table" and type(r.score) == "number" and type(b.score) == "number" then
            local d = r.score - b.score
            if math.abs(d) > 0.05 and (not best or math.abs(d) > math.abs(best.d)) then
                best = { id = id, d = d, label = r.label or id }
            end
        end
    end
    if not best then return nil end
    return ("%s %+.1f"):format(best.label, best.d)
end

-- Whole-build impact: fold EVERY planned talent onto your live loadout and diff the outcome
-- lenses - "what does this build do for you". Only for your OWN class (folding another class's
-- talents onto your character is meaningless). nil-degrades; never errors into the UI.
local function buildSummaryText()
    if state.class ~= playerClass() then return nil end
    if not next(state.build) then return nil end
    if not (HM.Snapshot and HM.Loadout and HM.Impact and HM.Impact.evaluate) then return nil end
    local ok, snap = pcall(HM.Snapshot.capture)
    if not ok or type(snap) ~= "table" then return nil end
    local base = HM.Loadout.fromSnapshot(snap)
    if not (base and base.withTalent) then return nil end
    local planned = base
    for tid, rank in pairs(state.build) do planned = foldTalent(planned, tid, rank) end
    local okb, before = pcall(HM.Impact.evaluate, base)
    local okp, after = pcall(HM.Impact.evaluate, planned)
    if not (okb and okp and type(before) == "table" and type(after) == "table") then return nil end
    local changes = {}
    for id, r in pairs(after) do
        local b = before[id]
        if type(r) == "table" and type(b) == "table" and type(r.score) == "number" and type(b.score) == "number" then
            local d = r.score - b.score
            if math.abs(d) >= 0.05 then changes[#changes + 1] = { label = r.label or id, d = d } end
        end
    end
    if #changes == 0 then return nil end
    table.sort(changes, function(a, b) return math.abs(a.d) > math.abs(b.d) end)
    local parts = {}
    for i = 1, math.min(5, #changes) do
        local col = changes[i].d >= 0 and "|cff6fcf7a" or "|cffe0704a"
        parts[#parts + 1] = ("%s %s%+.1f|r"):format(changes[i].label, col, changes[i].d)
    end
    return "This build: " .. table.concat(parts, "  ·  ")
end

-- ---- tooltip ---------------------------------------------------------------------------
-- The LIVE game-rendered talent description (same client data the Armory / the Forever talent
-- site show) for a node's spell. Read-only, pcall-guarded, degrades to nil if not yet cached.
local function talentDescription(spellId)
    if not spellId then return nil end
    if _G.C_Spell and _G.C_Spell.GetSpellDescription then
        local ok, d = pcall(_G.C_Spell.GetSpellDescription, spellId)
        if ok and type(d) == "string" and d ~= "" then return d end
    end
    if _G.GetSpellDescription then
        local ok, d = pcall(_G.GetSpellDescription, spellId)
        if ok and type(d) == "string" and d ~= "" then return d end
    end
    return nil
end

local function fmtVal(v, isPct)
    local r = math.floor(v + 0.5)
    local s = (math.abs(v - r) < 0.05) and tostring(r) or ("%.1f"):format(v)
    return isPct and (s .. "%") or s
end

-- OUR per-rank progression from the primary op (e.g. Mental Dexterity "33 / 66 / 100%"), via
-- the shared rank-rule resolver (datamined values > overrides/verified rule > presumed linear).
-- This is the FALLBACK shown when the client-authoritative description isn't available; the live
-- game description (which knows each talent's exact scaling) stands on top of it when the tree is
-- open. 2nd return = true when the scaling is presumed (so the caller tags it as our estimate).
local function perRankLine(t)
    local ops = type(t.ops) == "table" and t.ops or nil
    if not ops then return nil end
    local op
    for _, o in ipairs(ops) do
        if type(o) == "table" and type(o.maxValue) == "number" and o.maxValue ~= 0 then op = o; break end
    end
    local maxR = t.maxRank or 1
    if not op or maxR <= 1 then return nil end
    local F = HM.formulas
    local parts = {}
    for r = 1, maxR do
        local v = (F and F.talentRankValueFor)
            and F.talentRankValueFor(nil, op.maxValue, r, maxR, op.values)
            or (op.maxValue * r / maxR)
        parts[#parts + 1] = fmtVal(v, op.isPct)
    end
    return "Per rank: " .. table.concat(parts, " / "), type(op.values) ~= "table"
end

local function showTip(button, talentId)
    local t = talentDefs()[talentId]
    if not t then return end
    local cur = tonumber(state.build[talentId]) or 0
    local maxR = t.maxRank or 1
    local gt = _G.GameTooltip
    gt:SetOwner(button, "ANCHOR_RIGHT")
    gt:AddLine(t.name or ("Talent " .. talentId), 1, 0.82, 0.25)
    gt:AddLine(("Rank %d/%d"):format(cur, maxR), 0.7, 0.7, 0.7)
    -- Full description (live, matches the Forever talent site), then the per-rank numbers.
    local desc = talentDescription(t.spellRanks and t.spellRanks[1])
    if desc then gt:AddLine(desc, 1, 1, 1, true) end
    -- Our per-rank math from the baseline (shown always; the client description above is the
    -- authoritative actual when present, our line is the assumed progression - tagged (p)).
    local rankLine, presumed = perRankLine(t)
    if rankLine then
        gt:AddLine(rankLine .. (presumed and "  |cff9d9d9d(p)|r" or ""), 0.55, 0.8, 1, true)
    end
    local locked = TB() and TB().lockReason(state.build, talentId)
    if locked then gt:AddLine(locked, 1, 0.3, 0.3) end
    local imp = impactLine(talentId, math.min(maxR, cur + 1))
    if imp then gt:AddLine("Next point: " .. imp, 0.3, 1, 0.6) end
    gt:AddLine(" ")
    gt:AddLine("Left-click +  ·  Right-click -  (plan only; apply in-game yourself)", 0.5, 0.5, 0.55)
    gt:Show()
end

-- ---- render ----------------------------------------------------------------------------
local function refreshHeader()
    if not frame then return end
    local TBe = TB()
    local total = TBe and TBe.totalPoints(state.build) or 0
    local lvl = planLevel()
    local budget = TBe and TBe.budget(lvl, state.legacy) or 0
    frame.title:SetText(("Talent Planner  -  %s"):format(state.class or "?"))
    frame.points:SetText(("%d / %d points  ·  planning level %d%s"):format(
        total, budget, lvl, state.legacy and "  ·  legacy talent" or ""))
    local over = total > budget
    frame.points:SetTextColor(over and 1 or 0.8, over and 0.4 or 0.75, over and 0.4 or 0.6)
    if frame.summary then frame.summary:SetText(buildSummaryText() or "") end
    if frame.planControls then frame.planControls.refresh() end
end

local function paintButton(btn, talentId)
    local g = HM.gen or {}
    local t = talentDefs()[talentId]
    if not t then return end
    local cur = tonumber(state.build[talentId]) or 0
    local maxed = cur >= (t.maxRank or 1)
    local locked = (cur == 0) and (TB() ~= nil) and (TB().lockReason(state.build, talentId) ~= nil) or false
    btn.rank:SetText(("%d/%d"):format(cur, t.maxRank or 1))
    if maxed then btn.rank:SetTextColor(0.3, 1, 0.3)
    elseif cur > 0 then btn.rank:SetTextColor(1, 0.82, 0.25)
    else btn.rank:SetTextColor(0.7, 0.7, 0.7) end
    btn.icon:SetDesaturated(locked)
    btn.icon:SetAlpha(locked and 0.45 or 1)
    btn.border:SetShown(cur > 0)
    btn.border:SetVertexColor(maxed and 0.3 or 1, maxed and 1 or 0.82, maxed and 0.3 or 0.25)
end

local function updateButtons()
    for _, tree in ipairs(trees) do
        for tid, btn in pairs(tree.buttons) do paintButton(btn, tid) end
        local pts = TB() and TB().pointsInTab(state.build, tree.tabId) or 0
        tree.header:SetText(("%s  (%d)"):format(tree.name or "", pts))
    end
    refreshHeader()
    TT.refreshGlow()
end

local function onClick(btn, mouse)
    local TBe = TB()
    if not TBe then return end
    if mouse == "RightButton" then
        state.build = (TBe.remove(state.build, btn.talentId))
    else
        -- Plan budget: only the points you'd have at the planning level (+legacy) are spendable.
        if TBe.totalPoints(state.build) >= TBe.budget(planLevel(), state.legacy) then
            if HM.print then
                HM.print(("no points left at level %d%s - raise the planning level%s"):format(
                    planLevel(), state.legacy and " (legacy)" or "",
                    state.legacy and "" or " or toggle the legacy talent"))
            end
        else
            state.build = (TBe.add(state.build, btn.talentId))
        end
    end
    updateButtons()
    if _G.GameTooltip:IsOwned(btn) then showTip(btn, btn.talentId) end
end

local function makeButton(parent, talentId)
    local t = talentDefs()[talentId]
    local btn = _G.CreateFrame("Button", nil, parent)
    btn.talentId = talentId
    btn:SetSize(BTN, BTN)
    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetAllPoints()
    btn.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon:SetTexture(spellIcon(t.spellRanks and t.spellRanks[1]))
    btn.border = btn:CreateTexture(nil, "OVERLAY")
    btn.border:SetPoint("TOPLEFT", -2, 2)
    btn.border:SetPoint("BOTTOMRIGHT", 2, -2)
    btn.border:SetColorTexture(1, 0.82, 0.25, 0)
    btn.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    btn.border:SetBlendMode("ADD")
    btn.border:Hide()
    btn.rank = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    btn.rank:SetPoint("BOTTOMRIGHT", 2, -1)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", onClick)
    btn:SetScript("OnEnter", function(self) showTip(self, self.talentId) end)
    btn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    return btn
end

local function buildTrees(classToken)
    -- clear old tree boxes
    for _, tree in ipairs(trees) do if tree.box then tree.box:Hide() end end
    trees = {}
    local TBe = TB()
    local classId = TBe and TBe.classIdFor(classToken)
    if not classId then return end
    local tabs = TBe.tabsForClass(classId)
    local g = HM.gen
    for i, tabId in ipairs(tabs) do
        local box = _G.CreateFrame("Frame", nil, treeHost)
        box:SetSize(TREE_W, 10)
        box:SetPoint("TOPLEFT", treeHost, "TOPLEFT", (i - 1) * (TREE_W + 10), 0)
        local header = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        header:SetPoint("TOP", box, "TOP", 0, -2)
        local tab = g.talentTabs and g.talentTabs[tabId]
        local tree = { tabId = tabId, box = box, header = header, name = tab and tab.name or "?", buttons = {} }
        local maxTier = 0
        for _, tid in ipairs(TBe.talentsInTab(tabId)) do
            local t = talentDefs()[tid]
            local btn = makeButton(box, tid)
            btn:SetPoint("TOPLEFT", box, "TOPLEFT",
                12 + (t.column or 0) * (BTN + COL_GAP),
                -24 - (t.tier or 0) * (BTN + ROW_GAP))
            tree.buttons[tid] = btn
            if (t.tier or 0) > maxTier then maxTier = t.tier or 0 end
        end
        box:SetHeight(24 + (maxTier + 1) * (BTN + ROW_GAP) + 8)
        trees[i] = tree
    end
end

-- ---- saved-build chips -----------------------------------------------------------------
local function loadBuild(str, classToken)
    -- A stored COPIED SNAPSHOT is a raw node plan (nodeID -> ranks) table, not a code string.
    -- SavedVariables are user-editable, so re-validate to integers (untrusted-input law).
    if type(str) == "table" then
        local clean = {}
        for k, v in pairs(str) do
            local nid, rank = tonumber(k), tonumber(v)
            if nid and rank and rank > 0 then clean[nid] = rank end
        end
        if not next(clean) then return false end
        if HM.SynergyHighlight and HM.SynergyHighlight.setPlanPreview then
            HM.SynergyHighlight.setPlanPreview(clean)
        end
        state.build = TB().fromNodePlan(clean)
        -- A node-plan snapshot carries no class token; copied builds are same-class, so a grid
        -- load after a reload falls back to the player's class (never buildTrees(nil)).
        if not state.class then state.class = playerClass() end
        return true
    end
    -- FT1 = our classic build code
    local b, cls = TB().decode(str)
    if b then state.build = b; if cls then state.class = cls end; return true end
    -- FT2 = ForeverTalents' node code (interop): set the FULL node plan on the live overlay
    -- (incl. Forever-new nodes), and reflect the classic-overlap subset in the grid.
    if HM.FT2 and HM.FT2.decode and HM.SynergyHighlight and HM.SynergyHighlight.setPlanPreview then
        local dec = HM.FT2.decode(str)
        if dec then
            local nodePlan = HM.FT2.nodeRanks(dec)
            HM.SynergyHighlight.setPlanPreview(nodePlan)
            state.build = TB().fromNodePlan(nodePlan)
            return true
        end
    end
    return false
end

local function refreshChips()
    for _, c in ipairs(chips) do c:Hide() end
    chips = {}
    local p = planDb()
    local names = {}
    for name in pairs(p.builds) do names[#names + 1] = name end
    table.sort(names)
    local x = 0
    for _, name in ipairs(names) do
        local chip = _G.CreateFrame("Button", nil, frame.chipRow)
        chip:SetSize(100, 20)
        chip:SetPoint("LEFT", frame.chipRow, "LEFT", x, 0)
        local bg = chip:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.3)
        local fs = chip:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
        fs:SetPoint("LEFT", 5, 0); fs:SetText(name); fs:SetWidth(78); fs:SetJustifyH("LEFT")
        chip:SetScript("OnClick", function(_, mouse)
            if mouse == "RightButton" then
                p.builds[name] = nil; refreshChips()
            else
                if loadBuild(p.builds[name]) then state.name = name; buildTrees(state.class); updateButtons() end
            end
        end)
        chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        chip:SetScript("OnEnter", function(self)
            _G.GameTooltip:SetOwner(self, "ANCHOR_TOP")
            _G.GameTooltip:AddLine(name); _G.GameTooltip:AddLine("Left-click load  ·  Right-click delete", 0.6, 0.6, 0.6); _G.GameTooltip:Show()
        end)
        chip:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
        chips[#chips + 1] = chip
        x = x + 106
    end
end

-- ---- live overlay on the real tree: map the classic plan -> C_Traits node plan and hand
-- it to SynergyHighlight, which glows the planned path on the live tree (blue remaining /
-- gold done) and live-deltas it as you spend. Display-only; the frame may be closed (no-op).
function TT.refreshGlow()
    if not (HM.SynergyHighlight and HM.SynergyHighlight.mergeGridPlan and HM.TalentBuild) then return end
    -- merge (not replace) so Forever-new nodes from copy-inspect / FT2 import survive a grid edit
    pcall(HM.SynergyHighlight.mergeGridPlan, HM.TalentBuild.toNodePlan(state.build))
end

-- ---- frame -----------------------------------------------------------------------------
local function makeButtonBar()
    local bar = _G.CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", PAD, -70)
    bar:SetSize(10, 24)
    local function tbtn(label, x, onClick)
        local b = _G.CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(72, 22); b:SetPoint("LEFT", x, 0); b:SetText(label)
        b:SetScript("OnClick", onClick)
        return b
    end
    tbtn("Reset", 0, function()
        state.build = {}; state.name = nil
        -- Also drop any copied/edited overlay highlights (the inspect ghost, an imported code).
        if HM.SynergyHighlight and HM.SynergyHighlight.setPlanPreview then
            HM.SynergyHighlight.setPlanPreview(nil)
        end
        updateButtons()
    end)
    tbtn("Export", 76, function()
        local s = TB().encode(state.class, state.build)
        if s and HM.showExport then HM.showExport(s) end
    end)
    tbtn("Import", 154, function()
        if frame.importBox then frame.importBox:Show(); frame.importBox:SetFocus() end
    end)
    -- Save: name box + Save button
    local box = _G.CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    box:SetSize(120, 20); box:SetPoint("LEFT", 236, 0); box:SetAutoFocus(false)
    box:SetMaxLetters(32)
    frame.nameBox = box
    tbtn("Save", 362, function()
        local name = (box:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if name == "" then name = (state.class or "Unnamed") .. " build" end
        local s = TB().encode(state.class, state.build)
        if s then planDb().builds[name] = s; state.name = name; box:SetText(""); refreshChips() end
    end)
    -- Copy an inspected same-class player's tree -> a saved, deletable snapshot you can follow.
    tbtn("Copy", 440, function()
        local SH = HM.SynergyHighlight
        local plan, err, who = SH and SH.copyInspectedPlan and SH.copyInspectedPlan()
        if plan then
            TT.importPlan(plan, "Copy: " .. (who or "inspected"))
        elseif HM.print then
            HM.print("copy failed: " .. tostring(err or "inspect a same-class player with talents open"))
        end
    end)
    -- Load YOUR current allocation so you can plan by removing / reallocating (display-only).
    tbtn("Current", 518, function()
        local ok, err = TT.loadCurrent()
        if HM.print then
            HM.print(ok and "loaded your current build - remove or move points to plan (nothing is unlearned)"
                or tostring(err or "couldn't read your current build - open your talents"))
        end
    end)
end

local function makeImportBox()
    local box = _G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    box:SetSize(360, 22)
    box:SetPoint("TOP", frame, "TOP", 0, -44)
    box:SetAutoFocus(false)
    box:SetMaxLetters(256)
    box:Hide()
    box:SetScript("OnEnterPressed", function(self)
        local str = self:GetText()
        if loadBuild(str) then buildTrees(state.class); updateButtons() end
        self:SetText(""); self:Hide()
    end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(""); self:Hide() end)
    frame.importBox = box
end

local function ensureFrame()
    if frame then return end
    frame = _G.CreateFrame("Frame", "ForesightTalentPlanner", _G.UIParent,
        _G.BackdropTemplateMixin and "BackdropTemplate")
    frame:SetSize(3 * (TREE_W + 10) + 2 * PAD, 520)
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 30)
    frame:SetFrameStrata("HIGH")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        planDb().pos = { point = point, relPoint = rel, x = x, y = y }
    end)
    if frame.SetBackdrop then
        frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        frame:SetBackdropColor(0.04, 0.03, 0.02, 0.92)
        frame:SetBackdropBorderColor(0.78, 0.64, 0.30, 0.8)
    end

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", PAD, -PAD)
    frame.points = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.points:SetPoint("TOPLEFT", PAD, -36)
    frame.points:SetTextColor(0.8, 0.75, 0.6)

    -- Whole-build impact readout ("This build: Spellcasting +4.2 ...") - the talent-impact payoff.
    frame.summary = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    frame.summary:SetPoint("TOPLEFT", PAD, -52)
    frame.summary:SetWidth(3 * (TREE_W + 10))
    frame.summary:SetJustifyH("LEFT")

    local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    hint:SetPoint("TOPRIGHT", -30, -16)
    hint:SetText("Plan only - apply the points yourself in-game")

    -- Plan-for-a-future-level controls: pick the level you're planning toward (you get the
    -- points you'd have then) and toggle the legacy talent (+5 points). Display-only.
    local pc = _G.CreateFrame("Frame", nil, frame)
    pc:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -34)
    pc:SetSize(250, 22)
    local function pcBtn(label, x, w, onclick)
        local b = _G.CreateFrame("Button", nil, pc, "UIPanelButtonTemplate")
        b:SetSize(w, 20); b:SetPoint("LEFT", x, 0); b:SetText(label)
        b:SetScript("OnClick", onclick)
        return b
    end
    pcBtn("Lv -", 0, 34, function()
        state.planLevel = math.max(1, planLevel() - 1); updateButtons()
    end)
    pc.lvl = pc:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    pc.lvl:SetPoint("LEFT", 38, 0); pc.lvl:SetWidth(44); pc.lvl:SetJustifyH("CENTER")
    pcBtn("Lv +", 86, 34, function()
        local maxL = (TB() and TB().MAX_LEVEL) or 60
        state.planLevel = math.min(maxL, planLevel() + 1); updateButtons()
    end)
    pc.legacy = pcBtn("Legacy: off", 126, 118, function()
        state.legacy = not state.legacy; updateButtons()
    end)
    pc.legacy:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        _G.GameTooltip:SetText("Legacy talent", 0.2, 1, 0.6)
        _G.GameTooltip:AddLine("Forever's legacy-talent slot grants +5 points (tree unlocks at 5 instead of 10).",
            0.8, 0.8, 0.8, true)
        _G.GameTooltip:Show()
    end)
    pc.legacy:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    pc.refresh = function()
        pc.lvl:SetText(("Lv %d"):format(planLevel()))
        pc.legacy:SetText(state.legacy and "Legacy: ON" or "Legacy: off")
    end
    frame.planControls = pc

    frame.chipRow = _G.CreateFrame("Frame", nil, frame)
    frame.chipRow:SetPoint("BOTTOMLEFT", PAD, 10)
    frame.chipRow:SetSize(10, 22)

    treeHost = _G.CreateFrame("Frame", nil, frame)
    treeHost:SetPoint("TOPLEFT", PAD, -102)
    treeHost:SetSize(3 * (TREE_W + 10), 380)

    makeButtonBar()
    makeImportBox()

    -- restore position
    local pos = planDb().pos
    if type(pos) == "table" and pos.point then
        frame:ClearAllPoints()
        frame:SetPoint(pos.point, _G.UIParent, pos.relPoint or pos.point, pos.x or 0, pos.y or 0)
    end
    frame:Hide()
end

-- ---- public ----------------------------------------------------------------------------
-- Import a NODE plan (copy-from-inspect, or a public code we hand out) as a SAVED, deletable
-- snapshot: store it, set the live overlay, reflect the classic subset in the grid, and open
-- the planner. The snapshot shows as a chip (left-click load, right-click delete).
function TT.importPlan(plan, label)
    if type(plan) ~= "table" or not next(plan) then return false end
    ensureFrame()
    if not state.class then state.class = playerClass() end
    local name = tostring(label or "Copied build"):sub(1, 32)
    planDb().builds[name] = plan        -- stored as a table; loadBuild re-validates it
    loadBuild(plan)
    state.name = name
    buildTrees(state.class)
    refreshChips()
    updateButtons()
    frame:Show()
    return true
end

-- Seed the planner from the player's CURRENT allocation so they can plan by removing /
-- reallocating from where they are (display-only - never unlearns). Returns ok, err.
function TT.loadCurrent()
    local SH = HM.SynergyHighlight
    local plan, err = SH and SH.copyMyPlan and SH.copyMyPlan()
    if not plan then return false, err end
    ensureFrame()
    if not state.class then state.class = playerClass() end
    loadBuild(plan)
    state.name = "My current build"
    buildTrees(state.class)
    updateButtons()
    frame:Show()
    return true
end

function TT.show(classToken)
    ensureFrame()
    local cls = classToken or state.class or playerClass()
    if cls and cls ~= state.class then
        state.class = cls
        state.build = {}
        state.name = nil
    end
    if #trees == 0 or (classToken and classToken ~= trees.builtFor) then
        buildTrees(state.class); trees.builtFor = state.class
    end
    refreshChips()
    updateButtons()
    frame:Show()
end

function TT.toggle(classToken)
    ensureFrame()
    if frame:IsShown() and not classToken then frame:Hide() else TT.show(classToken) end
end

return TT
