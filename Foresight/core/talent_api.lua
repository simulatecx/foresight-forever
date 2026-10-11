-- Foresight talent API adapter.
-- GROUND TRUTH (Thunderz96/forever-addon-kit, scanned 2026-10-10): Forever talents are
-- Retail's C_Traits node trees - the classic GetTalentInfo/GetNumTalentTabs globals are
-- gone. We walk C_Traits exactly like the kit's dumpTraits: active config -> trees ->
-- nodes -> each purchased node's entry definition spellID, with node.ranksPurchased as
-- the rank. That spellID maps back to our generated classic talent via spellRanks (the
-- capture bridge, since our data is keyed by classic talent id, not trait node id).
-- Classic globals remain a fallback for any context that still exposes them. No talent
-- surface at all -> empty results (degrade-safe; never errors).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local TalentAPI = {}
HM.TalentAPI = TalentAPI

local mode -- "traits" | "classic" | nil (set once a read path yields data)

-- spellID -> our talent id, built once from generated talents' spellRanks.
local spellIndexCache
local function spellIndex()
    if spellIndexCache then return spellIndexCache end
    spellIndexCache = {}
    local talents = HM.gen and HM.gen.talents
    if talents then
        for tid, t in pairs(talents) do
            for _, sid in ipairs(t.spellRanks or {}) do
                if spellIndexCache[sid] == nil then spellIndexCache[sid] = tid end
            end
        end
    end
    return spellIndexCache
end

-- Candidate trait config IDs, gathered the way the kit's dumpTraits does.
local function traitConfigIDs()
    local CT, Traits = _G.C_ClassTalents, _G.C_Traits
    local ids, seen = {}, {}
    local function add(id) if id and not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
    if CT and CT.GetActiveConfigID then
        local ok, id = pcall(CT.GetActiveConfigID)
        if ok then add(id) end
    end
    if Traits and Traits.GetConfigsByType and _G.Enum and _G.Enum.TraitConfigType then
        for _, val in pairs(_G.Enum.TraitConfigType) do
            local ok, list = pcall(Traits.GetConfigsByType, val)
            if ok and type(list) == "table" then
                for _, id in ipairs(list) do add(id) end
            end
        end
    end
    return ids
end

