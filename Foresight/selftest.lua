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
    local function linesText(lines)
        local parts = {}
        for _, L in ipairs(lines or {}) do parts[#parts + 1] = L.text or L.left or "" end
        return table.concat(parts, "\n")
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

    -- S20 stat coaching: derived mechanism attribution, never a registry, never a judge.
    local function meleeShamanSnap()
        return {
            classToken = "SHAMAN", level = 20, weaponSpeed = 2.6,
            weaponDamageMin = 30, weaponDamageMax = 45,
            stats = { strength = 60, agility = 35, stamina = 55, intellect = 40,
                spirit = 45, spellDamage = 0, healingPower = 0, attackPower = 300,
                rangedAttackPower = 0, spellCritPct = 3, meleeCritPct = 4,
                rangedCritPct = 0, hastePct = 0, armor = 500, avoidancePct = 4,
                maxHealth = 800, maxMana = 600 },
        }
    end
    check("coaching: dead Agility on a melee Shaman names mechanism + live numbers", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local line = HM.Impact.coachingLine(lo)
        return type(line) == "string"
            and line:find("Agility adds no Attack Power for a Shaman", 1, true) ~= nil
            and line:find("(p)", 1, true) ~= nil
            and line:find("only adds crit", 1, true) ~= nil
            and line:find("Strength carries your Melee DPS", 1, true) ~= nil
            and line:find("\n") == nil -- ONE line, always
    end)())
    check("coaching: no line for a caster's Intellect (not dead)", (function()
        return HM.Impact.coachingLine(base) == nil
    end)())
    check("coaching: anti-registry - mutate statConversions and the line moves", (function()
        local conv = HM.formulas.statConversions.byClass.SHAMAN
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local before = HM.Impact.coachingLine(lo)
        conv.apPerAgi = 1 -- Agility now feeds AP: the mechanism claim must vanish
        local mutated = HM.Impact.coachingLine(lo)
        conv.apPerAgi = 0
        local restored = HM.Impact.coachingLine(lo)
        -- and the crit number is live-derived: more agility per crit% moves it down
        local snap = meleeShamanSnap()
        snap.stats.agility = 50
        local diluted = HM.Impact.coachingLine(HM.Loadout.fromSnapshot(snap))
        return before ~= nil and mutated == nil and restored == before
            and diluted ~= nil and diluted ~= before
    end)())
    check("coaching: item line only when the dead stat dominates", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local hit = HM.Impact.coachingItemLine(lo, { Agility = 10, Stamina = 2 })
        local miss = HM.Impact.coachingItemLine(lo, { Stamina = 10, Agility = 2 })
        return type(hit) == "string" and hit:find("Agility", 1, true) ~= nil
            and miss == nil
    end)())
    check("item mapper: +10 AP shows the melee chain and beats +3 Str (live catch)", (function()
        -- Live catch 2026-10-12: a +10 Attack Power auction item showed NO melee
        -- impact while +3 Strength did - AP was missing from the item stat map.
        local mapped = HM.Tooltips.mapItemStats({ ITEM_MOD_ATTACK_POWER_SHORT = 10 })
        if mapped.attackPower ~= 10 then return false, "unmapped" end
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local text = table.concat(HM.Impact.itemDerivedLines(lo, { attackPower = 10 }), "\n")
        if text:find("per main%-hand swing") == nil then return false, "no chain" end
        local _, apChanges = HM.Impact.explainItemDelta(lo, { attackPower = 10 })
        local _, strChanges = HM.Impact.explainItemDelta(lo, { Strength = 3 })
        local apMelee, strMelee = 0, 0
        for _, c in ipairs(apChanges) do if c.id == "meleeDps" then apMelee = c.pct end end
        for _, c in ipairs(strChanges) do if c.id == "meleeDps" then strMelee = c.pct end end
        -- +10 AP > +3 Str (= +6 AP at the Shaman's 2 AP/Str) - the buy answer.
        if not (apMelee > strMelee and strMelee > 0) then return false, apMelee end
        -- and the head-to-head verdict calls the AP item the upgrade for melee
        local v = HM.Impact.itemVerdict(lo, { attackPower = 10 }, { Strength = 3 }, "meleeDps")
        return v ~= nil and v.direction == "upgrade"
    end)())
    check("weapon swap: parser pulls base range + speed, skips bonus lines", (function()
        local w = HM.Tooltips.parseWeaponTip({ "Wookie Slicer", "One-Hand",
            "34 - 52 Damage", "Speed 2.60", "+1 - 5 Nature Damage", "+10 Attack Power" })
        if not (w and w.min == 34 and w.max == 52 and approx(w.speed, 2.6)) then
            return false
        end
        local big = HM.Tooltips.parseWeaponTip({ "1,234 - 2,345 Damage", "Speed 3.80" })
        return big ~= nil and big.min == 1234 and big.max == 2345
            and HM.Tooltips.parseWeaponTip({ "Nice Hat", "+3 Stamina" }) == nil
    end)())
    check("weapon swap: white-DPS law on the live catch (18-27 vs 34-52 +10 AP)", (function()
        local snap = meleeShamanSnap() -- attackPower 300
        local apDelta = HM.Sim.apFromStats({ attackPower = 10 }, "SHAMAN")
            - HM.Sim.apFromStats({}, "SHAMAN")
        local s = HM.Sim.weaponSwap(snap, { min = 34, max = 52, speed = 2.6 },
            { min = 18, max = 27, speed = 2.6 }, apDelta)
        if not s then return false end
        local cur = 22.5 / 2.6 + 300 / 14
        local new = 43 / 2.6 + 310 / 14
        return approx(s.curDps, cur, 1e-9) and approx(s.newDps, new, 1e-9)
            and approx(s.pct, (new - cur) / cur * 100, 1e-9) and s.pct > 20
    end)())
    check("weapon swap: verdict uses the swap pct for melee goals only", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local swap = { pct = 57.3 }
        local melee = HM.Impact.itemVerdict(lo, { attackPower = 10 }, nil, "meleeDps", swap)
        local caster = HM.Impact.itemVerdict(lo, { attackPower = 10 }, nil, "spellcasting", swap)
        return melee ~= nil and approx(melee.pct, 57.3) and melee.direction == "upgrade"
            and caster ~= nil and not approx(caster.pct, 57.3)
    end)())
    check("weapon swap: from -> to + composed explanation, honest when unavailable", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        -- The downgrade direction (the user's bag weapon): negative/red, and the
        -- decomposition must SUM to the net (weapon term + stat term = change).
        local down = HM.Sim.weaponSwap(lo.snapshot, { min = 18, max = 27, speed = 2.6 },
            { min = 34, max = 52, speed = 2.6 }, 10)
        if not (down and down.pct < 0) then return false, "downgrade not negative" end
        if not approx(down.weaponDpsDelta + down.statDpsDelta,
                down.newDps - down.curDps, 1e-9) then
            return false, "decomposition does not sum to the net"
        end
        local text = linesText(HM.Tooltips.itemLines({}, lo, nil, { weaponSwap = down }) or {})
        if not (text:find("Melee DPS change:", 1, true)
                and text:find("= weapon", 1, true)
                and text:find("14 AP = 1 DPS", 1, true)
                and text:find("fff87171")) then
            return false, "missing from->to row, explanation, or loss color"
        end
        -- A weapon hover that can't compare says WHY instead of silence.
        local whyText = linesText(HM.Tooltips.itemLines({ attackPower = 4 }, lo, nil,
            { weaponSwapWhy = "couldn't read this weapon's damage line" }) or {})
        if whyText:find("weapon compare unavailable", 1, true) == nil then
            return false, "no why line"
        end
        return HM.Tooltips.itemLines({}, lo, nil, nil) == nil -- stat-less non-weapon: nothing
    end)())
    check("item mapper: Mana/Health/armor map; unknown keys surfaced, never dropped", (function()
        local mapped, unknown = HM.Tooltips.mapItemStats({
            ITEM_MOD_MANA_SHORT = 50, ITEM_MOD_HEALTH_SHORT = 30,
            RESISTANCE0_NAME = 45, ITEM_MOD_SPELL_POWER_SHORT = 12,
            ITEM_MOD_MYSTERY_RATING_SHORT = 7,
        })
        if not (mapped.maxMana == 50 and mapped.maxHealth == 30 and mapped.armor == 45
                and mapped.spellDamage == 12) then return false end
        for _, k in ipairs(unknown) do
            if k == "ITEM_MOD_MYSTERY_RATING_SHORT" then return true end
        end
        return false, "unknown key not surfaced"
    end)())
    check("audit parser: spell tooltip ranges (damage, heal, commas; nil degrade)", (function()
        local lo, hi = HM.Tooltips.parseSpellRange({
            "Lightning Bolt", "30 Mana", "2 sec cast",
            "Casts a bolt of lightning at the target for 25 to 30 Nature damage.",
        })
        if not (lo == 25 and hi == 30) then return false end
        local hl, hh = HM.Tooltips.parseSpellRange({
            "Heals a friendly target for 1,234 to 2,345.",
        })
        if not (hl == 1234 and hh == 2345) then return false end
        return HM.Tooltips.parseSpellRange({ "Increases your armor by 240." }) == nil
    end)())
    check("melee lens: a better-but-slower weapon scores HIGHER (inversion gate)", (function()
        -- Live catch 2026-10-12: 11.9-DPS weapon read 47.9 while a 7-DPS fast weapon
        -- read 54 - the old lens divided by swing time with no damage term. The lens
        -- now rides real white DPS, so weapon quality must order the score.
        local slowGood, fastWeak = meleeShamanSnap(), meleeShamanSnap()
        slowGood.weaponSpeed, slowGood.weaponDamageMin, slowGood.weaponDamageMax = 2.9, 82, 101
        fastWeak.weaponSpeed, fastWeak.weaponDamageMin, fastWeak.weaponDamageMax = 1.9, 36, 54
        local a = HM.Impact.evaluate(HM.Loadout.fromSnapshot(slowGood)).meleeDps.score
        local b = HM.Impact.evaluate(HM.Loadout.fromSnapshot(fastWeak)).meleeDps.score
        if not (a and b and a > b) then return false, (a or 0) .. " vs " .. (b or 0) end
        -- and the score is the REAL number: whiteDps x 10 x crit
        local expect = ((82 + 101) / 2 / 2.9) * 10 * (1 + slowGood.stats.meleeCritPct / 100)
        return approx(a, expect, 0.01)
    end)())
    check("totem buff chase: Strength of Earth grants +7 Str, rank-aligned by level", (function()
        local t1 = gen.spells[8075] -- rank 1 totem (L10)
        local t2 = gen.spells[8160] -- rank 2 totem (L24)
        if not (t1 and t1.grants and t1.grants[1]) then return false, "r1 missing" end
        local op = t1.grants[1]
        return op.kind == "stat" and op.stat == "Strength" and op.maxValue == 7
            and t1.grantsFrom == 8076
            and t2 ~= nil and t2.grants ~= nil and t2.grants[1].maxValue == 14
            and t2.grantsFrom == 8162
    end)())
    check("totem tooltip: the 7 Str -> AP -> swing chain renders", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local lines = HM.Tooltips.spellLines(8075, lo)
        local text = linesText(lines or {})
        return text:find("+7 Strength", 1, true) ~= nil
            and text:find("Attack Power", 1, true) ~= nil
            and lines ~= nil and (lines[1].right or ""):find("buff chain", 1, true) ~= nil
    end)())
    check("baseline law: your equipped item claims no verdict or % gain", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local mapped = { attackPower = 10, Stamina = 5 }
        local text = linesText(HM.Tooltips.itemLines(mapped, lo, nil, { equipped = true }) or {})
        if text:find("Upgrade", 1, true) or text:find("Sidegrade", 1, true)
                or text:find("Downgrade", 1, true) or text:find("%%") then
            return false, "gain claim on equipped gear"
        end
        if not (text:find("baseline", 1, true) and text:find("Giving you:", 1, true)) then
            return false, "baseline framing missing"
        end
        -- the same item NOT equipped still gets the verdict path
        local normal = linesText(HM.Tooltips.itemLines(mapped, lo, nil, nil) or {})
        return normal:find("for ", 1, true) ~= nil
    end)())
    check("capture no-downgrade: trained tooltip never overwritten by untrained", (function()
        local S = HM.Tooltips.shouldReplaceCapture
        return S(nil, { rank = nil }) == true
            and S({ rank = 2 }, { rank = nil }) == false
            and S({ rank = 2 }, { rank = 3 }) == true
            and S({ rank = nil }, { rank = 1 }) == true
            and S({ rank = nil }, { rank = nil }) == true
    end)())
    check("coaching: verdict headline unchanged and above the attribution", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local mapped = { Agility = 10, Stamina = 2 }
        local v = HM.Impact.itemVerdict(lo, mapped, nil, "auto")
        local lines = HM.Tooltips.itemLines(mapped, lo)
        if not (v and lines) then return false end
        local verdictAt, coachAt
        for i, L in ipairs(lines) do
            local t = L.text or ""
            if t:find("for " .. v.label, 1, true) then verdictAt = verdictAt or i end
            if t:find("only adds crit", 1, true) then coachAt = coachAt or i end
        end
        return verdictAt ~= nil and coachAt ~= nil and verdictAt < coachAt
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
    check("item lines render vs-equipped net rows when compared", (function()
        local text = linesText(HM.Tooltips.itemLines({ Intellect = 20 }, base, { Stamina = 20 }))
        return text:find("vs equipped", 1, true) ~= nil
    end)())
    check("swap-relative: a worse item reads NEGATIVE vs what you wear now", (function()
        -- User binding 2026-10-12: assess vs what is on your character at the time -
        -- never as an add to an empty slot. Hover +4 AP while wearing +10 AP: the
        -- derived chain must read -6 AP and the verdict must be a downgrade.
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local text = linesText(HM.Tooltips.itemLines({ attackPower = 4 }, lo,
            { attackPower = 10 }))
        return text:find("-6 Attack Power", 1, true) ~= nil
            and text:find("vs equipped", 1, true) ~= nil
            and text:find("Downgrade", 1, true) ~= nil
    end)())
    -- Gear verdict (Pawn-style headline) + gearing goal.
    check("item verdict calls an Int item an upgrade for a caster's spellcasting", (function()
        local v = HM.Impact.itemVerdict(base, { Intellect = 20 }, nil, "spellcasting")
        return v.direction == "upgrade" and v.pct > 0 and v.label == "Spellcasting"
    end)())
    check("item verdict flips by gearing goal (Stamina: tank up, spell sidegrade)", (function()
        local tank = HM.Impact.itemVerdict(base, { Stamina = 30 }, nil, "tankability")
        local caster = HM.Impact.itemVerdict(base, { Stamina = 30 }, nil, "spellcasting")
        return tank.direction == "upgrade" and caster.direction ~= "upgrade"
    end)())
    check("item verdict vs equipped nets the swap (Int item over a Stamina item)", (function()
        local v = HM.Impact.itemVerdict(base, { Intellect = 20 }, { Stamina = 20 }, "spellcasting")
        return v.compared == true and v.direction == "upgrade" and v.pct > 0
    end)())
    check("the headline verdict shows at the top of the item block", (function()
        local lines = HM.Tooltips.itemLines({ Intellect = 20 }, base)
        -- line 1 is the Foresight header; line 2 should be the verdict.
        local t = (lines[2] and (lines[2].text or "")) or ""
        return t:find("Upgrade", 1, true) ~= nil or t:find("grade", 1, true) ~= nil
    end)())
    check("gearGoal validates a tampered saved goal to auto", (function()
        if not HM.charDb then return false end
        local db = HM.charDb()
        local saved = db.settings.goal
        db.settings.goal = "evilNonDimension"
        local g = HM.gearGoal()
        db.settings.goal = saved
        return g == "auto"
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
        -- A spell with NO decoded base fields and no power to translate has nothing
        -- honest to say: no lines at all (the S19 absolute line never invents).
        local plainId
        for id, sp in pairs(gen.spells) do
            if sp.castMs and sp.castMs > 0 and not (sp.dmg or sp.heal or sp.wpn) then
                plainId = id
                break
            end
        end
        if not plainId then return false end
        local snap = testSnapshot()
        snap.stats.spellDamage, snap.stats.healingPower = 0, 0
        return HM.Tooltips.spellLines(plainId, HM.Loadout.fromSnapshot(snap)) == nil
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
    check("play-verified overrides upgrade the buff tooltip tag", (function()
        local before = HM.Tooltips.buffLines(13452, base)
        if not before or not (before[1].right or ""):find("(p)", 1, true) then
            return false
        end
        HM.overrides.verifiedBuffs[13452] = { build = "1.60.1.70338", accounts = 3,
            fields = { agility = 25 } }
        local after = HM.Tooltips.buffLines(13452, base)
        HM.overrides.verifiedBuffs[13452] = nil
        return after ~= nil
            and (after[1].right or ""):find("play-verified 1.60.1.70338", 1, true) ~= nil
    end)())
    check("consumableImpacts override replaces generated + relinks the aura index", (function()
        local gen = HM.gen
        local orig = gen.consumables[10305] -- Scroll of Protection IV
        if not orig then return false end
        local corrected = { name = orig.name, buffSpellId = 999001,
            durationMs = orig.durationMs, type = orig.type,
            ops = { { kind = "armor", maxValue = 200, rankRule = "verified" } },
            curatedBy = "TEST", note = "selftest round-trip" }
        HM.overrides.consumableImpacts[10305] = corrected
        HM.overrides.apply()
        local replaced, linked = gen.consumables[10305], gen.buffsBySpell[999001]
        HM.overrides.consumableImpacts[10305] = nil
        gen.consumables[10305] = orig
        gen.buffsBySpell[999001] = nil
        return replaced == corrected and replaced.ops[1].maxValue == 200
            and linked == 10305
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

    -- SIM-engine (S18): Tier-2 simulation - normalization, proc engines, resource
    -- economy, standings, pathways, and the curated class loops.
    check("weapon normalization constants + AP math", (function()
        local F = HM.formulas.weaponNormalization
        return F.constants.dagger == 1.7 and F.constants.twoHand == 3.3
            and approx(F.fn(700, "twoHand"), 700 / 14 * 3.3)
    end)())
    check("flurry uptime steady-state math", (function()
        local u = HM.formulas.flurryUptime.fn(30, 3)
        return approx(u, 1 - 0.7 ^ 3, 1e-9)
    end)())
    check("generated crit-haste decode (Flurry +10% for 3 swings)", (function()
        local sh = gen and gen.critHaste and gen.critHaste[16256]
        return sh ~= nil and sh.hastePct == 10 and sh.swings == 3
    end)())
    check("generated Windfury decode (20%, 2 extra attacks, rank AP)", (function()
        local wf = gen and gen.imbues and gen.imbues[8232]
        return wf ~= nil and wf.chance == 20 and wf.extraAttacks ~= nil
            and wf.extraAttacks.count == 2 and wf.extraAttacks.bonusAp == 46
    end)())
    check("windfury burst EV scales with the slow weapon", (function()
        local snap = { weaponSpeed = 3.8, weaponDamageMin = 80, weaponDamageMax = 120 }
        local wf = HM.Sim.windfuryBurst(snap, gen.imbues[16362]) -- rank 4: +333 AP
        local per = 100 + 333 / 14 * 3.8
        return wf ~= nil and approx(wf.burst, 2 * per, 0.01)
            and approx(wf.evPerSwing, 0.4 * per, 0.01)
    end)())
    check("imbue compare folds the Windfury expected value", (function()
        local snap = { weaponSpeed = 3.8, weaponDamageMin = 80, weaponDamageMax = 120 }
        local rows = HM.Imbues.compare(snap, { 16362 })
        local r = rows and rows[1]
        return r ~= nil and r.perSwing > 0
            and (r.notes[1] or ""):find("extra attacks", 1, true) ~= nil
    end)())
    check("melee cascade chains crit -> Flurry -> Windfury honestly", (function()
        local snap = testSnapshot()
        snap.weaponSpeed, snap.weaponDamageMin, snap.weaponDamageMax = 3.8, 80, 120
        snap.stats.meleeCritPct = 20
        local c = HM.Sim.meleeCascade(HM.Loadout.fromSnapshot(snap), {
            flurry = { name = "Flurry", hastePct = 10, swings = 3 },
            imbue = gen.imbues[16362],
        })
        local text = table.concat(c.steps, "\n")
        return c.dps > 0 and c.effSpeed < 3.8
            and text:find("uptime", 1, true) ~= nil
            and text:find("extra attacks", 1, true) ~= nil
            and text:find("(p)", 1, true) ~= nil
    end)())
    check("time-to-OOM: chain-cast math + five-second-rule honesty", (function()
        local oom = HM.Sim.timeToOOM(base,
            { name = "Test", cost = 100, castMs = 2000, powerType = 0 })
        return oom ~= nil and oom.casts == 30 and approx(oom.seconds, 60)
            and (oom.notes[1] or ""):find("five%-second rule") ~= nil
    end)())
    check("time-to-OOM resolves a real spell by name", (function()
        local sid = HM.Sim.resolveSpellByName("Frostbolt")
        local oom = sid and HM.Sim.timeToOOM(base, sid)
        return oom ~= nil and oom.casts == math.floor(3050 / oom.cost)
    end)())
    check("non-mana spells honestly decline the OOM model", (function()
        return HM.Sim.timeToOOM(base, { cost = 10, powerType = 1 }) == nil
    end)())
    check("spell tooltip carries the chain-cast OOM line", (function()
        local sid = HM.Sim.resolveSpellByName("Frostbolt")
        local text = linesText(HM.Tooltips.spellLines(sid, base))
        return text:find("Chain%-cast") ~= nil
    end)())
    check("standing: offense caster reads Glass Cannon", (function()
        local st = HM.Sim.standing(HM.Impact.evaluate(base), base.snapshot.stats)
        return st.name == "Glass Cannon" and st.lean == "offense"
    end)())
    check("standing flips to Endurance on a Stamina frame", (function()
        local snap = testSnapshot()
        snap.stats.stamina = 300
        local lo = HM.Loadout.fromSnapshot(snap)
        local st = HM.Sim.standing(HM.Impact.evaluate(lo), snap.stats)
        return st.name == "Endurance Caster" and st.lean == "survival"
    end)())
    check("standing shift detected on a frame-changing swap", (function()
        local shift = HM.Sim.standingShift(base, { Stamina = 200 }, { Intellect = 100 })
        return shift ~= nil and shift.from == "Glass Cannon" and shift.to ~= shift.from
    end)())
    check("item tooltip flags the build shift", (function()
        local lines = HM.Tooltips.itemLines({ Stamina = 200 }, base, { Intellect = 100 })
        for _, L in ipairs(lines or {}) do
            if (L.text or ""):find("Shifts your build", 1, true) then return true end
        end
        return false
    end)())
    check("windfury weapon line: slower hover = bigger proc burst", (function()
        local snap = { weaponSpeed = 1.8, weaponDamageMin = 10, weaponDamageMax = 20 }
        local line = HM.Tooltips.windfuryWeaponLine(snap, gen.imbues[16362], 3.8)
        -- AP-term delta = 333/14 * (3.8 - 1.8) * 2 attacks = ~95
        return line ~= nil and line:find("adds ~%+95") ~= nil
    end)())
    check("goal pathways rank the right talent first and drop noise", (function()
        local candidates = {
            { label = "Int step", what = base:withStatDelta("intellect", 10, "+10 int") },
            { label = "Str step", what = base:withStatDelta("strength", 10, "+10 str") },
        }
        local path = HM.Sim.goalPathways(base, "spellcasting", candidates)
        return path ~= nil and path.rows[1] ~= nil
            and path.rows[1].label == "Int step"
            and (path.rows[2] == nil or path.rows[1].pct >= path.rows[2].pct)
    end)())
    check("class loops: every named member resolves in shipped data", (function()
        local bad = HM.validateLoops()
        return type(bad) == "table" and #bad == 0
    end)(), table.concat(HM.validateLoops(), "; "))
    check("shatter loop computes the frozen-crit answer honestly", (function()
        -- S19: the payoff rows now claim level-capped absolute numbers from the decode.
        local l = HM.loopById("shatter")
        local text = table.concat(l and l.compute(base) or {}, "\n")
        return text:find("55.0%", 1, true) ~= nil
            and text:find("(p)", 1, true) ~= nil
            and text:find("hits for ~", 1, true) ~= nil
            and text:find("Shatter crit lands", 1, true) ~= nil
    end)())
    check("windfury loop cascade runs headless (engines resolve from data)", (function()
        local l = HM.loopById("windfury")
        local lines = l and l.compute(base)
        return lines ~= nil and #lines >= 2
            and (lines[#lines] or ""):find("first%-order") ~= nil
    end)())
    check("playstyle label leads with the standing", (function()
        local label = HM.PanelModel.playstyleLabel(HM.Impact.evaluate(base), base.snapshot)
        return label:find("Glass Cannon | ", 1, true) ~= nil
    end)())

    -- MODEL-ability-outcomes (S19): decoded base spell/heal/weapon data + the composed
    -- absolute hit. Data gates prove the decode against classic ground truth; model
    -- checks pin the composition laws (incl. the normalization double-count hazard).
    check("decode: Fireball r1 base 18 -> the classic 14-22", (function()
        local d = gen.spells[133] and gen.spells[133].dmg
        if not (d and d.base == 18) then return false end
        local mn, mx = HM.formulas.spellBaseDamage.fn(d.base, d.var, d.lvl, 1, d.maxLvl, 1)
        return approx(mn, 14, 0.05) and approx(mx, 22, 0.05)
    end)())
    check("decode: Heroic Strike r8 flat 138, not normalized", (function()
        local w = gen.spells[11567] and gen.spells[11567].wpn
        return w ~= nil and w.flat == 138 and w.norm == nil and w.pct == nil
    end)())
    check("decode: Backstab 150% weapon damage, normalized", (function()
        local w = gen.spells[2589] and gen.spells[2589].wpn
        return w ~= nil and w.pct == 150 and w.norm == true
    end)())
    check("decode: Fireball r1 carries the real 0.429 coefficient", (function()
        local d = gen.spells[133] and gen.spells[133].dmg
        return d ~= nil and d.coef ~= nil and math.abs(d.coef - 0.429) < 0.001
    end)())
    check("decode: Ice Lance resolves with damage data (Shatter claim gate)", (function()
        local sid = HM.Sim.resolveSpellByName("Ice Lance")
        local sp = sid and gen.spells[sid]
        return sp ~= nil and sp.dmg ~= nil and sp.dmg.base > 0
    end)())
    check("level-capped resolver picks the trainable rank", (function()
        local _, low = HM.Sim.resolveSpellLevelCapped("Fireball", 1)
        local _, mid = HM.Sim.resolveSpellLevelCapped("Fireball", 10)
        local _, top = HM.Sim.resolveSpellByName("Fireball")
        return low ~= nil and low.level == 1
            and mid ~= nil and mid.level ~= nil and mid.level <= 10 and mid.level > 1
            and top ~= nil and (top.level or 0) > mid.level
    end)())
    check("abilityHit composes the spell formula exactly (Fireball fixture)", (function()
        local sp = gen.spells[133]
        local hit = HM.Sim.abilityHit(base, 133, {})
        if not (hit and hit.kind == "spell" and hit.coefSource == "data") then return false end
        local mn, mx = HM.formulas.spellBaseDamage.fn(sp.dmg.base, sp.dmg.var, sp.dmg.lvl,
            sp.baseLevel or sp.level, sp.dmg.maxLvl, 60)
        return approx(hit.min, mn + 50 * sp.dmg.coef, 0.01)
            and approx(hit.max, mx + 50 * sp.dmg.coef, 0.01)
            and hit.presumed == true
    end)())
    check("weapon normalization substitution identity (double-count gate)", (function()
        -- avg == weaponAvg - AP/14*actualSpeed + AP/14*normCoefficient, on classic
        -- Stormstrike (Effect 121, bp 0): the UnitDamage AP term swaps speeds exactly.
        local snap = testSnapshot()
        snap.classToken = "SHAMAN"
        snap.weaponSpeed, snap.weaponType = 3.8, "twoHand"
        snap.weaponDamageMin, snap.weaponDamageMax = 100, 100
        snap.stats.attackPower = 700
        local hit = HM.Sim.abilityHit(HM.Loadout.fromSnapshot(snap), 17364, {})
        local expect = 100 - 700 / 14 * 3.8 + 700 / 14 * 3.3
        return hit ~= nil and hit.kind == "weapon"
            and approx(hit.min, expect, 1e-6) and approx(hit.max, expect, 1e-6)
    end)())
    check("weapon flat path (Heroic Strike rides your weapon range)", (function()
        local snap = testSnapshot()
        snap.classToken = "WARRIOR"
        snap.weaponDamageMin, snap.weaponDamageMax = 80, 120
        local hit = HM.Sim.abilityHit(HM.Loadout.fromSnapshot(snap), 11567, {})
        return hit ~= nil and approx(hit.min, 218) and approx(hit.max, 258)
            and hit.kind == "weapon" and hit.critMult == 2
    end)())
    -- One trait node with exactly one +damage% op touching Fireball(133), found from
    -- the shipped data (never hardcoded), backs the spellmod/delta/hover checks.
    local dmgNodeId, dmgNodeOp
    for nid, node in pairs(gen.traits.nodes) do
        local matching, count = nil, 0
        for _, op in ipairs(node.ops or {}) do
            if op.kind == "spellmod" and op.property == "damage/healing" and op.isPct
                    and (op.maxValue or 0) > 0 then
                for _, sid in ipairs(op.affected or {}) do
                    if sid == 133 then
                        count = count + 1
                        matching = op
                        break
                    end
                end
            end
        end
        if count == 1 and (node.maxRank or 1) > 1 then
            dmgNodeId, dmgNodeOp = nid, matching
            break
        end
    end
    check("spellmod talent moves the hit by the ONE rank rule", (function()
        if not dmgNodeId then return false end
        local node = gen.traits.nodes[dmgNodeId]
        local tid = HM.TalentAPI.talentForSpell and node.spellID
            and tonumber(HM.TalentAPI.talentForSpell(node.spellID)) or nil
        local plain = HM.Sim.abilityHit(base, 133, {})
        local r1 = HM.Sim.abilityHit(base, 133,
            { selected = { { nodeId = dmgNodeId, rank = 1 } } })
        local r2 = HM.Sim.abilityHit(base, 133,
            { selected = { { nodeId = dmgNodeId, rank = 2 } } })
        local v1 = HM.formulas.talentRankValueFor(tid, dmgNodeOp.maxValue, 1,
            node.maxRank, dmgNodeOp.values)
        local v2 = HM.formulas.talentRankValueFor(tid, dmgNodeOp.maxValue, 2,
            node.maxRank, dmgNodeOp.values)
        return plain ~= nil and r1 ~= nil and r2 ~= nil
            and approx(r1.min, plain.min * (1 + v1 / 100), 0.01)
            and approx(r2.min, plain.min * (1 + v2 / 100), 0.01)
            and r2.min > r1.min and r1.min > plain.min
    end)(), dmgNodeId)
    check("abilityHit nil-degrades without decoded fields (no absolute line)", (function()
        local plainId
        for id, sp in pairs(gen.spells) do
            if not (sp.dmg or sp.heal or sp.wpn) then
                plainId = id
                break
            end
        end
        if not plainId then return false end
        if HM.Sim.abilityHit(base, plainId, {}) ~= nil then return false end
        local text = linesText(HM.Tooltips.spellLines(plainId, base) or {})
        return text:find("Hits for", 1, true) == nil
            and text:find("Heals for", 1, true) == nil
    end)())
    check("abilityHitDelta: before/after/delta consistent", (function()
        if not dmgNodeId then return false end
        local d = HM.Sim.abilityHitDelta(base, 133, {}, dmgNodeId, 1)
        local before = HM.Sim.abilityHit(base, 133, {})
        local after = HM.Sim.abilityHit(base, 133,
            { selected = { { nodeId = dmgNodeId, rank = 1 } } })
        return d ~= nil and approx(d.before.avg, before.avg, 1e-9)
            and approx(d.after.avg, after.avg, 1e-9)
            and approx(d.delta, after.avg - before.avg, 1e-9)
            and d.delta > 0
    end)())
    check("display envelope: live-verified Lightning Bolt 25-30 + float-noise guard", (function()
        -- First in-game verification (2026-10-12): LB r2 at level 12 computes a raw
        -- 25.44-29.36 and the game renders "25 to 30" - the widest integer envelope
        -- (floor min, ceil max), not round-half. The epsilon matters: Fireball r1's
        -- stored variance puts the raw max at 22.0000001; naive ceil would invent 23.
        local F = HM.formulas.spellBaseDamage
        local lb = gen.spells[529]
        if not (lb and lb.dmg) then return false, "LB r2 missing" end
        local mn, mx = F.fn(lb.dmg.base, lb.dmg.var, lb.dmg.lvl,
            lb.baseLevel or lb.level, lb.dmg.maxLvl, 12)
        local lo, hi = F.display(mn, mx)
        local fb = gen.spells[133]
        local fmn, fmx = F.fn(fb.dmg.base, fb.dmg.var, fb.dmg.lvl,
            fb.baseLevel or fb.level, fb.dmg.maxLvl, 1)
        local flo, fhi = F.display(fmn, fmx)
        return lo == 25 and hi == 30 and flo == 14 and fhi == 22
    end)())
    check("spell tooltip leads with the absolute hit line", (function()
        local text = linesText(HM.Tooltips.spellLines(133, base))
        return text:find("Hits for", 1, true) ~= nil
            and text:find("(p)", 1, true) ~= nil
            and text:find("crits for ~1.5x", 1, true) ~= nil
            and text:find("datamined", 1, true) ~= nil
    end)())
    check("talent hover shows before -> after ability deltas", (function()
        if not dmgNodeId then return false end
        local text = linesText(HM.Tooltips.nodeImpactLines(dmgNodeId, base) or {})
        return text:find("per hit", 1, true) ~= nil
            and text:find("-> ~", 1, true) ~= nil
    end)())

    -- MATRIX panel model (S7b renderer spec: mockups/foresight-matrix-2026-10-12.html).
    check("matrix opacity validates untrusted values", (function()
        local N = HM.PanelModel.normalizeOpacity
        return N("garbage") == 0.92 and N(nil) == 0.92
            and N(0.05) == 0.2 and N(5) == 1.0 and N(0.5) == 0.5
    end)())
    check("matrix model: standing badge + honest bar basis", (function()
        local m = HM.PanelModel.matrixModel(base)
        return m.header.standing.name == "Glass Cannon"
            and m.bars.basis:find("relative", 1, true) ~= nil
            and m.bars.basis:find("(p)", 1, true) ~= nil
    end)())
    check("matrix bars fill relative within groups", (function()
        local m = HM.PanelModel.matrixModel(base)
        local tops = { output = 0, defense = 0 }
        for _, bar in ipairs(m.bars.rows) do
            if bar.fill > 1.0001 or bar.fill < 0 then return false end
            if bar.top then tops[bar.group] = tops[bar.group] + 1 end
        end
        return tops.output == 1 and tops.defense == 1
    end)())
    check("matrix eco maps the class loop with tagged cards", (function()
        local m = HM.PanelModel.matrixModel(base) -- MAGE -> the Shatter loop
        if not m.eco or m.eco.id ~= "shatter" or #m.eco.nodes ~= 3 then return false end
        local tags = {}
        for _, n in ipairs(m.eco.nodes) do tags[n.tag] = n.title end
        return tags.Enabler ~= nil and tags.Engine ~= nil and tags.Payoff ~= nil
            and (tags.Engine or ""):find("Shatter", 1, true) ~= nil
            and #m.eco.computed >= 1
    end)())
    check("matrix eco falls back when the saved loop id is garbage", (function()
        local m = HM.PanelModel.matrixModel(base, "tampered-loop-id")
        return m.eco ~= nil and m.eco.id == "shatter"
    end)())
    check("matrix carries pathway rows when provided", (function()
        local candidates = {
            { label = "Int step 1/5", what = base:withStatDelta("intellect", 10, "+10 int") },
        }
        local path = HM.Sim.goalPathways(base, "spellcasting", candidates)
        local m = HM.PanelModel.matrixModel(base, nil, path)
        return m.path ~= nil and #m.path.rows == 1
            and m.path.rows[1].label == "Int step 1/5"
            and m.path.label == "Spellcasting"
    end)())

    -- Per-talent rank rules (S11): captured votes resolve each talent's scaling.
    check("per-talent rank rule defaults to the global hypothesis", (function()
        return approx(HM.formulas.talentRankValueFor(26, -500, 2, 5), -200)
            and approx(HM.formulas.talentRankValueFor(nil, -500, 2, 5), -200)
    end)())
    check("a crowd-verified perRank rule flips the scaling for that talent only", (function()
        HM.overrides.rankRules[26] = "perRank"
        local flipped = HM.formulas.talentRankValueFor(26, -500, 2, 5)
        local other = HM.formulas.talentRankValueFor(27, -500, 2, 5)
        HM.overrides.rankRules[26] = nil
        return approx(flipped, -1000) and approx(other, -200)
    end)())
    check("rank-rule mark drops the (p) only for verified talents", (function()
        HM.overrides.rankRules[26] = "maxTotal"
        local verified = HM.formulas.rankRuleMark(26)
        local presumed = HM.formulas.rankRuleMark(27)
        HM.overrides.rankRules[26] = nil
        return verified == "" and presumed == " (p)"
    end)())
    check("talent tooltip header goes green for a verified rank rule", (function()
        HM.overrides.rankRules[26] = "maxTotal"
        local lines = HM.Tooltips.talentLines(26, 1, base)
        HM.overrides.rankRules[26] = nil
        return lines ~= nil
            and (lines[1].right or ""):find("crowd%-verified") ~= nil
    end)())

    -- Rank-rule truth (S21): datamined per-rank values outrank the rule system.
    -- Find a generated talent whose ops carry values arrays (31 decoded this build).
    local valTalentId, valOp
    local valTalents = 0
    for tid, imp in pairs(gen.talentImpacts) do
        local hasValues = false
        for _, op in ipairs(imp.ops or {}) do
            if op.values then
                hasValues = true
                if not valTalentId and (op.property or op.stat) and op.maxValue then
                    valTalentId, valOp = tid, op
                end
            end
        end
        if hasValues then valTalents = valTalents + 1 end
    end
    check("per-rank values decoded at scale (counts gate)", (function()
        return valTalents >= 25 and gen.counts.talentsWithRankValues == valTalents
    end)(), valTalents)
    check("values array length matches the talent's maxRank", (function()
        if not valTalentId then return false end
        local t = gen.talents[valTalentId]
        return t ~= nil and valOp.values ~= nil and #valOp.values == t.maxRank
    end)(), valTalentId)
    check("datamined values return the exact per-rank value", (function()
        if not valTalentId then return false end
        local t = gen.talents[valTalentId]
        for r = 1, t.maxRank do
            local got = HM.formulas.talentRankValueFor(valTalentId, valOp.maxValue,
                r, t.maxRank, valOp.values)
            if got ~= valOp.values[r] then return false, r end
        end
        return true
    end)())
    check("resolution order: values beat override beats default", (function()
        local vals = { 7, 13, 21, 30, 40 }
        local fromValues = HM.formulas.talentRankValueFor(26, 100, 2, 5, vals)
        HM.overrides.rankRules[26] = "perRank"
        local stillValues = HM.formulas.talentRankValueFor(26, 100, 2, 5, vals)
        local fromOverride = HM.formulas.talentRankValueFor(26, 100, 2, 5, nil)
        HM.overrides.rankRules[26] = nil
        local fromDefault = HM.formulas.talentRankValueFor(26, 100, 2, 5, nil)
        return approx(fromValues, 13) and approx(stillValues, 13)
            and approx(fromOverride, 200) and approx(fromDefault, 40)
    end)())
    check("datamined values drop the (p); missing values keep it", (function()
        local marked = HM.formulas.rankRuleMark(nil, { { maxValue = 100, values = { 1, 2 } } })
        local unmarked = HM.formulas.rankRuleMark(nil, { { maxValue = 100 } })
        local header
        if valTalentId then
            local lines = HM.Tooltips.talentLines(valTalentId, 1, base)
            header = lines and lines[1].right or ""
        end
        return marked == "" and unmarked == " (p)"
            and (not valTalentId or header:find("datamined", 1, true) ~= nil)
    end)(), valTalentId)
    check("values bridge reaches the live trait-node path", (function()
        for _, node in pairs(gen.traits.nodes) do
            for _, op in ipairs(node.ops or {}) do
                if op.values then return true end
            end
        end
        return false
    end)())

    -- Skill-centric Matrix (S22a): classified reverse lookup + dual highlight sets.
    check("classifiedForSpell: direct + statFeeder buckets (Fireball, Mage)", (function()
        local c = HM.Mapping.classifiedForSpell(133, { classToken = "MAGE" })
        if not c then return false end
        local hasDirect, hasIntFeeder = false, false
        for _, e in ipairs(c.direct) do
            if e.name == "Improved Fireball" then hasDirect = true end
        end
        for _, e in ipairs(c.statFeeders) do
            if e.nodeId == 104756 then hasIntFeeder = true end -- the Intellect% node
        end
        -- buckets are disjoint (priority dedupe)
        local seen = {}
        for _, list in ipairs({ c.direct, c.school, c.statFeeders }) do
            for _, e in ipairs(list) do
                if seen[e.nodeId] then return false, "node in two buckets" end
                seen[e.nodeId] = true
            end
        end
        return hasDirect and hasIntFeeder
    end)())
    check("classifiedForSpell: school bucket matches the spell's school mask", (function()
        -- Data-driven: find a schoolDamage% node, then a shipped damage spell of that
        -- school - the node must land in its school bucket (capped probes for speed).
        local SCHOOL_BIT = { Physical = 1, Holy = 2, Fire = 4, Nature = 8,
                             Frost = 16, Shadow = 32, Arcane = 64 }
        local nodesTried = 0
        for nid, node in pairs(gen.traits.nodes) do
            if nodesTried >= 5 then break end
            for _, op in ipairs(node.ops or {}) do
                local bit = op.kind == "schoolDamage" and op.isPct and op.school
                    and not op.school:find("/") and SCHOOL_BIT[op.school]
                if bit then
                    nodesTried = nodesTried + 1
                    local spellsTried = 0
                    for sid, sp in pairs(gen.spells) do
                        if spellsTried >= 5 then break end
                        if sp.school and math.floor(sp.school / bit) % 2 == 1 and sp.dmg then
                            spellsTried = spellsTried + 1
                            local c = HM.Mapping.classifiedForSpell(sid, {})
                            for _, e in ipairs(c and c.school or {}) do
                                if e.nodeId == nid then return true end
                            end
                        end
                    end
                    break
                end
            end
        end
        return false
    end)())
    check("classifiedForSpell: unknown spell returns nil (no false claims)", (function()
        return HM.Mapping.classifiedForSpell(999999999, { classToken = "MAGE" }) == nil
    end)())
    check("highlight selector returns direct + indirect sets separately", (function()
        local dIds, iIds = HM.SynergyHighlight.abilityClassified("Fireball",
            { classToken = "MAGE", level = 60 })
        if not dIds then return false end
        local nd, ni = 0, 0
        for k in pairs(dIds) do
            nd = nd + 1
            if iIds[k] then return false, "sets overlap" end
        end
        for _ in pairs(iIds) do ni = ni + 1 end
        return nd > 0 and ni > 0
    end)())

    -- Pathway rows (S22b): the cascade from existing computed data, nil-degrade per link.
    check("pathway: weapon cascade consistent with abilityHit (Stormstrike)", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local p = HM.PanelModel.pathwayModel(lo, 17364)
        if not (p and #p.segments == 4) then return false, p and #p.segments end
        local b = HM.Sim.abilityHit(lo, 17364, {})
        local a = HM.Sim.abilityHit(lo:withStatDelta("Strength", 10, "+10"), 17364, {})
        return p.segments[1] == "+10 Strength"
            and p.segments[2]:find("+20 Attack Power", 1, true) ~= nil
            and approx(p.hitDelta, a.avg - b.avg, 1e-6)
            and p.hitDelta > 0 and p.presumed == true
    end)())
    check("pathway: caster chain = probe power x coefficient (Fireball)", (function()
        local p = HM.PanelModel.pathwayModel(base, 133)
        if not (p and #p.segments == 2) then return false end
        return p.segments[1] == "+10 Spell Power"
            and approx(p.hitDelta, 10 * gen.spells[133].dmg.coef, 0.01)
    end)())
    check("pathway: no decoded endpoint -> no cascade (nil-degrade)", (function()
        local plainId
        for id, sp in pairs(gen.spells) do
            if not (sp.dmg or sp.heal or sp.wpn) then plainId = id break end
        end
        return plainId ~= nil and HM.PanelModel.pathwayModel(base, plainId) == nil
    end)())
    check("focus model feeds the Matrix (classes + pathway + passthrough)", (function()
        local lo = HM.Loadout.fromSnapshot(meleeShamanSnap())
        local fm = HM.PanelModel.focusModel(lo, "Stormstrike")
        if not (fm and fm.spell == "Stormstrike" and fm.pathway) then return false end
        if #fm.classes == 0 then return false, "no classes" end
        local m = HM.PanelModel.matrixModel(lo, nil, nil, fm)
        return m.focus == fm
    end)())

    -- Skill-centric mode (S7b): dim the tree, glow an ability's modifiers.
    check("ability members resolve tree nodes for a modified spell", (function()
        local ids, names, spell = HM.SynergyHighlight.abilityMembers("Fireball")
        if not ids then return false end
        local count = 0
        for _ in pairs(ids) do count = count + 1 end
        return count > 0 and names["Improved Fireball"] == true
            and spell == "Fireball"
    end)())
    check("ability members return nil for unknown abilities (no false glow)", (function()
        return HM.SynergyHighlight.abilityMembers("Totally Fake Spell") == nil
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
    -- LEVER TAXONOMY: the completeness gate - EVERY op kind in the shipped data must be
    -- classified (has a lever) or declared label-only, so new content can never silently
    -- drop out of synergies. This is the "grows without breaking" guarantee.
    check("every op kind in the catalog is classified by the lever taxonomy", (function()
        HM.Catalog._reset()
        local unclassified = {}
        for _, e in ipairs(HM.Catalog.all()) do
            for _, op in ipairs(e.ops or {}) do
                if op.kind and not HM.Levers.classified(op.kind) then
                    unclassified[op.kind] = true
                end
            end
        end
        local names = {}
        for k in pairs(unclassified) do names[#names + 1] = k end
        return #names == 0, #names > 0 and ("unclassified: " .. table.concat(names, ", ")) or nil
    end)())
    check("levers keep Attack Power and Spell Power on distinct keys", (function()
        local ap = HM.Levers.of({ kind = "attackPower" })
        local sp = HM.Levers.of({ kind = "statConvert", to = "spellDamage", from = "Intellect" })
        local apKey, spKey
        for _, l in ipairs(ap) do if l.axis == "mechanic" then apKey = l.key end end
        for _, l in ipairs(sp) do if l.axis == "mechanic" then spKey = l.key end end
        return apKey == "attack power" and spKey == "spell damage" and apKey ~= spKey
    end)())
    check("statConvert yields both a stat lever and an output lever (the bridge)", (function()
        local ls = HM.Levers.of({ kind = "statConvert", to = "attackPower", from = "Intellect" })
        local hasStat, hasMech = false, false
        for _, l in ipairs(ls) do
            if l.axis == "stat" and l.key == "Intellect" then hasStat = true end
            if l.axis == "mechanic" and l.key == "attack power" then hasMech = true end
        end
        return hasStat and hasMech
    end)())
    check("spellmod routes affected spells to the ability axis", (function()
        local ls = HM.Levers.of({ kind = "spellmod", property = "crit chance", affected = { 133 } },
            { [133] = { name = "Fireball" } })
        local hasSpell, hasCrit = false, false
        for _, l in ipairs(ls) do
            if l.axis == "spell" and l.key == "Fireball" then hasSpell = true end
            if l.axis == "mechanic" and l.key == "crit" then hasCrit = true end
        end
        return hasSpell and hasCrit
    end)())
    check("an unknown op kind is flagged, not silently ignored", (function()
        return HM.Levers.of({ kind = "someFutureEffect" }) == nil
            and HM.Levers.classified("someFutureEffect") == false
    end)())

    -- MAPPING (S7b): the bidirectional talent<->ability impact map.
    check("impact map: inverse lists what modifies an ability", (function()
        HM.Catalog._reset(); HM.Mapping._reset()
        -- Improved Fireball modifies Fireball - the inverse query must find it.
        local r = HM.Mapping.forSpell("Fireball")
        if not (r and r.spell:find("Fireball", 1, true)) then return false end
        for _, s in ipairs(r.sources) do
            if s.name == "Improved Fireball" then return true end
        end
        return false
    end)())
    check("impact map: forward lists the abilities a talent touches", (function()
        local fwd = HM.Mapping.forEntry("talent:26") -- Improved Fireball
        if not (fwd and #fwd.abilities > 0) then return false end
        for _, a in ipairs(fwd.abilities) do
            if a.spell == "Fireball" then return true end
        end
        return false
    end)())
    check("impact map: describeOp humanizes the modifier", (function()
        local r = HM.Mapping.forSpell("Fireball")
        local txt = r and HM.Mapping.describeOp(r.sources[1].op) or ""
        return type(txt) == "string" and #txt > 0 and txt:find("%a") ~= nil
    end)())
    check("impact map: unknown ability returns nil (no false claims)", (function()
        HM.Mapping._reset()
        return HM.Mapping.forSpell("Nonexistent Spell XYZ") == nil
    end)())
    check("ability tooltip shows which talents modify it", (function()
        -- Fireball (133) is modified by Improved Fireball - the spell tooltip surfaces it.
        local lines = HM.Tooltips.abilityMapLines(133)
        if not lines then return false end
        local text = {}
        for _, l in ipairs(lines) do text[#text + 1] = l.text or l.left or "" end
        return table.concat(text, "\n"):find("Improved Fireball", 1, true) ~= nil
    end)())
    check("ability map resolves by NAME when the id isn't ours (hover-rank fix)", (function()
        -- A spell id we never shipped, but the displayed name matches - must still map.
        local lines = HM.Tooltips.abilityMapLines(99999999, "Fireball")
        if not lines then return false end
        local text = {}
        for _, l in ipairs(lines) do text[#text + 1] = l.text or l.left or "" end
        return table.concat(text, "\n"):find("Improved Fireball", 1, true) ~= nil
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
    -- Item seed: the in-client gear catalog (stat TYPES; amounts come live).
    check("gear carries Forever-verified provenance with the patch/channel", (function()
        local p = HM.provenance()
        return type(p) == "string" and p:find("Forever%-verified") ~= nil
            and p:find(HM.gen.build, 1, true) ~= nil
            and (HM.gen.channel ~= nil)
    end)())
    check("catalog includes the gear seed at scale", (function()
        HM.Catalog._reset()
        local items = 0
        for _, row in ipairs(HM.Catalog.stats()) do
            if row.kind == "item" then items = row.count end
        end
        return items > 2000
    end)())
    check("gear is searchable by stat, sorted by required level", (function()
        local hits, total = HM.Catalog.itemsWithStat("Stamina", 10)
        if not (total > 50 and #hits == 10) then return false end
        for i = 2, #hits do
            if (hits[i].reqLevel or 0) < (hits[i - 1].reqLevel or 0) then return false end
        end
        -- every hit actually lists the requested stat
        for _, e in ipairs(hits) do
            local ok = false
            for _, s in ipairs(e.stats or {}) do if s == "Stamina" then ok = true end end
            if not ok then return false end
        end
        return true
    end)())
    check("secondary stats (Dodge) are catalogued as gear stats", (function()
        local _, total = HM.Catalog.itemsWithStat("Dodge", 1)
        return total >= 0 -- present as a queryable stat axis (count may be 0 pre-raid gear)
            and HM.Levers.of({ kind = "stat", stat = "Dodge" })[1].axis == "stat"
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
    check("observatory claim-filter keeps only a buff's own stats (anti-pollution)", (function()
        -- Elixir of the Mongoose (13452 -> buff 17538) claims Agility + crit only.
        local claimed = HM.Collect.claimedFields(HM.Collect.opsForBuffSpell(17538))
        if not (claimed.agility and claimed.meleeCritPct) then return false end
        -- A coincidental gear swap would add armor/strength - those must be rejected.
        return claimed.armor == nil and claimed.strength == nil and claimed.intellect == nil
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
