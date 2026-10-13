-- Foresight Matrix panel renderer (S7b): the "class ecology" dashboard from
-- mockups/foresight-matrix-2026-10-12.html - standing badge, honest dimension bars,
-- and the Enabler -> Engine -> Payoff ecosystem for the class's loops.
-- Skin: dark translucent card in the house style (code-drawn textures, no art
-- assets, blends with default + reskin UIs). All numbers come from
-- PanelModel.matrixModel - zero computation here, layout only. In-game only.
-- USER-MODIFIABLE (baseline): background opacity via /foresight matrix opacity <v>
-- (validated by PanelModel.normalizeOpacity), position via drag (validated save).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

if not _G.CreateFrame then return end

local WIDTH = 320
local PAD = 12

-- Mockup palette (the brand emerald is the addon's chat color).
local BRAND = { r = 0.20, g = 1.00, b = 0.60 }  -- #33FF99
local BLUE  = { r = 0.30, g = 0.65, b = 1.00 }  -- enablers
local YELLOW = { r = 1.00, g = 0.82, b = 0.40 } -- engines
local MUTED = { r = 0.55, g = 0.55, b = 0.60 }

local panel
local fsPool, texPool = {}, {}

local function classColor()
    local _, token = _G.UnitClass("player")
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function uiState()
    local db = HM.charDb()
    db.settings.matrix = db.settings.matrix or {}
    return db.settings.matrix
end

local function opacity()
    return HM.PanelModel.normalizeOpacity(uiState().opacity)
end

local function restorePosition()
    if not panel then return end
    panel:ClearAllPoints()
    local pos = HM.PanelModel.normalizePanelPos(uiState().pos)
    if pos then
        panel:SetPoint(pos.point, _G.UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("CENTER", _G.UIParent, "CENTER", 220, 40)
    end
end

-- Font-string + texture pools: the panel rebuilds on every refresh/cycle.
local function acquireFS(layer, template)
    for _, f in ipairs(fsPool) do
        if not f.inUse then
            f.inUse = true
            f:SetFontObject(template or "GameFontHighlightSmall")
            f:SetJustifyH("LEFT")
            f:SetJustifyV("TOP")
            f:ClearAllPoints()
            f:SetText("")
            f:Show()
            return f
        end
    end
    local f = panel:CreateFontString(nil, layer or "ARTWORK",
        template or "GameFontHighlightSmall")
    f.inUse = true
    fsPool[#fsPool + 1] = f
    return f
end

local function acquireTex(layer, sublayer)
    for _, t in ipairs(texPool) do
        if not t.inUse then
            t.inUse = true
            t:ClearAllPoints()
            t:Show()
            return t
        end
    end
    local t = panel:CreateTexture(nil, layer or "ARTWORK", nil, sublayer or 0)
    t.inUse = true
    texPool[#texPool + 1] = t
    return t
end

local function releasePools()
    for _, f in ipairs(fsPool) do f.inUse = false; f:Hide() end
    for _, t in ipairs(texPool) do t.inUse = false; t:Hide() end
end

local TAG_COLOR = { Enabler = BLUE, Engine = YELLOW, Payoff = BRAND }

local function layout(model)
    releasePools()
    local r, g, b = classColor()
    local innerW = WIDTH - PAD * 2
    local y = -30 -- below the title bar

    -- Character header: name, descriptor, standing badge (mockup component 1).
    local name = acquireFS("ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOP", panel, "TOP", 0, y)
    name:SetJustifyH("CENTER")
    name:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255,
        (_G.UnitName and _G.UnitName("player")) or model.header.name or "?"))
    y = y - 20
    local desc = acquireFS("ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOP", panel, "TOP", 0, y)
    desc:SetJustifyH("CENTER")
    desc:SetText(("Level %s %s %s"):format(model.header.level or "?",
        model.header.raceToken or "", model.header.classToken or ""))
    y = y - 18

    local standing = model.header.standing or {}
    if standing.name then
    local badge = acquireFS("ARTWORK", "GameFontNormalSmall")
    badge:SetPoint("TOP", panel, "TOP", 0, y - 3)
    badge:SetJustifyH("CENTER")
    badge:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255,
        (standing.name or "?"):upper()))
    local bw = badge:GetStringWidth() + 24
    local badgeBg = acquireTex("BACKGROUND", 2)
    badgeBg:SetPoint("TOP", panel, "TOP", 0, y)
    badgeBg:SetSize(bw, 18)
    badgeBg:SetColorTexture(r, g, b, 0.12)
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local line = acquireTex("BORDER")
        line:SetPoint(edge, badgeBg, edge)
        line:SetSize(bw, 1)
        line:SetColorTexture(r, g, b, 0.7)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = acquireTex("BORDER")
        line:SetPoint(side, badgeBg, side)
        line:SetSize(1, 18)
        line:SetColorTexture(r, g, b, 0.7)
    end
    panel.badgeTip = standing.detail
    end
    y = y - 28

    -- Dimension bars (honest relative fill; basis printed under the block).
    for _, bar in ipairs(model.bars.rows) do
        local label = acquireFS("ARTWORK", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        label:SetText(bar.label)
        local value = acquireFS("ARTWORK", "GameFontHighlightSmall")
        value:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
        value:SetJustifyH("RIGHT")
        local vc = bar.top and BRAND or MUTED
        value:SetText(("|cff%02x%02x%02x%s|r"):format(vc.r * 255, vc.g * 255,
            vc.b * 255, bar.value))
        y = y - 14
        local track = acquireTex("BACKGROUND", 1)
        track:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        track:SetSize(innerW, 5)
        track:SetColorTexture(0, 0, 0, 0.55)
        local fillW = math.max(1, math.floor(innerW * math.min(bar.fill, 1)))
        local fill = acquireTex("BACKGROUND", 2)
        fill:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        fill:SetSize(fillW, 5)
        local fc = bar.top and BRAND or MUTED
        fill:SetColorTexture(fc.r, fc.g, fc.b, bar.top and 0.95 or 0.55)
        y = y - 12
    end
    local basis = acquireFS("ARTWORK", "GameFontDisableSmall")
    basis:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
    basis:SetWidth(innerW)
    basis:SetText(model.bars.basis)
    y = y - math.max(12, basis:GetStringHeight() + 2) - 8

    -- Goal pathways: your best unspent talent points for the dimension you're
    -- building toward (computed on talent changes, not every refresh).
    if model.path then
        local ph = acquireFS("ARTWORK", "GameFontNormalSmall")
        ph:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        ph:SetWidth(innerW)
        ph:SetText(("|cff9d9d9dBest next points -|r %s"):format(model.path.label or ""))
        y = y - math.max(14, ph:GetStringHeight() + 2)
        for i, row in ipairs(model.path.rows) do
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, y)
            f:SetWidth(innerW - 12)
            f:SetText(("%d. %s  |cff4ade80%+.1f%s|r"):format(i, row.label,
                row.pct, row.unit or "%"))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        y = y - 8
    end

    -- Skill focus (S22a/S22b): the three modifier classes for the focused ability +
    -- the cascade chip row. Wrapped FontStrings WRAP to extra rows at low
    -- resolution/scale (the mobile binding) - never truncate.
    if model.focus then
        local CLASS_HEX = { gold = "ffd24d", blue = "59a6ff" }
        local fh = acquireFS("ARTWORK", "GameFontNormalSmall")
        fh:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        fh:SetWidth(innerW)
        fh:SetText(("|cff9d9d9dFocused skill -|r |cffffd24d%s|r  |cff9d9d9d(/foresight focus clear)|r")
            :format(model.focus.spell or ""))
        y = y - math.max(14, fh:GetStringHeight() + 2)
        for _, cl in ipairs(model.focus.classes or {}) do
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, y)
            f:SetWidth(innerW - 12)
            f:SetText(("|cff%s%s:|r %s"):format(CLASS_HEX[cl.color] or "9d9d9d",
                cl.tag, cl.text))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        if model.focus.pathway then
            local chips = {}
            for _, seg in ipairs(model.focus.pathway.segments or {}) do
                chips[#chips + 1] = ("|cff33ff99[|r%s|cff33ff99]|r"):format(seg)
            end
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, y)
            f:SetWidth(innerW - 12)
            f:SetText(table.concat(chips, " -> ")
                .. (model.focus.pathway.presumed and " (p)" or ""))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        y = y - 8
    end

    -- Ecosystem map (mockup component 2): goal row + the three tagged cards.
    if model.eco then
        local goal = acquireFS("ARTWORK", "GameFontNormalSmall")
        goal:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        goal:SetWidth(innerW)
        goal:SetText(("|cff9d9d9dGoal:|r %s%s"):format(model.eco.name,
            (model.loopCount or 0) > 1 and "  |cff9d9d9d(click title to cycle)|r" or ""))
        y = y - math.max(14, goal:GetStringHeight() + 2) - 6

        for _, node in ipairs(model.eco.nodes) do
            local c = TAG_COLOR[node.tag] or MUTED
            local cardTop = y
            local tag = acquireFS("ARTWORK", "GameFontDisableSmall")
            tag:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 8, y - 4)
            tag:SetText(("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255,
                c.b * 255, node.tag:upper()))
            y = y - 16
            local title = acquireFS("ARTWORK", "GameFontNormalSmall")
            title:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 8, y - 4)
            title:SetWidth(innerW - 16)
            title:SetText("|cffffffff" .. (node.title or "") .. "|r")
            y = y - math.max(13, title:GetStringHeight() + 1)
            local d = acquireFS("ARTWORK", "GameFontDisableSmall")
            d:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 8, y - 4)
            d:SetWidth(innerW - 16)
            d:SetText(node.desc or "")
            y = y - math.max(12, d:GetStringHeight() + 1) - 8
            local cardH = cardTop - y - 2
            local cardBg = acquireTex("BACKGROUND", 1)
            cardBg:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cardTop)
            cardBg:SetSize(innerW, cardH)
            cardBg:SetColorTexture(1, 1, 1, 0.04)
            local strip = acquireTex("BACKGROUND", 2)
            strip:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, cardTop)
            strip:SetSize(3, cardH)
            strip:SetColorTexture(c.r, c.g, c.b, 0.9)
            y = y - 6
        end

        -- Actionable insight box: the loop's why + its live computed numbers.
        local boxTop = y
        local insight = acquireFS("ARTWORK", "GameFontHighlightSmall")
        insight:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + 6, y - 6)
        insight:SetWidth(innerW - 12)
        local lines = { "|cff33ff99Actionable insight:|r " .. (model.eco.insight or "") }
        for _, line in ipairs(model.eco.computed or {}) do
            lines[#lines + 1] = "|cffbfbfbf" .. line .. "|r"
        end
        insight:SetText(table.concat(lines, "\n"))
        y = y - math.max(16, insight:GetStringHeight() + 12)
        local boxH = boxTop - y
        local box = acquireTex("BACKGROUND", 1)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, boxTop)
        box:SetSize(innerW, boxH)
        box:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.05)
        for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local line = acquireTex("BORDER")
            line:SetPoint(edge[1], box, edge[1])
            line:SetPoint(edge[2], box, edge[2])
            line:SetHeight(1)
            line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.25)
        end
        y = y - 4
    end

    panel:SetHeight(math.max(160, -y + PAD))
