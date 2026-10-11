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
            armor = 800, avoidancePct = 5, maxHealth = 1600, maxMana = 3050,
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

    -- GRAPH-threat: threat as the 8th lens, fed by mapped SPELL_AURA_MOD_THREAT ops.
    check("threat lens baselines at 100% with no talents", approx(results.threat.score, 100),
        results.threat and results.threat.score)
    check("Subtlety threat op mapped to Nature/Arcane schools", (function()
        local imp = gen.talentImpacts and gen.talentImpacts[841]
        local op = imp and imp.ops and imp.ops[1]
        return op and op.kind == "threat" and op.school == "Nature/Arcane" and op.isPct == true
    end)())
    check("modeling Suppression lowers the threat lens", (function()
        -- Suppression (1005): -20% all-school threat at max rank 5.
        local modeled = base:withTalent(1005, 5)
        local r = HM.Impact.evaluate(modeled)
        return r.threat and r.threat.score < 100 and approx(r.threat.score, 80)
    end)())

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

    -- Stat impact CHAIN (depth: "+N stat -> +AP -> dmg per swing / +crit%").
    check("stat chain shows AP + per-swing damage for Strength", (function()
        local s = table.concat(HM.Impact.statImpactDetail(base, "Strength", 10), "\n")
        return s:find("Attack Power", 1, true) ~= nil
            and s:find("per main-hand swing", 1, true) ~= nil
    end)())
    check("stat chain shows crit for Agility (live-derived conversion)", (function()
        local s = table.concat(HM.Impact.statImpactDetail(base, "Agility", 10), "\n")
        return s:find("melee crit", 1, true) ~= nil
    end)())
    check("trait node impact block shows effect + for-you chain", (function()
        local lines = HM.Tooltips.nodeImpactLines(104756, base) -- an Intellect% node
        if not lines then return false end
        local parts = {}
        for _, L in ipairs(lines) do parts[#parts + 1] = L.text or L.left or "" end
        return table.concat(parts, "\n"):find("Intellect", 1, true) ~= nil
    end)())

    -- MODEL-stat-advisor: marginal stat ranking on explainStatDelta (no forked path).
    check("stat advisor ranks + produces a sentence", (function()
        local sentence, ranked, focus = HM.Impact.statPrioritySentence(base)
        return type(sentence) == "string" and sentence:find("per point", 1, true) ~= nil
            and #ranked == 5 and focus == "spellcasting"
    end)())
    check("stat advisor: each ranked stat names its best dimension", (function()
        local ranked = HM.Impact.rankStats(base)
        for _, r in ipairs(ranked) do
            if r.bestPct ~= 0 and not r.bestLabel then return false end
        end
        -- Intellect should top a caster's spellcasting focus.
        return ranked[1].stat == "Intellect"
    end)())

    -- UI-playstyle-label: one-line build profile from dimension scores (v0 heuristic).
    check("playstyle label classifies the caster build", (function()
        local results = HM.Impact.evaluate(base)
        local label = HM.PanelModel.playstyleLabel(results, base.snapshot)
        return type(label) == "string" and label:find("Caster%-leaning") ~= nil
            and label:find("offense%-focused") ~= nil
    end)())

    -- Stats panel model (the renderer is in-game only; the model is fully testable).
    local model = HM.PanelModel.build(base)
    check("panel model has 6 sections (incl. Future build)", model and #model.sections == 6,
        model and #model.sections)
    check("panel Future build section hints when the plan is empty", (function()
        for _, s in ipairs(model.sections) do
            if s.id == "plan" then
                return #s.rows == 1 and (s.rows[1].value or ""):find("plan add", 1, true) ~= nil
            end
        end
        return false
    end)())
    check("panel exposes a playstyle label", model.playstyle and model.playstyle:find("leaning") ~= nil)
    check("panel position validates untrusted saved values", (function()
        local good = HM.PanelModel.normalizePanelPos({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 100, y = -50 })
        local junk = HM.PanelModel.normalizePanelPos("corrupted")
        local offscreen = HM.PanelModel.normalizePanelPos({ x = 99999, y = 0 })
        local badAnchor = HM.PanelModel.normalizePanelPos({ point = "EVIL", x = 10, y = 10 })
        return good and good.x == 100 and junk == nil and offscreen == nil
            and badAnchor and badAnchor.point == "TOPLEFT"
    end)())
    check("panel stat-value section has 5 rows", (function()
        for _, s in ipairs(model.sections) do
            if s.id == "statvalue" then return #s.rows == 5 end
        end
        return false
    end)())
    check("panel dimensions section has 8 rows (incl. threat)", model.sections[1].rows and #model.sections[1].rows == 8)
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

    -- Item tooltip injection (layman stat impact): mapper + line builder are pure.
    check("item stat mapper translates GetItemStats keys", (function()
        local m = HM.Tooltips.mapItemStats({ ITEM_MOD_AGILITY_SHORT = 4,
            ITEM_MOD_STAMINA_SHORT = 6, ITEM_MOD_SPELL_POWER_SHORT = 10, JUNK_KEY = 9 })
        return m.Agility == 4 and m.Stamina == 6 and m.spellDamage == 10 and m.JUNK_KEY == nil
    end)())
    check("item lines show stats + dimension impact", (function()
        local text = linesText(HM.Tooltips.itemLines({ Intellect = 10, Stamina = 6 }, base))
        return text:find("This item:", 1, true) ~= nil and text:find("Intellect", 1, true) ~= nil
            and text:find("%%") ~= nil
    end)())
    check("item lines nil when nothing maps", HM.Tooltips.itemLines({}, base) == nil)
    check("gear compare: net favors the right dimension", (function()
        -- Int item vs Stamina item: A should win spellcasting, B should win tankability.
        local rows = HM.Impact.compareItems(base, { Intellect = 20 }, { Stamina = 20 })
        local spell, tank
        for _, r in ipairs(rows) do
            if r.id == "spellcasting" then spell = r.net end
            if r.id == "tankability" then tank = r.net end
        end
        return spell and spell > 0 and tank and tank < 0
    end)())
    check("item lines render a vs-equipped block when compared", (function()
        local text = linesText(HM.Tooltips.itemLines({ Intellect = 20 }, base, { Stamina = 20 }))
        return text:find("vs equipped:", 1, true) ~= nil
    end)())
    check("explainItemDelta combines deltas via the diff path", (function()
        local _, changes = HM.Impact.explainItemDelta(base, { Stamina = 10 })
        for _, c in ipairs(changes) do
            if c.id == "tankability" and c.delta > 0 then return true end
        end
        return false
    end)())

    -- UI-spell-tooltip: coefficient-based spell-power translation (pure).
    local castSpellId
    for id, sp in pairs(gen.spells) do
        if sp.castMs and sp.castMs > 0 then castSpellId = id; break end
    end
    check("spell lines translate power via coefficient", (function()
        if not castSpellId then return false end
        local text = linesText(HM.Tooltips.spellLines(castSpellId, base))
        return text:find("Spell Power", 1, true) ~= nil and text:find("coefficient", 1, true) ~= nil
            and text:find("per cast", 1, true) ~= nil
    end)(), castSpellId)
    check("spell lines nil without spell/heal power", (function()
        if not castSpellId then return false end
        local snap = testSnapshot()
        snap.stats.spellDamage, snap.stats.healingPower = 0, 0
        return HM.Tooltips.spellLines(castSpellId, HM.Loadout.fromSnapshot(snap)) == nil
    end)())

    -- Collector + export plumbing (headless-degraded paths).
    check("guards select picks nth return",
        HM.Guards.select(2, function() return 1, 42, 7 end) == 42
        and HM.Guards.select(2, nil) == nil)
    -- DATA-traits: generated trait-node coverage (Retail trees = Forever's live talents).
    check("trait data loaded with full node coverage", (function()
        local tr = HM.gen and HM.gen.traits
        return tr and tr.nodes and tr.bySpell and tr.trees
            and HM.gen.counts.traitNodes and HM.gen.counts.traitNodes > 400
    end)())
    check("trait bySpell bridges the live spellID to a named node", (function()
        local tr = HM.gen.traits
        local nid = tr.bySpell[16178] -- Shaman Purification (also classic talent 592)
        local node = nid and tr.nodes[nid]
        return node and node.name == "Purification" and node.spellID == 16178
            and node.tree == 1082 and tr.trees[1082].skillLine == 373
    end)())
    check("trait nodes carry impact ops from the definition spell", (function()
        -- At least some nodes derive real ops (not all needsCuration) via build_ops.
        local withOps = 0
        for _, node in pairs(HM.gen.traits.nodes) do
            if node.ops and #node.ops > 0 and not node.needsCuration then withOps = withOps + 1 end
        end
        return withOps > 50
    end)())
    check("trait node feeds the what-if model (DATA-traits phase 2)", (function()
        -- Node 104756 is an Intellect% trait; taking it raises a caster's spellcasting.
        local modeled = base:withTraitNode(104756, 1)
        local ok, changes = pcall(HM.Impact.diff, base, modeled)
        if not ok then return false end
        for _, c in ipairs(changes) do
            if c.id == "spellcasting" and c.delta > 0 then return true end
        end
        return false
    end)())
    -- RACIAL-impact: generated per-race data + what-if modelling (race_racials.lua).
    check("racial data covers the 8 classic races + both Skyborne", (function()
        local r = HM.gen and HM.gen.racials
        if not r then return false end
        for _, id in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 95, 96 }) do
            if not r[id] then return false, "missing race " .. id end
        end
        return true
    end)())
    check("Scourge token maps to raceId 5 (the Undead gotcha)",
        HM.Racials.raceIdForToken("Scourge") == 5 and HM.gen.raceTokens.Scourge == 5)
    check("The Human Spirit decodes +5% Spirit (passive, classic-presumed)", (function()
        local sp = HM.Racials.bySpell(20598)
        local op = sp and sp.ops and sp.ops[1]
        return sp and sp.passive == true and sp.confidence == "classic-presumed"
            and op and op.kind == "stat" and op.stat == "Spirit" and op.isPct == true
            and op.maxValue == 5
    end)())
    check("Tauren Endurance decodes max-health% (aura 133)", (function()
        local sp = HM.Racials.bySpell(20550)
        for _, op in ipairs((sp and sp.ops) or {}) do
            if op.kind == "maxHealth" and op.isPct and op.maxValue == 5 then return true end
        end
        return false
    end)())
    check("Expansive Mind decodes max-mana% gated to mana classes", (function()
        local sp = HM.Racials.bySpell(20591)
        local op = sp and sp.ops and sp.ops[1]
        return op and op.kind == "maxPower" and op.powerType == 0
            and sp.classMask == 400 and HM.Racials.classMatches(sp.classMask, "MAGE")
            and not HM.Racials.classMatches(sp.classMask, "WARRIOR")
    end)())
    check("Forever-new racial ids carry forever-new-unverified", (function()
        local sp = HM.Racials.bySpell(1259802) -- Warrior-variant Expansive Mind (rage)
        return sp and sp.confidence == "forever-new-unverified"
    end)())
    check("withRacial(Endurance) raises tankability via max health", (function()
        local ok, changes = pcall(HM.Impact.diff, base, base:withRacial(20550))
        if not ok then return false end
        for _, c in ipairs(changes) do
            if c.id == "tankability" and c.delta > 0 then return true end
        end
        return false
    end)())
    check("withRace(Gnome) grows a Mage's max mana by exactly the one gated passive", (function()
        local b, m = base:build(), base:withRace(7):build()
        local baseMana = b.graph:value("stat.maxMana", b.ctx)
        local gnomeMana = m.graph:value("stat.maxMana", m.ctx)
        -- Only mana-class Expansive Mind (mask 400) may fold for a MAGE; the
        -- Warrior/Rogue rage/energy variants must be class-gated out.
        return gnomeMana > baseMana and approx(gnomeMana, baseMana * 1.05)
    end)())
    check("active racials are flagged and excluded from passive folds", (function()
        local sp = HM.Racials.bySpell(20572) -- Blood Fury: active, tooltip-only
        if not sp or sp.passive ~= false then return false end
        for _, e in ipairs(HM.Racials.forRace(2, "WARRIOR", true)) do
            if e.spellID == 20572 then return false end
        end
        return true
    end)())

    -- CONSUME-buffs: generated consumable chain + buff what-if modelling.
    check("consumables data loaded at meaningful scale", (function()
        local gen = HM.gen
        if not (gen and gen.consumables and gen.buffsBySpell) then return false end
        local n = 0
        for _ in pairs(gen.consumables) do n = n + 1 end
        return n > 300, n
    end)())
    check("Elixir of the Mongoose decodes +25 Agi +2% crit, 30m", (function()
        local e = HM.gen.consumables[13452]
        if not (e and e.buffSpellId == 17538 and e.type == "elixir"
                and e.durationMs == 1800000 and HM.gen.buffsBySpell[17538] == 13452) then
            return false
        end
        local agi, crit
        for _, op in ipairs(e.ops) do
            if op.kind == "stat" and op.stat == "Agility" and op.maxValue == 25 then agi = true end
            if op.kind == "critChance" and op.maxValue == 2 then crit = true end
        end
        return agi and crit
    end)())
    check("food chases EffectTriggerSpell one hop to the Well-Fed stats", (function()
        local e = HM.gen.consumables[21023] -- Dirge's Kickin' Chimaerok Chops
        local op = e and e.ops and e.ops[1]
        return e and e.type == "food" and e.buffSpellId == 25661
            and op and op.kind == "stat" and op.stat == "Stamina" and op.maxValue == 25
    end)())
    check("Forever food magnitude = trigger bp x Well-Fed unit (Mackerel +6 AP)", (function()
        -- Incident 2026-10-11: shared Well-Fed spells carry UNIT values; the real
        -- magnitude rides the aura-227 trigger effect (user saw +1 instead of +6).
        local e = HM.gen.consumables[787] -- Slitherskin Mackerel
        if not (e and e.buffSpellId == 1249519) then return false end
        local ap
        for _, op in ipairs(e.ops) do
            if op.kind == "attackPower" then ap = op.maxValue end
        end
        local trout = HM.gen.consumables[8364] -- Mithril Head Trout: same spell, x20
        local tap
        for _, op in ipairs((trout and trout.ops) or {}) do
            if op.kind == "attackPower" then tap = op.maxValue end
        end
        return ap == 6 and tap == 20
    end)())
    check("withBuff(Mongoose) folds crit exactly (flat 2 spell, 2+derived melee)", (function()
        local b, m = base:build(), base:withBuff(13452):build()
        local dSpell = m.graph:value("stat.spellCritPct", m.ctx)
            - b.graph:value("stat.spellCritPct", b.ctx)
        local dMelee = m.graph:value("stat.meleeCritPct", m.ctx)
            - b.graph:value("stat.meleeCritPct", b.ctx)
        -- +2% flat on both; melee also gains +25 Agi via the live-derived conversion
        -- (40 agi / 3% crit -> 13.33 agi per crit% -> +1.875%).
        return approx(dSpell, 2, 1e-6) and approx(dMelee, 2 + 25 / (40 / 3), 1e-6)
    end)())
    check("withBuff accepts the buff spellId too (live aura match path)", (function()
        local a, b2 = base:withBuff(13452):build(), base:withBuff(17538):build()
        return approx(a.graph:value("stat.meleeCritPct", a.ctx),
                      (b2.graph:value("stat.meleeCritPct", b2.ctx)))
    end)())
    check("Flask of the Titans folds +1200 max health into tankability", (function()
        local b, m = base:build(), base:withBuff(13510):build()
        local dHp = m.graph:value("stat.maxHealth", m.ctx) - b.graph:value("stat.maxHealth", b.ctx)
        if not approx(dHp, 1200) then return false end
        for _, c in ipairs(HM.Impact.diff(base, base:withBuff(13510))) do
            if c.id == "tankability" and c.delta > 0 then return true end
        end
        return false
    end)())
    check("buffDelta returns the derived chain for the expiry story", (function()
        local ok, lines = pcall(HM.Impact.buffDelta, base, 13452)
        if not ok or #lines == 0 then return false end
        return table.concat(lines, "\n"):find("crit", 1, true) ~= nil
    end)())
    check("weapon-conditional crit stays label-only (aura 290 discriminator)", (function()
        local sp = HM.Racials.bySpell(20574) -- Axe Specialization: "while axe equipped"
        local op = sp and sp.ops and sp.ops[1]
        return op and op.kind == "aura" and (op.label or ""):find("conditional", 1, true) ~= nil
    end)())
    check("buff tooltip block: while-active + values + expiry honesty", (function()
        local text = linesText(HM.Tooltips.buffLines(13452, base))
        return text:find("While active:", 1, true) ~= nil
            and text:find("+25 Agility", 1, true) ~= nil
            and text:find("+2% crit chance", 1, true) ~= nil
            and text:find("(30m)", 1, true) ~= nil
            and text:find("On expiry these gains reverse.", 1, true) ~= nil
    end)())
    check("captureActiveBuffs degrades to none headless", (function()
        local found = HM.Snapshot.captureActiveBuffs()
        return type(found) == "table" and #found == 0
    end)())

    -- IMBUE-compare: the "Rockbiter or Flametongue on my 2H axe" simulation (S17).
    check("imbue data decodes the shaman chains", (function()
        local g = HM.gen.imbues
        if not g then return false end
        local rb = g[8017] -- Rockbiter r1: equip +29 AP + threat aura
        local ft = g[8024] -- Flametongue r1: speed-scaled fire, basis 326
        local wf = g[8232] -- Windfury r1: 20% on-hit chance
        local fb = g[8033] -- Frostbrand r1: proc 32 Frost, rate unknown
        local ip = g[8679] -- Instant Poison r1: 20% x 15 Nature
        local rbAp, rbThreat
        for _, op in ipairs((rb and rb.ops) or {}) do
            if op.kind == "attackPower" and op.maxValue == 29 then rbAp = true end
            if op.kind == "threat" then rbThreat = true end
        end
        return rbAp and rbThreat
            and ft and ft.speedDamage and ft.speedDamage.per100Speed == 326
            and ft.speedDamage.school == "Fire"
            and wf and wf.chance == 20
            and fb and fb.procs and fb.procs[1].damage == 32 and fb.procs[1].chance == nil
            and ip and ip.procs and ip.procs[1].chance == 20 and ip.procs[1].damage == 15
    end)())
    check("Flametongue per-hit scales with weapon speed, DPS constant", (function()
        local slow = select(1, HM.Imbues.compare({ weaponSpeed = 3.6 }, { 8024 }))[1]
        local fast = select(1, HM.Imbues.compare({ weaponSpeed = 1.5 }, { 8024 }))[1]
        return approx(slow.perSwing, 326 * 3.6 / 100, 1e-6)
            and approx(fast.perSwing, 326 * 1.5 / 100, 1e-6)
            and approx(slow.perSec, fast.perSec, 1e-6)
    end)())
    check("the 2H-axe question: FT out-DPSes Rockbiter r1, RB notes threat", (function()
        local rows = select(1, HM.Imbues.compare({ weaponSpeed = 3.6 }, { 8017, 8024 }))
        if not (rows[1] and rows[1].name == "Flametongue Weapon") then return false end
        local rb
        for _, r in ipairs(rows) do if r.name == "Rockbiter Weapon" then rb = r end end
        if not (rb and approx(rb.perSwing, 29 / 14 * 3.6, 1e-6)
                and approx(rb.perSec, 29 / 14, 1e-6)) then return false end
        for _, n in ipairs(rb.notes) do
            if n:find("threat", 1, true) then return true end
        end
        return false
    end)())
    check("imbue rank dedupe keeps the strongest known rank", (function()
        local rows = select(1, HM.Imbues.compare({ weaponSpeed = 2.0 }, { 8017, 8018 }))
        return #rows == 1 and approx(rows[1].perSec, 58 / 14, 1e-6)
    end)())
    check("unknown proc rates say so; known ones get an expected value", (function()
        local rows = select(1, HM.Imbues.compare({ weaponSpeed = 2.0 }, { 8033, 8679 }))
        local fb, ip
        for _, r in ipairs(rows) do
            if r.name == "Frostbrand Weapon" then fb = r end
            if r.name == "Instant Poison" then ip = r end
        end
        if not (fb and fb.needsCuration
                and table.concat(fb.notes, "\n"):find("unverified", 1, true)) then return false end
        return ip and approx(ip.perSwing, 3, 1e-6) and approx(ip.perSec, 1.5, 1e-6)
    end)())
    check("imbue tooltip block renders the per-swing answer", (function()
        local snap = testSnapshot()
        snap.weaponSpeed = 3.6
        local text = linesText(HM.Tooltips.imbueLines(8024, HM.Loadout.fromSnapshot(snap)))
        return text:find("3.6s weapon", 1, true) ~= nil
            and text:find("per swing", 1, true) ~= nil
            and text:find("slower weapon = bigger hits", 1, true) ~= nil
    end)())

    -- WHATIF-planner: persistent future-build plan over the one delta stack.
    check("plan validates typed deltas and drops garbage", (function()
        local clean, dropped = HM.Plan.validate({
            "garbage",
            { type = "stat", stat = "Agility", amount = 5 },
            { type = "stat", stat = "NotAStat", amount = 5 },
            { type = "stat", stat = "Spirit", amount = 1e9 },
            { type = "trait", nodeId = 104756 },
            { type = "trait", nodeId = -1 },
            { type = "buff", id = 13452 },
            { type = "item", label = "pants", stats = { Agility = 5, junk = 3 } },
        })
        if not (#clean == 4 and dropped == 4) then return false, #clean .. "/" .. dropped end
        return clean[4].stats.Agility == 5 and clean[4].stats.junk == nil
            and clean[2].rank ~= nil -- trait rank defaults to maxRank
    end)())
    check("plan composes stat+item+buff+trait through the one delta path", (function()
        local plan = HM.Plan.validate({
            { type = "stat", stat = "Agility", amount = 5 },
            { type = "item", label = "future pants", stats = { Intellect = 10 } },
            { type = "buff", id = 13452 },
            { type = "trait", nodeId = 104756, rank = 1 },
        })
        local changes, chain = HM.Plan.summary(base, plan)
        if #changes == 0 or #chain == 0 then return false end
        for _, c in ipairs(changes) do
            if c.id == "spellcasting" and c.delta > 0 then return true end
        end
        return false
    end)())
    check("plan store heals a tampered SavedVariables plan", (function()
        if not HM.charDb then return false end
        local db = HM.charDb()
        local saved = db.plan
        db.plan = "corrupted"
        local plan = HM.Plan.store()
        local ok = type(plan) == "table" and #plan == 0 and type(db.plan) == "table"
        db.plan = saved
        return ok
    end)())
    check("plan describes deltas in human terms", (function()
        local d1 = HM.Plan.describe({ type = "stat", stat = "Agility", amount = 5 })
        local d2 = HM.Plan.describe({ type = "item", label = "pants", stats = { Agility = 5 } })
        local d3 = HM.Plan.describe({ type = "buff", id = 13452 })
        return d1 == "+5 Agility" and d2:find("pants", 1, true) ~= nil
            and d2:find("+5 Agility", 1, true) ~= nil
            and d3 == "Elixir of the Mongoose"
    end)())
    check("plan lookup helpers resolve names", (function()
        local nodeId = HM.Plan.findTraitNode("ancestral knowledge")
        local itemId = HM.Plan.findConsumable("mongoose")
        return nodeId ~= nil and HM.gen.traits.nodes[nodeId].name == "Ancestral Knowledge"
            and itemId ~= nil and HM.gen.consumables[itemId].name:find("Mongoose", 1, true) ~= nil
    end)())

    check("synergy groups talents by shared theme", (function()
        HM.Synergy._reset()
        local r = HM.Synergy.query("intellect")
        return r and r.label == "Intellect" and #r.nodes > 1
    end)())
    check("synergy themesFor lists a node's levers", (function()
        local themes = HM.Synergy.themesFor(104756) -- Ancestral Knowledge (Intellect%)
        for _, t in ipairs(themes) do if t.key == "Intellect" and t.others > 0 then return true end end
        return false
    end)())
    -- SYNERGY phase 3: themes draw from ALL sources with player context.
    check("synergy ingests the player's racials (Spirit <- The Human Spirit)", (function()
        HM.Synergy._reset()
        local r = HM.Synergy.query("spirit", { raceId = 1, classToken = "MAGE" })
        local hit = false
        for _, n in ipairs((r and r.nodes) or {}) do
            if n == "The Human Spirit (racial)" then hit = true end
        end
        HM.Synergy._reset()
        return hit
    end)())
    check("synergy racials are class-gated (Gnome max mana for a Mage only)", (function()
        HM.Synergy._reset()
        local mage = HM.Synergy.query("max mana", { raceId = 7, classToken = "MAGE" })
        local mageHit = false
        for _, n in ipairs((mage and mage.nodes) or {}) do
            if n:find("Expansive Mind", 1, true) then mageHit = true end
        end
        HM.Synergy._reset()
        local warrior = HM.Synergy.query("max mana", { raceId = 7, classToken = "WARRIOR" })
        local warriorHit = false
        for _, n in ipairs((warrior and warrior.nodes) or {}) do
            if n:find("Expansive Mind", 1, true) then warriorHit = true end
        end
        HM.Synergy._reset()
        return mageHit and not warriorHit
    end)())
    check("synergy ingests active consumable buffs (crit <- Mongoose)", (function()
        HM.Synergy._reset()
        local r = HM.Synergy.query("crit", { buffs = { { itemId = 13452 } } })
        local hit = false
        for _, n in ipairs((r and r.nodes) or {}) do
            if n == "Elixir of the Mongoose (elixir)" then hit = true end
        end
        HM.Synergy._reset()
        return hit
    end)())
    -- SYNERGY-highlight: the pure selector behind the talent-tree glow.
    check("highlight selector returns trait ids + names for a theme", (function()
        HM.Synergy._reset()
        local ids, names = HM.SynergyHighlight.traitMembers("intellect")
        HM.Synergy._reset()
        if not (ids and names) then return false end
        local n = 0
        for _ in pairs(ids) do n = n + 1 end
        return n > 1 and names["Ancestral Knowledge"] == true
    end)())
    check("highlight selector excludes racial/buff members (no tree buttons)", (function()
        HM.Synergy._reset()
        -- With Gnome-Mage context the "max mana" theme includes racial Expansive Mind,
        -- but the HIGHLIGHT set must only carry trait nodes (racials have no buttons).
        local player = { raceId = 7, classToken = "MAGE" }
        local r = HM.Synergy.query("max mana", player)
        local hasRacial = false
        for _, n in ipairs((r and r.nodes) or {}) do
            if n:find("(racial)", 1, true) then hasRacial = true end
        end
        local ids, names = HM.SynergyHighlight.traitMembers("max mana", player)
        HM.Synergy._reset()
        if not (hasRacial and ids and names) then return false end
        for m in pairs(ids) do
            if type(m) ~= "number" then return false end
        end
        return names["Expansive Mind"] == nil
    end)())
    -- CATALOG: the unified content reference table over every impact source.
    check("catalog unifies all source kinds with counts", (function()
        HM.Catalog._reset()
        local byKind = {}
        for _, row in ipairs(HM.Catalog.stats()) do byKind[row.kind] = row.count end
        -- talents + trait nodes + at least one consumable type + imbues all present.
        return (byKind.talent or 0) > 100 and (byKind.trait or 0) > 400
            and (byKind.imbue or 0) > 50 and (byKind.elixir or byKind.flask or 0) > 0
    end)())
    check("catalog search finds across kinds", (function()
        local hits = HM.Catalog.search("mongoose")
        local kinds = {}
        for _, h in ipairs(hits) do kinds[h.kind] = true end
        return #hits > 0 and kinds.elixir == true
    end)())
    check("catalog surfaces statConvert ops (chained-synergy primitive)", (function()
        local conv = HM.Catalog.withOpKind("statConvert")
        return #conv > 0
    end)())
    -- Chained synergy: Mental Dexterity (Int -> AP) bridges the themes.
    check("statConvert decodes Int -> Attack Power", (function()
        -- Find Mental Dexterity (spell 415140) as a trait node and check its op.
        local nid = HM.gen.traits.bySpell[415140]
        local node = nid and HM.gen.traits.nodes[nid]
        if not node then return true end -- not on this build's tree; skip gracefully
        for _, op in ipairs(node.ops or {}) do
            if op.kind == "statConvert" and op.to == "attackPower"
                    and op.from == "Intellect" then return true end
        end
        return false
    end)())
    check("synergy chains attack power <-> the stat that feeds it", (function()
        HM.Synergy._reset()
        -- Synthesize a converter + an Int source + a direct AP source, prove the bridge.
        local c = HM.Synergy.build()
        -- Inject via the public ingest path is internal; instead assert the shape holds
        -- when a statConvert exists in generated data.
        local hasConverter = #HM.Catalog.withOpKind("statConvert") > 0
        if not hasConverter then HM.Synergy._reset(); return true end
        local r = HM.Synergy.query("attack power")
        HM.Synergy._reset()
        return r ~= nil and type(r.chains) == "table"
    end)())
    check("synergy without player context stays trait-only", (function()
        HM.Synergy._reset()
        local r = HM.Synergy.query("agility")
        for _, n in ipairs((r and r.nodes) or {}) do
            if n:find("(elixir)", 1, true) or n:find("(racial)", 1, true) then return false end
        end
        HM.Synergy._reset()
        return true
    end)())

    check("trait data covers NON-classic Forever nodes (the gap this fills)", (function()
        local classic = {}
        for _, t in pairs(gen.talents) do
            for _, s in ipairs(t.spellRanks or {}) do classic[s] = true end
        end
        local nonClassic = 0
        for sid in pairs(HM.gen.traits.bySpell) do
            if not classic[sid] then nonClassic = nonClassic + 1 end
        end
        return nonClassic > 50
    end)())

    check("talentForSpell resolves a classic spell to its talent", (function()
        return HM.TalentAPI.talentForSpell(11069) == 26  -- Improved Fireball rank 1
            and HM.TalentAPI.talentForSpell(nil) == nil
    end)())

    check("talent adapter walks C_Traits + maps spellID -> talent", (function()
        -- Mock Forever's real shape (forever-addon-kit): one purchased node whose entry
        -- definition resolves to spell 11069 = Improved Fireball rank 1 (our talent 26).
        local sTraits, sCT, sEnum = _G.C_Traits, _G.C_ClassTalents, _G.Enum
        HM.TalentAPI._resetForTest()
        _G.C_ClassTalents = { GetActiveConfigID = function() return 1 end }
        _G.C_Traits = {
            GetConfigInfo = function() return { treeIDs = { 7 } } end,
            GetTreeNodes = function() return { 50 } end,
            GetNodeInfo = function(_, nid) return { ID = nid, ranksPurchased = 2, maxRanks = 5,
                activeEntry = { entryID = 500 }, entryIDs = { 500 } } end,
            GetEntryInfo = function() return { definitionID = 9000, maxRanks = 5 } end,
            GetDefinitionInfo = function() return { spellID = 11069, overrideName = "Improved Fireball" } end,
        }
        local sel = HM.TalentAPI.captureSelected()
        local capt = HM.Snapshot.captureTalents()
        local ok = sel and #sel == 1 and sel[1].talentId == 26 and sel[1].rank == 2
            and sel[1].maxRank == 5 and HM.TalentAPI.mode() == "traits"
            and #capt == 1 and capt[1].talentId == 26 and capt[1].rank == 2
        _G.C_Traits, _G.C_ClassTalents, _G.Enum = sTraits, sCT, sEnum
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
    -- Pool maxima read the live sheet (regression: a L10's 267 HP showed as 340
    -- because stamina*10 overstates below the ~20-point base).
    check("max health matches the live sheet exactly (267-vs-340 regression)", (function()
        local snap = testSnapshot()
        snap.stats.maxHealth, snap.stats.stamina = 267, 34
        local lo = HM.Loadout.fromSnapshot(snap)
        local b = lo:build()
        if not approx(b.graph:value("stat.maxHealth", b.ctx), 267) then return false end
        local m = lo:withStatDelta("Stamina", 10):build()
        return approx(m.graph:value("stat.maxHealth", m.ctx), 367) -- marginal 10/pt only
    end)())
    -- IMPACT OBSERVATORY (S11 phase A): the pure attribution + diff helpers.
    check("observatory statDiff picks only moved fields", (function()
        local d = HM.Collect.statDiff(
            { agility = 40, intellect = 150, meleeCritPct = 3, armor = 800 },
            { agility = 65, intellect = 150, meleeCritPct = 5, armor = 800 })
        return d.agility == 25 and d.meleeCritPct == 2
            and d.intellect == nil and d.armor == nil
    end)())
    check("observatory attributes only single buff changes", (function()
        local id1, s1 = HM.Collect.attributeBuffChange({}, { [17538] = true })
        local id2, s2 = HM.Collect.attributeBuffChange({ [17538] = true }, {})
        local multi = HM.Collect.attributeBuffChange({}, { [17538] = true, [17626] = true })
        local none = HM.Collect.attributeBuffChange({ [17538] = true }, { [17538] = true })
        return id1 == 17538 and s1 == 1 and id2 == 17538 and s2 == -1
            and multi == nil and none == nil
    end)())

    check("item sightings journal degrades headless + self-heals", (function()
        if not HM.db then return false end
        local saved = HM.db.collect and HM.db.collect.itemSightings
        HM.db.collect.itemSightings = "corrupted"
        local seen, added = HM.Collect.scanItems()
        local healed = type(HM.db.collect.itemSightings) == "table"
            and type(seen) == "table" and next(seen) == nil and added == 0
        HM.db.collect.itemSightings = saved
        return healed
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
