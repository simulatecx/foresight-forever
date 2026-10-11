-- Foresight tooltip injection: THE one shared injection module (triage law: the future
-- spell-tooltip surface, UI-spell-tooltip, must reuse this core - never a second hook
-- system). S2 ships the talent provider: hovering a talent appends an honest Foresight
-- block - what the talent affects, what the next point is worth, and what that does to
-- your dimension scores - matching the approved design in mockups/foresight-ui.html.
--
-- Split: the resolver and line builders are pure Lua (selftest-covered headless); only
-- attach() and the hook install touch frames. Degrade law: any failure - secret values,
-- API-shape surprises, unresolvable talents - means NO injected lines, never an error.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Tooltips = {}
HM.Tooltips = Tooltips
Tooltips.installed = false

local BRAND = { r = 0.2, g = 1, b = 0.6 }
local GREY = { r = 0.62, g = 0.62, b = 0.62 }
local BODY = { r = 0.9, g = 0.9, b = 0.9 }
local MAX_AFFECTED_NAMES = 8

-- Talent resolver: classic-API position (1-based tab/tier/column) -> generated talent id ---

local CLASS_MASKS = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}

local classIndexCache

-- Per-class lookup tables built once from generated data: tab ids sorted by their
-- in-game order, talents keyed by "tabIndex:tier:column" (0-based, as generated)
-- and by lowercase name for the fallback path.
local function classIndex()
    if classIndexCache then return classIndexCache end
    local tabs = HM.gen and HM.gen.talentTabs
    local talents = HM.gen and HM.gen.talents
    if not (tabs and talents) then return nil end

    local perMask, maskToToken = {}, {}
    for tabId, tab in pairs(tabs) do
        perMask[tab.classMask] = perMask[tab.classMask] or {}
        local list = perMask[tab.classMask]
        list[#list + 1] = { id = tabId, order = tab.order }
    end
    classIndexCache = {}
    for token, mask in pairs(CLASS_MASKS) do
        maskToToken[mask] = token
        local list = perMask[mask] or {}
        table.sort(list, function(a, b) return a.order < b.order end)
        local tabIndexOf = {}
        for i, t in ipairs(list) do tabIndexOf[t.id] = i end
        classIndexCache[token] = { tabIndexOf = tabIndexOf, byPos = {}, byName = {} }
    end
    for id, t in pairs(talents) do
        local tab = tabs[t.tab]
        local entry = tab and classIndexCache[maskToToken[tab.classMask]]
        local tabIndex = entry and entry.tabIndexOf[t.tab]
        if tabIndex then
            entry.byPos[tabIndex .. ":" .. (t.tier or 0) .. ":" .. (t.column or 0)] = id
            entry.byName[(t.name or ""):lower()] = id
        end
    end
    return classIndexCache
end

-- Resolve a hovered talent to its generated id. Position (what the classic talent API
-- reports, 1-based) is primary; the displayed name arbitrates when they disagree.
function Tooltips.resolveTalent(classToken, tabIndex, tier, column, name)
    local idx = classIndex()
    local entry = idx and idx[classToken]
    if not entry then return nil end
    local id = entry.byPos[tabIndex .. ":" .. ((tier or 1) - 1) .. ":" .. ((column or 1) - 1)]
    if id and name and HM.gen.talents[id].name ~= name then
        id = nil -- position and displayed name disagree: trust the name the user sees
    end
    if not id and name then
        id = entry.byName[name:lower()]
    end
    return id
end

-- Line builders (pure) ---------------------------------------------------------

-- Generated time-type properties carry milliseconds; everything else is a plain
-- number or (isPct) a percentage.
local MS_PROPS = {
    ["cast time"] = true, ["cooldown"] = true, ["duration"] = true,
    ["global cooldown"] = true, ["activation time"] = true,
}

local function fmtValue(value, isPct, property)
    if isPct then return ("%+g%%"):format(value) end
    if property and MS_PROPS[property] then return ("%+gs"):format(value / 1000) end
    return ("%+g"):format(value)
end

-- "What does the next point do to my scores?" - diff one-more-rank against the current
-- rank. The snapshot's baked-in talent effects cancel out of the diff, so only the
-- marginal point shows. Returns nil when no dimension moves (cast time, cost and
-- cooldown ops don't fold into dimensions yet - see GRAPH-rotation-weights backlog).
local function dimFragment(loadout, talentId, rank, maxRank)
    if not loadout or rank >= maxRank then return nil end
    local ok, changes = pcall(function()
        return (HM.Impact.diff(loadout:withTalent(talentId, rank),
                               loadout:withTalent(talentId, rank + 1)))
    end)
    if not ok or type(changes) ~= "table" or #changes == 0 then return nil end
    local top = changes[1]
    local color = top.delta >= 0 and "|cff4ade80" or "|cfff87171"
    return ("-> for you now: %s%+.1f|r %s"):format(color, top.delta, top.label)
end

-- Build the injected block for a talent at the player's current rank. Returns a list
-- of { text, r, g, b, wrap } lines ({ kind = "double", left, right, ... } for the
-- header) or nil when there is nothing honest to say.
function Tooltips.talentLines(talentId, currentRank, loadout)
    local summary = HM.Impact.talentSummary(talentId)
    if not summary then return nil end
    local F = HM.formulas
    local rank = currentRank or 0
    local maxRank = summary.maxRank or 1
    local lines = {}

    local presumed = F.presumedMark(F.talentRankValue) ~= ""
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = presumed and "(p) rank rule presumed" or nil,
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }

    local affected = {}
    for _, op in ipairs(summary.ops) do
        for _, n in ipairs(op.affectedNames) do affected[#affected + 1] = n end
    end
    if #affected > 0 then
        local shown = {}
        for i = 1, math.min(#affected, MAX_AFFECTED_NAMES) do shown[i] = affected[i] end
        local more = #affected - #shown
        lines[#lines + 1] = {
            text = "|cff9d9d9dAffects:|r " .. table.concat(shown, ", ")
                .. (more > 0 and (" (+%d more)"):format(more) or ""),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
    end

    for _, op in ipairs(summary.ops) do
        if op.property and op.maxValue then
            local valueAt = function(r) return F.talentRankValue.fn(op.maxValue, r, maxRank) end
            local text
            if maxRank <= 1 then
                text = ("%s %s"):format(fmtValue(valueAt(1), op.isPct, op.property), op.property)
            elseif rank >= maxRank then
                text = ("Maxed: %s %s"):format(
                    fmtValue(valueAt(maxRank), op.isPct, op.property), op.property)
            else
                local marginal = fmtValue(valueAt(rank + 1) - valueAt(rank), op.isPct, op.property)
                local maxPart = fmtValue(valueAt(maxRank), op.isPct, op.property)
                if rank == 0 then
                    text = ("Next point: %s %s (max %s)"):format(marginal, op.property, maxPart)
                else
                    text = ("Next point: %s %s (now %s, max %s)"):format(
                        marginal, op.property,
                        fmtValue(valueAt(rank), op.isPct, op.property), maxPart)
                end
            end
            lines[#lines + 1] = { text = text, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
        end
    end

    local dim = dimFragment(loadout, talentId, rank, maxRank)
    if dim then
        lines[#lines + 1] = { text = dim, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
    end

    if summary.needsCuration then
        lines[#lines + 1] = {
            text = "Some effects aren't mapped yet - shown values may be incomplete (needs curation).",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end

    if #lines <= 1 then return nil end -- nothing beyond the header: inject nothing
    return lines
end

-- Impact block for ANY hovered trait node (classic talent OR new Forever node - the
-- generated trait data covers all 555). Shows the affected spells, each op's effect at
-- max rank, and the derived "what this does for you right now" chain. This is why a
-- talent hover answers "which of MY skills does this change, and how".
function Tooltips.nodeImpactLines(nodeId, loadout)
    local node = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nodeId]
    if not node then return nil end
    local F = HM.formulas
    local maxRank = node.maxRank or 1
    local lines = {}
    local presumed = F.presumedMark(F.talentRankValue) ~= ""
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = presumed and "(p) rank rule presumed" or nil,
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }

    local affected, seen = {}, {}
    for _, op in ipairs(node.ops or {}) do
        for _, sid in ipairs(op.affected or {}) do
            local sp = HM.gen.spells and HM.gen.spells[sid]
            if sp and sp.name and not seen[sp.name] then
                seen[sp.name] = true
                affected[#affected + 1] = sp.name
            end
        end
    end
    if #affected > 0 then
        table.sort(affected)
        local shown = {}
        for i = 1, math.min(#affected, MAX_AFFECTED_NAMES) do shown[i] = affected[i] end
        local more = #affected - #shown
        lines[#lines + 1] = {
            text = "|cff9d9d9dAffects:|r " .. table.concat(shown, ", ")
                .. (more > 0 and (" (+%d more)"):format(more) or ""),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
    end

    for _, op in ipairs(node.ops or {}) do
        local prop = op.property or op.stat
        if prop and op.maxValue then
            lines[#lines + 1] = {
                text = ("At max: %s %s"):format(
                    fmtValue(F.talentRankValue.fn(op.maxValue, maxRank, maxRank), op.isPct, op.property), prop),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end

    if loadout then
        local okc, chain = pcall(HM.Impact.talentChainLines, loadout, nodeId, maxRank)
        for _, l in ipairs(okc and chain or {}) do
            lines[#lines + 1] = { text = "  " .. l, r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
        end
    end

    -- Synergy: other talents that push the same lever (stat / mechanic / school).
    if HM.Synergy then
        local okt, themes = pcall(HM.Synergy.themesFor, nodeId)
        if okt and themes and #themes > 0 then
            local parts = {}
            for i = 1, math.min(#themes, 2) do
                parts[#parts + 1] = ("%s (+%d)"):format(themes[i].label, themes[i].others)
            end
            lines[#lines + 1] = {
                text = "|cff9d9d9dSynergy:|r " .. table.concat(parts, ", "),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end

    if node.needsCuration then
        lines[#lines + 1] = {
            text = "Some effects aren't mapped yet (needs curation).",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end

    if #lines <= 1 then return nil end
    return lines
end

-- Item provider (layman stat impact) ------------------------------------------

-- GetItemStats keys -> snapshot stat names the loadout models. v0 covers the primaries
-- plus spell power / healing power (all base graph nodes - safe to delta); gear ratings
-- (crit/haste/hit) wait until the model converts ratings.
local ITEM_STAT_MAP = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    ITEM_MOD_SPELL_POWER_SHORT = "spellDamage",
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healingPower",
}
local DISPLAY_STAT = {
    spellDamage = "Spell Power", healingPower = "Healing Power",
}
local STAT_ORDER = { "Strength", "Agility", "Stamina", "Intellect", "Spirit",
                     "spellDamage", "healingPower" }

-- Map a raw GetItemStats table to our stat names, summing duplicates.
function Tooltips.mapItemStats(raw)
    local out = {}
    if type(raw) ~= "table" then return out end
    for key, val in pairs(raw) do
        local name = ITEM_STAT_MAP[key]
        if name and type(val) == "number" then out[name] = (out[name] or 0) + val end
    end
    return out
end

-- INVTYPE -> the equipped inventory slot(s) to compare a hovered item against. First
-- matching slot that holds an item is used. Common slots only; unknown types skip.
local INVSLOT = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 }, INVTYPE_WAIST = { 6 },
    INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 }, INVTYPE_WRIST = { 9 },
    INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 }, INVTYPE_TRINKET = { 13, 14 },
    INVTYPE_CLOAK = { 15 }, INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 }, INVTYPE_RANGED = { 18 },
    INVTYPE_RANGEDRIGHT = { 18 }, INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
}

-- Build the injected block for an item's mapped stats. Returns line list or nil.
-- comparedStats (optional): the equipped item's mapped stats, for a "vs equipped" block.
function Tooltips.itemLines(mapped, loadout, comparedStats)
    if not loadout then return nil end
    local parts, any = {}, false
    for _, k in ipairs(STAT_ORDER) do
        local v = mapped[k]
        if v and v ~= 0 then
            any = true
            parts[#parts + 1] = ("%+g %s"):format(v, DISPLAY_STAT[k] or k)
        end
    end
    if not any then return nil end

    local ok, _, changes = pcall(Tooltips._itemDims, loadout, mapped)
    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight", right = "(p) for your character",
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    lines[#lines + 1] = {
        text = "|cff9d9d9dThis item:|r " .. table.concat(parts, ", "),
        r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
    }
    -- Concrete derived gains (the "+1 Agility -> +X% crit, +Y AP per swing" answer).
    local okd, derived = pcall(HM.Impact.itemDerivedLines, loadout, mapped)
    for _, l in ipairs(okd and derived or {}) do
        lines[#lines + 1] = { text = l, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
    end
    if ok and changes and #changes > 0 then
        for i = 1, math.min(#changes, 4) do
            local c = changes[i]
            local color = c.delta >= 0 and "|cff4ade80" or "|cfff87171"
            lines[#lines + 1] = {
                text = ("%s%+.1f%%|r %s"):format(color, c.pct or 0, c.label),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    elseif not (okd and derived and #derived > 0) then
        lines[#lines + 1] = {
            text = "no modeled dimension change for your class yet",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end

    -- vs equipped (DATA-items gear compare): net dimension swing of equipping this.
    if comparedStats then
        local okc, cmp = pcall(HM.Impact.compareItems, loadout, mapped, comparedStats)
        if okc and cmp and #cmp > 0 then
            local segs = {}
            for i = 1, math.min(#cmp, 3) do
                local c = cmp[i]
                local color = c.net >= 0 and "|cff4ade80" or "|cfff87171"
                segs[#segs + 1] = ("%s%+.1f%%|r %s"):format(color, c.net, c.label)
            end
            lines[#lines + 1] = {
                text = "|cff9d9d9dvs equipped:|r " .. table.concat(segs, ", "),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end
    return lines
end

-- Indirection so itemLines can pcall the model without a hard upvalue on Impact.
function Tooltips._itemDims(loadout, mapped)
    return HM.Impact.explainItemDelta(loadout, mapped)
end

-- Spell provider (UI-spell-tooltip) -------------------------------------------

-- What a spell does for YOU, honestly, from the data we actually ship: the client cast
-- time + the (p) coefficient formula translate your live Spell/Healing Power into "how
-- much of your gear lands on this button per cast". We deliberately do NOT invent a
-- flat hit number - base spell damage per rank isn't in the shipped tables yet.
function Tooltips.spellLines(spellId, loadout)
    if not loadout then return nil end
    local spell = HM.gen and HM.gen.spells and HM.gen.spells[spellId]
    if not spell then return nil end
    local s = (loadout.snapshot and loadout.snapshot.stats) or {}
    local sp, hp = s.spellDamage or 0, s.healingPower or 0
    local power, powerLabel = sp, "Spell Power"
    if hp > sp then power, powerLabel = hp, "Healing Power" end
    if power <= 0 then return nil end -- nothing of yours to translate onto this spell yet
    local castSec = (spell.castMs and spell.castMs > 0) and (spell.castMs / 1000) or 1.5
    local coef = HM.formulas.spellCoefficient.fn(castSec)
    local added = math.floor(power * coef + 0.5)

    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight", right = "(p) coefficient-based",
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    lines[#lines + 1] = {
        text = ("Your %s (+%d) adds about |cff4ade80+%d|r to this spell per cast"):format(
            powerLabel, power, added),
        r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
    }
    lines[#lines + 1] = {
        text = ("(%.0f%% coefficient at a %.1fs cast)"):format(coef * 100, castSec),
        r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
    }
    return lines
end

-- In-game wiring ---------------------------------------------------------------

local function attach(tip, lines)
    tip:AddLine(" ")
    for _, L in ipairs(lines) do
        if L.kind == "double" and L.right then
            tip:AddDoubleLine(L.left, L.right, L.r, L.g, L.b, L.r2, L.g2, L.b2)
        else
            tip:AddLine(L.text or L.left, L.r, L.g, L.b, L.wrap)
        end
    end
    tip:Show() -- recalculate tooltip height for the appended block
end

-- One injection per tooltip BUILD, re-injected on every rebuild. The flag is set before
-- attach (so attach's Show() can't recurse into us) and cleared on OnTooltipCleared, which
-- fires each time the tooltip is rebuilt - including the async item-data refresh that was
-- making our block flash then vanish.
local clearHooked = false
local function ensureClearHook()
    if clearHooked then return end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local t = _G[name]
        if t and t.HookScript then
            t:HookScript("OnTooltipCleared", function(self) self.foresightInjected = nil end)
        end
    end
    clearHooked = true
end

local function injectTalent(tip, tab, index)
    local info = HM.TalentAPI.get(tab, index)
    if not info then return end
    local _, classToken = _G.UnitClass("player")
    if not classToken then return end
    local talentId = Tooltips.resolveTalent(classToken, tab, info.tier, info.column, info.name)
    if not talentId then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local lines = Tooltips.talentLines(talentId, info.rank, loadout)
    if lines then attach(tip, lines) end
end

local function onSetTalent(tip, tab, index, inspect)
    if inspect then return end -- we model the player, never an inspected unit
    pcall(injectTalent, tip, tab, index)
end

function Tooltips.install()
    if Tooltips.installed then return true end
    local tip = _G.GameTooltip
    if not (tip and _G.hooksecurefunc and HM.TalentAPI and HM.TalentAPI.available()
            and type(tip.SetTalent) == "function") then
        return false -- headless, or API moved: degrade to no injection (S3 verify surfaces it)
    end
    -- Post-hook on THIS tooltip object only - never the shared template metatable - so
    -- the hidden ForesightScanTooltip probe keeps capturing clean, uninjected text.
    _G.hooksecurefunc(tip, "SetTalent", onSetTalent)
    Tooltips.installed = true
    return true
end

-- Item hook (shares attach/brand with the talent provider - one injection module) ----

local function resolveItemStats(link)
    local fn = (_G.C_Item and _G.C_Item.GetItemStats) or _G.GetItemStats
    if not (fn and link) then return nil end
    local ok, raw = pcall(fn, link)
    return ok and raw or nil
end

-- Mapped stats of the item currently equipped where a hovered item would go (live only,
-- no shipped item DB). nil if the slot is empty or the item isn't equippable gear.
local function equippedCompareStats(link)
    local equipLoc
    if _G.GetItemInfo then equipLoc = select(9, _G.GetItemInfo(link)) end
    local slots = equipLoc and INVSLOT[equipLoc]
    if not (slots and _G.GetInventoryItemLink) then return nil end
    for _, slot in ipairs(slots) do
        local eqLink = _G.GetInventoryItemLink("player", slot)
        if eqLink and eqLink ~= link then
            return Tooltips.mapItemStats(resolveItemStats(eqLink))
        end
    end
    return nil
end

local function injectItem(tip)
    if tip.foresightInjected then return end
    if type(tip.GetItem) ~= "function" then return end
    local _, link = tip:GetItem()
    if not link then return end
    local mapped = Tooltips.mapItemStats(resolveItemStats(link))
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local compared
    local okc, c = pcall(equippedCompareStats, link)
    if okc then compared = c end
    local lines = Tooltips.itemLines(mapped, loadout, compared)
    if lines then
        tip.foresightInjected = true
        attach(tip, lines)
    end
end

function Tooltips.installItems()
    if Tooltips.itemsInstalled then return true end
    local getStats = (_G.C_Item and _G.C_Item.GetItemStats) or _G.GetItemStats
    if not getStats then return false end
    ensureClearHook()
    local TDP, Enum = _G.TooltipDataProcessor, _G.Enum
    if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType
            and Enum.TooltipDataType.Item then
        -- Modern path: post-call fires after the item tooltip is (re)built.
        TDP.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip)
            if tip == _G.GameTooltip or tip == _G.ItemRefTooltip then pcall(injectItem, tip) end
        end)
        Tooltips.itemsInstalled = true
        return true
    end
    -- Legacy path: direct script hook.
    local tip = _G.GameTooltip
    if tip and tip.HookScript then
        tip:HookScript("OnTooltipSetItem", function(self) pcall(injectItem, self) end)
        Tooltips.itemsInstalled = true
        return true
    end
    return false
end

-- Spell hook (shares attach/brand - same one injection module) ----------------

local function injectSpell(tip, spellId)
    if tip.foresightInjected then return end
    if not spellId and type(tip.GetSpell) == "function" then
        local _, id = tip:GetSpell()
        spellId = id
    end
    if not spellId then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local lines = Tooltips.spellLines(spellId, loadout)
    if lines then
        tip.foresightInjected = true
        attach(tip, lines)
    end
end

-- Trait-node tooltip (the Forever talent UI). Live-verified: SetTalent renders nothing,
-- SetTraitEntry is NEVER called, and Enum.TooltipDataType.TraitEntry is not exposed - but
-- C_TooltipInfo.GetTraitEntry DOES exist (the 10.0.2 tooltip-data API), which is how the
-- node tooltip is built. We hook that to learn the hovered (configID, entryID), then inject
-- on the next frame once the base tooltip is populated. SetTraitEntry stays as a fallback.
local function activeConfigID()
    local CT = _G.C_ClassTalents
    if CT and CT.GetActiveConfigID then
        local ok, id = pcall(CT.GetActiveConfigID)
        if ok then return id end
    end
end

-- Resolve a (configID, entryID) to the entry's definition spell id.
local function traitEntrySpell(cfg, entryID)
    if type(entryID) ~= "number" or type(cfg) ~= "number" then return nil end
    local Traits = _G.C_Traits
    if not (Traits and Traits.GetEntryInfo and Traits.GetDefinitionInfo) then return nil end
    local okE, entry = pcall(Traits.GetEntryInfo, cfg, entryID)
    if not (okE and type(entry) == "table" and entry.definitionID) then return nil end
    local okD, def = pcall(Traits.GetDefinitionInfo, entry.definitionID)
    if okD and type(def) == "table" and def.spellID then return def.spellID end
end

-- Display-name -> nodeId index. LIVE-VERIFIED: Forever's trait UI sets GameTooltip's owner
-- to the node button, whose frame name IS the talent's name ("Ancestral Knowledge"). We
-- match that name to our generated trait node - no SetTraitEntry/GetTraitEntry needed.
local traitNameIndex
local function traitNodeByName(name)
    if type(name) ~= "string" then return nil end
    if not traitNameIndex then
        traitNameIndex = {}
        local nodes = HM.gen and HM.gen.traits and HM.gen.traits.nodes
        for nid, node in pairs(nodes or {}) do
            if node.name and traitNameIndex[node.name] == nil then traitNameIndex[node.name] = nid end
        end
    end
    return traitNameIndex[name]
end

-- Core: inject the impact block for a resolved node id, recording a diagnostic.
local function injectNodeBlock(tip, nodeId, source)
    if HM.db and type(HM.db.collect) == "table" then
        HM.db.collect.traitTipProbe = { source = source, nodeId = nodeId, injected = false }
    end
    if not nodeId or tip.foresightInjected then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local lines = Tooltips.nodeImpactLines(nodeId, loadout)
    if lines then
        tip.foresightInjected = true
        if HM.db and type(HM.db.collect) == "table" then HM.db.collect.traitTipProbe.injected = true end
        attach(tip, lines)
    end
end

local function injectTraitByEntry(tip, cfg, a, b, source)
    local spellID = traitEntrySpell(cfg, a) or traitEntrySpell(cfg, b)
        or traitEntrySpell(activeConfigID(), cfg)
    local nodeId = spellID and HM.gen and HM.gen.traits and HM.gen.traits.bySpell
        and HM.gen.traits.bySpell[spellID]
    injectNodeBlock(tip, nodeId, source)
end

function Tooltips.installTraitTooltips()
    if Tooltips.traitTipInstalled then return true end
    ensureClearHook()
    local installed = false
    local tip = _G.GameTooltip

    -- PRIMARY: match the GameTooltip owner's frame name (= the talent name) and inject on
    -- the next frame, once the base node tooltip is built.
    if tip and _G.hooksecurefunc and _G.C_Timer and type(tip.SetOwner) == "function" then
        _G.hooksecurefunc(tip, "SetOwner", function(self, owner)
            local name = owner and owner.GetName and owner:GetName()
            if HM.db and type(HM.db.collect) == "table" and name then
                HM.db.collect.lastTooltipOwner = name
            end
            local nodeId = traitNodeByName(name)
            if nodeId then
                _G.C_Timer.After(0, function()
                    if self and self.IsShown and self:IsShown() then
                        pcall(injectNodeBlock, self, nodeId, "ownerName")
                    end
                end)
            end
        end)
        installed = true
    end

    -- Fallbacks: the tooltip-data getter and SetTraitEntry, if a build uses them.
    local CTI = _G.C_TooltipInfo
    if _G.hooksecurefunc and _G.C_Timer and CTI and type(CTI.GetTraitEntry) == "function" then
        _G.hooksecurefunc(CTI, "GetTraitEntry", function(configID, entryID)
            _G.C_Timer.After(0, function()
                local gt = _G.GameTooltip
                if gt and gt.IsShown and gt:IsShown() then
                    pcall(injectTraitByEntry, gt, configID, entryID, nil, "GetTraitEntry")
                end
            end)
        end)
        installed = true
    end
    if tip and _G.hooksecurefunc and type(tip.SetTraitEntry) == "function" then
        _G.hooksecurefunc(tip, "SetTraitEntry", function(self, a, b)
            pcall(injectTraitByEntry, self, activeConfigID(), a, b, "SetTraitEntry")
        end)
    end

    Tooltips.traitTipInstalled = installed
    return installed
end

function Tooltips.installSpells()
    if Tooltips.spellsInstalled then return true end
    ensureClearHook()
    local TDP, Enum = _G.TooltipDataProcessor, _G.Enum
    if TDP and TDP.AddTooltipPostCall and Enum and Enum.TooltipDataType
            and Enum.TooltipDataType.Spell then
        TDP.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tip)
            if tip == _G.GameTooltip then pcall(injectSpell, tip, nil) end
        end)
        Tooltips.spellsInstalled = true
        return true
    end
    local tip = _G.GameTooltip
    if tip and tip.HookScript then
        tip:HookScript("OnTooltipSetSpell", function(self) pcall(injectSpell, self, nil) end)
        Tooltips.spellsInstalled = true
        return true
    end
    return false
end

if _G.CreateFrame then
    Tooltips.install()
    Tooltips.installItems()
    Tooltips.installSpells()
    Tooltips.installTraitTooltips()
end

return Tooltips
