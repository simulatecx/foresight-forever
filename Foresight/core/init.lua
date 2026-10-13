-- Foresight core bootstrap: addon namespace, saved variables, events, slash commands.
-- WoW-client-only wiring is gated on CreateFrame so every file also loads headless
-- under the test harness (pipeline/run_tests.py).

local ADDON_NAME, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end
_G.Foresight = HM

-- Kept in sync with Foresight.toc by the ship gate (run_tests.py reds on drift -
-- incident 2026-10-11: this constant sat at 0.10.0 for three releases and made a
-- harvest mis-diagnose a live-client state). Collect journals this stamp.
HM.version = "0.39.0"

-- Provenance stamp for generated content: everything in data/generated came straight
-- from the real Forever client DB2 at this build, so it is CLIENT-VERIFIED (distinct
-- from the (p) tags on presumed rank-scaling). Gear/catalog surfaces show this so the
-- player knows the data is real Forever content, not datamined guesswork.
function HM.provenance()
    local gen = HM.gen
    local build = gen and gen.build or "?"
    local channel = (gen and gen.channel) or "beta"
    return ("Forever-verified - %s %s"):format(channel, build)
end

-- Detect a stale in-client file list: /reload re-runs files but a client started
-- before a deploy that ADDED files to the .toc never loads them until a full restart.
-- Checks that every module this code generation expects actually loaded.
function HM.staleCodeCheck()
    local missing = {}
    for _, m in ipairs({ "Plan", "SynergyHighlight", "Racials", "Sim", "MatrixPanel" }) do
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

-- The dimension the player is gearing FOR (the gear-verdict lens). "auto" = the build's
-- primary output. Validated on read (untrusted-input law): an unknown saved goal falls
-- back to auto rather than erroring.
function HM.gearGoal()
    local db = HM.charDb and HM.charDb()
    local g = db and db.settings and db.settings.goal
    if type(g) == "string" and (g == "auto" or (HM.dimensions and HM.dimensions.byId(g))) then
        return g
    end
    return "auto"
end