end

local MatrixPanel = {}
HM.MatrixPanel = MatrixPanel

-- Goal pathways are one graph evaluate PER open talent node - too heavy for every
-- aura tick, so the result is cached and recomputed only when talents change
-- (invalidated by the talent events below) or the panel first shows.
local cachedPath
local function computePathways(loadout)
    if not (HM.TalentAPI and HM.TalentAPI.walkTraits and HM.Sim) then return nil end
    local walk = HM.TalentAPI.walkTraits(false)
    if not walk or #walk == 0 then return nil end
    local candidates = {}
    for _, n in ipairs(walk) do
        if (n.rank or 0) < (n.maxRank or 1) and n.nodeID then
            candidates[#candidates + 1] = {
                label = ("%s %d/%d"):format(n.name or ("node " .. n.nodeID),
                    (n.rank or 0) + 1, n.maxRank or 1),
                what = loadout:withTraitNode(n.nodeID, (n.rank or 0) + 1),
                nodeId = n.nodeID, rank = (n.rank or 0) + 1, -- S28 ability-goal mode
            }
        end
    end
    if #candidates == 0 then return nil end
    local dim = HM.gearGoal and HM.gearGoal() or "auto"
    if dim == "auto" then dim = HM.Impact.primaryDimension(loadout) end
    local ok, path = pcall(HM.Sim.goalPathways, loadout, dim, candidates, 4)
    return (ok and path) or nil
