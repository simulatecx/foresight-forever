-- Foresight stats panel renderer: side panel docked to the character frame.
-- Skin: dark translucent card, class-color accent, zebra rows, colored what-if
-- deltas - all code-drawn textures (no art assets), so it blends with both the
-- default and classic-reskin UIs. Walks the model from ui/panel_model.lua;
-- all layout here, zero computation. In-game only.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

if not _G.CreateFrame then return end

local PANEL_WIDTH = 240
local ROW_HEIGHT = 15
local HEADER_HEIGHT = 20
local PAD = 10

local panel, toggleButton
local rowPool, headerPool = {}, {}

local function classColor()
    local _, token = _G.UnitClass("player")
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function uiState()
    local db = HM.charDb()
    db.settings.panel = db.settings.panel or { collapsed = {} }
    return db.settings.panel
end

local DEFAULT_POINT = { "TOPLEFT", "TOPRIGHT", 2, -12 } -- anchored off CharacterFrame

-- Anchor the panel: to a saved (validated) screen position if the user moved it, else
-- the default dock beside the character frame.
local function restorePosition()
    if not panel then return end
    panel:ClearAllPoints()
    local pos = HM.PanelModel.normalizePanelPos(uiState().pos)
    if pos then
        panel:SetPoint(pos.point, _G.UIParent, pos.relPoint, pos.x, pos.y)
    else
        -- Default dock: ANCHOR to the character frame (we are a UIParent child, never
        -- a CharacterFrame child - the taint-isolation law). nil-safe if CharacterFrame
        -- isn't loaded yet.
        local anchor = _G.CharacterFrame or _G.UIParent
        panel:SetPoint(DEFAULT_POINT[1], anchor, DEFAULT_POINT[2],
            DEFAULT_POINT[3], DEFAULT_POINT[4])
    end
end

