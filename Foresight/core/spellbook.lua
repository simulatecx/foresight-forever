-- Foresight spellbook adapter (S31b): enumerate the player's KNOWN spells at their
-- highest trained rank, so the character tab can rank "your strongest buttons" on your
-- real spellbook (not the whole catalog). All reads Guards-routed; a 12.x C_SpellBook
-- path with a classic-global fallback; headless-degrades to an empty list. Cached per
-- login + SPELLS_CHANGED (enumerating every refresh is too heavy). apiWatch covers the
-- reads so a build moving them surfaces in the harvest.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Guards = HM.Guards
local Spellbook = {}
HM.Spellbook = Spellbook

local cache

-- Resolve the known-spell set to OUR generated spell ids. We already ship every
-- player spell with a decode; the spellbook tells us which the player actually has.
-- Returns a de-duplicated id list (one id per spell name, the known highest rank).
local function enumerate()
    local known = {}
    local gen = HM.gen and HM.gen.spells
    if not gen then return known end

    -- Path A (12.x): C_SpellBook.GetNumSpellBookSkillLines / GetSpellBookItemInfo.
    local CSB = _G.C_SpellBook
    local numLines = CSB and CSB.GetNumSpellBookSkillLines
        and Guards.number(Guards.call(CSB.GetNumSpellBookSkillLines))
    if CSB and numLines and CSB.GetSpellBookSkillLineInfo and CSB.GetSpellBookItemInfo then
        local SpellBank = _G.Enum and _G.Enum.SpellBookSpellBank
        local playerBank = SpellBank and SpellBank.Player or 0
        for line = 1, numLines do
            local okL, lineInfo = pcall(CSB.GetSpellBookSkillLineInfo, line)
            if okL and type(lineInfo) == "table" and lineInfo.numSpellBookItems then
                local offset = lineInfo.itemIndexOffset or 0
                for i = offset + 1, offset + lineInfo.numSpellBookItems do
                    local okI, info = pcall(CSB.GetSpellBookItemInfo, i, playerBank)
                    local sid = okI and type(info) == "table"
                        and (info.spellID or info.actionID)
                    if sid and gen[sid] then known[#known + 1] = sid end
                end
            end
        end
    elseif _G.GetNumSpellTabs and _G.GetSpellBookItemInfo then
        -- Path B (classic fallback): GetSpellBookItemInfo(index, "spell").
        for tab = 1, (Guards.number(Guards.call(_G.GetNumSpellTabs)) or 0) do
            local _, _, offset, count = Guards.call(_G.GetSpellTabInfo, tab)
            offset = Guards.number(offset) or 0
            count = Guards.number(count) or 0
            for i = offset + 1, offset + count do
                local _, sid = Guards.call(_G.GetSpellBookItemInfo, i, "spell")
                sid = Guards.number(sid)
                if sid and gen[sid] then known[#known + 1] = sid end
            end
        end
    end
    return known
end

-- The known-spell id list (cached). forceRefresh bypasses the cache.
function Spellbook.known(forceRefresh)
    if cache and not forceRefresh then return cache end
    local ok, list = pcall(enumerate)
    cache = (ok and list) or {}
    return cache
end

function Spellbook.invalidate() cache = nil end

if _G.CreateFrame then
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("SPELLS_CHANGED")
    f:SetScript("OnEvent", function() Spellbook.invalidate() end)
end

return Spellbook
