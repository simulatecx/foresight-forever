-- Foresight talent API adapter. Live-verified 2026-10-10 (build 70338): Forever ships
-- the Mainline surface WITHOUT the classic talent globals - talent info lives on
-- C_SpecializationInfo.GetTalentInfo, whose calling convention for classic trees is
-- undocumented, and the GetNum* enumerators are absent. This adapter tries each known
-- convention under pcall, locks onto the first that yields a sane result, and
-- normalizes everything to one classic-style shape:
--   { name, tier, column, rank, maxRank }   (1-based coordinates)
-- EVERY talent read (snapshot capture, tooltip probe, S2 hook) routes through here;
-- no consumer touches a raw talent API again. No data at all degrades to empty results.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local TalentAPI = {}
HM.TalentAPI = TalentAPI

local MAX_TABS, MAX_TALENTS, MISS_CUTOFF = 8, 64, 3

local mode -- "classic" | "spec-table" | "spec-positional"; nil until a call succeeds

-- Accept a TalentInfoResult-style table or classic multi-returns; nil when neither.
local function normalize(a, _, c, d, e, f)
    if type(a) == "table" then
        if type(a.name) ~= "string" or a.name == "" then return nil end
        return {
            name = a.name,
            tier = a.tier or a.row,
            column = a.column,
            rank = a.rank or a.currentRank or 0,
            maxRank = a.maxRank or a.maximumRank or 1,
        }
    end
    if type(a) ~= "string" or a == "" then return nil end
    return { name = a, tier = c, column = d, rank = e or 0, maxRank = f or 1 }
end

local function tryClassic(tab, index)
    if not _G.GetTalentInfo then return nil end
    local ok, a, b, c, d, e, f = pcall(_G.GetTalentInfo, tab, index)
    if not ok then return nil end
    return normalize(a, b, c, d, e, f)
end

local function trySpecTable(tab, index)
    local api = _G.C_SpecializationInfo
    if not (api and api.GetTalentInfo) then return nil end
    local ok, a = pcall(api.GetTalentInfo, { tabIndex = tab, talentIndex = index })
    if not ok then return nil end
    return normalize(a)
end

local function trySpecPositional(tab, index)
    local api = _G.C_SpecializationInfo
    if not (api and api.GetTalentInfo) then return nil end
    local ok, a, b, c, d, e, f = pcall(api.GetTalentInfo, tab, index)
    if not ok then return nil end
    return normalize(a, b, c, d, e, f)
end

local CONVENTIONS = {
    { id = "classic", fn = tryClassic },
    { id = "spec-table", fn = trySpecTable },
    { id = "spec-positional", fn = trySpecPositional },
}

-- Fetch one talent by classic-style coordinates; locks the working convention on
-- first success so steady-state reads don't re-probe.
function TalentAPI.get(tab, index)
    for _, c in ipairs(CONVENTIONS) do
        if not mode or mode == c.id then
            local info = c.fn(tab, index)
            if info then
                mode = c.id
                return info
            end
        end
    end
    return nil
end

-- Which convention answered (nil = none has yet; e.g. no talent data at this level).
function TalentAPI.mode() return mode end

-- Is any talent surface present at all (presence, not proof it returns data).
function TalentAPI.available()
    if _G.GetTalentInfo ~= nil then return true end
    local api = _G.C_SpecializationInfo
    return (api and api.GetTalentInfo) ~= nil
end

-- Enumerate every talent the client exposes as a flat { tab, index, info } list.
-- GetNumTalentTabs/GetNumTalents guide the walk when present (classic); otherwise
-- coordinates are brute-probed up to hard caps, ending a tab after MISS_CUTOFF
-- consecutive holes (talent lists are dense in classic-style trees).
function TalentAPI.all()
    local out = {}
    if not TalentAPI.available() then return out end
    local Guards = HM.Guards
    local numTabs = Guards.number(Guards.call(_G.GetNumTalentTabs)) or MAX_TABS
    for tab = 1, numTabs do
        local numTalents = Guards.number(Guards.call(_G.GetNumTalents, tab))
        local misses = 0
        for index = 1, numTalents or MAX_TALENTS do
            local info = TalentAPI.get(tab, index)
            if info then
                misses = 0
                out[#out + 1] = { tab = tab, index = index, info = info }
            elseif not numTalents then
                misses = misses + 1
                if misses >= MISS_CUTOFF then break end
            end
        end
    end
    return out
end

-- Test hook: clears the locked convention (the selftest mocks an API and must not
-- leave the adapter poisoned for real in-game use afterwards).
function TalentAPI._resetForTest() mode = nil end

return TalentAPI
