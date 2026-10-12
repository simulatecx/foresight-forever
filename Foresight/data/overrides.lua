-- Foresight curated overrides: hand-maintained corrections layered over generated data.
-- Primary feed: user reports ("this doesn't work because X") and probe mismatches.
-- Shape mirrors HM.gen.talentImpacts entries; an override fully replaces the
-- generated entry for that talent id. 186/432 talents are proc/trigger-style and
-- need curation (flagged needsCuration in generated data) - they land here over time.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

HM.overrides = {
    talentImpacts = {
        -- [talentId] = { ops = { { kind=..., property=..., maxValue=..., affected={...} } },
        --                curatedBy = "REQ-123", note = "why" },
    },
    -- Per-ability base threat values (GRAPH-threat): classic threat-per-damage differs by
    -- ability (e.g. taunts, Shield Slam bonus threat). These are NOT in client DB2; they
    -- arrive here via the k-of-n crowd rule + human-reviewed PR, never one submission.
    -- Until then the threat lens shows own-talent threat % modifiers only.
    abilityThreat = {
        -- [spellId] = { threat = <number>, curatedBy = "REQ-###", note = "source" },
    },
    -- Play-VERIFIED consumable impacts (S11 observed-vs-generated): entries arrive ONLY
    -- from the harvest draft (collected/overrides_draft.lua) after k-of-n distinct
    -- accounts agree and a human reviews the numbers. Verification upgrades the "(p)"
    -- display tag to "play-verified <build>" - the values themselves stay generated
    -- (play confirms the data, it never forks it).
    verifiedBuffs = {
        -- [itemId] = { build = "1.60.1.70338", accounts = 3, fields = { armor = 240 } },
    },
    -- Consumable CORRECTIONS: when play disagrees with the datamined ops (a mismatch in
    -- the harvest draft), the reviewed replacement entry lands here and fully replaces
    -- the generated consumable. Keep buffSpellId - the live-aura index follows it.
    consumableImpacts = {
        -- [itemId] = { name=..., buffSpellId=..., durationMs=..., type=...,
        --              ops = {...}, curatedBy = "REQ-###", note = "why" },
    },
}

-- Apply overrides on top of generated data. Factored + idempotent so the selftest can
-- exercise the replacement path; runs once at load.
function HM.overrides.apply()
    if HM.gen and HM.gen.talentImpacts then
        for id, entry in pairs(HM.overrides.talentImpacts) do
            HM.gen.talentImpacts[id] = entry
        end
    end
    if HM.gen and HM.gen.consumables then
        for id, entry in pairs(HM.overrides.consumableImpacts) do
            HM.gen.consumables[id] = entry
            if entry.buffSpellId and HM.gen.buffsBySpell then
                HM.gen.buffsBySpell[entry.buffSpellId] = id
            end
        end
    end
end

HM.overrides.apply()

return HM.overrides
