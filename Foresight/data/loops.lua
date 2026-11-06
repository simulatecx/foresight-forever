-- Foresight class loops (SIM-engine demystification): the Enabler -> Engine -> Payoff
-- mechanic chains that client data cannot express as rows - the WHY of a class.
-- Hand-curated like formulas.lua, confidence-tagged, and selftest-GATED: every named
-- member must resolve in the shipped data (spells, trait nodes, or imbues by name),
-- so a future-build rename reds the ship gate instead of silently rotting here.
-- compute(loadout) returns live lines from the player's own numbers - and only
-- numbers our data supports; absent facts are said out loud, never invented.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

-- Shared compute for the S26 loops: claim payoff numbers ONLY where the decode
-- exists (abilityHit nil-degrades); undecoded proc engines say so out loud (the
-- DATA-proc-families pipeline decode upgrades them later - backlogged).
local function loopCompute(payoffs, procNote)
    return function(loadout)
        local lines = {}
        local level = loadout.snapshot and loadout.snapshot.level
        local selected = loadout.snapshot and loadout.snapshot.talents
        for _, name in ipairs(payoffs) do
            local sid = HM.Sim.resolveSpellLevelCapped
                and HM.Sim.resolveSpellLevelCapped(name, level)
            local hit = sid and HM.Sim.abilityHit
                and HM.Sim.abilityHit(loadout, sid, { selected = selected })
            if hit and hit.kind == "dot" then
                -- A bleed/poison: its total over the duration, not a single hit.
                lines[#lines + 1] = ("%s bleeds for ~%d over %ds%s"):format(name,
                    math.floor((hit.avg or 0) + 0.5), math.floor((hit.durationSec or 0) + 0.5),
                    hit.presumed and " (p)" or "")
            elseif hit then
                local lo, hi = HM.formulas.spellBaseDamage.display(hit.min, hit.max,
                    hit.kind)
                lines[#lines + 1] = ("%s %s for ~%d-%d with your gear%s"):format(
                    name, hit.kind == "heal" and "heals" or "hits", lo, hi,
                    hit.presumed and " (p)" or "")
            end
        end
        if procNote then lines[#lines + 1] = procNote end
        if #lines == 0 then
            lines[1] = "numbers arrive once this class's decode lands - nothing invented"
        end
        return lines
    end
end

local PROC_GAP = "the engine's proc rate is not yet decoded - no expected value is claimed (honest gap)"

HM.loops = {
    {
        id = "shatter", classToken = "MAGE", name = "The Shatter Loop",
        specTab = "Frost",  -- data-located: this loop's talents live in Frost (S54 spec-aware default)
        confidence = "classic-presumed",
        enablers = { "Frost Nova", "Frostbite", "Cone of Cold" },
        engine = { "Shatter", "Ice Shards" },
        payoffs = { "Frostbolt", "Ice Lance" },
        insight = "Freezes are not just defense - they arm Shatter. Land a freeze, "
            .. "then cast the payoffs into it.",
        compute = function(loadout)
            local stats = (loadout.snapshot and loadout.snapshot.stats) or {}
            local crit = stats.spellCritPct or 0
            local lines = {
                ("Shatter at max rank vs a frozen target: your %.1f%% spell crit becomes ~%.1f%% (+50%% (p))")
                    :format(crit, math.min(crit + 50, 100)),
                "Ice Shards turns those crits from 1.5x into ~2x damage (p)",
            }
            -- Absolute payoff numbers (MODEL-ability-outcomes): the rank the player can
            -- actually cast at their level, composed with their gear. Decode absent ->
            -- the honest fallback line, never an invented number.
            local level = loadout.snapshot and loadout.snapshot.level
            local selected = loadout.snapshot and loadout.snapshot.talents
            local claimed = false
            for _, payoff in ipairs({ "Frostbolt", "Ice Lance" }) do
                local sid = HM.Sim.resolveSpellLevelCapped
                    and HM.Sim.resolveSpellLevelCapped(payoff, level)
                local hit = sid and HM.Sim.abilityHit
                    and HM.Sim.abilityHit(loadout, sid, { selected = selected })
                if hit then
                    claimed = true
                    local lo, hi = HM.formulas.spellBaseDamage.display(hit.min, hit.max)
                    lines[#lines + 1] = ("%s hits for ~%d-%d; a Shatter crit lands ~%gx that%s")
                        :format(payoff, lo, hi, hit.critMult or 2,
                            hit.presumed and " (p)" or "")
                end
            end
            if not claimed then
                lines[#lines + 1] =
                    "absolute hit numbers need the base-damage decode for your ranks - none claimed here"
            end
            return lines
        end,
    },
    {
        id = "windfury", classToken = "SHAMAN", name = "The Windfury Engine",
        specTab = "Enhancement",  -- data-located: this loop's talents live in Enhancement (S54 spec-aware default)
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
        -- Arms / generic melee - the DEFAULT warrior loop (owner 2026-11-06: an Arms
        -- warrior shouldn't be shown Fury's Flurry as their engine). Bleeds tick between
        -- swings; rage spends on strikes. Fury players title-click to cycle to Flurry.
        id = "arms", classToken = "WARRIOR", name = "The Bleed & Strike Engine",
        specTab = "Arms",  -- the Matrix leads with this loop when you've invested in Arms
        confidence = "classic-presumed",
        enablers = { "Battle Shout", "Rend" },
        engine = { "Deep Wounds", "Overpower" },
        payoffs = { "Mortal Strike", "Heroic Strike" },
        insight = "Keep Rend bleeding and let Deep Wounds stack from your crits, then spend "
            .. "rage on Mortal Strike and Heroic Strike - punish a dodge with Overpower. "
            .. "Your bleeds tick between every swing, so they add up even while you auto-attack.",
        compute = function(loadout)
            local lines = loopCompute({ "Mortal Strike", "Heroic Strike", "Overpower", "Rend" })(loadout)
            -- CRIT -> BLEED (owner 2026-11-06: "crits to bleed"): Deep Wounds (Arms talent)
            -- turns each crit into an extra bleed - the Arms crit-scaling loop. Its bleed
            -- damage is a talent PROC we haven't decoded, so no EV is claimed; the crit
            -- RELATIONSHIP is real and that's what we describe (honest-gap law).
            local crit = loadout.snapshot and loadout.snapshot.stats
                and loadout.snapshot.stats.meleeCritPct
            if crit then
                lines[#lines + 1] = ("Crit -> bleed: Deep Wounds makes each crit (%.0f%% now) add a bleed on top; more crit = more bleed uptime (proc damage not yet decoded, no EV)"):format(crit)
            end
            return lines
        end,
    },
    {
        id = "flurry", classToken = "WARRIOR", name = "The Flurry Engine (Fury)",
        specTab = "Fury",  -- the Matrix leads with this once you've invested in Fury
        confidence = "classic-presumed",
        enablers = { "Battle Shout" },
        engine = { "Flurry" },
        payoffs = { "Heroic Strike" },
        insight = "Fury path: critical strikes keep Flurry's attack speed running; attack "
            .. "power and crit gear feed each other through it. Spec into Flurry to light it.",
        compute = function(loadout)
            local sel = HM.TalentAPI and HM.TalentAPI.walkTraits
                and HM.TalentAPI.walkTraits(true) or nil
            local cascade = HM.Sim.meleeCascade(loadout, { flurry = HM.Sim.flurryFor(sel) })
            return cascade.steps
        end,
    },
    {
        id = "combo", classToken = "ROGUE", name = "The Combo Engine",
        specTab = "Assassination",  -- data-located: this loop's talents live in Assassination (S54 spec-aware default)
        confidence = "classic-presumed",
        enablers = { "Sinister Strike", "Slice and Dice" },
        engine = { "Lethality", "Instant Poison" },
        payoffs = { "Eviscerate" },
        insight = "Builders feed combo points; Slice and Dice spends them to speed "
            .. "every poison-carrying swing; Eviscerate cashes the rest in.",
        compute = function(loadout)
            local lines = loopCompute({ "Eviscerate", "Sinister Strike" })(loadout)
            local ok, rows, speed = pcall(HM.Imbues.compare, loadout.snapshot,
                HM.Sim.imbuesByName("Instant Poison"))
            local r = ok and rows and rows[1]
            if r and r.perSwing and r.perSwing > 0 then
                lines[#lines + 1] = ("Instant Poison on your %.1fs weapon: ~%+.1f per swing (%+.2f DPS) (p)")
                    :format(speed or 2, r.perSwing, r.perSec or 0)
            end
            return lines
        end,
    },
    {
        id = "hawk", classToken = "HUNTER", name = "The Hawk's Shot",
        confidence = "classic-presumed",
        enablers = { "Hunter's Mark", "Serpent Sting" },
        engine = { "Aspect of the Hawk" },
        payoffs = { "Aimed Shot", "Arcane Shot" },
        insight = "Mark and sting soften the target; Hawk's attack power carries "
            .. "every shot; the big payoffs land between autos.",
        compute = loopCompute({ "Aimed Shot", "Arcane Shot" }, PROC_GAP),
    },
    {
        id = "seal", classToken = "PALADIN", name = "Seal and Judgement",
        specTab = "Retribution",  -- data-located: this loop's talents live in Retribution (S54 spec-aware default)
        confidence = "classic-presumed",
        enablers = { "Seal of Command", "Seal of Righteousness" },
        engine = { "Vengeance" },
        payoffs = { "Judgement", "Holy Light" },
        insight = "Seals arm the swing, Judgement cashes the seal, and Vengeance "
            .. "turns crits into a running damage engine.",
        compute = loopCompute({ "Holy Light" }, PROC_GAP),
    },
    {
        id = "weave", classToken = "PRIEST", name = "The Shadow Weave",
        specTab = "Shadow",  -- data-located: this loop's talents live in Shadow (S54 spec-aware default)
        confidence = "classic-presumed",
        enablers = { "Shadow Word: Pain" },
        engine = { "Shadow Weaving" },
        payoffs = { "Mind Blast", "Mind Flay" },
        insight = "Shadow damage stacks the Weave; every stack makes the next shadow "
            .. "hit bigger - keep Pain rolling and cash with Blast.",
        compute = loopCompute({ "Mind Blast", "Smite" }),
    },
    {
        id = "nightfall", classToken = "WARLOCK", name = "The Nightfall Engine",
        specTab = "Affliction",  -- data-located: this loop's talents live in Affliction (S54 spec-aware default)
        confidence = "classic-presumed",
        enablers = { "Corruption", "Immolate" },
        engine = { "Nightfall" },
        payoffs = { "Shadow Bolt" },
        insight = "DoTs tick toward a Nightfall proc; the instant Shadow Bolt it "
            .. "grants is the payoff - keep Corruption up on everything.",
        compute = loopCompute({ "Shadow Bolt", "Immolate" }, PROC_GAP),
    },
    {
        id = "clarity", classToken = "DRUID", name = "Omen of Clarity",
        confidence = "classic-presumed",
        enablers = { "Faerie Fire", "Moonfire" },
        engine = { "Omen of Clarity" },
        payoffs = { "Shred", "Healing Touch", "Wrath" },
        insight = "Keep attacking and Clarity procs free casts - spend them on your "
            .. "most expensive button, form permitting.",
        compute = loopCompute({ "Wrath", "Healing Touch" }, PROC_GAP),
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