local function acquire(pool, create)
    for _, f in ipairs(pool) do
        if not f.inUse then
            f.inUse = true
            f:Show()
            return f
        end
    end
    local f = create()
    f.inUse = true
    pool[#pool + 1] = f
    return f
end

local function releaseAll(pool)
    for _, f in ipairs(pool) do
        f.inUse = false
        f:Hide()
    end
end

-- Color positive/negative percentages in what-if lines green/red.
local function colorizeDeltas(text)
    text = text:gsub("(%+%d+%.?%d*%%?)", "|cff4ade80%1|r")
    text = text:gsub("(%-%d+%.?%d*%%)", "|cfff87171%1|r")
    return text
end

local function createRow()
    local f = _G.CreateFrame("Frame", nil, panel)
    f:SetHeight(ROW_HEIGHT)
    f.stripe = f:CreateTexture(nil, "BACKGROUND")
    f.stripe:SetAllPoints()
    f.stripe:SetColorTexture(1, 1, 1, 0.04)
    f.label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    f.label:SetPoint("LEFT", 6, 0)
    f.label:SetJustifyH("LEFT")
    f.value = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.value:SetPoint("RIGHT", -6, 0)
    f.value:SetJustifyH("RIGHT")
    -- S33: value-change flash accent (ours, hidden until Motion lights it).
    f.flash = f:CreateTexture(nil, "OVERLAY")
    f.flash:SetPoint("RIGHT", -2, 0)
    f.flash:SetSize(72, ROW_HEIGHT - 2)
    f.flash:Hide()
    f:SetScript("OnEnter", function(self)
        self.stripe:SetColorTexture(1, 1, 1, 0.10)
        if self.tooltipText then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(self.tooltipText, nil, nil, nil, nil, true)
            _G.GameTooltip:Show()
        end
    end)
    f:SetScript("OnLeave", function(self)
        self.stripe:SetColorTexture(1, 1, 1, self.zebra and 0.04 or 0)
        _G.GameTooltip:Hide()
    end)
    return f
end

local function createHeader()
    local f = _G.CreateFrame("Button", nil, panel)
    f:SetHeight(HEADER_HEIGHT)
    f.accent = f:CreateTexture(nil, "ARTWORK")
    f.accent:SetPoint("LEFT", 0, 0)
    f.accent:SetSize(3, HEADER_HEIGHT - 6)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(1, 1, 1, 0.06)
    f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    f.text:SetPoint("LEFT", 10, 0)
    f.chevron = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    f.chevron:SetPoint("RIGHT", -6, 0)
    f:SetScript("OnClick", function(self)
        local state = uiState()
        state.collapsed[self.sectionId] = not state.collapsed[self.sectionId]
        HM.StatsPanel.refresh()
    end)
    return f
end

-- S33 RADAR CHART: the drawn shape (spokes + SetVertexOffset polygon fill + plan
-- outline) the S31 spec deferred. Renders ABOVE the section's text rows - the rows
-- and the basis line stay (text reduced, never removed; the display law owns the
-- numbers). Honest degrades: no CreateLine/SetVertexOffset -> text rows only.
local RADAR_ABBREV = { meleeDps = "Melee", spellcasting = "Spell", healing = "Heal",
    survivability = "Surv", sustain = "Sust", threat = "Threat",
    rangedDps = "Ranged", tankability = "Tank" }
local CHART_H = 168
local CHART_RADIUS = 56

local function renderRadar(chart, yTop, innerW, r, g, b)
    local M = HM.Motion
    local cf = panel.radarChart
    if not cf then
        cf = _G.CreateFrame("Frame", nil, panel)
        cf.labels = {}
        panel.radarChart = cf
    end
    if not cf.CreateLine then return false end
    M.releaseLines(cf)
    M.releaseTris(cf)
    cf:ClearAllPoints()
    cf:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, yTop)
    cf:SetSize(innerW, CHART_H)
    cf:Show()
    local cx, cy = innerW / 2, -CHART_H / 2
    local axes = chart.axes
    local n = #axes
    if n < 3 then cf:Hide() return false end
    local ones, cur, plan, hasPlan = {}, {}, {}, false
    for i, ax in ipairs(axes) do
        ones[i] = 1
        cur[i] = ax.curFill or 0
        plan[i] = ax.planFill or ax.curFill or 0
        if ax.planFill then hasPlan = true end
    end
    local rim = M.radarPoints(ones, CHART_RADIUS)
    -- spokes + rim (the reference web)
    for i = 1, n do
        M.line(cf, "TOPLEFT", cx, cy, cx + rim[i].x, cy + rim[i].y,
            { r = 1, g = 1, b = 1, a = 0.10 }, 1)
        local nxt = rim[(i % n) + 1]
        M.line(cf, "TOPLEFT", cx + rim[i].x, cy + rim[i].y, cx + nxt.x, cy + nxt.y,
            { r = 1, g = 1, b = 1, a = 0.14 }, 1)
    end
    -- current shape: filled polygon + bright outline (class color)
    local pts = M.radarPoints(cur, CHART_RADIUS)
    M.drawFan(cf, "TOPLEFT", cx, cy, pts, { r = r, g = g, b = b, a = 0.20 })
    for i = 1, n do
        local nxt = pts[(i % n) + 1]
        M.line(cf, "TOPLEFT", cx + pts[i].x, cy + pts[i].y, cx + nxt.x, cy + nxt.y,
            { r = r, g = g, b = b, a = 0.85 }, 1.5)
    end
    -- plan overlay: OUTLINE only (never a second fill - the shapes must both read)
    if hasPlan then
        local ppts = M.radarPoints(plan, CHART_RADIUS)
        for i = 1, n do
            local nxt = ppts[(i % n) + 1]
            M.line(cf, "TOPLEFT", cx + ppts[i].x, cy + ppts[i].y,
                cx + nxt.x, cy + nxt.y, { r = 1, g = 0.82, b = 0.3, a = 0.9 }, 1)
        end
    end
    -- Axis tips: an abbreviated label + an invisible HOVER TARGET. Hovering a tip
    -- expands that dimension's detail (value, plan projection, what it measures) so
    -- the per-axis rows below can collapse - the raw numbers still live in the
    -- Dimensions section above, so nothing is hidden. Goal axis reads in class color
    -- with a star. All on our own frame (cf -> UIParent), taint-safe.
    local tips = M.radarPoints(ones, CHART_RADIUS + 16)
    cf.tipBtns = cf.tipBtns or {}
    for i = 1, n do
        local ax = axes[i]
        local fs = cf.labels[i]
        if not fs then
            fs = cf:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            cf.labels[i] = fs
        end
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", cf, "TOPLEFT", cx + tips[i].x, cy + tips[i].y)
        local ab = RADAR_ABBREV[ax.id] or (ax.label or ""):sub(1, 5)
        local normalText = ax.isGoal
            and ("|cff%02x%02x%02x* %s|r"):format(r * 255, g * 255, b * 255, ab) or ab
        fs:SetText(normalText)
        fs:Show()

        local btn = cf.tipBtns[i]
        if not btn then
            btn = _G.CreateFrame("Button", nil, cf)
            cf.tipBtns[i] = btn
            btn:SetScript("OnEnter", function(self)
                local info = self.info
                if not info then return end
                if self.fs and info.hl then self.fs:SetText(info.hl) end
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                _G.GameTooltip:SetText(info.label
                    .. (info.isGoal and "  |cffffd24d(goal)|r" or ""), 1, 1, 1)
                _G.GameTooltip:AddLine(info.value, 0.2, 1, 0.6)
                if info.plan then
                    _G.GameTooltip:AddLine("with your plan: " .. info.plan, 0.83, 0.72, 0.3)
                end
                if info.unit then
                    _G.GameTooltip:AddLine(info.unit, 0.6, 0.6, 0.6, true)
                end
                _G.GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                _G.GameTooltip:Hide()
                if self.fs and self.normalText then self.fs:SetText(self.normalText) end
            end)
        end
        local dim = HM.dimensions and HM.dimensions.byId and HM.dimensions.byId(ax.id)
        local hl = ("|cff%02x%02x%02x%s|r"):format(
            math.min(255, r * 255 + 60), math.min(255, g * 255 + 60),
            math.min(255, b * 255 + 60), ax.isGoal and ("* " .. ab) or ab)
        btn.fs, btn.normalText = fs, normalText
        btn.info = {
            label = ax.label or ab,
            value = HM.dimensions.display(ax.id, ax.current),
            plan = ax.plan and HM.dimensions.display(ax.id, ax.plan) or nil,
            unit = dim and dim.unit, isGoal = ax.isGoal, hl = hl,
        }
        btn:SetSize(48, 16)
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", cf, "TOPLEFT", cx + tips[i].x, cy + tips[i].y)
        btn:Show()
    end
    for i = n + 1, #cf.labels do cf.labels[i]:Hide() end
    for i = n + 1, #cf.tipBtns do cf.tipBtns[i]:Hide() end
    return true
