-- Foresight core bootstrap: addon namespace, saved variables, events, slash commands.
-- WoW-client-only wiring is gated on CreateFrame so every file also loads headless
-- under the test harness (pipeline/run_tests.py).

local ADDON_NAME, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end
_G.Foresight = HM

HM.version = "0.6.2" -- keep in sync with Foresight.toc (collect journals this stamp)

-- Defensive load: SavedVariables are user-editable files, so every field is
-- type-validated and anything malformed is reset, never trusted. A tampered or
-- corrupted file degrades to defaults instead of erroring the addon.
function HM.initSavedVariables()
    if type(ForesightDB) ~= "table" then ForesightDB = {} end
    if type(ForesightDB.version) ~= "number" then ForesightDB.version = 1 end
    if type(ForesightDB.chars) ~= "table" then ForesightDB.chars = {} end
    if type(ForesightDB.reports) ~= "table" then ForesightDB.reports = {} end
    if ForesightDB.collect ~= nil and type(ForesightDB.collect) ~= "table" then
        ForesightDB.collect = nil
    end
    HM.db = ForesightDB
end
local initSavedVariables = HM.initSavedVariables

local function charKey()
    local name = _G.UnitName and _G.UnitName("player") or "test"
    local realm = _G.GetRealmName and _G.GetRealmName() or "test"
    return name .. "-" .. realm
end

function HM.charDb()
    local key = charKey()
    HM.db.chars[key] = HM.db.chars[key] or { escapeRegistry = nil, settings = {} }
    return HM.db.chars[key]
end

local function printMsg(msg)
    if _G.DEFAULT_CHAT_FRAME then
        _G.DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Foresight|r: " .. msg)
    else
        print("Foresight: " .. msg)
    end
end
HM.print = printMsg

-- Find talents by id or (partial, case-insensitive) name. Returns list of
-- { id, name, tabName }; an exact name match returns only that talent.
function HM.findTalents(query)
    local talents = HM.gen and HM.gen.talents
    if not talents then return {} end
    local id = tonumber(query)
    if id then
        return talents[id] and { { id = id, name = talents[id].name } } or {}
    end
    local needle = query:lower()
    local matches, exact = {}, nil
    for tid, t in pairs(talents) do
        local name = (t.name or ""):lower()
        if name == needle then
            exact = tid
        elseif name:find(needle, 1, true) then
            local tab = HM.gen.talentTabs and HM.gen.talentTabs[t.tab]
            matches[#matches + 1] = { id = tid, name = t.name, tabName = tab and tab.name }
        end
    end
    if exact then
        return { { id = exact, name = talents[exact].name } }
    end
    table.sort(matches, function(a, b) return a.name < b.name end)
    return matches
end

local function onSlash(input)
    input = (input or ""):gsub("^%s+", "")
    local cmd, rest = input:match("^(%S*)%s*(.-)$")
    if cmd == "selftest" then
        HM.runSelftest(printMsg)
    elseif cmd == "talent" then
        local found = HM.findTalents(rest)
        if #found == 0 then
            printMsg("no talent matches '" .. rest .. "' (usage: /foresight talent <name or id>)")
            return
        elseif #found > 1 then
            printMsg(#found .. " matches - be more specific:")
            for i = 1, math.min(#found, 8) do
                printMsg(("  %s (%s, id %d)"):format(found[i].name,
                    found[i].tabName or "?", found[i].id))
            end
            return
        end
        local summary = HM.Impact.talentSummary(found[1].id)
        printMsg(("%s (%d ranks)%s"):format(summary.name, summary.maxRank,
            summary.needsCuration and " [needs curation]" or ""))
        for _, op in ipairs(summary.ops) do
            local affected = #op.affectedNames > 0
                and (" -> " .. table.concat(op.affectedNames, ", ")) or ""
            printMsg(("  %s %s%s%s"):format(
                op.value or "?", op.isPct and "%" or "", op.property or op.kind, affected))
        end
    elseif cmd == "stat" then
        local stat, amount = rest:match("^(%S+)%s+(-?%d+%.?%d*)$")
        if not stat then
            printMsg("usage: /foresight stat <Spirit|Intellect|...> <amount>")
            return
        end
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local lines = HM.Impact.explainStatDelta(loadout, stat, tonumber(amount))
        printMsg(("+%s %s means:"):format(amount, stat))
        for _, line in ipairs(lines) do printMsg("  " .. line) end
    elseif cmd == "advisor" or cmd == "stats" then
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local sentence, ranked = HM.Impact.statPrioritySentence(loadout)
        printMsg(sentence)
        for _, r in ipairs(ranked) do
            printMsg(("  %s: %s"):format(r.stat,
                r.bestLabel and ("%+.1f%% %s"):format(r.bestPct, r.bestLabel)
                    or "no modeled effect"))
        end
    elseif cmd == "build" or cmd == "playstyle" then
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local results = HM.Impact.evaluate(loadout)
        printMsg("your build: " .. HM.PanelModel.playstyleLabel(results, snapshot))
    elseif cmd == "verify" then
        HM.Collect.verify(printMsg)
        HM.Collect.probeTalentApiShape(printMsg)
        HM.Collect.probeTalentTooltips(printMsg)
    elseif cmd == "export" then
        local payload = HM.db and HM.db.collect or {}
        if HM.showExport then
            HM.showExport(HM.serialize(payload))
        else
            printMsg("export window unavailable outside the game client")
        end
    else
        printMsg("commands: /foresight talent <name|id> | stat <name> <amount> | advisor | build | verify | export | selftest")
    end
end

-- WoW client wiring -----------------------------------------------------------
if _G.CreateFrame then
    local frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
            initSavedVariables()
        elseif event == "PLAYER_LOGIN" then
            local gen = HM.gen
            printMsg(("v%s loaded - data build %s (%s talents)"):format(
                HM.version, gen and gen.build or "?",
                gen and gen.counts and gen.counts.talents or "?"))
            if HM.Guards.inRestrictedContext() then
                printMsg("restricted context detected - advisory features degrade to display-only")
            end
        end
    end)

    _G.SLASH_FORESIGHT1 = "/foresight"
    _G.SLASH_FORESIGHT2 = "/fore"
    _G.SLASH_FORESIGHT3 = "/helpme" -- legacy alias from the HelpMe era
    _G.SlashCmdList["FORESIGHT"] = onSlash
else
    initSavedVariables()
end

HM.onSlash = onSlash

return HM