end

function MatrixPanel.invalidatePathways()
    cachedPath = nil
end

function MatrixPanel.refresh()
    if not panel or not panel:IsShown() then return end
    local snapshot = HM.Snapshot.capture()
    if not snapshot then return end
    local loadout = HM.Loadout.fromSnapshot(snapshot)
    if cachedPath == nil then
        cachedPath = computePathways(loadout) or false -- false = computed, none found
    end
    -- Skill focus (S22a): the saved focus feeds the insight block + pathway chips.
    local focusModel
    local focusName = HM.SynergyHighlight and HM.SynergyHighlight.savedFocus
        and HM.SynergyHighlight.savedFocus() or nil
    if focusName then
        local okf, fm = pcall(HM.PanelModel.focusModel, loadout, focusName)
        focusModel = (okf and fm) or nil
    end
    local ok, model = pcall(HM.PanelModel.matrixModel, loadout, uiState().loop,
        cachedPath or nil, focusModel)
    if ok and model then
        panel.model = model
        layout(model)
        panel.bg:SetColorTexture(0.055, 0.055, 0.07, opacity())
    else
        HM.print("matrix refresh failed: " .. tostring(model))
    end
end

function MatrixPanel.toggle()
    if not panel then
        HM.print("matrix panel is in-game only")
        return
    end
    panel:SetShown(not panel:IsShown())
    MatrixPanel.refresh()
