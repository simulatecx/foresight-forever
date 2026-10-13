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

-- ITEM-sightings (crowd-DB phase A): journal which item IDs this character actually
-- encounters (equipped + bags), so harvested data can confirm the generated tables
-- against the LIVE game - "this item really drops/sells here" beats datamined-only.
-- IDs + a seen-counter only: no quantities, no bank, no money (privacy floor).
-- Scanned at login and logout (the SavedVariables flush points). Read-only APIs.
local MAX_SIGHTINGS = 400

function Collect.scanItems()
    local c = store()
    if type(c.itemSightings) ~= "table" then c.itemSightings = {} end
    local seen = {}
    local function note(id)
        if type(id) == "number" and id > 0 then seen[id] = true end
    end
    if _G.GetInventoryItemID then
        for slot = 1, 19 do
            local ok, id = pcall(_G.GetInventoryItemID, "player", slot)
            if ok then note(id) end
        end
    end
    local numSlots = (_G.C_Container and _G.C_Container.GetContainerNumSlots)
        or _G.GetContainerNumSlots
    local itemAt = (_G.C_Container and _G.C_Container.GetContainerItemID)
        or _G.GetContainerItemID
    if numSlots and itemAt then
        for bag = 0, 4 do
            local okN, n = pcall(numSlots, bag)
            for slot = 1, ((okN and type(n) == "number") and n or 0) do
                local ok, id = pcall(itemAt, bag, slot)
                if ok then note(id) end
            end
        end
    end
    local total, added = 0, 0
    for _ in pairs(c.itemSightings) do total = total + 1 end
    local stamp = now():sub(1, 10)
    for id in pairs(seen) do
        local e = c.itemSightings[id]
        if type(e) == "table" then
            e.c = (tonumber(e.c) or 1) + 1
            e.last = stamp
        elseif total + added < MAX_SIGHTINGS then
            c.itemSightings[id] = { c = 1, last = stamp }
            added = added + 1
        end
    end
    return seen, added
end

-- IMPACT OBSERVATORY (S11 phase A): turn real gameplay into verification data.
-- When exactly ONE known consumable buff appears or fades - and gear did not change
-- in the same window - the live stat sheet is diffed around the event and the
-- OBSERVED impact is journaled per buff spellId. The harvester compares this ground
-- truth against the generated ops, so datamined predictions get verified (or
-- corrected) by actual play. Read-only; attribution is conservative by design.
local OBSERVED_FIELDS = {
    "strength", "agility", "stamina", "intellect", "spirit", "attackPower",
    "rangedAttackPower", "spellDamage", "healingPower", "spellCritPct",
    "meleeCritPct", "rangedCritPct", "armor", "maxHealth", "maxMana",
}
local MAX_OBSERVED = 60

-- Pure: numeric stat fields that moved between two snapshots.
function Collect.statDiff(before, after)
    local out = {}
    for _, f in ipairs(OBSERVED_FIELDS) do
        local b, a = tonumber(before and before[f]), tonumber(after and after[f])
        if b and a and math.abs(a - b) > 0.01 then out[f] = a - b end
    end
    return out
end

-- op kind -> the snapshot stat fields that op is EXPECTED to move. The observatory
-- records only these for a given buff, so a coincidental gear swap or second buff in
-- the same window (big armor/stat jumps) can't pollute the ground truth - we confirm
-- what the buff CLAIMS, nothing else. A statConvert's output field; a crit op all three.
local STAT_FIELD = { Strength = "strength", Agility = "agility", Stamina = "stamina",
                     Intellect = "intellect", Spirit = "spirit" }
local CONVERT_FIELD = { attackPower = "attackPower", spellDamage = "spellDamage",
                        healingPower = "healingPower" }

-- Pure: the set of snapshot fields a buff's ops claim to move.
function Collect.claimedFields(ops)
    local claimed = {}
    for _, op in ipairs(ops or {}) do
        local k = op.kind
        if k == "stat" and STAT_FIELD[op.stat] then
            claimed[STAT_FIELD[op.stat]] = true
        elseif k == "critChance" then
            claimed.meleeCritPct = true; claimed.spellCritPct = true; claimed.rangedCritPct = true
        elseif k == "armor" then
            claimed.armor = true
        elseif k == "attackPower" then
            claimed.attackPower = true
        elseif k == "rangedAttackPower" then
            claimed.rangedAttackPower = true
        elseif k == "maxHealth" then
            claimed.maxHealth = true
        elseif k == "maxPower" and op.powerType == 0 then
            claimed.maxMana = true
        elseif (k == "schoolDamage" or k == "spellmod") then
            claimed.spellDamage = true
        elseif k == "statConvert" and CONVERT_FIELD[op.to] then
            claimed[CONVERT_FIELD[op.to]] = true
        end
    end
    return claimed
