-- Foresight core bootstrap: addon namespace, saved variables, events, slash commands.
-- WoW-client-only wiring is gated on CreateFrame so every file also loads headless
-- under the test harness (pipeline/run_tests.py).

local ADDON_NAME, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end
_G.Foresight = HM

-- Kept in sync with Foresight.toc by the ship gate (run_tests.py reds on drift -
-- incident 2026-10-11: this constant sat at 0.10.0 for three releases and made a
-- harvest mis-diagnose a live-client state). Collect journals this stamp.
HM.version = "0.19.2"

-- Detect a stale in-client file list: /reload re-runs files but a client started
-- before a deploy that ADDED files to the .toc never loads them until a full restart.
-- Checks that every module this code generation expects actually loaded.
function HM.staleCodeCheck()
    local missing = {}
    for _, m in ipairs({ "Plan", "SynergyHighlight", "Racials" }) do
        if not HM[m] then missing[#missing + 1] = m end
    end
    for _, g in ipairs({ "consumables", "racials" }) do
        if not (HM.gen and HM.gen[g]) then missing[#missing + 1] = "gen." .. g end
    end
    local meta
    local getMeta = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
    if getMeta then
        local ok, ver = pcall(getMeta, "Foresight", "Version")
        if ok then meta = ver end
    end
    if #missing > 0 then
        return ("missing modules: %s (code v%s, client TOC v%s)"):format(
            table.concat(missing, ", "), HM.version, tostring(meta))
    end
    if meta and meta ~= HM.version then
        return ("client TOC v%s vs code v%s"):format(tostring(meta), HM.version)
    end
    return nil
end

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
        local lines = HM.Impact.statImpactDetail(loadout, stat, tonumber(amount))
        printMsg(("+%s %s does this for you:"):format(amount, stat))
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
    elseif cmd == "synergy" then
        if not HM.Synergy then
            printMsg("synergy engine unavailable")
            return
        end
        -- Player context folds YOUR racials + active consumable buffs into the themes.
        local player
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if snapshot then
            player = { raceId = snapshot.raceId, classToken = snapshot.classToken,
                       buffs = HM.Snapshot.captureActiveBuffs() }
        end
        if rest == "" then
            printMsg("synergy themes - /foresight synergy <name> (or clear):")
            printMsg("  " .. table.concat(HM.Synergy.themes(player), ", "))
        elseif rest == "clear" then
            if HM.SynergyHighlight then
                HM.SynergyHighlight.setTheme(nil)
                if HM.SynergyHighlight.clear then pcall(HM.SynergyHighlight.clear) end
            end
            printMsg("synergy highlight cleared")
        else
            local r = HM.Synergy.query(rest, player)
            if r then
                printMsg(("%s synergy - %d sources push this lever:"):format(r.label, #r.nodes))
                printMsg("  " .. table.concat(r.nodes, ", "))
                if r.chains and #r.chains > 0 then
                    printMsg("  chains (stat -> output):")
                    for _, ch in ipairs(r.chains) do printMsg("    " .. ch) end
                end
                -- SYNERGY-highlight: save the theme + glow the talent tree now/on open.
                if HM.SynergyHighlight and HM.SynergyHighlight.apply then
                    HM.SynergyHighlight.setTheme(rest)
                    local okh, lit = pcall(HM.SynergyHighlight.apply, rest)
                    if okh and type(lit) == "number" and lit > 0 then
                        printMsg(("%d talent nodes highlighted (/foresight synergy clear to stop)"):format(lit))
                    else
                        printMsg("theme saved - your talent tree glows when opened (/foresight synergy clear to stop)")
                    end
                end
            else
                printMsg("no synergy matches '" .. rest .. "' (try: intellect, crit, threat, nature, lightning)")
            end
        end
    elseif cmd == "buffs" then
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local active = HM.Snapshot.captureActiveBuffs()
        if #active == 0 then
            printMsg("no known consumable buffs active (or aura data is restricted here)")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local now = _G.GetTime and _G.GetTime() or nil
        for _, b in ipairs(active) do
            local entry = HM.gen.consumables[b.itemId]
            local remaining = (b.expirationTime and now and b.expirationTime > now)
                and math.floor((b.expirationTime - now) / 60 + 0.5) .. "m left" or nil
            printMsg(("%s (%s)%s"):format(entry.name, entry.type,
                remaining and (" - " .. remaining) or ""))
            local okd, lines = pcall(HM.Impact.buffDelta, loadout, b.itemId)
            for _, line in ipairs(okd and lines or {}) do printMsg("  " .. line) end
            printMsg("  on expiry these gains reverse")
        end
    elseif cmd == "catalog" or cmd == "db" then
        -- The content reference table: counts per kind, or a search across everything.
        if not HM.Catalog then
            printMsg("catalog unavailable")
            return
        end
        if rest ~= "" then
            local hits = HM.Catalog.search(rest)
            printMsg(("catalog: %d match '%s'"):format(#hits, rest))
            for i = 1, math.min(#hits, 15) do
                printMsg(("  [%s] %s"):format(hits[i].kind, hits[i].name))
            end
            if #hits > 15 then printMsg(("  ...and %d more"):format(#hits - 15)) end
        else
            printMsg("Foresight content catalog (impact sources we model):")
            local total = 0
            for _, row in ipairs(HM.Catalog.stats()) do
                total = total + row.count
                printMsg(("  %-10s %4d  (%d with impact%s)"):format(
                    row.kind, row.count, row.withOps,
                    row.needsCuration > 0 and (", " .. row.needsCuration .. " need curation") or ""))
            end
            printMsg(("  total: %d catalogued - /foresight catalog <name> to search"):format(total))
        end
    elseif cmd == "items" or cmd == "gear" then
        -- Browse the in-client gear seed by stat: "what has Dodge / Frost Resistance".
        if not HM.Catalog then
            printMsg("catalog unavailable")
            return
        end
        if rest == "" then
            printMsg("usage: /foresight items <stat> (e.g. Dodge, Parry, Attack Power, Intellect)")
            return
        end
        local hits, total = HM.Catalog.itemsWithStat(rest, 15)
        printMsg(("gear with '%s': %d found%s"):format(rest, total,
            total > 15 and " (showing 15 by required level)" or ""))
        for _, e in ipairs(hits) do
            printMsg(("  [%s] %s (req %d, %s) - %s"):format(
                e.slot or "?", e.name, e.reqLevel or 0, e.quality or "?",
                table.concat(e.stats or {}, ", ")))
        end
    elseif cmd == "imbue" or cmd == "imbues" then
        -- IMBUE-compare: Rockbiter vs Flametongue (etc.) on YOUR weapon, as numbers.
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local ids = HM.Imbues and HM.Imbues.known() or {}
        if #ids == 0 then
            printMsg("no known weapon imbues (shaman weapon imbues / rogue poisons)")
            return
        end
        local rows, speed = HM.Imbues.compare(snapshot, ids)
        printMsg(("weapon imbues on your %.1fs weapon (p):"):format(speed))
        local bestSwing = rows[1]
        for _, r in ipairs(rows) do
            if r.perSwing > bestSwing.perSwing then bestSwing = r end
            if r.perSwing > 0 then
                printMsg(("  %s: ~%+.1f damage per swing (%+.2f DPS)")
                    :format(r.name, r.perSwing, r.perSec))
            else
                printMsg("  " .. r.name .. ":")
            end
            for _, n in ipairs(r.notes) do printMsg("    " .. n) end
            if r.needsCuration then
                printMsg("    (some effects aren't mapped - the spell tooltip knows more)")
            end
        end
        if #rows >= 2 and rows[1].perSec > 0 then
            printMsg(("  -> best estimated DPS: %s%s"):format(rows[1].name,
                bestSwing.name ~= rows[1].name
                    and ("; biggest single swing: " .. bestSwing.name) or ""))
        end
    elseif cmd == "plan" then
        -- WHATIF-planner: compose a persistent future build and see its net impact.
        local Plan = HM.Plan
        if not Plan then
            printMsg("plan module unavailable")
            return
        end
        local sub, planArgs = rest:match("^(%S*)%s*(.-)$")
        local plan = Plan.store()
        local function rerender()
            if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
        end
        if sub == "" or sub == "show" then
            if #plan == 0 then
                printMsg("plan is empty - /foresight plan add stat Agility 5 | add item <label> Stat=N,... | add buff <name> | add talent <name> [rank] | remove <n> | clear")
                return
            end
            printMsg("your future build:")
            for i, d in ipairs(plan) do printMsg(("  %d. %s"):format(i, Plan.describe(d))) end
            local snapshot = HM.Snapshot and HM.Snapshot.capture()
            if snapshot then
                local loadout = HM.Loadout.fromSnapshot(snapshot)
                local okp, changes, chain = pcall(Plan.summary, loadout, plan)
                for _, l in ipairs(okp and chain or {}) do printMsg("  " .. l) end
                for _, c in ipairs(okp and changes or {}) do
                    printMsg(("  -> %s %+.1f%%"):format(c.label, c.pct or 0))
                end
            end
        elseif sub == "clear" then
            Plan.save({})
            rerender()
            printMsg("plan cleared")
        elseif sub == "remove" then
            local n = tonumber(planArgs)
            if n and plan[n] then
                local gone = Plan.describe(plan[n])
                table.remove(plan, n)
                Plan.save(plan)
                rerender()
                printMsg("removed " .. gone)
            else
                printMsg("usage: /foresight plan remove <entry number>")
            end
        elseif sub == "add" then
            local kind, spec = planArgs:match("^(%S*)%s*(.-)$")
            local delta
            if kind == "stat" then
                local stat, amount = spec:match("^(%S+)%s+(-?%d+%.?%d*)$")
                -- Accept lowercase primaries ("agility" -> "Agility").
                if stat and not Plan.stats[stat] then
                    local cap = stat:sub(1, 1):upper() .. stat:sub(2):lower()
                    if Plan.stats[cap] then stat = cap end
                end
                delta = stat and { type = "stat", stat = stat, amount = tonumber(amount) }
            elseif kind == "item" then
                local label, bundle = spec:match("^(.-)%s+(%S+=%S+)$")
                local stats = {}
                for statName, amount in (bundle or ""):gmatch("(%a+)=(-?%d+%.?%d*)") do
                    local key = statName
                    if not Plan.stats[key] then
                        local cap = key:sub(1, 1):upper() .. key:sub(2):lower()
                        if Plan.stats[cap] then key = cap end
                    end
                    stats[key] = tonumber(amount)
                end
                delta = { type = "item", label = label or "item", stats = stats }
            elseif kind == "buff" then
                local id = Plan.findConsumable(spec)
                delta = id and { type = "buff", id = id }
                if not delta then printMsg("no consumable matches '" .. spec .. "'") end
            elseif kind == "talent" then
                local name, rank = spec:match("^(.-)%s+(%d+)$")
                if not name then name = spec end
                local nodeId = Plan.findTraitNode(name)
                delta = nodeId and { type = "trait", nodeId = nodeId, rank = tonumber(rank) }
                if not delta then printMsg("no talent matches '" .. spec .. "'") end
            end
            local clean = delta and Plan.validateDelta(delta)
            if clean then
                plan[#plan + 1] = clean
                Plan.save(plan)
                rerender()
                printMsg(("planned: %s (%d in plan - /foresight plan to review)"):format(
                    Plan.describe(clean), #plan))
            elseif kind ~= "buff" and kind ~= "talent" then
                printMsg("usage: /foresight plan add stat <Stat> <n> | add item <label> Stat=N,... | add buff <name> | add talent <name> [rank]")
            end
        else
            printMsg("usage: /foresight plan [show] | add ... | remove <n> | clear")
        end
    elseif cmd == "panel" then
        if rest == "reset" then
            if HM.StatsPanel and HM.StatsPanel.resetPosition then
                HM.StatsPanel.resetPosition()
                printMsg("panel position reset - re-docked beside the character frame")
            else
                local db = HM.charDb()
                if db.settings.panel then db.settings.panel.pos = nil end
                printMsg("panel position reset")
            end
        elseif HM.StatsPanel and HM.StatsPanel.toggle then
            HM.StatsPanel.toggle()
        else
            printMsg("stats panel is in-game only")
        end
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
        printMsg("commands: /foresight talent <name|id> | stat <name> <amount> | advisor | build | synergy [name|clear] | catalog [name] | items <stat> | buffs | imbue | plan [add|remove|clear] | panel [reset] | verify | export | selftest")
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
            local stale = HM.staleCodeCheck and HM.staleCodeCheck()
            if stale then
                printMsg("|cfff87171STALE FILE LIST|r - " .. stale
                    .. ". Fully EXIT and restart the game (a /reload cannot load newly added files).")
            end
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
