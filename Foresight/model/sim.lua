-- Foresight simulation engine (SIM-engine): Tier 2 of the modeling stack.
-- Tier 1 (stat conversion, data/formulas.lua) feeds these first-order combat-loop
-- models:
--   crit -> Flurry uptime -> effective swing speed -> Windfury expected value ->
--   sustained melee throughput  ·  mana pool vs rotation drain -> time-to-OOM  ·
--   dimension ratios -> plain-English build standing  ·  per-talent goal pathways.
-- Everything here is PURE (no game reads - callers resolve live context) and
-- honesty-tagged: unverified rates and missing data say so, nothing is invented.
-- Out-of-combat surfaces only (commands/tooltips drive it); nothing runs on combat
-- events, so there is no frame-time or API-restriction exposure.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Sim = {}
HM.Sim = Sim

local AP_PER_DPS = 14 -- the classic law: 14 Attack Power = 1 weapon DPS (p)

-- Resolve a gen.spells entry by case-insensitive name. Prefers a mana-costing
-- variant, then the highest-level one (the rank the player most likely casts).
function Sim.resolveSpellByName(name)
    if type(name) ~= "string" or name == "" then return nil end
    local want = name:lower()
    local bestId, best
    for id, s in pairs((HM.gen and HM.gen.spells) or {}) do
        if (s.name or ""):lower() == want then
            local better
            if not best then
                better = true
            else
                local sCost, bCost = (s.cost or 0) > 0, (best.cost or 0) > 0
                if sCost ~= bCost then better = sCost
                else better = (s.level or 0) > (best.level or 0) end
            end
            if better then bestId, best = id, s end
        end
    end
    return bestId, best
end

-- Level-capped rank resolver: the highest rank the player can actually have trained
-- (spell.level <= playerLevel). resolveSpellByName prefers the highest rank outright,
-- which over-claims for a leveling character - absolute hit numbers use this instead.
function Sim.resolveSpellLevelCapped(name, playerLevel)
    if type(name) ~= "string" or name == "" then return nil end
    local want, cap = name:lower(), playerLevel or 60
    local bestId, best
    for id, s in pairs((HM.gen and HM.gen.spells) or {}) do
        if (s.name or ""):lower() == want then
            local lvl = s.level or 0
            local better
            if not best then
                better = true
            else
                local bLvl = best.level or 0
                local sFits, bFits = lvl <= cap, bLvl <= cap
                if sFits ~= bFits then better = sFits
                elseif sFits then better = lvl > bLvl
                else better = lvl < bLvl end -- nothing fits: lowest rank over-claims least
            end
            if better then bestId, best = id, s end
        end
    end
    return bestId, best
end

