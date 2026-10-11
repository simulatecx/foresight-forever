-- Foresight data collector: turns every Foresight user into a database contributor.
-- Everything lands in ForesightDB.collect (SavedVariables); the offline harvester
-- (pipeline/harvest.py) reads the file after logout. The addon never networks -
-- file-based collection is the compliant channel (WowUp/Warcraft Logs pattern).
--
-- Collected:
--   sessions     - char/class/race/level/game build per login (growth DB over time)
--   levels       - PLAYER_LEVEL_UP journal with full stat snapshots
--   verify       - live API/environment verification results (/foresight verify)
--   talentProbe  - raw in-game talent tooltip text per rank: the authoritative data
--                  that settles the disputed rank-scaling rule, for EVERY talent the
--                  client can render, not just hand-picked ones
--   reports      - user "this is wrong" reports (existing ForesightDB.reports)

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Collect = {}
HM.Collect = Collect

local MAX_SESSIONS, MAX_LEVELS = 50, 100

local function store()
    if type(HM.db.collect) ~= "table" then
        HM.db.collect = { sessions = {}, levels = {} }
    end
    local c = HM.db.collect
    if type(c.sessions) ~= "table" then c.sessions = {} end
    if type(c.levels) ~= "table" then c.levels = {} end
    return c
end

local function now()
    return (_G.date and _G.date("%Y-%m-%d %H:%M:%S")) or "?"
end

local function trim(list, max)
    while #list > max do table.remove(list, 1) end
end

local function charInfo()
    local name = _G.UnitName and _G.UnitName("player") or "?"
    local _, classToken = _G.UnitClass and _G.UnitClass("player") or nil, nil
    if _G.UnitClass then _, classToken = _G.UnitClass("player") end
    local _, raceToken = _G.UnitRace and _G.UnitRace("player") or nil, nil
    if _G.UnitRace then _, raceToken = _G.UnitRace("player") end
    return {
        name = name,
        class = classToken,
        race = raceToken,
        level = _G.UnitLevel and _G.UnitLevel("player") or 0,
    }
end