end

-- The generated ops a live aura spellId belongs to (consumable buff), for claim-filtering.
function Collect.opsForBuffSpell(spellId)
    local gen = HM.gen
    local itemId = gen and gen.buffsBySpell and gen.buffsBySpell[spellId]
    local entry = itemId and gen.consumables and gen.consumables[itemId]
    return entry and entry.ops or nil
end

-- Pure: which single tracked buff changed between two id-sets (nil unless EXACTLY
-- one, so simultaneous changes never pollute an attribution). sign: +1 gained/-1 faded.
function Collect.attributeBuffChange(oldIds, newIds)
    local changed, sign
    for id in pairs(newIds or {}) do
        if not (oldIds and oldIds[id]) then
            if changed then return nil end
            changed, sign = id, 1
        end
    end
    for id in pairs(oldIds or {}) do
        if not (newIds and newIds[id]) then
            if changed then return nil end
            changed, sign = id, -1
        end
    end
    return changed, sign
end

local lastObsSnap, lastObsBuffs, gearDirty

local function buffIdSet()
    local set = {}
    for _, b in ipairs(HM.Snapshot.captureActiveBuffs()) do set[b.spellId] = true end
    return set
end

function Collect.observe()
    local newBuffs = buffIdSet()
    local snap = HM.Snapshot.capture()
    if lastObsSnap and lastObsBuffs and not gearDirty and snap then
        local id, sign = Collect.attributeBuffChange(lastObsBuffs, newBuffs)
        if id then
            local deltas = Collect.statDiff(lastObsSnap.stats, snap.stats)
            if sign == -1 then -- a fading buff reads as losses; store the GAIN shape
                for f, v in pairs(deltas) do deltas[f] = -v end
            end
            -- Claim-filter: keep only the fields THIS buff is known to move, so a
            -- coincidental gear/other-buff change in the window can't pollute it. If we
            -- have no ops for the buff, keep the raw diff (an unknown buff to learn).
            local claimed = Collect.claimedFields(Collect.opsForBuffSpell(id))
            if next(claimed) then
                for f in pairs(deltas) do
                    if not claimed[f] then deltas[f] = nil end
                end
            end
            if next(deltas) then
                local c = store()
                if type(c.observedImpacts) ~= "table" then c.observedImpacts = {} end
                local n = 0
                for _ in pairs(c.observedImpacts) do n = n + 1 end
                local e = c.observedImpacts[id]
                if e or n < MAX_OBSERVED then
                    e = type(e) == "table" and e or {}
                    e.n = (tonumber(e.n) or 0) + 1
                    e.stats = deltas
                    e.at = now()
                    c.observedImpacts[id] = e
                end
            end
        end
    end
    gearDirty = nil
    lastObsSnap, lastObsBuffs = snap, newBuffs
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
        -- Trait-node tooltip surfaces (S2 on the Forever trait UI; SetTalent is dead).
        "Enum.TooltipDataType.TraitEntry", "GameTooltip.SetTraitEntry",
        "C_TooltipInfo.GetTraitEntry", "ClassTalentFrame", "PlayerSpellsFrame",
        -- Live buff read (CONSUME-buffs) + item identity for the missed-item journal.
        "C_UnitAuras.GetPlayerAuraBySpellID", "AuraUtil.ForEachAura", "GetItemInfoInstant",
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
        local classic, traitKnown = 0, 0
        for _, t in ipairs(sel) do
            if t.talentId then classic = classic + 1 end
            if t.talentId or t.traitKnown then traitKnown = traitKnown + 1 end
        end
        adapterOk = #sel > 0
        adapterDetail = ("mode=%s selected=%d resolved=%d (classic-mapped=%d)"):format(
            tostring(HM.TalentAPI.mode() or "none-answered"), #sel, traitKnown, classic)
    end
    result("talent API adapter returns data", adapterOk, adapterDetail)
    result("C_SpecializationInfo present", _G.C_SpecializationInfo ~= nil)
    result("C_AssistedCombat present", _G.C_AssistedCombat ~= nil,
        _G.C_AssistedCombat and (_G.C_AssistedCombat.GetNextCastSpell and "has GetNextCastSpell" or "no GetNextCastSpell") or nil)
    result("secret values system present", _G.issecretvalue ~= nil or _G.C_Secrets ~= nil)
    result("C_TooltipInfo present", _G.C_TooltipInfo ~= nil)
    result("talent tooltip injection hook (S2 classic)", HM.Tooltips and HM.Tooltips.installed or false,
        (HM.Tooltips and HM.Tooltips.installed) and "GameTooltip.SetTalent hooked" or "not installed")
    result("talent tooltip injection hook (S2 trait)", HM.Tooltips and HM.Tooltips.traitTipInstalled or false,
        (HM.Tooltips and HM.Tooltips.traitTipInstalled) and "GameTooltip.SetTraitEntry hooked" or "no trait tooltip surface")
    result("item tooltip injection hook", HM.Tooltips and HM.Tooltips.itemsInstalled or false,
        (HM.Tooltips and HM.Tooltips.itemsInstalled) and "GetItemStats path hooked" or "not installed")
    result("spell tooltip injection hook", HM.Tooltips and HM.Tooltips.spellsInstalled or false,
        (HM.Tooltips and HM.Tooltips.spellsInstalled) and "spell tooltip hooked" or "not installed")

    -- All-sources data + the stale-file-list check (incident 2026-10-11: a client
    -- running since before a deploy that ADDS toc files silently misses them).
    local stale = HM.staleCodeCheck and HM.staleCodeCheck()
    result("running code matches the loaded file list", not stale,
        stale and (stale .. " - FULL RESTART required") or ("v" .. tostring(HM.version)))
    local counts = HM.gen and HM.gen.counts or {}
    result("all-sources data loaded",
        (counts.consumables or 0) > 0 and (counts.racialSpells or 0) > 0
            and (counts.imbues or 0) > 0,
        ("consumables=%s racials=%s traitNodes=%s imbues=%s"):format(
            tostring(counts.consumables), tostring(counts.racialSpells),
            tostring(counts.traitNodes), tostring(counts.imbues)))
    result("live buff read available",
        _G.C_UnitAuras and _G.C_UnitAuras.GetPlayerAuraBySpellID ~= nil,
        _G.C_UnitAuras and "C_UnitAuras.GetPlayerAuraBySpellID" or "C_UnitAuras absent")
    local okBuffs, active = pcall(HM.Snapshot.captureActiveBuffs)
    result("active known buffs captured", okBuffs,
        okBuffs and (#active .. " active") or tostring(active))
    local okScan = pcall(Collect.scanItems)
    local sightings = 0
    for _ in pairs(store().itemSightings or {}) do sightings = sightings + 1 end
    result("item sightings journaled", okScan, sightings .. " distinct items seen")

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
        -- S25 in-game verification lever: the six retained school pools, printed so
        -- one glance against the character sheet confirms the pool law.
        local sdPools = snap.stats.schoolDamage
        result("school damage pools retained", type(sdPools) == "table", (function()
            if type(sdPools) ~= "table" then return "missing" end
            local parts = {}
            for _, name in ipairs({ "holy", "fire", "nature", "frost", "shadow", "arcane" }) do
                parts[#parts + 1] = ("%s=%d"):format(name, sdPools[name] or 0)
            end
            return table.concat(parts, " ")
        end)())
        result("talents captured", snap.talents ~= nil, tostring(snap.talents and #snap.talents or 0) .. " talents with ranks")
    else
        result("snapshot captures stats", false, "capture returned nil")
    end

    -- API DRIFT WATCHLIST (user binding 2026-10-12, after the GetItemInfo ambush):
    -- presence of every API path we depend on, journaled each login so the harvest
    -- flags any that MOVE between builds - a global-to-C_ migration at live launch
    -- becomes a report, not a silent feature outage.
    v.apiWatch = Collect.apiWatch()
    local absent = {}
    for path, present in pairs(v.apiWatch) do
        if not present then absent[#absent + 1] = path end
    end
    table.sort(absent)
    result("API watchlist journaled", true, #absent == 0 and "all present"
        or (#absent .. " absent: " .. table.concat(absent, ", ")))

    store().verify = v
    out("verify results saved - log out (or /reload) then run the harvester")
    return v
end

-- The watchlist: every external API path the addon calls, probed for PRESENCE only
-- (never called here). Both the legacy global and the C_ namespace are listed where
-- a migration pair exists. paths (optional) overrides for the selftest.
local API_WATCH = {
    "GetItemInfo", "GetItemStats", "GetItemInfoInstant",
    "C_Item.GetItemInfo", "C_Item.GetItemStats", "C_Item.GetItemInfoInstant",
    "GetInventoryItemLink", "GetInventoryItemID",
    "UnitStat", "UnitAttackSpeed", "UnitDamage", "UnitArmor", "UnitAttackPower",
    "UnitRangedAttackPower", "UnitHealthMax", "UnitPowerMax", "UnitRace", "UnitClass",
    "UnitLevel", "GetSpellBonusDamage", "GetSpellBonusHealing", "GetSpellCritChance",
    "GetCritChance", "GetRangedCritChance", "GetHaste", "GetDodgeChance",
    "GetParryChance",
    "IsPlayerSpell", "C_ClassTalents.GetActiveConfigID", "C_Traits.GetNodeInfo",
    "C_SpellBook.GetNumSpellBookSkillLines", "C_SpellBook.GetSpellBookItemInfo",
    "GetNumSpellTabs", "GetSpellBookItemInfo", "C_Spell.GetSpellTexture",
    "GetActionInfo", "IsAltKeyDown", "IsShiftKeyDown",
    "C_Traits.GetEntryInfo", "C_Traits.GetDefinitionInfo",
    "C_SpecializationInfo.GetTalentInfo",
    "C_UnitAuras.GetPlayerAuraBySpellID", "C_TooltipInfo.GetTraitEntry",
    "TooltipDataProcessor.AddTooltipPostCall", "Enum.TooltipDataType",
    "C_Timer.After", "hooksecurefunc", "Screenshot",
}

function Collect.apiWatch(paths)
    local out = {}
    for _, path in ipairs(paths or API_WATCH) do
        local node = _G
        for part in path:gmatch("[^%.]+") do
            node = (type(node) == "table") and node[part] or nil
        end
        out[path] = node ~= nil
    end
    return out
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

    -- TAINT LEAD (2026-10-12 harvest): the failing CSI.GetTalentInfo shape-guess
    -- calls error with "Lua Taint: Foresight" attached - calling a spec-system query
    -- wrong at LOGIN can taint the talent path and block protected talent actions
    -- later ("blocked from an action only available to the Blizzard UI" on opening
    -- talents). The question they probed is ANSWERED (S3: none-answered; the live
    -- path is C_Traits) - so these are now PRESENCE-ONLY, never called.
    local CSI = _G.C_SpecializationInfo or {}
    shape.calls["CSI.GetTalentInfo (presence only - call shapes retired, taint lead)"] =
        { present = type(CSI.GetTalentInfo) == "function" }
    record("CSI.GetSpecialization()", CSI.GetSpecialization)
    record("CSI.GetNumSpecializations()", CSI.GetNumSpecializations)

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
            local purchased, matched, sample, others = 0, 0, {}, 0
            for _, n in ipairs(nodes) do
                local isPurchased = (n.rank or 0) > 0
                if isPurchased then purchased = purchased + 1 end
                if n.talentId then matched = matched + 1 end
                -- Always sample purchased nodes (what the player actually has), plus a
                -- cap of other nodes for context - so the harvest shows every selection.
                if isPurchased or others < 10 then
                    if not isPurchased then others = others + 1 end
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
    f:RegisterEvent("PLAYER_LOGOUT")
    pcall(f.RegisterEvent, f, "UNIT_AURA")
    pcall(f.RegisterEvent, f, "PLAYER_EQUIPMENT_CHANGED")
    local obsPending
    f:SetScript("OnEvent", function(_, event, arg1)
        if event == "PLAYER_LOGIN" then
            Collect.onLogin()
            -- Defer the probe pass one frame so all addons/APIs have finished loading.
            if _G.C_Timer and _G.C_Timer.After then
                _G.C_Timer.After(1, function()
                    pcall(Collect.autoCollect)
                    pcall(Collect.observe) -- prime the observatory baseline
                end)
            else
                pcall(Collect.autoCollect)
            end
        elseif event == "PLAYER_LEVEL_UP" then
            Collect.onLevelUp(arg1)
            gearDirty = true -- a level-up moves stats; never attribute that to a buff
        elseif event == "PLAYER_EQUIPMENT_CHANGED" then
            gearDirty = true
        elseif event == "UNIT_AURA" and arg1 == "player" then
            -- Settle-debounced: diff once the burst of aura events quiets down.
            if not obsPending and _G.C_Timer and _G.C_Timer.After then
                obsPending = true
                _G.C_Timer.After(0.5, function()
                    obsPending = nil
                    pcall(Collect.observe)
                end)
            end
        elseif event == "PLAYER_LOGOUT" then
            -- Last write before the SavedVariables flush: the freshest sightings.
            pcall(Collect.scanItems)
        end
    end)
end

return Collect