end

function MatrixPanel.setOpacity(v)
    local a = HM.PanelModel.normalizeOpacity(v)
    uiState().opacity = a
    if panel and panel.bg then
        panel.bg:SetColorTexture(0.055, 0.055, 0.07, a)
    end
    return a
end

function MatrixPanel.resetPosition()
    if not panel then return end
    uiState().pos = nil
    restorePosition()
end

-- Cycle the active loop (the mockup's goal dropdown, taint-free).
function MatrixPanel.cycleLoop()
    if not panel or not panel.model then return end
    local snapshot = HM.Snapshot.capture()
    local loops = HM.loopsForClass(snapshot and snapshot.classToken) or {}
    if #loops < 2 then return end
    local cur = uiState().loop
    local idx = 1
    for i, l in ipairs(loops) do
        if l.id == cur then idx = i end
    end
    uiState().loop = loops[(idx % #loops) + 1].id
    MatrixPanel.refresh()
end

local function createPanel()
    panel = _G.CreateFrame("Frame", "ForesightMatrixPanel", _G.UIParent)
    panel:SetWidth(WIDTH)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        uiState().pos = { point = point, relPoint = relPoint,
                          x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    end)
    restorePosition()

    -- Dark card + hairline border; the bg alpha is the user's opacity baseline.
    panel.bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0.055, 0.055, 0.07, opacity())
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        line:SetHeight(1)
        line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.35)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint("TOP" .. side)
        line:SetPoint("BOTTOM" .. side)
        line:SetWidth(1)
        line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.25)
    end

    -- Title bar: the brand header doubles as the loop cycler (mockup's dropdown).
    local titleBtn = _G.CreateFrame("Button", nil, panel)
    titleBtn:SetPoint("TOPLEFT")
    titleBtn:SetPoint("TOPRIGHT")
    titleBtn:SetHeight(24)
    local title = titleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("|cff33ff99FORESIGHT MATRIX|r")
    local titleLine = panel:CreateTexture(nil, "BORDER")
    titleLine:SetPoint("TOPLEFT", 0, -24)
    titleLine:SetPoint("TOPRIGHT", 0, -24)
    titleLine:SetHeight(1)
    titleLine:SetColorTexture(1, 1, 1, 0.08)
    titleBtn:SetScript("OnClick", function() MatrixPanel.cycleLoop() end)
    titleBtn:SetScript("OnEnter", function(self)
        if panel.badgeTip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(panel.badgeTip, nil, nil, nil, nil, true)
            _G.GameTooltip:Show()
        end
    end)
    titleBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    local close = _G.CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)

    panel:Hide()

    -- Live refresh while visible (same debounced event set as the stats panel).
    local events = _G.CreateFrame("Frame")
    for _, ev in ipairs({ "UNIT_STATS", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA",
                          "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
                          "CHARACTER_POINTS_CHANGED" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    local TALENT_EVENTS = { TRAIT_CONFIG_UPDATED = true, PLAYER_TALENT_UPDATE = true,
                            CHARACTER_POINTS_CHANGED = true }
    local pending
    events:SetScript("OnEvent", function(_, event, unit)
        if TALENT_EVENTS[event] then
            -- talent events carry a configID/points arg, not a unit - never unit-gate them
            MatrixPanel.invalidatePathways()
        elseif unit ~= nil and unit ~= "player" then
            return
        end
        if not panel:IsShown() or pending then return end
        pending = true
        local function run() pending = nil; MatrixPanel.refresh() end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.2, run) else run() end
    end)
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if not panel then createPanel() end
end)