end

local FLASH_SECTIONS = { dimensions = true, ledger = true, statvalue = true }

local function layout(model)
    releaseAll(rowPool)
    releaseAll(headerPool)
    if HM.Motion then HM.Motion.cancelOwner("fs") end
    local motion = HM.Motion and HM.Motion.level() or "off"
    if panel.radarChart and motion == "off" then panel.radarChart:Hide() end
    local state = uiState()
    if panel.collapseChevron then
        panel.collapseChevron:SetText(state.panelCollapsed and "+" or "-")
    end
    if state.panelCollapsed then
        -- Collapsed: everything released above; keep only the title bar visible.
        if panel.radarChart then panel.radarChart:Hide() end
        if panel.radarHint then panel.radarHint:Hide() end
        panel:SetHeight(26)
        return
    end
    local r, g, b = classColor()
    local y = -PAD - 22 -- below title bar
    for _, section in ipairs(model.sections) do
        local header = acquire(headerPool, createHeader)
        header.sectionId = section.id
        local collapsed = state.collapsed[section.id]
        header.accent:SetColorTexture(r, g, b, 0.9)
        header.text:SetText(section.title)
        header.chevron:SetText(collapsed and "+" or "-")
        header:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
        header:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
        y = y - HEADER_HEIGHT - 2
        if section.id == "radar" and panel.radarChart
                and (collapsed or motion == "off" or not section.chart) then
            panel.radarChart:Hide()
            if panel.radarHint then panel.radarHint:Hide() end
        end
        if not collapsed then
            local radarCharted = false
            if section.id == "radar" and section.chart and motion ~= "off"
                    and HM.Motion then
                -- Discoverability hint above the chart: the per-axis rows collapsed, so
                -- tell the player the detail is a hover away.
                if not panel.radarHint then
                    panel.radarHint = panel:CreateFontString(nil, "ARTWORK",
                        "GameFontDisableSmall")
                end
                panel.radarHint:ClearAllPoints()
                panel.radarHint:SetPoint("TOP", panel, "TOPLEFT", PANEL_WIDTH / 2, y - 1)
                panel.radarHint:SetText("|cff9d9d9dmouseover an axis for details|r")
                local chartTop = y - 13
                if renderRadar(section.chart, chartTop, PANEL_WIDTH - PAD * 2, r, g, b) then
                    panel.radarHint:Show()
                    y = chartTop - CHART_H - 6
                    radarCharted = true
                else
                    panel.radarHint:Hide()
                end
            end
            -- When the radar DREW, collapse its per-axis text rows: hover a tip for the
            -- detail. Keep the basis line (the empty-label row). The numbers stay in the
            -- Dimensions section above, so nothing is hidden. Text fallback (motion off)
            -- keeps every row.
            local rows = section.rows
            if radarCharted then
                rows = {}
                for _, row in ipairs(section.rows) do
                    if (row.label or "") == "" then rows[#rows + 1] = row end
                end
            end
            local zebra = false
            for _, row in ipairs(rows) do
                local f = acquire(rowPool, createRow)
                f.tooltipText = row.tooltip
                f.flash:Hide()
                if HM.Motion and FLASH_SECTIONS[section.id] then
                    local key = "fs:" .. section.id .. ":" .. tostring(row.label)
                    local prev = HM.Motion.trackValue(key, row.value)
                    if motion ~= "off" and prev ~= nil and prev ~= row.value then
                        HM.Motion.flash("fs", f.flash, r, g, b, 0.20)
                    end
                end
                f.zebra = zebra
                f.stripe:SetColorTexture(1, 1, 1, zebra and 0.04 or 0)
                zebra = not zebra
                if row.wide then
                    -- Wide rows hold a full sentence; anchor the label to the top and
                    -- let it wrap, then size the row to the wrapped height so rows
                    -- never overlap. Wrap must be EXPLICIT (live catch 2026-10-12: the
                    -- 12.x client ellipsized what-if rows to one line otherwise).
                    f.label:ClearAllPoints()
                    f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -1)
                    f.label:SetPoint("RIGHT", f, "RIGHT", -6, 0)
                    f.label:SetJustifyH("LEFT")
                    f.label:SetWordWrap(true)
                    if f.label.SetMaxLines then f.label:SetMaxLines(0) end
                    f.label:SetText(("|cff%02x%02x%02x%s|r  %s"):format(
                        r * 255, g * 255, b * 255, row.label, colorizeDeltas(row.value)))
                    f.value:SetText("")
                else
                    f.label:ClearAllPoints()
                    f.label:SetWordWrap(false)
                    f.label:SetPoint("LEFT", f, "LEFT", 6, 0)
                    f.label:SetPoint("RIGHT", f.value, "LEFT", -4, 0)
                    f.label:SetText(row.label)
                    f.value:SetText(colorizeDeltas(row.value))
                end
                f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
                f:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
                -- MEASURED height for every row (not only wide ones): if ElvUI or a locale
                -- grows the global fonts, rows grow instead of glyphs touching.
                local rowH = ROW_HEIGHT
                local h = f.label:GetStringHeight()
                if h and h > 0 then rowH = math.max(ROW_HEIGHT, math.ceil(h) + 4) end
                f:SetHeight(rowH)
                y = y - rowH
            end
        end
        y = y - 6
    end
    panel:SetHeight(math.max(140, -y + PAD))
