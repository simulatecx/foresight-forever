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

local WIDTH, HEIGHT, PAD = 420, 320, 14
local TABW = 120
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
    row:SetSize(innerW, 36)
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
        end)
        widgets[#widgets + 1] = sl
    end
    return y - 42
end

local function layout()
    releaseWidgets()
    local r, g, b = classColor()
    local groups = liveGroups()
    local contentX = PAD + TABW + PAD
    local innerW = WIDTH - contentX - PAD

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
    for _, key in ipairs(keysInGroup(activeGroup)) do
        y = renderKey(key, y, contentX, innerW)
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
    panel:SetSize(WIDTH, HEIGHT)
    panel:SetPoint("CENTER")
    panel:SetMovable(true)
    panel:EnableMouse(true)
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
