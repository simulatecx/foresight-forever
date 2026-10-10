-- Foresight export window: copyable text out of the game (WoW chat can't be copied).
-- A scrollable EditBox pre-highlighted for CTRL+C - the WeakAuras-export pattern.
-- In-game only.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

-- Serialize a Lua table to readable indented text (for export eyes, not re-import).
-- Defined before the frame guard so the headless harness can test it.
function HM.serialize(value, indent)
    indent = indent or ""
    local t = type(value)
    if t == "table" then
        local parts = { "{" }
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        for _, k in ipairs(keys) do
            parts[#parts + 1] = ("%s  %s = %s,"):format(
                indent, tostring(k), HM.serialize(value[k], indent .. "  "))
        end
        parts[#parts + 1] = indent .. "}"
        return table.concat(parts, "\n")
    elseif t == "string" then
        return ("%q"):format(value)
    end
    return tostring(value)
end

if not _G.CreateFrame then return end

local frame, editBox

local function ensureFrame()
    if frame then return end
    frame = _G.CreateFrame("Frame", "ForesightExportFrame", _G.UIParent, "BackdropTemplate")
    frame:SetSize(460, 320)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 24,
            insets = { left = 6, right = 6, top = 6, bottom = 6 },
        })
    end

    local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Foresight export - CTRL+C to copy")

    local close = _G.CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local scroll = _G.CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)

    editBox = _G.CreateFrame("EditBox", nil, scroll)
    editBox:SetMultiLine(true)
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetWidth(400)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Keep the full text selected so CTRL+C always grabs everything.
    editBox:SetScript("OnTextChanged", function(self) self:HighlightText() end)
    editBox:SetScript("OnCursorChanged", function(self) self:HighlightText() end)
    scroll:SetScrollChild(editBox)
end

function HM.showExport(text)
    ensureFrame()
    editBox:SetText(text or "")
    frame:Show()
    editBox:SetFocus()
    editBox:HighlightText()
end
