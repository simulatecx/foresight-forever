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

local function layout(model)
    releaseAll(rowPool)
    releaseAll(headerPool)
    local state = uiState()
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
        if not collapsed then
            local zebra = false
            for _, row in ipairs(section.rows) do
                local f = acquire(rowPool, createRow)
                f.tooltipText = row.tooltip
                f.zebra = zebra
                f.stripe:SetColorTexture(1, 1, 1, zebra and 0.04 or 0)
                zebra = not zebra
                if row.wide then
                    f.label:SetText(("|cff%02x%02x%02x%s|r  %s"):format(
                        r * 255, g * 255, b * 255, row.label, colorizeDeltas(row.value)))
                    f.label:SetPoint("RIGHT", f, "RIGHT", -6, 0)
                    f.value:SetText("")
                else
                    f.label:SetText(row.label)
                    f.label:SetPoint("RIGHT", f.value, "LEFT", -4, 0)
                    f.value:SetText(colorizeDeltas(row.value))
                end
                f:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, y)
                f:SetPoint("RIGHT", panel, "RIGHT", -PAD, 0)
                y = y - ROW_HEIGHT
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
    local snapshot = HM.Snapshot.capture()
    if not snapshot then return end
    local loadout = HM.Loadout.fromSnapshot(snapshot)
    local ok, model = pcall(HM.PanelModel.build, loadout)
    if ok and model then
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

local function createPanel()
    local parent = _G.CharacterFrame
    if not parent then return end
    local r, g, b = classColor()

    panel = _G.CreateFrame("Frame", "ForesightStatsPanel", parent)
    panel:SetWidth(PANEL_WIDTH)
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, -12)

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
    local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    subtitle:SetPoint("TOPRIGHT", -PAD, -9)
    subtitle:SetText("what more would do")

    toggleButton = _G.CreateFrame("Button", "ForesightToggleButton", parent, "UIPanelButtonTemplate")
    toggleButton:SetSize(36, 18)
    toggleButton:SetText("FS")
    toggleButton:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -40, 4)
    toggleButton:SetScript("OnClick", StatsPanel.toggle)

    parent:HookScript("OnHide", function() panel:Hide() end)

    local events = _G.CreateFrame("Frame")
    events:RegisterEvent("UNIT_STATS")
    events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    events:SetScript("OnEvent", function(_, _, unit)
        if unit == nil or unit == "player" then
            StatsPanel.refresh()
        end
    end)
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if not panel then createPanel() end
end)