-- All imbue spell ids sharing a name (ranks), from generated data - never hardcoded.
function Sim.imbuesByName(name)
    local ids = {}
    for sid, e in pairs((HM.gen and HM.gen.imbues) or {}) do
        if e.name == name then ids[#ids + 1] = sid end
    end
    table.sort(ids)
    return ids
end

-- "At current cast rates you will deplete your mana in X seconds." Chain-cast model:
-- every cast restarts the five-second rule, so spirit regen contributes 0 for the
-- whole window (classic FSR law, (p)); instants pay the 1.5s GCD as cast time.
function Sim.timeToOOM(loadout, spell)
    local s = spell
    if type(spell) ~= "table" then
        s = HM.gen and HM.gen.spells and HM.gen.spells[spell]
    end
    if not s or (s.cost or 0) <= 0 then return nil end
    if (s.powerType or 0) ~= 0 then return nil, "not a mana spell" end
    local stats = (loadout.snapshot and loadout.snapshot.stats) or {}
    local mana = stats.maxMana or 0
    if mana <= 0 then return nil, "no mana pool" end
    local castSec = (s.castMs and s.castMs > 0) and (s.castMs / 1000) or 1.5
    local casts = math.floor(mana / s.cost)
    local out = {
        name = s.name, cost = s.cost, castSec = castSec,
        casts = casts, seconds = casts * castSec,
        drainPerSec = s.cost / castSec,
        notes = {
            "chain-casting keeps you inside the five-second rule: spirit regen halted (p)",
        },
    }
    local okT, tick = pcall(function()
        local built = loadout:build()
        return built.graph:value("mech.manaPerTick", built.ctx, {})
    end)
    if okT and tick and tick > 0 then
        out.regenTick = tick
        out.notes[#out.notes + 1] =
            ("stop casting for 5s and regen resumes at %.0f mana per tick (p)"):format(tick)
    end
    return out
end

-- Internal: fold the damage/healing spellmods among SELECTED trait nodes that touch
-- this spell. Walks the SAME generated affected edges Mapping uses (never the
-- name-keyed catalog); every magnitude goes through the ONE rank rule
-- (talentRankValueFor). selected entries accept both the walkTraits shape (nodeID)
-- and the snapshot.talents shape (nodeId/talentId). extraNode replaces that node's
-- selected rank (set-with-override), so rank what-ifs never double-count.
local function selectedSpellMods(spellId, selected, extraNode)
    local F = HM.formulas
    local gen = HM.gen or {}
    local nodes = gen.traits and gen.traits.nodes
    local pct, flat, names, presumed = 0, 0, {}, false
    local function fold(ops, rank, maxRank, talentId, name)
        for _, op in ipairs(ops or {}) do
            if op.kind == "spellmod" and op.property == "damage/healing" and op.affected then
                local hits = false
                for _, sid in ipairs(op.affected) do
                    if sid == spellId then hits = true break end
                end
                if hits then
                    local v = F.talentRankValueFor(talentId, op.maxValue or 0, rank,
                        maxRank, op.values)
                    if op.isPct then pct = pct + v else flat = flat + v end
                    names[#names + 1] = name
                    -- Per-op honesty: datamined values or a verified rule drop the (p).
                    if F.rankRuleMark(talentId, { op }) ~= "" then presumed = true end
                end
            end
        end
    end
    local function foldRef(n, rank)
        local nid = n.nodeID or n.nodeId
        local node = nid and nodes and nodes[nid]
        if node then
            local talentId = HM.TalentAPI and HM.TalentAPI.talentForSpell and node.spellID
                and tonumber(HM.TalentAPI.talentForSpell(node.spellID)) or nil
            fold(node.ops, rank, node.maxRank or 1, talentId, node.name or ("node:" .. tostring(nid)))
        elseif n.talentId and gen.talentImpacts and gen.talentImpacts[n.talentId] then
            -- Classic-shape fallback (no trait node id): same op shape, same rank rule.
            local t = gen.talents and gen.talents[n.talentId]
            fold(gen.talentImpacts[n.talentId].ops, rank, (t and t.maxRank) or 1,
                n.talentId, (t and t.name) or ("talent:" .. tostring(n.talentId)))
        end
    end
    local extraId = extraNode and (extraNode.nodeId or extraNode.nodeID)
    for _, n in ipairs(selected or {}) do
        local nid = n.nodeID or n.nodeId
        if (n.rank or 0) > 0 and not (extraId and nid == extraId) then
            foldRef(n, n.rank)
        end
    end
    if extraId and (extraNode.rank or 0) > 0 then
        foldRef({ nodeId = extraId }, extraNode.rank)
    end
    return pct, flat, names, presumed
end

-- What this button actually does, composed from decoded client data and YOUR numbers.
-- Pure: one graph build per call, so every existing what-if delta (stat/trait/buff/
-- racial/plan) flows into the number for free. Returns nil when the spell has no
-- decoded dmg/heal/wpn fields (honest degrade - never an invented number).
--   opts = { selected = <walkTraits/snapshot.talents list>, extraNode = {nodeId, rank} }
--   -> { min, max, avg, kind = "spell"|"weapon"|"heal", coefSource = "data"|"presumed"|nil,
--        mods = {names}, presumed, critPct, critMult, baseMin, baseMax, power, coef,
--        pctMods, flatMods }
-- Known limit (documented): extraNode folds the node's DIRECT spellmods only; its
-- stat-side ops (e.g. +Int) don't reach the graph in the what-if - mixed nodes
-- understate slightly rather than double-count.
function Sim.abilityHit(loadout, spellId, opts)
    opts = opts or {}
    local F = HM.formulas
    local spell = HM.gen and HM.gen.spells and HM.gen.spells[spellId]
    if not (loadout and spell and F) then return nil end
    local dmg, heal, wpn = spell.dmg, spell.heal, spell.wpn
    if not (dmg or heal or wpn) then return nil end
    local snap = loadout.snapshot or {}
    local built = loadout:build()
    local function stat(node)
        local ok, v = pcall(function() return built.graph:value(node, built.ctx, {}) end)
        return (ok and type(v) == "number") and v or 0
    end
    local pctMods, flatMods, modNames, modsPresumed =
        selectedSpellMods(spellId, opts.selected, opts.extraNode)
    local lawPresumed = F.presumedMark(F.spellBaseDamage) ~= ""
    local out

    if wpn then
        local wmin, wmax = snap.weaponDamageMin or 0, snap.weaponDamageMax or 0
        if wmax <= 0 then return nil end -- no weapon baseline: claim nothing
        local ap = stat("stat.attackPower")
        -- The snapshot's weapon range contains the SNAPSHOT AP's term (UnitDamage is
        -- static data here); the graph AP may differ under a what-if. Subtract what
        -- the range actually contains, fold the live/what-if AP back in.
        local snapAp = (snap.stats and snap.stats.attackPower) or ap
        local speed = snap.weaponSpeed or 2.0
        local shift
        if wpn.norm then
            -- Normalized instants: re-add AP at NORMALIZED speed (the double-count
            -- hazard; the selftest identity check pins this).
            shift = -(snapAp / AP_PER_DPS * speed)
                + F.weaponNormalization.fn(ap, snap.weaponType)
        else
            -- Non-normalized strikes ride the weapon range as-is; only the MARGINAL
            -- what-if AP folds, at actual speed (zero on the live loadout).
            shift = (ap - snapAp) / AP_PER_DPS * speed
        end
        local pctW = (wpn.pct or 100) / 100
        local minv = ((wmin + shift) * pctW + (wpn.flat or 0)) * (1 + pctMods / 100) + flatMods
        local maxv = ((wmax + shift) * pctW + (wpn.flat or 0)) * (1 + pctMods / 100) + flatMods
        out = {
            min = minv, max = maxv, kind = "weapon",
            critPct = stat("stat.meleeCritPct"), critMult = F.critMultiplier.melee,
            baseMin = wmin, baseMax = wmax, power = ap,
            -- lawPresumed covers the whole decode interpretation (weapon-effect rows
            -- included); the in-game tooltip pass upgrades F.spellBaseDamage for all.
            presumed = lawPresumed or modsPresumed
                or (wpn.norm and F.presumedMark(F.weaponNormalization) ~= "")
                or false,
        }
    else
        local d = dmg or heal
        local kind = dmg and "spell" or "heal"
        local baseMin, baseMax = F.spellBaseDamage.fn(d.base, d.var, d.lvl,
            spell.baseLevel or spell.level, d.maxLvl, snap.level)
        local power = (kind == "heal") and stat("stat.healingPower") or stat("stat.spellDamage")
        local coef, coefSource = d.coef, d.coef and "data" or nil
        if not coef then
            local castSec = (spell.castMs and spell.castMs > 0) and (spell.castMs / 1000) or 1.5
            coef = F.spellCoefficient.fn(castSec)
            coefSource = "presumed"
        end
        local minv = (baseMin + power * coef) * (1 + pctMods / 100) + flatMods
        local maxv = (baseMax + power * coef) * (1 + pctMods / 100) + flatMods
        out = {
            min = minv, max = maxv, kind = kind, coefSource = coefSource,
            critPct = stat("stat.spellCritPct"), critMult = F.critMultiplier.spell,
            baseMin = baseMin, baseMax = baseMax, power = power, coef = coef,
            presumed = lawPresumed or modsPresumed or coefSource == "presumed" or false,
        }
    end
    out.avg = (out.min + out.max) / 2
    out.mods = modNames
    out.pctMods, out.flatMods = pctMods, flatMods
    return out
end

-- Before/after/delta of one trait-node rank change on one ability - the
-- Sim.standingShift pattern exactly: same snapshot, extra what-if on top.
function Sim.abilityHitDelta(loadout, spellId, selected, nodeId, rank)
    local before = Sim.abilityHit(loadout, spellId, { selected = selected })
    local after = Sim.abilityHit(loadout, spellId,
        { selected = selected, extraNode = { nodeId = nodeId, rank = rank } })
    if not (before and after) then return nil end
    return { before = before, after = after, delta = after.avg - before.avg,
             presumed = before.presumed or after.presumed }
end

-- AP-equivalent of an item's mapped stat bundle (flat AP + Str/Agi through the class
-- conversion rates). Feeds the weapon-swap compare so a +Strength weapon and a
-- +Attack Power weapon are judged in the same unit.
function Sim.apFromStats(mapped, classToken)
    local conv = ((HM.formulas.statConversions.byClass or {})[classToken]) or {}
    local m = mapped or {}
    return (m.attackPower or 0)
        + (m.Strength or 0) * (conv.apPerStr or 0)
        + (m.Agility or 0) * (conv.apPerAgi or 0)
end

-- Weapon-swap honesty (live catch 2026-10-12): a weapon's own damage range is the
-- DOMINANT term of a melee swap - stats alone called an 18-27 -> 34-52 upgrade
-- "+4.7%". White DPS = baseAvg/speed + AP/14 (the one AP law); apDelta is the net
-- AP-equivalent change between the two items' stat bundles. Pure; both weapons'
-- BASE ranges come from their tooltips (never UnitDamage, which already folds AP).
function Sim.weaponSwap(snapshot, hovered, equipped, apDelta)
    if not (snapshot and hovered and equipped) then return nil end
    if (hovered.speed or 0) <= 0 or (equipped.speed or 0) <= 0 then return nil end
    local curAvg = ((equipped.min or 0) + (equipped.max or 0)) / 2
    local newAvg = ((hovered.min or 0) + (hovered.max or 0)) / 2
    if curAvg <= 0 or newAvg <= 0 then return nil end
    local ap = (snapshot.stats and snapshot.stats.attackPower) or 0
    local cur = curAvg / equipped.speed + ap / AP_PER_DPS
    local new = newAvg / hovered.speed + (ap + (apDelta or 0)) / AP_PER_DPS
    if cur <= 0 then return nil end
    return {
        curDps = cur, newDps = new, pct = (new - cur) / cur * 100,
        curSwing = curAvg + ap / AP_PER_DPS * equipped.speed,
        newSwing = newAvg + (ap + (apDelta or 0)) / AP_PER_DPS * hovered.speed,
        -- Decomposition (the explain layer): the game's own diffs re-composed - the
        -- weapon's DPS term and the stat bundle's AP-equivalent term sum to the net.
        weaponDpsDelta = newAvg / hovered.speed - curAvg / equipped.speed,
        statDpsDelta = (apDelta or 0) / AP_PER_DPS,
        apDelta = apDelta or 0,
    }
end

-- The crit-haste engine (Flurry family) among the player's selected trait nodes.
-- selected: TalentAPI.walkTraits-shaped list ({spellID, rank}). Data: gen.critHaste.
function Sim.flurryFor(selected)
    local gen = HM.gen and HM.gen.critHaste
    if not gen then return nil end
    for _, node in ipairs(selected or {}) do
        local e = node.spellID and gen[node.spellID]
        if e and (node.rank or 0) > 0 then
            return { name = e.name, hastePct = e.hastePct, swings = e.swings,
                     rank = node.rank, confidence = e.confidence }
        end
    end
    return nil
end

-- The strongest extra-attack imbue (Windfury family) among the given imbue spell ids.
function Sim.windfuryFor(ids)
    local gen = (HM.gen and HM.gen.imbues) or {}
    local best
    for _, sid in ipairs(ids or {}) do
        local e = gen[sid]
        if e and e.extraAttacks and e.chance then
            if not best or (e.extraAttacks.bonusAp or 0) > (best.extraAttacks.bonusAp or 0) then
                best = e
            end
        end
    end
    return best
end

-- One Windfury-style proc on THIS weapon: the burst when it fires + the expected
-- value per swing. Extra attacks are real swings - they keep the ACTUAL weapon speed
-- (normalization applies to instant yellow abilities, not these; classic rule, (p)).
-- Each extra attack lands avg weapon damage (which already includes your current AP)
-- plus the proc's bonus AP scaled by your weapon speed.
function Sim.windfuryBurst(snapshot, entry)
    if not (snapshot and entry and entry.extraAttacks) then return nil end
    local speed = snapshot.weaponSpeed or 2.0
    local avg = ((snapshot.weaponDamageMin or 0) + (snapshot.weaponDamageMax or 0)) / 2
    local x = entry.extraAttacks
    local perAttack = avg + (x.bonusAp or 0) / AP_PER_DPS * speed
    local burst = (x.count or 1) * perAttack
    return {
        burst = burst, perAttack = perAttack, count = x.count or 1,
        bonusAp = x.bonusAp or 0, chance = entry.chance or 0,
        evPerSwing = (entry.chance or 0) / 100 * burst,
        baseKnown = avg > 0,
    }
end

-- The cascade the design docs ask for, made real: +crit -> Flurry uptime -> effective
-- swing speed -> more Windfury rolls -> expected sustained melee throughput. Returns
-- human-readable steps plus the first-order estimate. opts.flurry from Sim.flurryFor,
-- opts.imbue from Sim.windfuryFor - absent engines are skipped, never guessed.
function Sim.meleeCascade(loadout, opts)
    opts = opts or {}
    local snap = loadout.snapshot or {}
    local stats = snap.stats or {}
    local speed = snap.weaponSpeed or 2.0
    local crit = stats.meleeCritPct or 0
    local avg = ((snap.weaponDamageMin or 0) + (snap.weaponDamageMax or 0)) / 2
    local steps = {}
    steps[#steps + 1] = ("baseline: %.2fs swings, ~%.0f avg hit, %.1f%% crit")
        :format(speed, avg, crit)
    local effSpeed, uptime = speed, 0
    if opts.flurry then
        uptime = HM.formulas.flurryUptime.fn(crit, opts.flurry.swings)
        effSpeed = speed / (1 + (opts.flurry.hastePct or 0) * uptime / 100)
        steps[#steps + 1] = ("%s: %.1f%% crit -> ~%.0f%% uptime on +%g%% speed -> effective %.2fs swings (p)")
            :format(opts.flurry.name or "Flurry", crit, uptime * 100,
                opts.flurry.hastePct or 0, effSpeed)
    end
    local swingsPerSec = effSpeed > 0 and (1 / effSpeed) or 0
    local autoDps = avg * (1 + crit / 100) * swingsPerSec -- 2x crits fold as +crit% (p)
    steps[#steps + 1] = ("auto-attacks: ~%.1f DPS including crits (p)"):format(autoDps)
    local dps = autoDps
    if opts.imbue then
        local wf = Sim.windfuryBurst(snap, opts.imbue)
        if wf then
            local wfDps = wf.evPerSwing * swingsPerSec
            dps = dps + wfDps
            steps[#steps + 1] = ("%s: %d%% per hit -> %d extra attacks at +%d AP = ~%.0f burst, ~+%.1f DPS%s (p)")
                :format(opts.imbue.name or "Windfury", wf.chance, wf.count, wf.bonusAp,
                    wf.burst, wfDps, wf.baseKnown and "" or " - weapon damage unknown here")
            if uptime > 0 then
                steps[#steps + 1] =
                    "faster swings from Flurry also mean more Windfury rolls - the engines compound (p)"
            end
        end
    end
    steps[#steps + 1] = ("expected sustained melee: ~%.1f DPS - first-order model (p)")
        :format(dps)
    return { steps = steps, dps = dps, effSpeed = effSpeed, uptimePct = uptime * 100 }
end

-- Tier 3 standings, done honestly: our dimension scores are relative indices, not
-- percentages - so standings only compare WITHIN comparable groups (the four output
-- lenses against each other; Stamina against the archetype's key stat; threat
-- against its own 100% baseline), never across unlike units.
local OUTPUTS = {
    { id = "spellcasting", word = "Caster", stat = "intellect",
      glass = "Glass Cannon", endure = "Endurance Caster" },
    { id = "meleeDps", word = "Melee", stat = "strength",
      glass = "Glass Bruiser", endure = "Endurance Brawler" },
    { id = "rangedDps", word = "Ranged", stat = "agility",
      glass = "Glass Sniper", endure = "Endurance Ranger" },
    { id = "healing", word = "Healer", stat = "intellect",
      glass = "Battle Medic", endure = "Steadfast Healer" },
}

-- results = Impact.evaluate output; stats = snapshot-shaped stat table.
-- HONESTY NOTE: the dimension scores are per-lens indices on different scales (the
-- known fill-basis limit), so they are only used to pick the TOP output word. All
-- ratio decisions (hybrid, lean) run in same-unit STAT space, which is comparable
-- within one character by construction.
function Sim.standing(results, stats)
    local best
    for _, o in ipairs(OUTPUTS) do
        local r = results and results[o.id]
        local score = r and r.score
        if score and (not best or score > best.score) then
            best = { o = o, score = score }
        end
    end
    if not best then
        return { name = "Unmeasured", word = "?", lean = "unknown",
                 detail = "no dimension scores available" }
    end
    local o = best.o
    stats = stats or {}
    local key, sta = stats[o.stat] or 0, stats.stamina or 0
    local lean = "balanced"
    if sta > key * 1.15 then lean = "survival"
    elseif key > sta * 1.15 then lean = "offense" end
    local threat = results.threat and results.threat.score
    local str, int = stats.strength or 0, stats.intellect or 0
    local hi, lo = math.max(str, int), math.min(str, int)
    local name, detail
    if threat and threat >= 110 and lean ~= "offense" then
        name = "Threat Anchor"
        detail = ("threat at %d%% of baseline - built to hold attention"):format(threat)
    elseif lo > 0 and lo >= hi * 0.8 and lo >= sta * 0.8 then
        -- Hybrid = real investment in BOTH scaling families, measured where units
        -- match: Strength (physical) running level with Intellect (magical).
        name = "Primal Hybrid"
        detail = ("Strength %d and Intellect %d run together - physical and magical scaling both invested")
            :format(str, int)
    elseif lean == "offense" then
        name = o.glass
        detail = ("%s output leads and %s outweighs Stamina - high damage, thin armor plan")
            :format(o.word, o.stat)
    elseif lean == "survival" then
        name = o.endure
        detail = ("a %s build carried on a Stamina frame - safe, low-downtime"):format(o.word)
    else
        name = o.word .. " All-Rounder"
        detail = "offense and Stamina in balance"
    end
    return { name = name, word = o.word, lean = lean, detail = detail }
end

-- Fold item stat deltas onto a snapshot stat table (primaries only - that is all the
-- lean reads). Mapped keys arrive capitalized ("Intellect"); snapshot keys are lower.
local function effectiveStats(stats, mapped, compared)
    local out = {}
    for k, v in pairs(stats or {}) do out[k] = v end
    local function fold(deltas, sign)
        for k, v in pairs(deltas or {}) do
            if type(v) == "number" then
                local key = tostring(k):lower():gsub("%s", "")
                if out[key] ~= nil then out[key] = out[key] + sign * v end
            end
        end
    end
    fold(compared, -1)
    fold(mapped, 1)
    return out
end

-- Does swapping an item change the plain-English standing? Returns nil when the
-- standing holds, else { from, to } for the tooltip to flag prominently.
function Sim.standingShift(loadout, mapped, comparedStats)
    local baseStats = (loadout.snapshot and loadout.snapshot.stats) or {}
    local before = Sim.standing(HM.Impact.evaluate(loadout), baseStats)
    local modeled = loadout
    for stat, amount in pairs(comparedStats or {}) do
        if type(amount) == "number" and amount ~= 0 then
            modeled = modeled:withStatDelta(stat, -amount, ("-%g %s"):format(amount, stat))
        end
    end
    for stat, amount in pairs(mapped or {}) do
        if type(amount) == "number" and amount ~= 0 then
            modeled = modeled:withStatDelta(stat, amount, ("+%g %s"):format(amount, stat))
        end
    end
    local after = Sim.standing(HM.Impact.evaluate(modeled),
        effectiveStats(baseStats, mapped, comparedStats))
    if before.name ~= after.name then
        return { from = before.name, to = after.name }
    end
    return nil
end

-- Goal-oriented pathways: rank candidate talent steps by their marginal impact on
-- the chosen dimension. candidates: { { label, what = <what-if loadout> } } - the
-- caller builds them (live: next rank of every unfinished trait node). Out-of-combat
-- command surface only: this evaluates one graph per candidate.
function Sim.goalPathways(loadout, dimId, candidates, topN)
    local dim = HM.dimensions.byId and HM.dimensions.byId(dimId)
    if not dim then return nil, "unknown dimension" end
    local base = HM.Impact.evaluate(loadout)
    local b = base[dimId] and base[dimId].score
    if not b or b == 0 then return nil, "dimension not scorable for this character" end
    local rows = {}
    for _, c in ipairs(candidates or {}) do
        local ok, after = pcall(HM.Impact.evaluate, c.what)
        local a = ok and after[dimId] and after[dimId].score
        if a then
            local pct = (a - b) / math.abs(b) * 100
            if pct > 0.005 then
                rows[#rows + 1] = { label = c.label, pct = pct }
            end
        end
    end
    table.sort(rows, function(x, y)
        if x.pct ~= y.pct then return x.pct > y.pct end
        return x.label < y.label
    end)
    local out = {}
    for i = 1, math.min(topN or 8, #rows) do out[i] = rows[i] end
    return { dim = dimId, label = dim.label, rows = out,
             considered = #(candidates or {}) }
end

return Sim