function Collect.onLogin()
    local c = store()
    local info = charInfo()
    info.at = now()
    info.addonVersion = HM.version
    info.gameBuild = _G.GetBuildInfo and select(2, _G.GetBuildInfo()) or "?"
    info.dataBuild = HM.gen and HM.gen.build or "?" -- gen.build is the build STRING
    c.sessions[#c.sessions + 1] = info
    trim(c.sessions, MAX_SESSIONS)
end

function Collect.onLevelUp(newLevel)
    local c = store()
    local snap = HM.Snapshot.capture()
    c.levels[#c.levels + 1] = {
        at = now(),
        level = newLevel,
        char = charInfo().name,
        stats = snap and snap.stats or nil,
    }
    trim(c.levels, MAX_LEVELS)
end

-- Live environment verification: the S3 checklist, automated. Results are both
-- printed and persisted for the harvester.
function Collect.verify(out)
    out = out or HM.print
    local v = { at = now(), char = charInfo(), results = {} }
    local function result(name, ok, detail)
        v.results[#v.results + 1] = { name = name, ok = ok and true or false, detail = detail }
        out(("%s %s%s"):format(ok and "PASS" or "CHECK", name, detail and (" - " .. detail) or ""))
    end

    -- API shapes.
    result("classic talent API (GetTalentInfo)", _G.GetTalentInfo ~= nil and _G.GetNumTalentTabs ~= nil)

    -- Talent-API shape discovery (live-verified 2026-10-10: the classic globals are
    -- ABSENT on Forever, which disables captureTalents, the tooltip probe, and the S2
    -- hook - all degrade by design). Presence-only checks over candidate surfaces;
    -- the harvest of this result decides what S2 hooks instead.
    local candidates = {
        "GetTalentInfo", "GetNumTalentTabs", "GetNumTalents", "GetTalentTabInfo",
        "C_SpecializationInfo.GetTalentInfo", "C_SpecializationInfo.GetNumTalents",
        "C_SpecializationInfo.GetNumTalentTabs", "C_SpecializationInfo.GetTalentTabInfo",
        "C_SpecializationInfo.GetSpecialization", "C_SpecializationInfo.GetSpecializationInfo",
        "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo",
        "C_TooltipInfo.GetTalent", "TooltipDataProcessor.AddTooltipPostCall",
        "Enum.TooltipDataType.Talent", "GameTooltip.SetTalent",
    }
    local found = {}
    for _, path in ipairs(candidates) do
        local node = _G
        for part in path:gmatch("[^.]+") do
            node = (type(node) == "table" or type(node) == "userdata") and node[part] or nil
            if node == nil then break end
        end
        if node ~= nil then found[#found + 1] = path end
    end
    result("talent API shape discovery", #found > 0,
        #found > 0 and table.concat(found, ", ") or "NO candidate surface found")

    -- Adapter proof: does the normalized read path actually return data (and via
    -- which convention)? This is the line that locks the S3 answer.
    local adapterOk, adapterDetail = false, "no talent surface"
    if HM.TalentAPI and HM.TalentAPI.available() then
        local sample = HM.TalentAPI.get(1, 1)
        adapterOk = sample ~= nil
        adapterDetail = ("mode=%s sample=%s"):format(
            tostring(HM.TalentAPI.mode() or "none-answered"),
            sample and ("%s r%s/%s"):format(sample.name,
                tostring(sample.rank), tostring(sample.maxRank)) or "nil")
    end
    result("talent API adapter returns data", adapterOk, adapterDetail)
    result("C_SpecializationInfo present", _G.C_SpecializationInfo ~= nil)
    result("C_AssistedCombat present", _G.C_AssistedCombat ~= nil,
        _G.C_AssistedCombat and (_G.C_AssistedCombat.GetNextCastSpell and "has GetNextCastSpell" or "no GetNextCastSpell") or nil)
    result("secret values system present", _G.issecretvalue ~= nil or _G.C_Secrets ~= nil)
    result("C_TooltipInfo present", _G.C_TooltipInfo ~= nil)
    result("talent tooltip injection hook (S2)", HM.Tooltips and HM.Tooltips.installed or false,
        (HM.Tooltips and HM.Tooltips.installed) and "GameTooltip.SetTalent hooked" or "not installed")

    -- Live snapshot sanity.
    local snap = HM.Snapshot.capture()
    if snap then
        v.snapshot = snap
        local s = snap.stats
        result("snapshot captures stats",
            s.stamina > 0 and s.intellect > 0 and s.spirit > 0,
            ("str=%d agi=%d sta=%d int=%d spi=%d ap=%d armor=%d"):format(
                s.strength, s.agility, s.stamina, s.intellect, s.spirit, s.attackPower, s.armor))
        result("weapon speed sane", snap.weaponSpeed > 0.5 and snap.weaponSpeed < 6,
            tostring(snap.weaponSpeed))
        result("talents captured", snap.talents ~= nil, tostring(snap.talents and #snap.talents or 0) .. " talents with ranks")
    else
        result("snapshot captures stats", false, "capture returned nil")
    end

    store().verify = v
    out("verify results saved - log out (or /reload) then run the harvester")
    return v
end

-- Talent tooltip probe: renders every talent tooltip of the player's class via a
-- hidden tooltip and stores the raw text. Offline analysis compares these
-- authoritative numbers against generated data to settle the rank-scaling rule.
function Collect.probeTalentTooltips(out)
    out = out or HM.print
    if not (_G.CreateFrame and HM.TalentAPI and HM.TalentAPI.available()) then
        out("talent tooltip probe needs a talent API surface (see /foresight verify)")
        return nil
    end
    local tip = _G.ForesightScanTooltip
    if not tip then
        tip = _G.CreateFrame("GameTooltip", "ForesightScanTooltip", nil, "GameTooltipTemplate")
        tip:SetOwner(_G.UIParent, "ANCHOR_NONE")
    end
    local probe = { at = now(), char = charInfo(), talents = {} }
    for _, t in ipairs(HM.TalentAPI.all()) do
        local info = t.info
        tip:ClearLines()
        local okSet = type(tip.SetTalent) == "function" and pcall(tip.SetTalent, tip, t.tab, t.index)
        local lines = {}
        if okSet then
            for L = 1, tip:NumLines() do
                local fs = _G["ForesightScanTooltipTextLeft" .. L]
                local text = fs and fs:GetText()
                if text and text ~= "" then lines[#lines + 1] = text end
            end
        end
        probe.talents[#probe.talents + 1] = {
            tab = t.tab, index = t.index, tier = info.tier, column = info.column,
            name = info.name, rank = info.rank, maxRank = info.maxRank,
            tooltip = table.concat(lines, "\n"),
        }
    end
    probe.adapterMode = HM.TalentAPI.mode()
    store().talentProbe = probe
    out(("talent tooltip probe: captured %d talents (adapter mode %s) - log out then run the harvester")
        :format(#probe.talents, tostring(probe.adapterMode or "none")))
    return probe
end

-- Wire events (in-game only).
if _G.CreateFrame then
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_LOGIN" then
            Collect.onLogin()
        elseif event == "PLAYER_LEVEL_UP" then
            Collect.onLevelUp(arg1)
        end
    end)
end

return Collect
