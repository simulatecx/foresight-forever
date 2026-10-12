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
