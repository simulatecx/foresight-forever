-- Foresight options panel (CORE-options, S30): the GUI face of the settings spine
-- (core/settings.lua). Tab column left, content right - built ENTIRELY from the
-- declared SETTINGS_KEYS table, so a key is one edit and the GUI, slash command and
-- docs all follow. A group with no shipped keys renders no tab (no Panic tab until the
-- Panic pillar exists). House-skinned custom frame (no Blizzard Settings API - fork-
-- safe); combat-gated open; every write goes through the same validators as the slash
-- path. In-game only.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

if not _G.CreateFrame then return end

-- Enlarged v0.45.8 (user: the window was too small): wider content, taller body,
-- roomier rows so the settings are comfortable to read and adjust.
local WIDTH, HEIGHT, PAD = 560, 460, 16    -- default size (restored from saved if present)
local WMIN, HMIN, WMAX, HMAX = 440, 320, 980, 860  -- resize bounds (UI-overhaul flexibility)
local TABW = 140
local ROW_H, ROW_STEP = 40, 48
local BRAND = { r = 0.20, g = 1.00, b = 0.60 }
local GOLD  = { r = 1.00, g = 0.82, b = 0.40 }
local MUTED = { r = 0.55, g = 0.55, b = 0.60 }

local panel, activeGroup
local widgets = {}

local function classColor()
    local _, token = _G.UnitClass("player")
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return GOLD.r, GOLD.g, GOLD.b
end

