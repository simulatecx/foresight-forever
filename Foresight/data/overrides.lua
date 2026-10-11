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
}

-- Apply overrides on top of generated data at load time.
if HM.gen and HM.gen.talentImpacts then
    for id, entry in pairs(HM.overrides.talentImpacts) do
        HM.gen.talentImpacts[id] = entry
    end
end

return HM.overrides