end

local StatsPanel = {}
HM.StatsPanel = StatsPanel

function StatsPanel.refresh()
    if not panel or not panel:IsShown() then return end
    -- v0.45.8: user-set panel scale (addon coexistence).
    if HM.Settings and HM.Settings.get then
        panel:SetScale(HM.Settings.get("panelScale") or 1)
    end
    local snapshot = HM.Snapshot.capture()
    if not snapshot then return end
    local loadout = HM.Loadout.fromSnapshot(snapshot)
    local ok, model = pcall(HM.PanelModel.build, loadout)
    if ok and model then
        if panel.subtitle and model.playstyle then
            panel.subtitle:SetText((model.playstyle:gsub(" %(v0 heuristic%)", "")))
        end
        layout(model)
    else
        HM.print("stats panel refresh failed: " .. tostring(model))
    end
end

function StatsPanel.toggle()
    if not panel then return end
    panel:SetShown(not panel:IsShown())
    StatsPanel.refresh()
end

-- The stats-panel frame, so the Matrix can open right beside it (FS master button opens
-- the pair adjacent). Returns nil out of game / before creation.
function StatsPanel.getFrame() return panel end

-- Clear the saved position and re-dock beside the character frame.
function StatsPanel.resetPosition()
    if not panel then return end
    uiState().pos = nil
    restorePosition()