-- Per-character options-window state (saved size, so a user's expanded window persists).
local function optState()
    local db = HM.charDb and HM.charDb()
    if not db then return {} end
    db.settings.options = db.settings.options or {}
    return db.settings.options
end

-- Groups that actually own >= 1 shipped key (the no-empty-tab law).
local function liveGroups()
    local counts, out = {}, {}
    for _, spec in pairs(HM.Settings.KEYS) do counts[spec.group] = true end
    for _, g in ipairs(HM.Settings.GROUPS) do
        if counts[g] then out[#out + 1] = g end
    end
    return out
end

local function keysInGroup(group)
    local out = {}
    for key, spec in pairs(HM.Settings.KEYS) do
        if spec.group == group then out[#out + 1] = key end
    end
    table.sort(out)
    return out
end

local function releaseWidgets()
    for _, w in ipairs(widgets) do w:Hide() end
    widgets = {}
end

-- One row per key, rendered by type. Returns the next y.
local function renderKey(key, y, innerX, innerW)
    local spec = HM.Settings.KEYS[key]
    local row = _G.CreateFrame("Button", nil, panel)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", innerX, y)
    row:SetSize(innerW, ROW_H)
    widgets[#widgets + 1] = row

    local label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    label:SetText(spec.label)
    local desc = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    desc:SetWidth(innerW - 60)
    desc:SetJustifyH("LEFT")
    desc:SetText(spec.desc)

    local value = HM.Settings.get(key)
    if spec.type == "toggle" then
        local box = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        box:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        local function paint()
            local on = HM.Settings.get(key) == true
            box:SetText(on and "|cff4ade80[ON]|r" or "|cff9d9d9d[off]|r")
        end
        paint()
        row:SetScript("OnClick", function()
            HM.Settings.setValue(key, HM.Settings.get(key) ~= true)
            paint()
            if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
            if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
        end)
    elseif spec.type == "enum" then
        local box = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        box:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
        local function paint()
            box:SetText("|cff33ff99[" .. tostring(HM.Settings.get(key)) .. "]|r")
        end
        paint()
        row:SetScript("OnClick", function()
            -- cycle to the next value
            local cur, nextV = HM.Settings.get(key)
            for i, v in ipairs(spec.values) do
                if v == cur then nextV = spec.values[(i % #spec.values) + 1] end
            end
            HM.Settings.setValue(key, nextV or spec.default)
            paint()
            if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
            if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
        end)
    elseif spec.type == "slider" then
        local sl = _G.CreateFrame("Slider", nil, row, "OptionsSliderTemplate")
        sl:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        sl:SetWidth(120)
        sl:SetMinMaxValues(spec.min, spec.max)
        sl:SetValueStep(0.05)
        sl:SetObeyStepOnDrag(true)
        sl:SetValue(value)
        if sl.Low then sl.Low:SetText("") end
        if sl.High then sl.High:SetText("") end
        sl:SetScript("OnValueChanged", function(_, v)
            HM.Settings.setValue(key, v)
            if key == "panelAlpha" and HM.MatrixPanel and HM.MatrixPanel.setOpacity then
                pcall(HM.MatrixPanel.setOpacity, v)
            end
            -- Any slider (panelScale, growth, etc.) applies live to the panels.
            if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
            if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
        end)
        widgets[#widgets + 1] = sl
    elseif spec.type == "text" then
        -- Editable text (handle / armory). EditBox lives on OUR row frame (taint-safe,
        -- same as the slider); commits on Enter or focus-loss through the validated store.
        local eb = _G.CreateFrame("EditBox", nil, row, "InputBoxTemplate")
        eb:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
        eb:SetSize(160, 20)
        eb:SetAutoFocus(false)
        eb:SetMaxLetters(spec.max or 200)
        eb:SetText(tostring(value or ""))
        eb:SetCursorPosition(0)
        local function commit()
            local clean = HM.Settings.setValue(key, eb:GetText())
            eb:SetText(tostring(clean or ""))
            eb:SetCursorPosition(0)
            eb:ClearFocus()
            if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
            if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
        end
        eb:SetScript("OnEnterPressed", commit)
        eb:SetScript("OnEditFocusLost", commit)
        eb:SetScript("OnEscapePressed", function()
            eb:SetText(tostring(HM.Settings.get(key) or "")); eb:SetCursorPosition(0); eb:ClearFocus()
        end)
        widgets[#widgets + 1] = eb
    end
    return y - ROW_STEP
end

-- Character tab: a read-only identity readout at the very top (who you are / share as).
local function renderReadout(y, innerX, innerW)
    local name = (_G.UnitName and _G.UnitName("player")) or "?"
    local className = (_G.UnitClass and (_G.UnitClass("player"))) or ""
    local race = (_G.UnitRace and (_G.UnitRace("player"))) or ""
    local level = (_G.UnitLevel and _G.UnitLevel("player")) or 0
    local r, g, b = classColor()
    local head = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", innerX, y)
    head:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, name))
    widgets[#widgets + 1] = head
    local sub = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", panel, "TOPLEFT", innerX, y - 16)
    sub:SetWidth(innerW)
    sub:SetJustifyH("LEFT")
    sub:SetText(("Level %d %s %s - set how you appear on the ladders below."):format(
        level, race, className))
    widgets[#widgets + 1] = sub
    return y - 44
end

-- One action row (label + desc + a button). Used by the Layout tab for resets.
local function renderAction(label, desc, btnText, y, innerX, innerW, onClick)
    local row = _G.CreateFrame("Frame", nil, panel)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", innerX, y)
    row:SetSize(innerW, ROW_H)
    widgets[#widgets + 1] = row
    local lab = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    lab:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    lab:SetText(label)
    local d = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    d:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -14)
    d:SetWidth(innerW - 130)
    d:SetJustifyH("LEFT")
    d:SetText(desc)
    local btn = _G.CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    btn:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    btn:SetSize(120, 22)
    btn:SetText(btnText)
    btn:SetScript("OnClick", function() pcall(onClick) end)
    widgets[#widgets + 1] = btn
    return y - ROW_STEP
end

local function layout()
    releaseWidgets()
    local r, g, b = classColor()
    local groups = liveGroups()
    local contentX = PAD + TABW + PAD
    local innerW = math.max(180, (panel:GetWidth() or WIDTH) - contentX - PAD) -- reflow to live width

    -- Tab column.
    local ty = -40
    for _, group in ipairs(groups) do
        local tab = _G.CreateFrame("Button", nil, panel)
        tab:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, ty)
        tab:SetSize(TABW, 22)
        local on = (group == activeGroup)
        local fs = tab:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        fs:SetPoint("LEFT", 4, 0)
        fs:SetText(on and ("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255, group)
            or ("|cff9d9d9d%s|r"):format(group))
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(r, g, b, on and 0.12 or 0)
        tab:SetScript("OnClick", function() activeGroup = group; layout() end)
        widgets[#widgets + 1] = tab
        ty = ty - 24
    end

    -- Content for the active group.
    local y = -40
    if activeGroup == "Character" then
        y = renderReadout(y, contentX, innerW)
    end
    for _, key in ipairs(keysInGroup(activeGroup)) do
        y = renderKey(key, y, contentX, innerW)
    end
    if activeGroup == "Layout" then
        y = renderAction("Reset window positions",
            "Move the stats panel and the Matrix back to their default spots beside the character sheet.",
            "Reset positions", y, contentX, innerW, function()
                if HM.StatsPanel and HM.StatsPanel.resetPosition then HM.StatsPanel.resetPosition() end
                if HM.MatrixPanel and HM.MatrixPanel.resetPosition then HM.MatrixPanel.resetPosition() end
            end)
        y = renderAction("Reset Matrix width",
            "Return the Foresight Matrix to its default width (undo a drag-resize).",
            "Reset width", y, contentX, innerW, function()
                if HM.MatrixPanel and HM.MatrixPanel.resetWidth then HM.MatrixPanel.resetWidth() end
            end)
    end

    -- "Report an issue" button (the backlogged report button, S30).
    local report = _G.CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    report:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -PAD, PAD)
    report:SetSize(130, 22)
    report:SetText("Report an issue")
    report:SetScript("OnClick", function()
        if HM.onSlash then HM.onSlash("report from the options window") end
    end)
    widgets[#widgets + 1] = report
end

local OptionsPanel = {}
HM.OptionsPanel = OptionsPanel

local function createPanel()
    panel = _G.CreateFrame("Frame", "ForesightOptionsPanel", _G.UIParent)
    local sz = optState().size
    panel:SetSize((sz and sz.w) or WIDTH, (sz and sz.h) or HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:SetResizable(true)
    panel:EnableMouse(true)
    panel:SetClampedToScreen(true) -- always reachable, whatever UI overhaul is loaded
    if panel.SetResizeBounds then
        pcall(panel.SetResizeBounds, panel, WMIN, HMIN, WMAX, HMAX)
    else
        pcall(panel.SetMinResize, panel, WMIN, HMIN)
        pcall(panel.SetMaxResize, panel, WMAX, HMAX)
    end
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    panel:SetFrameStrata("DIALOG")

    panel.bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0.055, 0.055, 0.07, 0.96)
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1]); line:SetPoint(edge[2]); line:SetHeight(1)
        line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.35)
    end

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -12)
    title:SetText("|cff33ff99FORESIGHT OPTIONS|r")
    local titleLine = panel:CreateTexture(nil, "BORDER")
    titleLine:SetPoint("TOPLEFT", 0, -32); titleLine:SetPoint("TOPRIGHT", 0, -32)
    titleLine:SetHeight(1); titleLine:SetColorTexture(1, 1, 1, 0.08)
    -- Vertical divider between the tab column and content.
    local divider = panel:CreateTexture(nil, "BORDER")
    divider:SetPoint("TOPLEFT", PAD + TABW + PAD / 2, -36)
    divider:SetPoint("BOTTOMLEFT", PAD + TABW + PAD / 2, PAD + 28)
    divider:SetWidth(1); divider:SetColorTexture(1, 1, 1, 0.08)

    local close = _G.CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)

    -- Resize grip (bottom-right): drag to expand the window; content reflows to the new
    -- width and the size is saved per character. Flexibility for heavy UI-overhaul setups.
    local grip = _G.CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(panel:GetFrameLevel() + 10) -- clickable above the report button
    grip:EnableMouse(true)
    local gt = grip:CreateTexture(nil, "OVERLAY")
    gt:SetAllPoints()
    gt:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function() panel:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        optState().size = { w = math.floor(panel:GetWidth() + 0.5),
                            h = math.floor(panel:GetHeight() + 0.5) }
        layout() -- reflow once at release (the bg/border track the size live via SetAllPoints);
                 -- we avoid a per-frame relayout during the drag since layout() isn't pooled yet
    end)

    panel:Hide()
end

function OptionsPanel.toggle()
    if not panel then
        HM.print("options window is in-game only")
        return
    end
    if _G.InCombatLockdown and _G.InCombatLockdown() then
        HM.print("can't open options in combat")
        return
    end
    if panel:IsShown() then panel:Hide(); return end
    activeGroup = activeGroup or liveGroups()[1]
    layout()
    panel:Show()
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function() if not panel then createPanel() end end)

return OptionsPanel
