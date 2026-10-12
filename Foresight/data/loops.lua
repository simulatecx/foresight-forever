-- Foresight class loops (SIM-engine demystification): the Enabler -> Engine -> Payoff
-- mechanic chains that client data cannot express as rows - the WHY of a class.
-- Hand-curated like formulas.lua, confidence-tagged, and selftest-GATED: every named
-- member must resolve in the shipped data (spells, trait nodes, or imbues by name),
-- so a future-build rename reds the ship gate instead of silently rotting here.
-- compute(loadout) returns live lines from the player's own numbers - and only
-- numbers our data supports; absent facts are said out loud, never invented.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

HM.loops = {
    {
        id = "shatter", classToken = "MAGE", name = "The Shatter Loop",
        confidence = "classic-presumed",
        enablers = { "Frost Nova", "Frostbite", "Cone of Cold" },
        engine = { "Shatter", "Ice Shards" },
        payoffs = { "Frostbolt", "Ice Lance" },
        insight = "Freezes are not just defense - they arm Shatter. Land a freeze, "
            .. "then cast the payoffs into it.",
        compute = function(loadout)
            local stats = (loadout.snapshot and loadout.snapshot.stats) or {}
            local crit = stats.spellCritPct or 0
            return {
                ("Shatter at max rank vs a frozen target: your %.1f%% spell crit becomes ~%.1f%% (+50%% (p))")
                    :format(crit, math.min(crit + 50, 100)),
                "Ice Shards turns those crits from 1.5x into ~2x damage (p)",
                "absolute hit numbers need base spell damage per rank - not in the shipped data yet, so none are claimed",
            }
        end,
    },
    {
        id = "windfury", classToken = "SHAMAN", name = "The Windfury Engine",
        confidence = "classic-presumed",
        enablers = { "Windfury Weapon" },
        engine = { "Flurry" },
        payoffs = { "Stormstrike" },
        insight = "Slow weapons make Windfury's bonus AP hit harder; crits keep Flurry "
            .. "running, and faster swings roll more Windfury procs - the engines compound.",
        compute = function(loadout)
            local sel = HM.TalentAPI and HM.TalentAPI.walkTraits
                and HM.TalentAPI.walkTraits(true) or nil
            local cascade = HM.Sim.meleeCascade(loadout, {
                flurry = HM.Sim.flurryFor(sel),
                imbue = HM.Sim.windfuryFor(HM.Sim.imbuesByName("Windfury Weapon")),
            })
            return cascade.steps
        end,
    },
    {
        id = "flurry", classToken = "WARRIOR", name = "The Flurry Engine",
        confidence = "classic-presumed",
        enablers = { "Battle Shout" },
        engine = { "Flurry" },
        payoffs = { "Heroic Strike" },
        insight = "Critical strikes keep Flurry's attack speed running; attack power "
            .. "and crit gear feed each other through it.",
        compute = function(loadout)
            local sel = HM.TalentAPI and HM.TalentAPI.walkTraits
                and HM.TalentAPI.walkTraits(true) or nil
            local cascade = HM.Sim.meleeCascade(loadout, { flurry = HM.Sim.flurryFor(sel) })
            return cascade.steps
        end,
    },
}

function HM.loopsForClass(classToken)
    local out = {}
    for _, l in ipairs(HM.loops) do
        if not classToken or l.classToken == classToken then out[#out + 1] = l end
    end
    return out
end

function HM.loopById(id)
    for _, l in ipairs(HM.loops) do
        if l.id == id then return l end
    end
    return nil
end

-- Selftest gate: every named member must resolve in shipped data. Returns the list
-- of unresolved "loopId: member" strings (empty = green).
function HM.validateLoops()
    local names = {}
    for _, s in pairs((HM.gen and HM.gen.spells) or {}) do
        if s.name then names[s.name] = true end
    end
    local nodes = HM.gen and HM.gen.traits and HM.gen.traits.nodes
    for _, n in pairs(nodes or {}) do
        if n.name then names[n.name] = true end
    end
    for _, e in pairs((HM.gen and HM.gen.imbues) or {}) do
        if e.name then names[e.name] = true end
    end
    local bad = {}
    for _, l in ipairs(HM.loops) do
        for _, group in ipairs({ l.enablers, l.engine, l.payoffs }) do
            for _, member in ipairs(group or {}) do
                if not names[member] then
                    bad[#bad + 1] = l.id .. ": " .. member
                end
            end
        end
    end
    return bad
end

return HM.loops