end

local function createPanel()
    local charFrame = _G.CharacterFrame
    if not charFrame then return end
    local r, g, b = classColor()

    -- TAINT-ISOLATION LAW (v0.45.5, after a live gamepad-interact block with the
    -- character tab open): our panel and its buttons are UIParent children that merely
    -- ANCHOR to the character frame - never children of it. A child inherits
    -- CharacterFrame's secure context, so when the client ran a protected gamepad
    -- interact-target operation it blocked on our tainted frame. On our own layer it
    -- can't. We show/hide them with the character frame via hooks below.
    panel = _G.CreateFrame("Frame", "ForesightStatsPanel", _G.UIParent)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetFrameStrata("HIGH") -- above the char frame (was implicit as its child)

    -- Movable: drag the panel anywhere (it sits beside the character sheet by default,
    -- which can overlap other panels); position is saved per character and restored.
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true) -- never let a drag strand the panel off-screen
    panel:SetToplevel(true)        -- clicked window raises above our other windows
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        uiState().pos = { point = point, relPoint = relPoint,
                          x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    end)
    restorePosition()

    -- Dark card: base fill + hairline border + class-color top strip, all textures.
    local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints()
    bg:SetColorTexture(0.07, 0.07, 0.09, 0.92)
    local topStrip = panel:CreateTexture(nil, "BACKGROUND", nil, -7)
    topStrip:SetPoint("TOPLEFT")
    topStrip:SetPoint("TOPRIGHT")
    topStrip:SetHeight(26)
    topStrip:SetColorTexture(r, g, b, 0.18)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT", 1 }, { "BOTTOMLEFT", "BOTTOMRIGHT", 1 } }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        line:SetHeight(edge[3])
        line:SetColorTexture(r, g, b, 0.5)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint("TOP" .. side)
        line:SetPoint("BOTTOM" .. side)
        line:SetWidth(1)
        line:SetColorTexture(r, g, b, 0.35)
    end
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -7)
    title:SetText(("|cff%02x%02x%02xForesight|r"):format(r * 255, g * 255, b * 255))

    -- Independent collapse/expand: shrink the stats table to just this title bar without
    -- touching the Matrix (the FS master button toggles both; this is the stats-only lever).
    local collapseBtn = _G.CreateFrame("Button", nil, panel)
    collapseBtn:SetSize(18, 18)
    collapseBtn:SetPoint("TOPRIGHT", -4, -4)
    collapseBtn:SetFrameLevel(panel:GetFrameLevel() + 5)
    local chev = collapseBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    chev:SetAllPoints()
    collapseBtn:SetScript("OnClick", function()
        local st = uiState()
        st.panelCollapsed = not st.panelCollapsed
        StatsPanel.refresh()
    end)
    collapseBtn:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText("Collapse / expand the stats table", 0.2, 1, 0.6)
        _G.GameTooltip:Show()
    end)
    collapseBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    panel.collapseChevron = chev

    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    subtitle:SetPoint("TOPRIGHT", -26, -9)
    subtitle:SetText("what more would do")
    panel.subtitle = subtitle -- updated each refresh with the playstyle label

    -- The FS toggle + options buttons: also UIParent children, ANCHORED to the char
    -- frame's bottom-right (they must sit on the character sheet, but not live inside
    -- its frame tree). They're shown/hidden with the character frame via the hooks
    -- below, since anchoring alone won't track its visibility.
    -- Tooltip helper for the furniture buttons.
    local function furnitureTip(btn, text)
        btn:SetScript("OnEnter", function(self)
            if _G.GameTooltip then
                _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                _G.GameTooltip:SetText(text, 0.2, 1, 0.6, 1, true) -- wrap: no mile-wide tooltip
                _G.GameTooltip:Show()
            end
        end)
        btn:SetScript("OnLeave", function() if _G.GameTooltip then _G.GameTooltip:Hide() end end)
    end

    -- FS is the ONE master button (user restructure 2026-10-14): it expands/collapses the
    -- whole Foresight view - the character stats panel AND the Matrix - in lockstep. Share
    -- is button 2, Options button 3. Each calls into our functions DIRECTLY (never a typed
    -- slash) so there's no chat-parse taint on a controller. All are UIParent children
    -- ANCHORED to the char frame's bottom-right (taint-isolation law), shown/hidden with it.
    toggleButton = _G.CreateFrame("Button", "ForesightToggleButton", _G.UIParent, "UIPanelButtonTemplate")
    toggleButton:SetFrameStrata("HIGH")
    toggleButton:SetSize(36, 18)
    toggleButton:SetText("FS")
    toggleButton:SetPoint("BOTTOMRIGHT", charFrame, "BOTTOMRIGHT", -40, 4)
    toggleButton:SetScript("OnClick", function()
        local show = not panel:IsShown()
        panel:SetShown(show)
        StatsPanel.refresh()
        if HM.MatrixPanel and HM.MatrixPanel.setShown then HM.MatrixPanel.setShown(show) end
    end)
    furnitureTip(toggleButton, "Foresight: show/hide your character stats + the Matrix")

    local shareBtn = _G.CreateFrame("Button", "ForesightShareButton", _G.UIParent, "UIPanelButtonTemplate")
    shareBtn:SetFrameStrata("HIGH")
    shareBtn:SetSize(44, 18)
    shareBtn:SetText("Share")
    shareBtn:SetPoint("RIGHT", toggleButton, "LEFT", -2, 0)
    shareBtn:SetScript("OnClick", function() if HM.onSlash then HM.onSlash("share") end end)
    furnitureTip(shareBtn, "Copy your crowd-compare link (no typing needed)")

    local optBtn = _G.CreateFrame("Button", "ForesightOptionsButton", _G.UIParent, "UIPanelButtonTemplate")
    optBtn:SetFrameStrata("HIGH")
    optBtn:SetSize(20, 18)
    optBtn:SetText("|TInterface\\Buttons\\UI-OptionsButton:12:12|t")
    optBtn:SetPoint("RIGHT", shareBtn, "LEFT", -2, 0)
    optBtn:SetScript("OnClick", function()
        if HM.OptionsPanel and HM.OptionsPanel.toggle then HM.OptionsPanel.toggle() end
    end)
    furnitureTip(optBtn, "Foresight options")

    -- Track the character frame's visibility (we're anchored, not parented): the
    -- buttons appear only while the char sheet is open; closing it also hides the panel.
    local function setFurnitureShown(show)
        toggleButton:SetShown(show)
        shareBtn:SetShown(show)
        optBtn:SetShown(show)
        if not show then panel:Hide() end  -- Matrix is independent/pinnable: it stays until FS-toggled
    end
    charFrame:HookScript("OnShow", function() setFurnitureShown(true) end)
    charFrame:HookScript("OnHide", function() setFurnitureShown(false) end)
    setFurnitureShown(charFrame.IsShown and charFrame:IsShown() and true or false)

    -- S33 throttle law: a hidden panel runs zero animation work.
    panel:SetScript("OnHide", function()
        if HM.Motion then HM.Motion.cancelOwner("fs") end
    end)

    -- Live refresh while visible: gear, stats, talents, and buffs all re-snapshot.
    -- pcall per registration - event names drift across client flavors (degrade law).
    local events = _G.CreateFrame("Frame")
    for _, ev in ipairs({ "UNIT_STATS", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA",
                          "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
                          "CHARACTER_POINTS_CHANGED" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    -- Debounced: UNIT_AURA can burst in combat; one rebuild per 0.2s is plenty.
    local pending
    events:SetScript("OnEvent", function(_, _, unit)
        if unit ~= nil and unit ~= "player" then return end
        if not panel:IsShown() or pending then return end
        pending = true
        local function run() pending = nil; StatsPanel.refresh() end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.2, run) else run() end
    end)
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
-- createPanel early-returns when CharacterFrame isn't loaded yet; retry on ADDON_LOADED so
-- a load-on-demand/reskinned character frame can't silently kill the whole stats feature
-- (UI audit 2026-10-20 latent trap).
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, event)
    if not panel then createPanel() end
    if panel and event == "ADDON_LOADED" then self:UnregisterEvent("ADDON_LOADED") end
end)
