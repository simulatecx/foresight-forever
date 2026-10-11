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

-- Compact value describer for API-shape capture: records types and table keys
-- (depth-limited, count-capped) so an undocumented API's real return shape lands in
-- SavedVariables without dumping unbounded data. Secret/odd values never error it.
local function describe(v, depth)
    local t = type(v)
    if t == "table" then
        if depth and depth <= 0 then return "table{...}" end
        local out, n = {}, 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 24 then out["..."] = "(more keys)" break end
            out[tostring(k)] = describe(val, (depth or 2) - 1)
        end
        if n == 0 then return "table{}" end
        return out
    elseif t == "string" then
        return #v > 120 and (v:sub(1, 120) .. "...") or v
    elseif t == "number" or t == "boolean" then
        return v
    elseif t == "nil" then
        return "nil"
    else
        return t -- function, userdata, thread
    end
end
HM.describeValue = describe

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
        -- Item/spell impact surfaces (for UI-spell-tooltip + item tooltip injection).
        "Enum.TooltipDataType.Item", "Enum.TooltipDataType.Spell",
        "GetItemStats", "C_Item.GetItemStats", "GameTooltip.SetSpellByID",
        "GameTooltip.GetItem", "C_TooltipInfo.GetBagItem", "C_TooltipInfo.GetHyperlink",
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

    -- Adapter proof: does the C_Traits walk return purchased talents, and how many map
    -- back to our generated data via spellID? This line locks the S3 answer.
    local adapterOk, adapterDetail = false, "no talent surface"
    if HM.TalentAPI and HM.TalentAPI.available() then
        local sel = HM.TalentAPI.captureSelected() or {}
        local matched = 0
        for _, t in ipairs(sel) do if t.talentId then matched = matched + 1 end end
        adapterOk = #sel > 0
        adapterDetail = ("mode=%s selected=%d mapped-to-generated=%d"):format(
            tostring(HM.TalentAPI.mode() or "none-answered"), #sel, matched)
    end
    result("talent API adapter returns data", adapterOk, adapterDetail)
    result("C_SpecializationInfo present", _G.C_SpecializationInfo ~= nil)
    result("C_AssistedCombat present", _G.C_AssistedCombat ~= nil,
        _G.C_AssistedCombat and (_G.C_AssistedCombat.GetNextCastSpell and "has GetNextCastSpell" or "no GetNextCastSpell") or nil)
    result("secret values system present", _G.issecretvalue ~= nil or _G.C_Secrets ~= nil)
    result("C_TooltipInfo present", _G.C_TooltipInfo ~= nil)
    result("talent tooltip injection hook (S2)", HM.Tooltips and HM.Tooltips.installed or false,
        (HM.Tooltips and HM.Tooltips.installed) and "GameTooltip.SetTalent hooked" or "not installed")
    result("item tooltip injection hook", HM.Tooltips and HM.Tooltips.itemsInstalled or false,
        (HM.Tooltips and HM.Tooltips.itemsInstalled) and "GetItemStats path hooked" or "not installed")
    result("spell tooltip injection hook", HM.Tooltips and HM.Tooltips.spellsInstalled or false,
        (HM.Tooltips and HM.Tooltips.spellsInstalled) and "spell tooltip hooked" or "not installed")

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

-- Raw talent-API shape capture. The discovery proved C_SpecializationInfo.GetTalentInfo
-- EXISTS but no guessed calling convention returned usable data (adapter mode
-- none-answered). Rather than keep guessing in shipped code, this records the literal
-- return of each candidate call shape - table keys, scalar values, or the error string -
-- so the harvest shows the real signature and the adapter is written against ground
-- truth. Pure diagnostic: calls only info-reads, each pcall-wrapped.
function Collect.probeTalentApiShape(out)
    out = out or HM.print
    local shape = { at = now(), char = charInfo(), calls = {} }

    local function record(label, fn, ...)
        if type(fn) ~= "function" then
            shape.calls[label] = { present = false }
            return
        end
        local res = { pcall(fn, ...) }
        if res[1] then
            local returns = {}
            for i = 2, #res do returns[#returns + 1] = describe(res[i], 2) end
            shape.calls[label] = { present = true, ok = true, nreturns = #res - 1, returns = returns }
        else
            shape.calls[label] = { present = true, ok = false, err = tostring(res[2]) }
        end
    end

    local CSI = _G.C_SpecializationInfo or {}
    record("CSI.GetTalentInfo(1,1)", CSI.GetTalentInfo, 1, 1)
    record("CSI.GetTalentInfo(1,1,1)", CSI.GetTalentInfo, 1, 1, 1)
    record("CSI.GetTalentInfo{tabIndex=1,talentIndex=1}", CSI.GetTalentInfo, { tabIndex = 1, talentIndex = 1 })
    record("CSI.GetTalentInfo{tier=1,column=1}", CSI.GetTalentInfo, { tier = 1, column = 1 })
    record("CSI.GetTalentInfo{tier=1,column=1,groupIndex=1}", CSI.GetTalentInfo, { tier = 1, column = 1, groupIndex = 1 })
    record("CSI.GetSpecialization()", CSI.GetSpecialization)
    record("CSI.GetSpecializationInfo(1)", CSI.GetSpecializationInfo, 1)
    record("CSI.GetNumSpecializations()", CSI.GetNumSpecializations)
    record("CSI.GetActiveSpecGroup()", CSI.GetActiveSpecGroup)

    -- Trait/config system (the Mainline node-based path, in case talents live there).
    local CT = _G.C_ClassTalents or {}
    record("C_ClassTalents.GetActiveConfigID()", CT.GetActiveConfigID)
    local configID
    if type(CT.GetActiveConfigID) == "function" then
        local ok, id = pcall(CT.GetActiveConfigID)
        if ok then configID = id end
    end
    local CTr = _G.C_Traits or {}
    record("C_Traits.GetConfigInfo(activeConfigID=" .. tostring(configID) .. ")", CTr.GetConfigInfo, configID)

    -- Does GameTooltip:SetTalent(1,1) actually render anything? (The S2 hook target.)
    local tip = _G.ForesightScanTooltip
    if not tip and _G.CreateFrame then
        tip = _G.CreateFrame("GameTooltip", "ForesightScanTooltip", nil, "GameTooltipTemplate")
        tip:SetOwner(_G.UIParent, "ANCHOR_NONE")
    end
    if tip and type(tip.SetTalent) == "function" then
        tip:ClearLines()
        local okSet = pcall(tip.SetTalent, tip, 1, 1)
        local lines = {}
        if okSet then
            for L = 1, tip:NumLines() do
                local fs = _G["ForesightScanTooltipTextLeft" .. L]
                local txt = fs and fs:GetText()
                if txt and txt ~= "" then lines[#lines + 1] = txt end
            end
        end
        shape.setTalentProbe = { ok = okSet, lineCount = #lines, lines = lines }
    end

    -- The decisive capture: walk C_Traits exactly as the adapter does and record the
    -- live node tree (counts + a sample with spellIDs + how many map to generated data).
    -- Confirms the forever-addon-kit path on THIS client and proves the spellID bridge.
    if HM.TalentAPI and _G.C_Traits then
        local ok, nodes = pcall(HM.TalentAPI.walkTraits, false)
        if ok and type(nodes) == "table" then
            local purchased, matched, sample = 0, 0, {}
            for _, n in ipairs(nodes) do
                if (n.rank or 0) > 0 then purchased = purchased + 1 end
                if n.talentId then matched = matched + 1 end
                if #sample < 15 then
                    sample[#sample + 1] = { nodeID = n.nodeID, spellID = n.spellID,
                        rank = n.rank, maxRank = n.maxRank, talentId = n.talentId, name = n.name }
                end
            end
            shape.traitWalk = { nodes = #nodes, purchased = purchased,
                                mappedToGenerated = matched, sample = sample }
        end
    end

    store().talentApiShape = shape
    out("talent API shape probe captured - log out (or /reload) then run the harvester")
    return shape
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

-- Automatic collection pass: runs verify + the API-shape and tooltip probes once per
-- login, silently (persists for the harvester; one summary line to chat). Means a
-- player never has to type /foresight verify for us to gather data - a reload is enough.
function Collect.autoCollect()
    local silent = function() end
    local v = Collect.verify(silent)
    Collect.probeTalentApiShape(silent)
    local probe = Collect.probeTalentTooltips(silent)
    local flagged = 0
    for _, r in ipairs(v and v.results or {}) do
        if not r.ok then flagged = flagged + 1 end
    end
    HM.print(("auto-collected: verify (%d checks, %d flagged), talent probe (%d) - /foresight verify for detail")
        :format(v and #v.results or 0, flagged, probe and #probe.talents or 0))
end

-- Wire events (in-game only).
if _G.CreateFrame then
    local f = _G.CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("PLAYER_LEVEL_UP")
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_LOGIN" then
            Collect.onLogin()
            -- Defer the probe pass one frame so all addons/APIs have finished loading.
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(1, function() pcall(Collect.autoCollect) end)
            else
                pcall(Collect.autoCollect)
            end
        elseif event == "PLAYER_LEVEL_UP" then
            Collect.onLevelUp(arg1)
        end
    end)
end

return Collect
