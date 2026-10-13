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

    -- Per-talent honesty: datamined per-rank values (S21) or a crowd-verified rank
    -- rule (overrides.rankRules) drop the presumed mark for THIS talent, in green.
    local datamined = true
    for _, op in ipairs(summary.ops) do
        if not op.values then datamined = false end
    end
    datamined = datamined and #summary.ops > 0
    local verified = F.rankRuleMark and F.rankRuleMark(talentId, summary.ops) == ""
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = (verified and datamined and "rank values datamined")
            or (verified and "rank rule crowd-verified") or "(p) rank rule presumed",
        r = BRAND.r, g = BRAND.g, b = BRAND.b,
        r2 = verified and 0.29 or GREY.r, g2 = verified and 0.87 or GREY.g,
        b2 = verified and 0.50 or GREY.b,
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
            local valueAt = function(r)
                return F.talentRankValueFor(talentId, op.maxValue, r, maxRank, op.values)
            end
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
    -- Honesty header via the ONE mark: datamined per-rank values (S21) or a verified
    -- rank rule (bridged through the classic talent id) drop the (p).
    local bridgedTalent = HM.TalentAPI and HM.TalentAPI.talentForSpell and node.spellID
        and tonumber(HM.TalentAPI.talentForSpell(node.spellID)) or nil
    local presumed = F.rankRuleMark(bridgedTalent, node.ops) ~= ""
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
                    fmtValue(F.talentRankValueFor(bridgedTalent, op.maxValue, maxRank,
                        maxRank, op.values), op.isPct, op.property), prop),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end

    if loadout then
        local okc, chain = pcall(HM.Impact.talentChainLines, loadout, nodeId, maxRank)
        for _, l in ipairs(okc and chain or {}) do
            lines[#lines + 1] = { text = "  " .. l, r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
        end
        -- Context for crit talents (Thundering Strikes): show your CURRENT crit so
        -- "+1% crit" reads against a real baseline, not in a vacuum.
        local hasCrit = false
        for _, op in ipairs(node.ops or {}) do
            if op.kind == "critChance" or (op.kind == "spellmod" and op.property == "crit chance") then
                hasCrit = true
            end
        end
        local st = loadout.snapshot and loadout.snapshot.stats
        if hasCrit and st then
            lines[#lines + 1] = {
                text = ("Your crit now: %.1f%% melee, %.1f%% spell"):format(
                    st.meleeCritPct or 0, st.spellCritPct or 0),
                r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
            }
        end
        -- Ability outcome deltas (MODEL-ability-outcomes): what the next point does to
        -- the buttons this node actually modifies, before -> after. Capped at 3 lines;
        -- spells without decoded damage degrade to no line (never an invented number).
        if HM.Sim and HM.Sim.abilityHitDelta then
            local snapTalents = (loadout.snapshot and loadout.snapshot.talents) or {}
            local curRank = 0
            for _, t in ipairs(snapTalents) do
                if t.nodeId == nodeId then curRank = t.rank or 0 break end
            end
            if curRank < maxRank then
                local level = loadout.snapshot and loadout.snapshot.level
                local seenAbility, shown = {}, 0
                for _, op in ipairs(node.ops or {}) do
                    if op.kind == "spellmod" and op.property == "damage/healing" and shown < 3 then
                        for _, sid in ipairs(op.affected or {}) do
                            if shown >= 3 then break end
                            local sp = HM.gen.spells and HM.gen.spells[sid]
                            local name = sp and sp.name
                            if name and not seenAbility[name] then
                                seenAbility[name] = true
                                -- The rank the player actually casts, not the top rank.
                                local cid = HM.Sim.resolveSpellLevelCapped(name, level) or sid
                                local okD, dlt = pcall(HM.Sim.abilityHitDelta, loadout, cid,
                                    snapTalents, nodeId, curRank + 1)
                                if okD and dlt and math.abs(dlt.delta) >= 0.5 then
                                    shown = shown + 1
                                    local unit = dlt.before.kind == "heal" and "per cast" or "per hit"
                                    lines[#lines + 1] = {
                                        text = ("%s: ~%d -> ~%d %s (|cff4ade80%+d|r)%s"):format(
                                            name, math.floor(dlt.before.avg + 0.5),
                                            math.floor(dlt.after.avg + 0.5), unit,
                                            math.floor(dlt.delta + 0.5),
                                            dlt.presumed and " (p)" or ""),
                                        r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
                                    }
                                end
                            end
                        end
                    end
                end
            end
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

-- GetItemStats keys -> snapshot stat names the loadout models: primaries, spell/healing
-- power, and flat attack power (all base graph nodes - safe to delta; live catch
-- 2026-10-12: a +10 AP auction item showed NO melee impact while +3 Strength did,
-- because AP was unmapped). Gear RATINGS (crit/haste/hit) still wait until the model
-- converts ratings.
local ITEM_STAT_MAP = {
    ITEM_MOD_STRENGTH_SHORT = "Strength",
    ITEM_MOD_AGILITY_SHORT = "Agility",
    ITEM_MOD_STAMINA_SHORT = "Stamina",
    ITEM_MOD_INTELLECT_SHORT = "Intellect",
    ITEM_MOD_SPIRIT_SHORT = "Spirit",
    -- classic combined stat: damage (ALL schools) AND healing (S25 catch:
    -- the Cauldron Stirrer's +8 must raise Healing Wave too)
    ITEM_MOD_SPELL_POWER_SHORT = "spellPower",
    ITEM_MOD_DAMAGE_PER_SECOND_SHORT = "weaponDps", -- display-only (x1889 journal catch)
    ITEM_MOD_SPELL_DAMAGE_DONE_SHORT = "spellDamage",
    ITEM_MOD_SPELL_HEALING_DONE_SHORT = "healingPower",
    ITEM_MOD_ATTACK_POWER_SHORT = "attackPower",
    ITEM_MOD_RANGED_ATTACK_POWER_SHORT = "rangedAttackPower",
    ITEM_MOD_MANA_SHORT = "maxMana",
    ITEM_MOD_HEALTH_SHORT = "maxHealth",
    RESISTANCE0_NAME = "armor", -- physical resistance index 0 = armor (classic shape)
}
local DISPLAY_STAT = {
    spellPower = "Spell Power", weaponDps = "Damage Per Second",
    spellDamage = "Spell Damage", healingPower = "Healing Power",
    attackPower = "Attack Power", rangedAttackPower = "Ranged Attack Power",
    maxMana = "Mana", maxHealth = "Health", armor = "Armor",
    ["school.holy"] = "Holy Spell Damage", ["school.fire"] = "Fire Spell Damage",
    ["school.nature"] = "Nature Spell Damage", ["school.frost"] = "Frost Spell Damage",
    ["school.shadow"] = "Shadow Spell Damage", ["school.arcane"] = "Arcane Spell Damage",
    ["resist.holy"] = "Holy Resistance", ["resist.fire"] = "Fire Resistance",
    ["resist.nature"] = "Nature Resistance", ["resist.frost"] = "Frost Resistance",
    ["resist.shadow"] = "Shadow Resistance", ["resist.arcane"] = "Arcane Resistance",
}
local STAT_ORDER = { "Strength", "Agility", "Stamina", "Intellect", "Spirit",
                     "spellPower", "spellDamage", "healingPower", "attackPower", "rangedAttackPower", "weaponDps",
                     "maxMana", "maxHealth", "armor",
                     "school.holy", "school.fire", "school.nature", "school.frost",
                     "school.shadow", "school.arcane",
                     "resist.holy", "resist.fire", "resist.nature", "resist.frost",
                     "resist.shadow", "resist.arcane" }

-- Elemental resistances (2026-10-13 journal triage, x1239-1585 sightings each):
-- display-only like weaponDps - no graph node models mitigation yet. The client emits
-- BOTH key shapes for the same stat on the same item (RESISTANCE2_NAME +
-- ITEM_MOD_FIRE_RESISTANCE_SHORT arrived with identical journal counts), so the index
-- shape maps only when its named twin is absent - summing twins would double-count.
-- Index enum 1-6 = holy/fire/nature/frost/shadow/arcane (0 = armor above,
-- classic shape).
local RESIST_INDEX = {
    RESISTANCE1_NAME = { "holy",   "ITEM_MOD_HOLY_RESISTANCE_SHORT" },
    RESISTANCE2_NAME = { "fire",   "ITEM_MOD_FIRE_RESISTANCE_SHORT" },
    RESISTANCE3_NAME = { "nature", "ITEM_MOD_NATURE_RESISTANCE_SHORT" },
    RESISTANCE4_NAME = { "frost",  "ITEM_MOD_FROST_RESISTANCE_SHORT" },
    RESISTANCE5_NAME = { "shadow", "ITEM_MOD_SHADOW_RESISTANCE_SHORT" },
    RESISTANCE6_NAME = { "arcane", "ITEM_MOD_ARCANE_RESISTANCE_SHORT" },
}

-- S25: per-school item damage keys translate by PATTERN (the ITEM_MOD_<SCHOOL>_SPELL_
-- DAMAGE family); the unknownItemStats journal stays the tripwire for any key shape
-- Forever actually emits that this misses.
local SCHOOL_KEY_NAMES = { HOLY = "holy", FIRE = "fire", NATURE = "nature",
                           FROST = "frost", SHADOW = "shadow", ARCANE = "arcane" }

-- Map a raw GetItemStats table to our stat names, summing duplicates. Second return:
-- the keys we did NOT map (the AP live catch proved silent drops hide real impact -
-- unknowns get journaled so the harvest surfaces what Forever items actually carry).
function Tooltips.mapItemStats(raw)
    local out, unknown = {}, {}
    if type(raw) ~= "table" then return out, unknown end
    for key, val in pairs(raw) do
        local name, twinSkip = ITEM_STAT_MAP[key], false
        if not name and type(key) == "string" then
            local school = key:match("^ITEM_MOD_(%u+)_SPELL_DAMAGE")
            if school and SCHOOL_KEY_NAMES[school] then
                name = "school." .. SCHOOL_KEY_NAMES[school]
            end
            if not name then
                local rschool = key:match("^ITEM_MOD_(%u+)_RESISTANCE")
                if rschool and SCHOOL_KEY_NAMES[rschool] then
                    name = "resist." .. SCHOOL_KEY_NAMES[rschool]
                end
            end
            if not name then
                local twin = RESIST_INDEX[key]
                if twin then
                    if raw[twin[2]] == nil then
                        name = "resist." .. twin[1]
                    else
                        twinSkip = true -- named twin carries the value; not unknown
                    end
                end
            end
        end
        if name and type(val) == "number" then
            out[name] = (out[name] or 0) + val
        elseif not twinSkip and type(val) == "number" and val ~= 0 then
            unknown[#unknown + 1] = tostring(key)
        end
    end
    return out, unknown
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

-- Pure (weapon-swap honesty): pull base damage range + speed out of an item
-- tooltip's text lines ("18 - 27 Damage" left, "Speed 2.60" right; enUS house
-- state). Bonus-damage lines ("+1 - 5 Nature Damage") don't match the anchored
-- pattern - only the weapon's own range is claimed. nil when not a weapon.
function Tooltips.parseWeaponTip(lines)
    local dmin, dmax, speed
    for _, t in ipairs(lines or {}) do
        if type(t) == "string" then
            if not dmin then
                local a, b = t:match("^%s*([%d,]+)%s*%-%s*([%d,]+)%s+Damage")
                if a then
                    dmin = tonumber((a:gsub(",", "")))
                    dmax = tonumber((b:gsub(",", "")))
                end
            end
            if not speed then
                local s = t:match("Speed%s+([%d%.]+)")
                if s then speed = tonumber(s) end
            end
        end
    end
    if dmin and dmax and speed and speed > 0 then
        return { min = dmin, max = dmax, speed = speed }
    end
    return nil
end

-- Pure (baseline-detection fix, live catch 2026-10-12: an EQUIPPED weapon still
-- showed "+2.8" because exact link-string equality fails - WoW item links carry
-- volatile trailing fields like linkLevel that differ between the paper-doll hover
-- and GetInventoryItemLink for the SAME item). The stable identity = the first 8
-- payload fields (itemID:enchant:gems x4:suffix:uniqueID); everything after is
-- context, not identity.
function Tooltips.itemKey(link)
    if type(link) ~= "string" then return nil end
    local payload = link:match("item:([%-%d:]*)")
    if not payload then return nil end
    local fields = {}
    for f in (payload .. ":"):gmatch("([^:]*):") do
        fields[#fields + 1] = f
        if #fields >= 8 then break end
    end
    if not fields[1] or fields[1] == "" then return nil end
    return table.concat(fields, ":")
end

local function sameItem(linkA, linkB)
    local a, b = Tooltips.itemKey(linkA), Tooltips.itemKey(linkB)
    return a ~= nil and a == b
end

-- Pure (prevalidation audit): pull the "X to Y" damage/heal range out of a rendered
-- SPELL tooltip's text lines (enUS: "...for 25 to 30 Nature damage.", "...heals ...
-- for 40 to 47."). First range wins; comma numbers handled; nil when no range shows.
function Tooltips.parseSpellRange(lines)
    for _, t in ipairs(lines or {}) do
        if type(t) == "string" then
            local a, b = t:match("([%d,]+)%s+to%s+([%d,]+)")
            if a then
                local lo = tonumber((a:gsub(",", "")))
                local hi = tonumber((b:gsub(",", "")))
                if lo and hi and hi >= lo then return lo, hi end
            end
        end
    end
    return nil
end

-- Pure (capture no-downgrade law): a TRAINED talent-tooltip capture (rank known) is
-- rank-scaling ground truth - a later untrained hover must never overwrite it (live
-- catch 2026-10-12: Deflection's trained capture degraded to a weak untrained vote
-- after a re-hover). Newer trained captures always win.
function Tooltips.shouldReplaceCapture(old, new)
    if not old then return true end
    if old.rank ~= nil and not (new and new.rank ~= nil) then return false end
    return true
end

-- SIM-engine "Pro highlight": hovering a WEAPON while a Windfury-style imbue is
-- known - slower weapons raise the proc's bonus-AP term. Honest scope: compares the
-- AP term only (the hovered weapon's base damage isn't in the offline data; the
-- label says "AP term" so no larger claim is made).
function Tooltips.windfuryWeaponLine(snapshot, imbueEntry, hoverSpeedSec)
    if not (snapshot and imbueEntry and imbueEntry.extraAttacks and hoverSpeedSec) then
        return nil
    end
    local cur = snapshot.weaponSpeed or 2.0
    if math.abs(hoverSpeedSec - cur) < 0.05 then return nil end
    local x = imbueEntry.extraAttacks
    local per = (x.bonusAp or 0) / 14 * (hoverSpeedSec - cur) * (x.count or 1)
    if per >= 0.5 then
        return ("Windfury engine: at %.1fs this weapon adds ~+%.0f to each proc burst vs your %.1fs weapon (AP term) (p)")
            :format(hoverSpeedSec, per, cur)
    elseif per <= -0.5 then
        return ("Windfury engine: at %.1fs this weapon gives up ~%.0f per proc burst vs your %.1fs weapon (AP term) (p)")
            :format(hoverSpeedSec, -per, cur)
    end
    return nil
end

-- Build the injected block for an item's mapped stats. Returns line list or nil.
-- comparedStats (optional): the equipped item's mapped stats, for a "vs equipped" block.
-- ctx (optional): { itemId, speedMs, wfImbue } - offline weapon context for the
-- Windfury-engine synergy line.
function Tooltips.itemLines(mapped, loadout, comparedStats, ctx)
    if not loadout then return nil end
    local parts, any = {}, false
    for _, k in ipairs(STAT_ORDER) do
        local v = mapped[k]
        if v and v ~= 0 then
            any = true
            parts[#parts + 1] = ("%+g %s"):format(v, DISPLAY_STAT[k] or k)
        end
    end
    -- A stat-less WEAPON still gets judged - its damage range IS the item (the S20
    -- user binding: count everything the item brings, weapon DPS included) - and an
    -- uncomparable weapon still says why.
    if not any and not (ctx and (ctx.weaponSwap or ctx.weaponSwapWhy)) then return nil end

    local equipped = ctx and ctx.equipped
    local ok, _, changes = pcall(Tooltips._itemDims, loadout, mapped)
    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = equipped and "equipped - your baseline" or "(p) for your character",
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    if equipped then
        -- BASELINE LAW (user binding 2026-10-12): once an item is ON the character it
        -- IS the base - its stats are already in every number we show, so claiming a
        -- "+%" for it would double-count. Show what it contributes, never a gain.
        lines[#lines + 1] = {
            text = "You're wearing this - it's your baseline. Hover alternatives to compare.",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    else
        -- Headline verdict (the Pawn-style at-a-glance answer, judged for your goal).
        local goal = HM.gearGoal and HM.gearGoal() or "auto"
        local okv, verdict = pcall(HM.Impact.itemVerdict, loadout, mapped, comparedStats,
            goal, ctx and ctx.weaponSwap)
        if okv and verdict then
            -- S27: the ONE verdict shape (Display grammar).
            local word = verdict.direction == "upgrade" and "Upgrade"
                or verdict.direction == "downgrade" and "Downgrade" or "Sidegrade"
            lines[#lines + 1] = {
                text = HM.Display.verdict(word, verdict.label, verdict.pct)
                    .. (verdict.compared and "" or " |cff9d9d9d(added)|r"),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
            if verdict.note then
                lines[#lines + 1] = { text = verdict.note,
                    r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
            end
            -- S28b: ONE plan-relevance line - a world drop that serves a saved plan
            -- goal says so in concrete units, never on equipped gear (baseline law).
            local okP, planLine = pcall(Tooltips._planRelevanceLine, loadout, mapped,
                comparedStats)
            if okP and planLine then
                lines[#lines + 1] = { text = planLine,
                    r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
            end
        end
        -- Weapon-swap rows (the honest A->B of equipping this weapon): from -> to in
        -- real units, red when it's a loss - base ranges from both tooltips + your AP
        -- through Sim.weaponSwap. A weapon hover that CAN'T compare says why, never
        -- silently falls back to stat-only rows.
        if ctx and ctx.weaponSwap then
            local w = ctx.weaponSwap
            local net = w.newDps - w.curDps
            local color = (w.pct >= 0.5 and "|cff4ade80")
                or (w.pct <= -0.5 and "|cfff87171") or "|cff9d9d9d"
            lines[#lines + 1] = {
                -- S27: the ONE comparison shape (Display grammar), direction-colored.
                text = "|cff9d9d9dMelee DPS change:|r " .. color
                    .. HM.Display.comparison(w.curDps, w.newDps, "DPS") .. "|r (p)",
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
            -- The explain layer (user binding 2026-10-12): the game already prints the
            -- component diffs - we COMPOSE them: weapon term + stat term = the net.
            lines[#lines + 1] = {
                text = (math.abs(w.apDelta or 0) >= 0.5)
                    and ("= weapon %+.1f DPS; its stats are worth %+.0f AP = %+.1f DPS (14 AP = 1 DPS for you (p))")
                        :format(w.weaponDpsDelta, w.apDelta, w.statDpsDelta)
                    or ("= weapon %+.1f DPS (no stat difference between them)")
                        :format(w.weaponDpsDelta),
                r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
            }
        elseif ctx and ctx.weaponSwapWhy then
            lines[#lines + 1] = {
                text = "weapon compare unavailable: " .. ctx.weaponSwapWhy,
                r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
            }
        end
    end
    -- S20 coaching attribution, BENEATH the verdict it never alters: fires only when
    -- the item's largest stat is the mechanism-dead stat for the focus lens.
    local okCoach, coach = pcall(HM.Impact.coachingItemLine, loadout, mapped)
    if okCoach and coach then
        lines[#lines + 1] = { text = coach, r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
    end
    -- Archetype shift (SIM-engine): when the swap changes the plain-English standing
    -- of the whole build, say so prominently - that is a bigger call than +x%.
    -- (Suppressed for your own equipped item: re-adding its stats is a false shift.)
    if HM.Sim and not equipped and (not HM.showSetting or HM.showSetting("standing")) then
        local oks, shift = pcall(HM.Sim.standingShift, loadout, mapped, comparedStats)
        if oks and shift then
            lines[#lines + 1] = {
                text = ("|cfffbbf24Shifts your build:|r %s -> %s (p)")
                    :format(shift.from, shift.to),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end
    -- Windfury-engine weapon synergy (SIM-engine): offline speed from the gear DB.
    if ctx and ctx.speedMs and ctx.wfImbue then
        local wline = Tooltips.windfuryWeaponLine(loadout.snapshot, ctx.wfImbue,
            ctx.speedMs / 1000)
        if wline then
            lines[#lines + 1] = {
                text = "|cff4ade80" .. wline .. "|r",
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
    end
    if any then
        lines[#lines + 1] = {
            text = (equipped and "|cff9d9d9dGiving you:|r " or "|cff9d9d9dThis item:|r ")
                .. table.concat(parts, ", "),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
    end
    -- Concrete derived lines (the "+1 Agility -> +X% crit, +Y AP per swing" answer).
    -- SWAP-RELATIVE when something comparable is equipped (user binding 2026-10-12:
    -- assess vs what is on your character at the time - a worse weapon must read
    -- NEGATIVE, never as an add to an empty slot). For an equipped item they read as
    -- the current CONTRIBUTION (absolute units, no % claim).
    local okd, derived = pcall(HM.Impact.itemDerivedLines, loadout, mapped,
        (not equipped) and comparedStats or nil)
    for _, l in ipairs(okd and derived or {}) do
        lines[#lines + 1] = { text = l, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
    end
    if equipped then
        -- No % dimension lines on your own gear: it is the base, not a change.
        local _ = nil
    elseif comparedStats then
        -- The NET swap per dimension IS the primary block when you wear a comparable.
        local okc, cmp = pcall(HM.Impact.compareItems, loadout, mapped, comparedStats)
        local rows = okc and cmp or {}
        -- CONSISTENCY LAW (live catch 2026-10-12: verdict said +17%% while this block
        -- said -1.2%% Melee DPS): for weapon hovers the melee row IS the weapon-aware
        -- swap number - one claim, one number, everywhere.
        if ctx and ctx.weaponSwap and type(ctx.weaponSwap.pct) == "number" then
            local replaced = false
            for _, c in ipairs(rows) do
                if c.id == "meleeDps" then
                    c.net = ctx.weaponSwap.pct
                    replaced = true
                end
            end
            if not replaced then
                rows[#rows + 1] = { id = "meleeDps", label = "Melee DPS",
                                    net = ctx.weaponSwap.pct }
            end
            table.sort(rows, function(x, y) return math.abs(x.net) > math.abs(y.net) end)
        end
        -- What-is-this-FOR lines (user ask 2026-10-12): when the swap moves caster
        -- inputs, name YOUR abilities it improves in their units.
        local okRel, rel = pcall(Tooltips._casterRelevanceLines, loadout, mapped,
            comparedStats)
        for i = 1, math.min(#rows, 4) do
            local c = rows[i]
            local color = c.net >= 0 and "|cff4ade80" or "|cfff87171"
            lines[#lines + 1] = {
                text = ("%s%+.1f%%|r %s |cff9d9d9d(vs equipped)|r"):format(
                    color, c.net, c.label),
                r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
            }
        end
        for _, l in ipairs(okRel and rel or {}) do
            lines[#lines + 1] = { text = l, r = BODY.r, g = BODY.g, b = BODY.b, wrap = true }
        end
    elseif ok and changes and #changes > 0 then
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
    return lines
end

-- Indirection so itemLines can pcall the model without a hard upvalue on Impact.
function Tooltips._itemDims(loadout, mapped)
    return HM.Impact.explainItemDelta(loadout, mapped)
end

-- S28b: the ONE plan-relevance line. When a saved plan has goal abilities, compute
-- the hovered item's net-swap effect on each and name the STRONGEST POSITIVE one in
-- concrete units - never a "closeness %%", never more than one line.
function Tooltips._planRelevanceLine(loadout, mapped, comparedStats)
    if not (loadout and HM.Plan and HM.Plan.goals and HM.Sim and HM.Sim.abilityHit) then
        return nil
    end
    local goals = HM.Plan.goals()
    if #goals == 0 then return nil end
    local modeled = loadout
    local function fold(bundle, sign)
        for stat, v in pairs(bundle or {}) do
            if type(v) == "number" and v ~= 0 and stat ~= "weaponDps"
                    and not stat:find("^resist%.") then
                modeled = modeled:withStatDelta(stat, sign * v, "planswap:" .. stat)
            end
        end
    end
    fold(comparedStats, -1)
    fold(mapped, 1)
    local bestName, bestDelta, bestKind
    for _, sid in ipairs(goals) do
        local okB, b = pcall(HM.Sim.abilityHit, loadout, sid, {})
        local okA, a = pcall(HM.Sim.abilityHit, modeled, sid, {})
        if okB and okA and b and a then
            local d = a.avg - b.avg
            if d >= 0.5 and (not bestDelta or d > bestDelta) then
                local sp = HM.gen.spells[sid]
                bestName, bestDelta, bestKind = sp and sp.name, d, a.kind
            end
        end
    end
    if not bestName then return nil end
    return ("|cff9d9d9dYour '%s' plan:|r this adds |cff4ade80~%+.1f|r per %s (p)")
        :format(bestName, bestDelta, bestKind == "heal" and "cast" or "hit")
end

-- "What is this FOR" (user ask 2026-10-12): when a swap moves caster inputs (spell
-- power, school damage, healing), compute the net effect on YOUR best known damage
-- spell and heal via abilityHit and say it in their units: "With this: Lightning
-- Bolt +3 per hit, Healing Wave +3 per cast (p)". In-game only (IsPlayerSpell);
-- max two lines; |delta| < 0.5 says nothing.
local CASTER_KEYS = { "spellPower", "spellDamage", "healingPower", "school.holy",
    "school.fire", "school.nature", "school.frost", "school.shadow", "school.arcane" }
local knownCasterPicks -- session cache: new ranks land on the next /reload

function Tooltips._casterRelevanceLines(loadout, mapped, comparedStats)
    if not (loadout and HM.Sim and HM.Sim.abilityHit and _G.IsPlayerSpell) then
        return {}
    end
    local moves = false
    for _, k in ipairs(CASTER_KEYS) do
        if ((mapped and mapped[k]) or 0) ~= 0
                or ((comparedStats and comparedStats[k]) or 0) ~= 0 then
            moves = true
            break
        end
    end
    if not moves then return {} end
    if not knownCasterPicks then
        local bestDmg, bestHeal
        local spells = (HM.gen and HM.gen.spells) or {}
        for sid, sp in pairs(spells) do
            if _G.IsPlayerSpell(sid) then
                if sp.dmg and not sp.wpn and (not bestDmg
                        or (sp.level or 0) > (spells[bestDmg].level or 0)) then
                    bestDmg = sid
                end
                if sp.heal and not sp.dmg and (not bestHeal
                        or (sp.level or 0) > (spells[bestHeal].level or 0)) then
                    bestHeal = sid
                end
            end
        end
        knownCasterPicks = { bestDmg, bestHeal }
    end
    -- Net-of-swap modeled loadout (baseline law: minus equipped, plus hovered).
    local modeled = loadout
    local function fold(bundle, sign)
        for stat, v in pairs(bundle or {}) do
            if type(v) == "number" and v ~= 0 and stat ~= "weaponDps"
                    and not stat:find("^resist%.") then
                modeled = modeled:withStatDelta(stat, sign * v,
                    ("swap:%s"):format(stat))
            end
        end
    end
    fold(comparedStats, -1)
    fold(mapped, 1)
    local out = {}
    for _, sid in ipairs(knownCasterPicks) do
        local okB, b = pcall(HM.Sim.abilityHit, loadout, sid, {})
        local okA, a = pcall(HM.Sim.abilityHit, modeled, sid, {})
        if okB and okA and b and a and math.abs(a.avg - b.avg) >= 0.5 then
            local sp = HM.gen.spells[sid]
            local color = (a.avg > b.avg) and "|cff4ade80" or "|cfff87171"
            out[#out + 1] = ("|cff9d9d9dWith this:|r %s %s%+.0f|r per %s (p)"):format(
                sp.name, color, a.avg - b.avg, a.kind == "heal" and "cast" or "hit")
        end
    end
    return out
end

-- Consumable-buff provider (CONSUME-buffs) --------------------------------------

local function fmtDuration(ms)
    local s = math.floor(ms / 1000 + 0.5)
    if s >= 3600 and s % 3600 == 0 then return (s / 3600) .. "h" end
    if s >= 60 then return math.floor(s / 60 + 0.5) .. "m" end
    return s .. "s"
end

-- One human fragment per decoded op; nil for unmapped kinds (honesty: never invent).
local POWER_NAMES = { [0] = "mana", [1] = "rage", [3] = "energy" }
local function describeOp(op)
    local v = op.maxValue or 0
    if op.kind == "stat" then
        return ("%s %s"):format(fmtValue(v, op.isPct), op.stat or "stat")
    elseif op.kind == "schoolDamage" then
        return ("%s %s spell damage"):format(fmtValue(v, op.isPct), op.school or "")
    elseif op.kind == "maxHealth" then
        return ("%s max health"):format(fmtValue(v, op.isPct))
    elseif op.kind == "maxPower" then
        return ("%s max %s"):format(fmtValue(v, op.isPct), POWER_NAMES[op.powerType] or "power")
    elseif op.kind == "armor" then
        return ("%s armor"):format(fmtValue(v, false))
    elseif op.kind == "attackPower" then
        return ("%s Attack Power"):format(fmtValue(v, false))
    elseif op.kind == "rangedAttackPower" then
        return ("%s ranged Attack Power"):format(fmtValue(v, false))
    elseif op.kind == "critChance" then
        return ("%s crit chance"):format(fmtValue(v, true))
    elseif op.kind == "threat" then
        return ("%s %s"):format(fmtValue(v, true), op.property or "threat")
    elseif op.kind == "spellmod" and op.property then
        return ("%s %s"):format(fmtValue(v, op.isPct, op.property), op.property)
    elseif op.kind == "aura" and op.label then
        return ("%s %s"):format(fmtValue(v, op.isPct), op.label)
    end
    return nil
end
Tooltips.describeOp = describeOp -- shared with /foresight buffs

-- Build the injected block for a consumable with generated buff data: what it is worth
-- for YOUR character while active - and the honest reminder that expiry reverses it.
function Tooltips.buffLines(itemId, loadout)
    local entry = HM.gen and HM.gen.consumables and HM.gen.consumables[itemId]
    if not entry then return nil end
    local parts = {}
    for _, op in ipairs(entry.ops or {}) do
        parts[#parts + 1] = describeOp(op)
    end
    if #parts == 0 then return nil end

    -- Play verification (S11): a k-of-n + human-reviewed overrides entry upgrades the
    -- presumed tag - real gameplay confirmed these numbers at that build.
    local verified = HM.overrides and HM.overrides.verifiedBuffs
        and HM.overrides.verifiedBuffs[itemId]
    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = verified and ("play-verified " .. (verified.build or ""))
            or ("(p) " .. (entry.confidence or "classic-presumed")),
        r = BRAND.r, g = BRAND.g, b = BRAND.b,
        r2 = verified and 0.29 or GREY.r, g2 = verified and 0.87 or GREY.g,
        b2 = verified and 0.50 or GREY.b,
    }
    lines[#lines + 1] = {
        text = ("|cff9d9d9dWhile active:|r %s%s"):format(table.concat(parts, ", "),
            entry.durationMs and (" (" .. fmtDuration(entry.durationMs) .. ")") or ""),
        r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
    }
    if loadout then
        local okc, chain = pcall(HM.Impact.buffDelta, loadout, itemId)
        for _, l in ipairs(okc and chain or {}) do
            lines[#lines + 1] = { text = "  " .. l, r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
        end
    end
    lines[#lines + 1] = {
        text = "On expiry these gains reverse.",
        r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
    }
    return lines
end

-- Spell provider (UI-spell-tooltip) -------------------------------------------

-- What a spell does for YOU, honestly, from the data we actually ship. The decoded
-- SpellEffect base (MODEL-ability-outcomes) composes with your live numbers into an
-- absolute "hits for ~X-Y" lead line; the coefficient block translates your Spell/
-- Healing Power per cast. Spells without decoded fields keep the coefficient-only
-- block (nil-degrade: no absolute line is ever invented).
function Tooltips.spellLines(spellId, loadout)
    if not loadout then return nil end
    local spell = HM.gen and HM.gen.spells and HM.gen.spells[spellId]
    if not spell then return nil end
    local s = (loadout.snapshot and loadout.snapshot.stats) or {}
    local sp, hp = s.spellDamage or 0, s.healingPower or 0
    local power, powerLabel = sp, "Spell Power"
    if hp > sp then power, powerLabel = hp, "Healing Power" end

    -- The absolute answer, when the decode covers this button.
    local hit
    if HM.Sim and HM.Sim.abilityHit then
        local okH, h = pcall(HM.Sim.abilityHit, loadout, spellId,
            { selected = loadout.snapshot and loadout.snapshot.talents })
        hit = okH and h or nil
    end
    if not hit and power <= 0 and not spell.grants then
        return nil -- nothing of yours to translate yet
    end
    local castSec = (spell.castMs and spell.castMs > 0) and (spell.castMs / 1000) or 1.5
    -- Prefer the datamined coefficient when the decode carries one; else the (p) formula.
    local coef = (hit and hit.coef) or HM.formulas.spellCoefficient.fn(castSec)
    local added = math.floor(power * coef + 0.5)

    local lines = {}
    local headerRight = "(p) coefficient-based"
    if hit and hit.coefSource == "data" then headerRight = "datamined coefficient"
    elseif hit and hit.kind == "weapon" then headerRight = "(p) with your weapon"
    elseif not hit and spell.grants then headerRight = "(p) buff chain" end
    lines[#lines + 1] = {
        kind = "double", left = "Foresight", right = headerRight,
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    -- Buff-granting abilities (totems, v0.34.0 user ask): the chain from the buff's
    -- stats to YOUR numbers - "+7 Strength -> +14 Attack Power -> ~+1.3 per swing" -
    -- short and simple, on the button that drops it. Rides statImpactDetail (the ONE
    -- stat-chain path); non-stat grants get the shared describeOp line.
    if spell.grants then
        for _, op in ipairs(spell.grants) do
            if op.kind == "stat" and op.stat and not op.isPct and (op.maxValue or 0) > 0 then
                lines[#lines + 1] = {
                    text = ("|cff9d9d9dIts buff gives you:|r +%g %s"):format(
                        op.maxValue, op.stat),
                    r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
                }
                local okc, chain = pcall(HM.Impact.statImpactDetail, loadout,
                    op.stat, op.maxValue)
                for i = 1, math.min(#(okc and chain or {}), 3) do
                    lines[#lines + 1] = { text = "  " .. chain[i],
                        r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
                end
            else
                local desc = describeOp(op)
                if desc then
                    lines[#lines + 1] = {
                        text = "|cff9d9d9dIts buff gives you:|r " .. desc,
                        r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
                    }
                end
            end
        end
    end
    if hit then
        -- Widest integer envelope (floor min, ceil max) - matches the game's own
        -- rendering, live-verified on Lightning Bolt r2 (25 to 30).
        local lo, hi = HM.formulas.spellBaseDamage.display(hit.min, hit.max, hit.kind)
        local range = (lo == hi) and ("~%d"):format(lo) or ("~%d-%d"):format(lo, hi)
        lines[#lines + 1] = {
            text = ("%s for |cff4ade80%s|r with your gear%s"):format(
                hit.kind == "heal" and "Heals" or "Hits", range,
                hit.presumed and " (p)" or ""),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
        if (hit.critPct or 0) > 0 then
            lines[#lines + 1] = {
                text = ("crits for ~%gx at your %.1f%% crit (p)"):format(
                    hit.critMult or 2, hit.critPct),
                r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
            }
        end
    end
    -- Power translation: only where spell power actually lands (never on weapon hits).
    if power > 0 and not (hit and hit.kind == "weapon") then
        lines[#lines + 1] = {
            text = ("Your %s (+%d) adds about |cff4ade80+%d|r to this spell per cast"):format(
                powerLabel, power, added),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
        lines[#lines + 1] = {
            text = (hit and hit.coefSource == "data")
                and ("(%.0f%% coefficient, datamined)"):format(coef * 100)
                or ("(%.0f%% coefficient at a %.1fs cast)"):format(coef * 100, castSec),
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end
    -- Resource economy (SIM-engine): what chain-casting this does to your mana pool.
    local okO, oom
    if HM.Sim then okO, oom = pcall(HM.Sim.timeToOOM, loadout, spellId) end
    if okO and oom then
        lines[#lines + 1] = {
            text = ("Chain-cast: ~%d casts, empty mana in ~%ds (p)")
                :format(oom.casts, math.floor(oom.seconds + 0.5)),
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end
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
-- making our block flash then vanish. TAINT ISOLATION: the flag lives in OUR weak-keyed
-- table - Foresight writes no key onto any Blizzard object, ever.
local injectedTips = setmetatable({}, { __mode = "k" })
local clearHooked = false
local function ensureClearHook()
    if clearHooked then return end
    for _, name in ipairs({ "GameTooltip", "ItemRefTooltip" }) do
        local t = _G[name]
        if t and t.HookScript then
            t:HookScript("OnTooltipCleared", function(self) injectedTips[self] = nil end)
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

-- All item-API access rides HM.Client (core/client.lua) - the ONE namespacing swap
-- point (the GetItemInfo live catch, 2026-10-12).
local function resolveItemStats(link)
    if not link then return nil end
    local ok, raw = pcall(HM.Client.getItemStats, link)
    return ok and raw or nil
end

local function getItemInfo(...)
    return HM.Client.getItemInfo(...)
end
local function getItemInfoInstant(...)
    return HM.Client.getItemInfoInstant(...)
end

-- Mapped stats of the item currently equipped where a hovered item would go (live only,
-- no shipped item DB). nil if the slot is empty or the item isn't equippable gear.
local function equippedCompareStats(link)
    local equipLoc
    equipLoc = select(9, getItemInfo(link))
    local slots = equipLoc and INVSLOT[equipLoc]
    if not (slots and _G.GetInventoryItemLink) then return nil end
    for _, slot in ipairs(slots) do
        local eqLink = _G.GetInventoryItemLink("player", slot)
        if eqLink and not sameItem(eqLink, link) then
            return Tooltips.mapItemStats(resolveItemStats(eqLink))
        end
    end
    return nil
end

-- Write-back journal (CONSUME-buffs QA loop): every consumable hover is logged to
-- SavedVariables - injected ones into buffTipLog (last 15, proves the surface works
-- and shows exactly what we displayed), and ClassID-0 items we have NO data for into
-- missedConsumables (capped). The harvester surfaces both; data gaps close through
-- the pipeline/overrides - the addon never edits its own data in-game.
local function journalConsumableTip(itemId, link, injected)
    if not (HM.db and type(HM.db.collect) == "table") then return end
    local c = HM.db.collect
    local name = type(link) == "string" and link:match("%[(.-)%]") or nil
    if injected then
        if type(c.buffTipLog) ~= "table" then c.buffTipLog = {} end
        for i = #c.buffTipLog, 1, -1 do
            if c.buffTipLog[i].itemId == itemId then table.remove(c.buffTipLog, i) end
        end
        c.buffTipLog[#c.buffTipLog + 1] = { itemId = itemId, name = name,
            at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?" }
        while #c.buffTipLog > 15 do table.remove(c.buffTipLog, 1) end
        return
    end
    local ok, _, _, _, _, _, classID, subClassID = pcall(getItemInfoInstant, itemId)
    if not ok or classID ~= 0 then return end -- only consumables are data gaps
    if type(c.missedConsumables) ~= "table" then c.missedConsumables = {} end
    local entry = c.missedConsumables[itemId]
    if entry then
        entry.count = (entry.count or 1) + 1
        return
    end
    local n = 0
    for _ in pairs(c.missedConsumables) do n = n + 1 end
    if n >= 100 then return end
    c.missedConsumables[itemId] = { name = name, subClass = subClassID, count = 1,
        at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?" }
end

-- Scan a weapon link's BASE damage/speed off its rendered tooltip via the house
-- hidden scan frame (same one collect.lua probes with - never a second scanner).
-- Base range, not UnitDamage: UnitDamage already folds AP in.
local function weaponFacts(link)
    if not (link and _G.CreateFrame) then return nil end
    local tip = _G.ForesightScanTooltip
    if not tip then
        tip = _G.CreateFrame("GameTooltip", "ForesightScanTooltip", nil, "GameTooltipTemplate")
    end
    tip:SetOwner(_G.UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    if not pcall(tip.SetHyperlink, tip, link) then return nil end
    local texts = {}
    for i = 1, (tip:NumLines() or 0) do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G["ForesightScanTooltipText" .. side .. i]
            local t = fs and fs:GetText()
            if t and t ~= "" then texts[#texts + 1] = t end
        end
    end
    return Tooltips.parseWeaponTip(texts)
end

-- Scan a spell's rendered tooltip for its damage/heal range (the audit lever): the
-- same hidden frame, SetSpellByID. Returns lo, hi or nil (display-only read).
function Tooltips.scanSpellRange(spellId)
    if not (spellId and _G.CreateFrame) then return nil end
    local tip = _G.ForesightScanTooltip
    if not tip then
        tip = _G.CreateFrame("GameTooltip", "ForesightScanTooltip", nil, "GameTooltipTemplate")
    end
    tip:SetOwner(_G.UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    if not (type(tip.SetSpellByID) == "function"
            and pcall(tip.SetSpellByID, tip, spellId)) then
        return nil
    end
    local texts = {}
    for i = 1, (tip:NumLines() or 0) do
        local fs = _G["ForesightScanTooltipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and t ~= "" then texts[#texts + 1] = t end
    end
    return Tooltips.parseSpellRange(texts)
end

local SWAP_EQUIP_LOC = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
}

-- Read the VISIBLE tooltip's own text lines (left + right columns) - the most robust
-- source for the hovered weapon's damage/speed: no hidden-scan round trip can fail.
local function liveTipTexts(tip)
    local name = tip and tip.GetName and tip:GetName()
    if not name then return nil end
    local texts = {}
    for i = 1, (tip:NumLines() or 0) do
        for _, side in ipairs({ "Left", "Right" }) do
            local fs = _G[name .. "Text" .. side .. i]
            local t = fs and fs:GetText()
            if t and t ~= "" then texts[#texts + 1] = t end
        end
    end
    return texts
end

-- Weapon-swap context for a hovered MELEE weapon: both base ranges read (hovered side
-- from the visible tooltip first, hidden scan as fallback), the two stat bundles'
-- AP-equivalents netted, composed by pure Sim.weaponSwap. Second return: an HONEST
-- reason when a weapon hover can't be compared (shown grey, never silent).
local function weaponSwapFor(link, mapped, loadout, hovFacts)
    if not (loadout and HM.Sim and HM.Sim.weaponSwap) then return nil end
    local equipLoc = select(9, getItemInfo(link))
    if not (equipLoc and SWAP_EQUIP_LOC[equipLoc]) then return nil end
    local eqLink = _G.GetInventoryItemLink and _G.GetInventoryItemLink("player", 16)
    if not eqLink then return nil, "no main-hand weapon equipped to compare against" end
    if sameItem(eqLink, link) then return nil end -- your own weapon: baseline mode covers it
    local hov = hovFacts or weaponFacts(link)
    if not hov then return nil, "couldn't read this weapon's damage line" end
    local eq = weaponFacts(eqLink)
    if not eq then return nil, "couldn't read your equipped weapon's damage line" end
    local classToken = loadout.snapshot.classToken
    local apDelta = HM.Sim.apFromStats(mapped, classToken)
        - HM.Sim.apFromStats(Tooltips.mapItemStats(resolveItemStats(eqLink)), classToken)
    return HM.Sim.weaponSwap(loadout.snapshot, hov, eq, apDelta)
end

-- The Windfury-style imbue the player knows, cached per session (IsPlayerSpell over
-- the imbue table is too heavy per hover; new ranks land on the next /reload).
local wfKnownCache
local function knownWindfury()
    if wfKnownCache ~= nil then return wfKnownCache or nil end
    local known = HM.Imbues and HM.Imbues.known() or {}
    wfKnownCache = (HM.Sim and HM.Sim.windfuryFor(known)) or false
    return wfKnownCache or nil
end

-- Journal unmapped GetItemStats keys (capped counts): the self-correcting loop for
-- stat coverage - the harvest prints what live Forever items carry that we drop.
local function journalUnknownStatKeys(unknown)
    if not (unknown and #unknown > 0 and HM.db and type(HM.db.collect) == "table") then return end
    local c = HM.db.collect
    if type(c.unknownItemStats) ~= "table" then c.unknownItemStats = {} end
    for _, key in ipairs(unknown) do
        if c.unknownItemStats[key] then
            c.unknownItemStats[key] = c.unknownItemStats[key] + 1
        else
            local n = 0
            for _ in pairs(c.unknownItemStats) do n = n + 1 end
            if n < 40 then c.unknownItemStats[key] = 1 end
        end
    end
end

local function injectItem(tip)
    if injectedTips[tip] then return end
    if type(tip.GetItem) ~= "function" then return end
    local _, link = tip:GetItem()
    if not link then return end
    local mapped, unknownKeys = Tooltips.mapItemStats(resolveItemStats(link))
    pcall(journalUnknownStatKeys, unknownKeys)
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local compared
    local okc, c = pcall(equippedCompareStats, link)
    if okc then compared = c end
    local itemId = tonumber(type(link) == "string" and link:match("item:(%d+)") or nil)
    local ctx
    local genItem = itemId and HM.gen and HM.gen.items and HM.gen.items[itemId]
    if genItem and genItem.speedMs then
        ctx = { itemId = itemId, speedMs = genItem.speedMs, wfImbue = knownWindfury() }
    end
    -- Weapon-swap honesty: the hovered weapon's own damage range vs your main hand.
    -- The hovered side parses the VISIBLE tooltip's lines first (most robust).
    local okSwap, swap, why = pcall(weaponSwapFor, link, mapped, loadout,
        Tooltips.parseWeaponTip(liveTipTexts(tip)))
    if okSwap and (swap or why) then
        ctx = ctx or {}
        ctx.weaponSwap = swap
        ctx.weaponSwapWhy = (not swap) and why or nil
    end
    -- BASELINE LAW: hovering an item you're WEARING switches to baseline mode - its
    -- stats are already inside every number, so no verdict/% is ever claimed for it.
    -- Identity by itemKey, never raw link equality (live catch: linkLevel drift made
    -- the equipped weapon read as a different item and claim "+2.8").
    local okEq, equippedSelf = pcall(function()
        local equipLoc = select(9, getItemInfo(link))
        for _, slot in ipairs((equipLoc and INVSLOT[equipLoc]) or {}) do
            if _G.GetInventoryItemLink
                    and sameItem(_G.GetInventoryItemLink("player", slot), link) then
                return true
            end
        end
        return false
    end)
    if okEq and equippedSelf then
        compared = nil
        ctx = ctx or {}
        ctx.equipped = true
        ctx.weaponSwap = nil
    end
    local lines = Tooltips.itemLines(mapped, loadout, compared, ctx)
    if not lines then
        -- No gear stats: consumables carry their impact as a generated buff block.
        if itemId then
            lines = Tooltips.buffLines(itemId, loadout)
            journalConsumableTip(itemId, link, lines ~= nil)
        end
    end
    -- Provenance: if this item is in our client-decoded catalog, stamp it so the player
    -- knows the data is real Forever content at a known patch, not a datamined guess.
    if lines and itemId and HM.gen and HM.gen.items and HM.gen.items[itemId] then
        lines[#lines + 1] = {
            text = "|cff4ade80" .. (HM.provenance and HM.provenance() or "Forever-verified") .. "|r",
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true,
        }
    end
    if lines then
        injectedTips[tip] = true
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

-- Imbue block (IMBUE-compare): hovering a weapon imbue (Rockbiter/Flametongue/
-- poison) answers "what is this worth per swing on MY weapon" from the generated
-- enchant data + the live weapon speed.
function Tooltips.imbueLines(spellId, loadout)
    if not (loadout and HM.Imbues and HM.gen and HM.gen.imbues
            and HM.gen.imbues[spellId]) then return nil end
    local ok, rows, speed = pcall(HM.Imbues.compare, loadout.snapshot, { spellId })
    local r = ok and rows and rows[1]
    if not r then return nil end
    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight",
        right = "(p) " .. (r.confidence or "classic-presumed"),
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    if r.perSwing > 0 then
        lines[#lines + 1] = {
            text = ("On your %.1fs weapon: |cff4ade80~%+.1f|r damage per swing (%+.2f DPS)")
                :format(speed, r.perSwing, r.perSec),
            r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
        }
    end
    for _, n in ipairs(r.notes) do
        lines[#lines + 1] = { text = n, r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
    end
    if #lines <= 1 then return nil end
    return lines
end

-- Impact-map block (S7b on the spell tooltip): hovering an ability shows which talents
-- modify it - the inverse map made visible where players decide what to press. Pure.
local MAX_MAP_SOURCES = 6
-- spellName optional: resolve by NAME (always matches our name-keyed map) so a hovered
-- rank id the game hands us that isn't our shipped id still finds its modifiers.
function Tooltips.abilityMapLines(spellId, spellName)
    local name = spellName
    if not name then
        local sp = HM.gen and HM.gen.spells and HM.gen.spells[spellId]
        name = sp and sp.name
    end
    if not (name and HM.Mapping) then return nil end
    local r = HM.Mapping.forSpell(name)
    if not (r and r.sources and #r.sources > 0) then return nil end
    local lines = {}
    lines[#lines + 1] = {
        kind = "double", left = "Foresight", right = "talents affecting this",
        r = BRAND.r, g = BRAND.g, b = BRAND.b, r2 = GREY.r, g2 = GREY.g, b2 = GREY.b,
    }
    local shown, seen = 0, {}
    for _, s in ipairs(r.sources) do
        if not seen[s.name] then           -- one line per source talent
            seen[s.name] = true
            shown = shown + 1
            if shown <= MAX_MAP_SOURCES then
                lines[#lines + 1] = {
                    text = ("|cff9d9d9d%s|r %s"):format(s.name, HM.Mapping.describeOp(s.op)),
                    r = BODY.r, g = BODY.g, b = BODY.b, wrap = true,
                }
            end
        end
    end
    if shown > MAX_MAP_SOURCES then
        lines[#lines + 1] = { text = ("+%d more"):format(shown - MAX_MAP_SOURCES),
            r = GREY.r, g = GREY.g, b = GREY.b, wrap = true }
    end
    return lines
end

local function injectSpell(tip, spellId)
    if injectedTips[tip] then return end
    local spellName
    if type(tip.GetSpell) == "function" then
        local a, b = tip:GetSpell()  -- (name, spellID) on both classic and mainline
        if type(a) == "string" then spellName = a end
        spellId = spellId or (type(b) == "number" and b) or nil
    end
    if not (spellId or spellName) then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    local lines = (spellId and (Tooltips.imbueLines(spellId, loadout)
        or Tooltips.spellLines(spellId, loadout))) or nil
    -- Append the "which talents modify this" block (its own header if it stands alone).
    local map = Tooltips.abilityMapLines(spellId, spellName)
    if map then
        if lines then
            for _, l in ipairs(map) do if not l.kind then lines[#lines + 1] = l end end
        else
            lines = map
        end
    end
    if lines then
        injectedTips[tip] = true
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

-- Capture the REAL rendered node tooltip text + the node's current rank, journaled per
-- node. This is the authoritative rank-scaling ground truth (the classic SetTalent probe
-- is dead on Forever), gathered passively as the player mouses over talents - the harvest
-- compares these numbers against the generated ops to settle each (p) rank rule.
local function journalTalentTooltip(tip, nodeId, snap)
    if not (HM.db and type(HM.db.collect) == "table") then return end
    if type(tip.NumLines) ~= "function" then return end
    local lines = {}
    for i = 1, tip:NumLines() do
        local fs = _G["GameTooltipTextLeft" .. i]
        local t = fs and fs:GetText()
        if t and t ~= "" then lines[#lines + 1] = t end
    end
    if #lines == 0 then return end
    local rank
    for _, t in ipairs((snap and snap.talents) or {}) do
        if t.nodeId == nodeId then rank = t.rank; break end
    end
    local node = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nodeId]
    local c = HM.db.collect
    if type(c.talentTooltips) ~= "table" then c.talentTooltips = {} end
    -- No-downgrade law: a trained capture (rank known) is ground truth - a later
    -- untrained hover never overwrites it (live catch: Deflection, 2026-10-12).
    if not Tooltips.shouldReplaceCapture(c.talentTooltips[nodeId], { rank = rank }) then
        return
    end
    local n = 0
    for _ in pairs(c.talentTooltips) do n = n + 1 end
    if c.talentTooltips[nodeId] or n < 300 then
        c.talentTooltips[nodeId] = {
            rank = rank, maxRank = node and node.maxRank,
            name = node and node.name, spellID = node and node.spellID,
            text = table.concat(lines, "\n"),
            at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?",
        }
    end
end

-- Core: inject the impact block for a resolved node id, recording a diagnostic.
local function injectNodeBlock(tip, nodeId, source)
    if HM.db and type(HM.db.collect) == "table" then
        HM.db.collect.traitTipProbe = { source = source, nodeId = nodeId, injected = false }
    end
    if not nodeId or injectedTips[tip] then return end
    local loadout
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then loadout = HM.Loadout.fromSnapshot(snap) end
    -- Capture the game's base tooltip text BEFORE we append our block.
    pcall(journalTalentTooltip, tip, nodeId, snap)
    local lines = Tooltips.nodeImpactLines(nodeId, loadout)
    if lines then
        injectedTips[tip] = true
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
