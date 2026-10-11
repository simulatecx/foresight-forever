-- Foresight selftest: exercises the graph, formulas, loadout modelling and generated
-- data without touching game state. Runs in-game via /foresight selftest and headless
-- via pipeline/run_tests.py. Every assertion is a named check; output is a scoreboard.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local function approx(a, b, eps)
    return math.abs(a - b) <= (eps or 1e-6)
end

local function testSnapshot()
    return {
        classToken = "MAGE",
        level = 60,
        referenceSpell = 116, -- Frostbolt
        weaponSpeed = 2.0,
        stats = {
            strength = 30, agility = 40, stamina = 60, intellect = 150, spirit = 100,
            spellDamage = 50, healingPower = 0, attackPower = 60, rangedAttackPower = 10,
            spellCritPct = 5, meleeCritPct = 3, rangedCritPct = 2, hastePct = 0,
            armor = 800, avoidancePct = 5, baseHealth = 1000, baseMana = 800,
        },
    }
end

function HM.runSelftest(out)
    out = out or print
    local checks, failed = {}, 0
    local function check(name, cond, detail)
        checks[#checks + 1] = { name = name, ok = cond and true or false, detail = detail }
        if not cond then failed = failed + 1 end
    end

    -- Graph core ---------------------------------------------------------------
    local g = HM.Graph.new()
    g:addNode{ id = "a", base = 100 }
    g:addModifier{ target = "a", op = "flat", value = 10, source = "t1" }
    g:addModifier{ target = "a", op = "pctAdd", value = 10, source = "t2" }
    g:addModifier{ target = "a", op = "pctAdd", value = 10, source = "t3" }
    g:addModifier{ target = "a", op = "pctMult", value = 50, source = "t4" }
    local v = g:value("a", {})
    check("graph stacking (flat+pctAdd group+pctMult)", approx(v, 110 * 1.2 * 1.5), tostring(v))

    g:addNode{ id = "b", formula = function(get) return get("a") * 2 end }
    check("graph formula composition", approx(g:value("b", {}), v * 2))

    g:addModifier{ target = "a", op = "override", value = 42, source = "t5" }
    check("graph override wins", approx(g:value("a", {}), 42))
    check("graph removeBySource", g:removeModifiersBySource("t5") == 1 and approx(g:value("a", {}), 198))

    local okCycle = pcall(function()
        local cg = HM.Graph.new()
        cg:addNode{ id = "x", formula = function(get) return get("y") end }
        cg:addNode{ id = "y", formula = function(get) return get("x") end }
        cg:value("x", {})
    end)
    check("graph cycle detection", not okCycle)

    -- Formulas -------------------------------------------------------------------
    local mageFn = HM.formulas.manaRegenTick.byClass.MAGE
    check("mage regen formula 13+spirit/4", approx(mageFn(100), 38))
    check("swing time haste", approx(HM.formulas.swingTime.fn(3.6, 20), 3))
    check("talent rank rule linear", approx(HM.formulas.talentRankValue.fn(-500, 2, 5), -200))

    -- Generated data -------------------------------------------------------------
    local gen = HM.gen
    check("generated data loaded", gen and gen.talents and gen.spells and gen.build)
    if gen and gen.talents then
        local impFireball = gen.talents[26]
        check("Improved Fireball present", impFireball and impFireball.name == "Improved Fireball")
        local imp = gen.talentImpacts and gen.talentImpacts[26]
        local castOp = imp and imp.ops and imp.ops[1]
        check("Improved Fireball maps cast-time op",
            castOp and castOp.property == "cast time" and castOp.maxValue == -500)
        check("Improved Fireball affects Fireball(133)", (function()
            if not castOp or not castOp.affected then return false end
            for _, sid in ipairs(castOp.affected) do if sid == 133 then return true end end
            return false
        end)())
        check("Fireball has tick data from client", gen.spells[133] and gen.spells[133].tickMs == 2000)
        -- Incident-to-gate 2026-10-10: modern-format stat auras encode the stat as a
        -- MiscValue_1 bitmask; index-decoding misc0 mislabeled six talents "Strength".
        check("Ancestral Knowledge maps Intellect% (stat bitmask decode)", (function()
            local op = gen.talentImpacts and gen.talentImpacts[614]
                and gen.talentImpacts[614].ops and gen.talentImpacts[614].ops[1]
            return op and op.kind == "stat" and op.stat == "Intellect" and op.isPct == true
        end)())
    end

    -- Loadout modelling ------------------------------------------------------------
    local base = HM.Loadout.fromSnapshot(testSnapshot())
    local results = HM.Impact.evaluate(base)
    check("all dimensions evaluate", (function()
        for _, dim in ipairs(HM.dimensions.list) do
            if not results[dim.id] or not results[dim.id].score then return false, dim.id end
        end
        return true
    end)())
    check("sustain = manaTick*30", approx(results.sustain.score, 38 * 30))

    -- The +2 Spirit question.
    local lines, changes = HM.Impact.explainStatDelta(base, "Spirit", 2)
    check("+2 Spirit produces explanation lines", #lines > 0, table.concat(lines or {}, " | "))
    check("+2 Spirit moves sustain by 0.5/tick*30", (function()
        for _, c in ipairs(changes) do
            if c.id == "sustain" then return approx(c.delta, 15) end
        end
        return false
    end)())

    -- Talent modelling: Arcane Mind style stat talent vs throughput talent.
    local modeled = base:withTalent(26, 5) -- Improved Fireball (cast time: tooltip-only in v0)
    local okDiff = pcall(HM.Impact.diff, base, modeled)
    check("talent what-if diff runs", okDiff)

    local summary = HM.Impact.talentSummary(26, 3)
    check("talentSummary humanizes rank 3", summary and approx(summary.ops[1].value, -300)
        and #summary.ops[1].affectedNames > 0)

    local byName = HM.findTalents("improved fireball")
    check("findTalents by name (case-insensitive)", #byName == 1 and byName[1].id == 26)
    check("findTalents partial lists candidates", #HM.findTalents("improved") > 1)

    -- Marginal stat conversions: Str/Agi/Int now move dimensions through classic rates.
    check("+10 Strength raises melee DPS (marginal AP)", (function()
        local changes = select(2, HM.Impact.explainStatDelta(base, "Strength", 10))
        for _, c in ipairs(changes) do
            if c.id == "meleeDps" and c.delta > 0 then return true end
        end
        return false
    end)())
    check("+10 Intellect raises spellcasting (spell crit)", (function()
        local changes = select(2, HM.Impact.explainStatDelta(base, "Intellect", 10))
        for _, c in ipairs(changes) do
            if c.id == "spellcasting" and c.delta > 0 then return true end
        end
        return false
    end)())
    check("unchanged stats keep snapshot AP exactly", (function()
        local built = base:build()
        return approx(built.graph:value("stat.attackPower", built.ctx), 60)
    end)())

    -- Stats panel model (the renderer is in-game only; the model is fully testable).
    local model = HM.PanelModel.build(base)
    check("panel model has 4 sections", model and #model.sections == 4)
    check("panel dimensions section has 7 rows", model.sections[1].rows and #model.sections[1].rows == 7)
    check("panel regen marks presumed formulas", (function()
        local v = model.sections[2].rows[1].value
        return type(v) == "string" and v:find("%(p%)") ~= nil
    end)())
    check("panel what-if rows are human lines", (function()
        local rows = model.sections[4].rows
        return #rows == 5 and rows[1].label == "+10 Spirit" and rows[1].value:find("mana/min") ~= nil
    end)())

    -- Tooltip injection module (S2): resolver + line builders are pure, fully testable.
    local function linesText(lines)
        local parts = {}
        for _, L in ipairs(lines or {}) do parts[#parts + 1] = L.text or L.left or "" end
        return table.concat(parts, "\n")
    end
    local impFB = gen and gen.talents and gen.talents[26]
    local fireTabIndex = 1
    if impFB then
        -- Derive the 1-based tab index the classic talent API would report for Fire.
        local fire = gen.talentTabs[impFB.tab]
        for _, tab in pairs(gen.talentTabs) do
            if tab.classMask == fire.classMask and tab.order < fire.order then
                fireTabIndex = fireTabIndex + 1
            end
        end
    end
    check("tooltip resolves talent by position", impFB and HM.Tooltips.resolveTalent(
        "MAGE", fireTabIndex, impFB.tier + 1, impFB.column + 1, "Improved Fireball") == 26)
    check("tooltip resolve falls back to name, rejects unknowns",
        impFB and HM.Tooltips.resolveTalent("MAGE", fireTabIndex, impFB.tier + 7, 1, "Improved Fireball") == 26
        and HM.Tooltips.resolveTalent("MAGE", 1, 1, 1, "No Such Talent") == nil)
    local tl = HM.Tooltips.talentLines(26, 2)
    check("tooltip header carries presumed rank-rule tag",
        tl and tl[1].kind == "double" and (tl[1].right or ""):find("(p)", 1, true) ~= nil)
    check("tooltip affects + next-point marginal value", (function()
        local text = linesText(tl)
        return text:find("Affects:", 1, true) ~= nil and text:find("Fireball", 1, true) ~= nil
            and text:find("Next point: -0.1s cast time (now -0.2s, max -0.5s)", 1, true) ~= nil
    end)(), tl and linesText(tl))
    check("tooltip maxed rank drops next-point line", (function()
        local text = linesText(HM.Tooltips.talentLines(26, 5))
        return text:find("Maxed: -0.5s cast time", 1, true) ~= nil
            and text:find("Next point", 1, true) == nil
    end)())
    check("tooltip dim fragment: damage talent moves a dimension", (function()
        local conc = HM.findTalents("Concussion")
        if #conc ~= 1 then return false end
        local text = linesText(HM.Tooltips.talentLines(conc[1].id, 1, base))
        return text:find("for you now:", 1, true) ~= nil
            and text:find("Spellcasting", 1, true) ~= nil
    end)())
    check("tooltip cast-time talent has no dim fragment yet (honest v0)", (function()
        local text = linesText(HM.Tooltips.talentLines(26, 2, base))
        return text:find("for you now:", 1, true) == nil
    end)())
    check("tooltip needs-curation honesty line", (function()
        local anyId
        for id, imp in pairs(gen.talentImpacts) do
            if imp.needsCuration then anyId = id; break end
        end
        local text = linesText(HM.Tooltips.talentLines(anyId, 0))
        return text:find("needs curation", 1, true) ~= nil
    end)())

    -- Collector + export plumbing (headless-degraded paths).
    check("guards select picks nth return",
        HM.Guards.select(2, function() return 1, 42, 7 end) == 42
        and HM.Guards.select(2, nil) == nil)
    check("talent adapter: modern convention, sparse cutoff, capture", (function()
        local savedApi = _G.C_SpecializationInfo
        HM.TalentAPI._resetForTest()
        -- Mock Forever's shape: table-query GetTalentInfo, only tab 1 has 2 talents.
        _G.C_SpecializationInfo = { GetTalentInfo = function(q)
            if type(q) == "table" and q.tabIndex == 1 and q.talentIndex <= 2 then
                return { name = "Mock Talent " .. q.talentIndex, tier = 2, column = 3,
                         rank = 1, maxRank = 5 }
            end
        end }
        local info = HM.TalentAPI.get(1, 1)
        local all = HM.TalentAPI.all()
        local captured = HM.Snapshot.captureTalents()
        local ok = info and info.name == "Mock Talent 1" and info.tier == 2
            and info.rank == 1 and info.maxRank == 5
            and HM.TalentAPI.mode() == "spec-table"
            and #all == 2 and #captured == 2 and captured[1].tier == 2
        _G.C_SpecializationInfo = savedApi
        HM.TalentAPI._resetForTest()
        return ok
    end)())
    check("collect session journals the data build", (function()
        if not HM.db then return false end
        local saved = HM.db.collect
        HM.db.collect = nil
        HM.Collect.onLogin()
        local s = HM.db.collect and HM.db.collect.sessions
        local ok = s and s[1] and s[1].dataBuild == HM.gen.build
        HM.db.collect = saved
        return ok
    end)())
    check("describeValue captures table keys + caps strings", (function()
        local d = HM.describeValue({ name = "X", nested = { a = 1 }, big = string.rep("y", 200) }, 2)
        return type(d) == "table" and d.name == "X" and type(d.nested) == "table"
            and d.nested.a == 1 and #d.big <= 123
    end)())
    check("talent API shape probe runs headless + persists", (function()
        local shape = HM.Collect.probeTalentApiShape(function() end)
        return shape and shape.calls
            and shape.calls["CSI.GetTalentInfo(1,1)"].present == false
            and HM.db.collect.talentApiShape ~= nil
    end)())
    check("serialize renders nested tables", (function()
        local s = HM.serialize({ a = 1, b = { c = "x" } })
        return s:find('c = "x"') ~= nil and s:find("a = 1") ~= nil
    end)())
    check("collect.verify runs headless and persists", (function()
        if not HM.db then return false end
        local v = HM.Collect.verify(function() end)
        return v and #v.results >= 5 and HM.db.collect and HM.db.collect.verify ~= nil
    end)())
    check("tampered SavedVariables degrade to defaults", (function()
        local saved = _G.ForesightDB
        _G.ForesightDB = "corrupted garbage"
        HM.initSavedVariables()
        local ok = type(_G.ForesightDB) == "table" and type(_G.ForesightDB.chars) == "table"
        _G.ForesightDB = saved
        HM.db = saved
        return ok
    end)())
    check("corrupted collect store self-heals", (function()
        local saved = HM.db.collect
        HM.db.collect = 12345
        local v = HM.Collect.verify(function() end)
        local ok = type(HM.db.collect) == "table" and v ~= nil
        HM.db.collect = saved
        return ok
    end)())

    -- Scoreboard -------------------------------------------------------------------
    for _, c in ipairs(checks) do
        out(("%s %s%s"):format(c.ok and "PASS" or "FAIL", c.name,
            (not c.ok and c.detail) and (" [" .. tostring(c.detail) .. "]") or ""))
    end
    out(("selftest: %d/%d passed"):format(#checks - failed, #checks))
    return failed == 0, checks
end

return HM.runSelftest