-- Per-character display settings (S27, recorded user decision: standing names STAY,
-- default ON, toggleable). Validated on read; only whitelisted keys exist. The full
-- options GUI is backlogged - /foresight set <key> on|off is the lever until then.
local SHOW_KEYS = { standing = true }
function HM.showSetting(key)
    if not SHOW_KEYS[key] then return true end
    local db = HM.charDb and HM.charDb()
    local show = db and db.settings and db.settings.show
    if type(show) == "table" and show[key] == false then return false end
    return true
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
        local sentence, ranked, focus = HM.Impact.statPrioritySentence(loadout)
        printMsg(sentence)
        -- S20 coaching: one derived attribution line when a stat is dead by mechanism.
        local okCoach, coach = pcall(HM.Impact.coachingLine, loadout, ranked, focus)
        if okCoach and coach then printMsg(coach) end
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
    elseif cmd == "goal" then
        -- What you're gearing FOR - the dimension the item verdict judges against.
        local ALIAS = { survival = "survivability", tank = "tankability",
                        dps = "meleeDps", melee = "meleeDps", ranged = "rangedDps",
                        caster = "spellcasting", spell = "spellcasting", mana = "sustain" }
        local db = HM.charDb()
        if rest == "" then
            local cur = HM.gearGoal()
            printMsg("gearing goal: " .. cur .. " (what the item verdict judges)")
            local ids = { "auto" }
            for _, d in ipairs(HM.dimensions.list) do ids[#ids + 1] = d.id end
            printMsg("  set with /foresight goal <" .. table.concat(ids, " | ") .. ">")
        elseif rest == "auto" or rest == "clear" then
            db.settings.goal = "auto"
            printMsg("gearing goal: auto (follows your build's primary output)")
        else
            local want = ALIAS[rest:lower()] or rest
            local dim = HM.dimensions.byId(want)
            if not dim then
                for _, d in ipairs(HM.dimensions.list) do
                    if d.label:lower():find(rest:lower(), 1, true) then dim = d; want = d.id end
                end
            end
            if dim then
                db.settings.goal = want
                printMsg("gearing goal set: " .. dim.label .. " - item verdicts now judge for this")
                if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
            else
                printMsg("unknown goal '" .. rest .. "' - try: survival, tank, dps, caster, healing, auto")
            end
        end
    elseif cmd == "affects" or cmd == "map" then
        -- The impact map: what modifies an ability (inverse), or what an ability's
        -- talent touches (forward, when given a talent name).
        if not HM.Mapping then
            printMsg("impact map unavailable")
            return
        end
        if rest == "" then
            printMsg("usage: /foresight affects <ability> [show]  (show = dim the tree, glow its modifiers)")
            return
        end
        -- Skill-centric mode: "affects <ability> show" dims the talent tree and glows
        -- the modifiers (transient; /foresight synergy clear stops it).
        local query = rest:match("^(.-)%s+show$") or rest
        local r = HM.Mapping.forSpell(query)
        if r then
            printMsg(("%s is modified by %d source(s):"):format(r.spell, #r.sources))
            for _, s in ipairs(r.sources) do
                printMsg(("  [%s] %s: %s"):format(s.kind, s.name, HM.Mapping.describeOp(s.op)))
            end
            if rest:match("%s+show$") and HM.SynergyHighlight
                    and HM.SynergyHighlight.applyAbility then
                local lit = HM.SynergyHighlight.applyAbility(query)
                if lit and lit > 0 then
                    printMsg(("%d modifier node(s) glowing, rest of the tree dimmed "
                        .. "(/foresight synergy clear to stop)"):format(lit))
                else
                    printMsg("open the talent frame, then run this again to see the glow")
                end
            end
        else
            -- Maybe they named a talent - show the forward direction.
            local found = HM.findTalents and HM.findTalents(rest)
            local fwd = found and found[1] and HM.Mapping.forEntry(found[1].id)
            if fwd and #fwd.abilities > 0 then
                printMsg(("%s touches %d abilit(ies):"):format(fwd.name, #fwd.abilities))
                for _, a in ipairs(fwd.abilities) do
                    printMsg(("  %s: %s"):format(a.spell, HM.Mapping.describeOp(a.op)))
                end
            else
                printMsg("nothing modifies '" .. rest .. "' in the data (try an ability or talent name)")
            end
        end
    elseif cmd == "focus" then
        -- Skill-centric mode (S22a): persistently study ONE ability - the talent tree
        -- lights its modifiers (gold direct / blue indirect, rest overlay-dimmed) and
        -- the Matrix insight block shows the classes + the cascade chip row.
        if not (HM.SynergyHighlight and HM.SynergyHighlight.setFocus) then
            printMsg("focus mode unavailable")
            return
        end
        if rest == "" or rest == "clear" then
            HM.SynergyHighlight.setFocus(nil)
            pcall(HM.SynergyHighlight.clear)
            if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
            printMsg(rest == "clear" and "skill focus cleared"
                or "usage: /foresight focus <ability> (or clear)")
            return
        end
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        local level = snapshot and snapshot.level
        local sid, spell = HM.Sim.resolveSpellLevelCapped(rest, level)
        if not sid then
            printMsg("no ability named '" .. rest .. "' in the shipped data")
            return
        end
        HM.SynergyHighlight.setFocus(spell.name)
        local c = HM.Mapping and HM.Mapping.classifiedForSpell
            and HM.Mapping.classifiedForSpell(sid,
                { classToken = snapshot and snapshot.classToken })
        if c then
            printMsg(("focused on %s: %d direct, %d school, %d stat-feeder modifier(s)")
                :format(c.spell, #c.direct, #c.school, #c.statFeeders))
        else
            printMsg("focused on " .. spell.name)
        end
        local okh, n = pcall(HM.SynergyHighlight.applyAbility, spell.name)
        if okh and type(n) == "number" and n > 0 then
            printMsg(("%d node(s) lit - gold direct, blue indirect; rest dimmed "
                .. "(/foresight focus clear to stop)"):format(n))
        else
            printMsg("open the talent frame to see the tree light up; the Matrix shows the pathway")
        end
        if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
    elseif cmd == "set" then
        -- Generic settings lever (S27; the options GUI menu is backlogged).
        local key, val = rest:match("^(%S+)%s+(%S+)$")
        if key ~= "standing" or (val ~= "on" and val ~= "off") then
            printMsg("usage: /foresight set standing on|off (hides the archetype NAME; your numbers never hide)")
            return
        end
        local db = HM.charDb()
        if type(db.settings.show) ~= "table" then db.settings.show = {} end
        db.settings.show.standing = (val == "on")
        printMsg("standing names " .. val .. (val == "off" and " - lean and goal text remain" or ""))
        if HM.StatsPanel and HM.StatsPanel.refresh then pcall(HM.StatsPanel.refresh) end
        if HM.MatrixPanel and HM.MatrixPanel.refresh then pcall(HM.MatrixPanel.refresh) end
    elseif cmd == "report" then
        -- One-command calc-issue report (user binding 2026-10-12): bundle the live
        -- context, take a screenshot (official API), journal it - the next harvest
        -- surfaces pending reports for review. Display-only; nothing leaves the
        -- machine except via the user's own harvest.
        if not HM.db then
            printMsg("saved variables unavailable")
            return
        end
        -- Self-initialize: a fresh install's FIRST command may precede any journaling.
        if type(HM.db.collect) ~= "table" then
            HM.db.collect = { sessions = {}, levels = {} }
        end
        local c = HM.db.collect
        if type(c.reports) ~= "table" then c.reports = {} end
        while #c.reports >= 20 do table.remove(c.reports, 1) end
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        c.reports[#c.reports + 1] = {
            at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?",
            note = rest ~= "" and rest:sub(1, 200) or nil,
            version = HM.version,
            build = (HM.gen and HM.gen.build) or "?",
            level = snapshot and snapshot.level or nil,
            classToken = snapshot and snapshot.classToken or nil,
            mainHand = _G.GetInventoryItemLink
                and _G.GetInventoryItemLink("player", 16) or nil,
            stats = snapshot and snapshot.stats or nil,
            lastTooltipOwner = c.lastTooltipOwner,
        }
        if _G.Screenshot then _G.Screenshot() end
        printMsg(("report #%d captured%s - it reaches review on your next logout or /reload"
            .. (rest == "" and "; add context next time: /foresight report <what looks wrong>" or ""))
            :format(#c.reports, _G.Screenshot and " with screenshot" or ""))
    elseif cmd == "audit" then
        -- PREVALIDATION (S19 verification, automated): compare the GAME'S OWN rendered
        -- spell tooltips against our composed claims for every known decoded spell -
        -- one command instead of eyeballing ability by ability. Also settles whether
        -- Forever folds gear bonuses into tooltip numbers. Display-only reads, out of
        -- combat; results journal to SavedVariables for the harvest.
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        if not (_G.IsPlayerSpell and HM.Tooltips.scanSpellRange) then
            printMsg("audit needs the live client (IsPlayerSpell + tooltip scan)")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local F = HM.formulas
        local scanned, gearHits, baseHits, misses, unparsed = 0, 0, 0, 0, 0
        local rows = {}
        for sid, sp in pairs(HM.gen.spells) do
            if scanned >= 60 then break end
            if (sp.dmg or sp.heal) and not sp.wpn and _G.IsPlayerSpell(sid) then
                scanned = scanned + 1
                local tipLo, tipHi = HM.Tooltips.scanSpellRange(sid)
                local hit = HM.Sim.abilityHit(loadout, sid, { selected = snapshot.talents })
                if not (tipLo and hit) then
                    unparsed = unparsed + 1
                    rows[#rows + 1] = { spellId = sid, name = sp.name, verdict = "unparsed" }
                else
                    local d = sp.dmg or sp.heal
                    local kind = (sp.heal and not sp.dmg) and "heal" or nil
                    local rawLo, rawHi = F.spellBaseDamage.fn(
                        d.base, d.var, d.lvl, sp.baseLevel or sp.level, d.maxLvl,
                        snapshot.level)
                    local bLo, bHi = F.spellBaseDamage.display(rawLo, rawHi, kind)
                    local gLo, gHi = F.spellBaseDamage.display(hit.min, hit.max, kind)
                    local verdict
                    if tipLo == gLo and tipHi == gHi then
                        verdict = "gear"
                        gearHits = gearHits + 1
                    elseif tipLo == bLo and tipHi == bHi then
                        verdict = "base"
                        baseHits = baseHits + 1
                    else
                        verdict = "mismatch"
                        misses = misses + 1
                        printMsg(("  MISMATCH %s: tooltip %d-%d vs base %d-%d / with-gear %d-%d")
                            :format(sp.name, tipLo, tipHi, bLo, bHi, gLo, gHi))
                    end
                    rows[#rows + 1] = { spellId = sid, name = sp.name, verdict = verdict,
                        tipMin = tipLo, tipMax = tipHi, baseMin = bLo, baseMax = bHi,
                        gearMin = gLo, gearMax = gHi }
                end
            end
        end
        if HM.db and type(HM.db.collect) == "table" then
            HM.db.collect.hitAudit = {
                at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?",
                build = (HM.gen and HM.gen.build) or "?", rows = rows,
            }
        end
        printMsg(("audit: %d known decoded spells scanned - %d match with your gear, "
            .. "%d match base only (tooltip ignores gear), %d mismatch, %d unparsed")
            :format(scanned, gearHits, baseHits, misses, unparsed))
        if scanned > 0 then
            printMsg("journaled for the harvest - log out or /reload to flush")
        else
            printMsg("no known decoded spells found to audit")
        end
    elseif cmd == "hit" then
        -- MODEL-ability-outcomes: the composed absolute answer for one ability with
        -- every step shown - the in-game verification lever for the decode.
        if rest == "" then
            printMsg("usage: /foresight hit <ability name>")
            return
        end
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local sid, spell = HM.Sim.resolveSpellLevelCapped(rest, snapshot.level)
        if not sid then
            printMsg("no spell named '" .. rest .. "' in the shipped data")
            return
        end
        local hit = HM.Sim.abilityHit(loadout, sid, { selected = snapshot.talents })
        if not hit then
            printMsg(("%s: no decoded base data for this ability - nothing to claim")
                :format(spell.name))
            return
        end
        printMsg(("%s%s:"):format(spell.name,
            (spell.level and spell.level > 0) and (" (rank at level " .. spell.level .. ")") or ""))
        if hit.kind == "weapon" then
            local wpn = spell.wpn or {}
            printMsg(("  your weapon: %.0f-%.0f over %.1fs%s"):format(
                hit.baseMin, hit.baseMax, snapshot.weaponSpeed or 2.0,
                wpn.norm and (" - instant normalized at " .. (snapshot.weaponType or "oneHand")
                    .. " speed (p)") or ""))
            if wpn.pct then printMsg(("  x %g%% weapon damage"):format(wpn.pct)) end
            if wpn.flat then printMsg(("  + %g flat"):format(wpn.flat)) end
        else
            local bLo, bHi = HM.formulas.spellBaseDamage.display(hit.baseMin, hit.baseMax, hit.kind)
            printMsg(("  base: %d-%d at your level (p)"):format(bLo, bHi))
            if (hit.power or 0) > 0 then
                printMsg(("  + %d %s x %.3f coefficient (%s)"):format(hit.power,
                    hit.kind == "heal" and "Healing Power" or "Spell Power", hit.coef or 0,
                    hit.coefSource == "data" and "datamined" or "presumed (p)"))
            end
        end
        if (hit.pctMods or 0) ~= 0 or (hit.flatMods or 0) ~= 0 then
            local parts = {}
            if (hit.pctMods or 0) ~= 0 then parts[#parts + 1] = ("%+g%%"):format(hit.pctMods) end
            if (hit.flatMods or 0) ~= 0 then parts[#parts + 1] = ("%+g flat"):format(hit.flatMods) end
            printMsg(("  talents: %s (%s)"):format(table.concat(parts, ", "),
                table.concat(hit.mods or {}, ", ")))
        end
        local fLo, fHi = HM.formulas.spellBaseDamage.display(hit.min, hit.max, hit.kind)
        printMsg(("  = ~%d-%d per %s%s"):format(fLo, fHi,
            hit.kind == "heal" and "cast" or "hit",
            hit.presumed and " (p)" or ""))
        if (hit.critPct or 0) > 0 then
            printMsg(("  crits for ~%gx at your %.1f%% crit (p)"):format(
                hit.critMult or 2, hit.critPct))
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
            printMsg(("Foresight content catalog [%s]:"):format(HM.provenance()))
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
        printMsg(("gear with '%s': %d found%s  [%s]"):format(rest, total,
            total > 15 and " (showing 15 by required level)" or "", HM.provenance()))
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
    elseif cmd == "sim" then
        -- SIM-engine: the crit -> Flurry -> swing speed -> Windfury cascade on YOUR
        -- numbers, plus your build standing. Out-of-combat command, display-only.
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local sel = HM.TalentAPI.walkTraits and HM.TalentAPI.walkTraits(true)
        local known = HM.Imbues and HM.Imbues.known() or {}
        local cascade = HM.Sim.meleeCascade(loadout, {
            flurry = HM.Sim.flurryFor(sel),
            imbue = HM.Sim.windfuryFor(known),
        })
        local standing = HM.Sim.standing(HM.Impact.evaluate(loadout), snapshot.stats)
        printMsg(("melee simulation - %s (%s):"):format(standing.name, standing.detail))
        for _, s in ipairs(cascade.steps) do printMsg("  " .. s) end
    elseif cmd == "oom" then
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        if rest == "" then
            printMsg("usage: /foresight oom <spell name> - the chain-cast mana answer")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local sid = HM.Sim.resolveSpellByName(rest)
        local oom = sid and HM.Sim.timeToOOM(loadout, sid)
        if not oom then
            printMsg(("no mana-costing spell named '%s' in the data"):format(rest))
            return
        end
        printMsg(("%s: %d mana per %.1fs cast = %.0f mana/s drain"):format(
            oom.name, oom.cost, oom.castSec, oom.drainPerSec))
        printMsg(("  chain-casting empties your pool in ~%ds (~%d casts)"):format(
            oom.seconds, oom.casts))
        for _, n in ipairs(oom.notes) do printMsg("  " .. n) end
    elseif cmd == "path" then
        -- Goal pathways: rank your UNSPENT talent steps by what they do for a
        -- dimension (default: your gearing goal / primary output).
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        if not snapshot then
            printMsg("no character snapshot available")
            return
        end
        local loadout = HM.Loadout.fromSnapshot(snapshot)
        local dimId = rest ~= "" and rest or (HM.gearGoal and HM.gearGoal() or "auto")
        if dimId == "auto" then dimId = HM.Impact.primaryDimension(loadout) end
        local walk = HM.TalentAPI.walkTraits and HM.TalentAPI.walkTraits(false)
        if not walk or #walk == 0 then
            printMsg("talent tree unavailable - open the talent frame once, then retry")
            return
        end
        local candidates = {}
        for _, n in ipairs(walk) do
            if (n.rank or 0) < (n.maxRank or 1) and n.nodeID then
                candidates[#candidates + 1] = {
                    label = ("%s %d/%d"):format(n.name or ("node " .. n.nodeID),
                        (n.rank or 0) + 1, n.maxRank or 1),
                    what = loadout:withTraitNode(n.nodeID, (n.rank or 0) + 1),
                }
            end
        end
        local path, err = HM.Sim.goalPathways(loadout, dimId, candidates)
        if not path then
            printMsg("pathways: " .. (err or "unavailable"))
            return
        end
        printMsg(("best next talent points for %s (%d candidates considered):"):format(
            path.label, path.considered))
        if #path.rows == 0 then
            printMsg("  none of your open talent steps move this dimension in the data")
        end
        for i, r in ipairs(path.rows) do
            printMsg(("  %d. %s  %+.1f%%"):format(i, r.label, r.pct))
        end
    elseif cmd == "loop" or cmd == "loops" then
        local snapshot = HM.Snapshot and HM.Snapshot.capture()
        local classToken = snapshot and snapshot.classToken
        if rest == "" then
            local avail = HM.loopsForClass(classToken)
            if #avail == 0 then avail = HM.loops end
            printMsg("class loops - /foresight loop <id>:")
            for _, l in ipairs(avail) do
                printMsg(("  %s - %s (%s)"):format(l.id, l.name, l.classToken))
            end
            return
        end
        local l = HM.loopById(rest)
        if not l then
            printMsg("no loop named '" .. rest .. "'")
            return
        end
        printMsg(("%s (%s, %s):"):format(l.name, l.classToken, l.confidence))
        printMsg("  enablers: " .. table.concat(l.enablers, ", "))
        printMsg("  engine:   " .. table.concat(l.engine, ", "))
        printMsg("  payoffs:  " .. table.concat(l.payoffs, ", "))
        printMsg("  " .. l.insight)
        if snapshot and l.compute then
            local okc, computed = pcall(l.compute, HM.Loadout.fromSnapshot(snapshot))
            for _, line in ipairs(okc and computed or {}) do
                printMsg("  " .. line)
            end
        end
    elseif cmd == "matrix" then
        -- The Matrix dashboard (S7b): standing badge + dimension bars + the class's
        -- Enabler -> Engine -> Payoff loops. Modifiable: opacity + drag position.
        local sub, arg = rest:match("^(%S*)%s*(.-)$")
        if not HM.MatrixPanel then
            printMsg("matrix panel is in-game only")
        elseif sub == "opacity" then
            local a = HM.MatrixPanel.setOpacity(arg)
            printMsg(("matrix background opacity set to %.2f (0.2 - 1.0)"):format(a))
        elseif sub == "reset" then
            HM.MatrixPanel.resetPosition()
            printMsg("matrix position reset to center")
        else
            HM.MatrixPanel.toggle()
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
        printMsg("commands: /foresight talent <name|id> | stat <name> <amount> | advisor | build | goal <focus> | sim | oom <spell> | hit <ability> | audit | report [note] | set standing on|off | focus <ability|clear> | path [dimension] | loop [id] | matrix [opacity <v>|reset] | synergy [name|clear] | affects <ability> | catalog [name] | items <stat> | buffs | imbue | plan [add|remove|clear] | panel [reset] | verify | export | selftest")
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

    -- TAINT SENTINEL (account-safety doctrine): if the client ever blocks a protected
    -- action and names Foresight, journal WHICH function plus context so the harvest
    -- surfaces the exact vector - never guess from a dialog screenshot again.
    -- Observer only; it changes no behavior.
    local sentinel = _G.CreateFrame("Frame")
    sentinel:RegisterEvent("ADDON_ACTION_BLOCKED")
    sentinel:RegisterEvent("ADDON_ACTION_FORBIDDEN")
    local taintWarned
    sentinel:SetScript("OnEvent", function(_, event, addon, func)
        if addon ~= ADDON_NAME then return end
        if HM.db and type(HM.db.collect) == "table" then
            local c = HM.db.collect
            if type(c.taintEvents) ~= "table" then c.taintEvents = {} end
            if #c.taintEvents < 20 then
                c.taintEvents[#c.taintEvents + 1] = {
                    event = event, func = tostring(func),
                    at = _G.date and _G.date("%Y-%m-%d %H:%M:%S") or "?",
                    talentUIOpen = (_G.PlayerSpellsFrame and _G.PlayerSpellsFrame.IsShown
                        and _G.PlayerSpellsFrame:IsShown()) and true or false,
                    inCombat = (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false,
                }
            end
        end
        if not taintWarned then
            taintWarned = true
            printMsg(("the client blocked '%s' (%s) with Foresight on the stack - journaled for the harvest; please /reload and report what you were doing"):format(
                tostring(func), event))
        end
    end)
else
    initSavedVariables()
end

HM.onSlash = onSlash

return HM