-- Resolve a node's spell: prefer the active entry, else the first entry with a spell.
local function nodeSpell(configID, node)
    local Traits = _G.C_Traits
    local candidates = {}
    if node.activeEntry and node.activeEntry.entryID then candidates[1] = node.activeEntry.entryID end
    for _, eid in ipairs(node.entryIDs or {}) do candidates[#candidates + 1] = eid end
    for _, eid in ipairs(candidates) do
        local okE, entry = pcall(Traits.GetEntryInfo, configID, eid)
        if okE and type(entry) == "table" and entry.definitionID then
            local okD, def = pcall(Traits.GetDefinitionInfo, entry.definitionID)
            if okD and type(def) == "table" and def.spellID then
                return def.spellID, def.overrideName, entry.maxRanks
            end
        end
    end
    return nil
end

-- Walk C_Traits -> list of { nodeID, rank, maxRank, spellID, name, talentId }.
-- onlyPurchased=true keeps nodes with ranks > 0; false returns every node (shape probe).
-- Returns nil when C_Traits is not present (so callers can fall back).
function TalentAPI.walkTraits(onlyPurchased)
    local Traits = _G.C_Traits
    if not (Traits and Traits.GetConfigInfo and Traits.GetTreeNodes and Traits.GetNodeInfo) then
        return nil
    end
    local idx = spellIndex()
    local genNodes = HM.gen and HM.gen.traits and HM.gen.traits.nodes
    local out = {}
    for _, configID in ipairs(traitConfigIDs()) do
        local okC, info = pcall(Traits.GetConfigInfo, configID)
        if okC and type(info) == "table" then
            for _, treeID in ipairs(info.treeIDs or {}) do
                local okN, nodes = pcall(Traits.GetTreeNodes, treeID)
                for _, nodeID in ipairs(okN and nodes or {}) do
                    local okNode, node = pcall(Traits.GetNodeInfo, configID, nodeID)
                    if okNode and type(node) == "table" and node.ID and node.ID ~= 0 then
                        local rank = node.ranksPurchased or 0
                        if (not onlyPurchased) or rank > 0 then
                            local spellID, oname, emax = nodeSpell(configID, node)
                            -- Generated trait data (DATA-traits) covers EVERY node -
                            -- new Forever nodes + baseline passives, not just classic.
                            local tnode = genNodes and genNodes[nodeID]
                            out[#out + 1] = {
                                nodeID = nodeID, rank = rank,
                                maxRank = node.maxRanks or (tnode and tnode.maxRank) or emax or 1,
                                spellID = spellID or (tnode and tnode.spellID),
                                name = oname or (tnode and tnode.name),
                                talentId = spellID and idx[spellID] or nil,
                                traitKnown = tnode ~= nil,
                            }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- Is any talent surface present at all (presence, not proof it returns data).
function TalentAPI.available()
    local Traits = _G.C_Traits
    if Traits and Traits.GetConfigInfo and Traits.GetTreeNodes then return true end
    return _G.GetTalentInfo ~= nil
end

-- Selected talents for the snapshot, matched to our generated talent ids via spellID.
-- Returns { { talentId?, rank, maxRank, name, spellID, nodeID } } (or classic shape on
-- the fallback path). Locks `mode` to whichever path answered.
function TalentAPI.captureSelected()
    local traits = TalentAPI.walkTraits(true)
    if traits then
        mode = "traits"
        return traits
    end
    local out = {}
    if _G.GetTalentInfo and _G.GetNumTalentTabs and _G.GetNumTalents then
        mode = "classic"
        for tab = 1, (_G.GetNumTalentTabs() or 0) do
            for i = 1, (_G.GetNumTalents(tab) or 0) do
                local name, _, tier, column, rank, maxRank = _G.GetTalentInfo(tab, i)
                if name and rank and rank > 0 then
                    out[#out + 1] = { name = name, rank = rank, maxRank = maxRank,
                                      tier = tier, column = column }
                end
            end
        end
    end
    return out
end

-- Classic single-talent fetch (for the S2 SetTalent hook path, classic clients only;
-- returns nil on Forever, where the trait UI uses a different tooltip mechanism).
function TalentAPI.get(tab, index)
    if not _G.GetTalentInfo then return nil end
    local name, _, tier, column, rank, maxRank = _G.GetTalentInfo(tab, index)
    if not name then return nil end
    mode = mode or "classic"
    return { name = name, tier = tier, column = column, rank = rank or 0, maxRank = maxRank or 1 }
end

-- Classic flat enumeration (classic clients only; empty on Forever) - the tooltip probe
-- uses this with GameTooltip:SetTalent, which does not exist for trait nodes.
function TalentAPI.all()
    local out = {}
    if not (_G.GetTalentInfo and _G.GetNumTalentTabs and _G.GetNumTalents) then return out end
    for tab = 1, (_G.GetNumTalentTabs() or 0) do
        for i = 1, (_G.GetNumTalents(tab) or 0) do
            local name, _, tier, column, rank, maxRank = _G.GetTalentInfo(tab, i)
            if name then
                out[#out + 1] = { tab = tab, index = i, info = {
                    name = name, tier = tier, column = column,
                    rank = rank or 0, maxRank = maxRank or 1 } }
            end
        end
    end
    return out
end

-- Our classic talent id for a spell (via spellRanks), or nil. Used by the trait-node
-- tooltip hook to turn a hovered entry's spell into a talent summary.
function TalentAPI.talentForSpell(spellID)
    return spellID and spellIndex()[spellID] or nil
end

function TalentAPI.mode() return mode end

-- Test hook: clears locked state so a mocked API can't poison real in-game reads.
function TalentAPI._resetForTest() mode = nil; spellIndexCache = nil end

return TalentAPI
