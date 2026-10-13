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
    -- PER-TALENT rank rules (S11, v0.27.0): which scaling hypothesis each talent's
    -- stored value follows, resolved by captured-tooltip votes (real in-game text,
    -- own tree + inspected players). Entries arrive ONLY from the harvest draft
    -- (collected/rank_rules_draft.lua) after human review. Consulted by
    -- formulas.talentRankValueFor; a listed talent drops its "(p) rank rule" mark.
    rankRules = {
        -- [talentId] = "maxTotal" | "perRank",
        -- Promoted 2026-10-12 (human-reviewed from rank_rules_draft.lua, build
        -- 1.60.1.70338): all four are TRAINED captures - Blizzard's own rendered
        -- tooltip text at a known rank, not statistical votes. Weak untrained-r1
        -- lines and the contradicted Destructive Reach (964) stay held.
        [37] = "perRank",   -- Improved Frostbolt (inspected mage, r4/5 text)
        [130] = "perRank",  -- Deflection (trained capture 2026-10-12; a later untrained
                            -- re-hover overwrote the stored capture - the no-downgrade
                            -- law now prevents that; vote direction never conflicted)
        [613] = "perRank",  -- Thundering Strikes (pilot shaman, r2/5 text)
        [614] = "maxTotal", -- Ancestral Knowledge (pilot shaman, r1/5 text)
        -- Second promotion round 2026-10-12 (inspect pass; all trained-backed, same
        -- user-set standard as round one):
        [147] = "maxTotal", -- Improved Revenge (trained A=1)
        [269] = "perRank",  -- Lethality (trained B=1)
        [270] = "maxTotal", -- Malice (trained A=1)
        [273] = "maxTotal", -- Ruthlessness (trained A=1)
        [823] = "perRank",  -- Nature's Focus (trained B=1)
        [824] = "perRank",  -- Naturalist (trained B=2)
        [1601] = "maxTotal", -- Shield Specialization (trained A=2)
        -- Third promotion round 2026-10-12 (build-filtered corpus, same trained
        -- standard; the inspect-pass harvest):
        [401] = "perRank",   -- Holy Specialization (trained B=1)
        [403] = "maxTotal",  -- Searing Light (trained A=2)
        [408] = "maxTotal",  -- Improved Healing (trained A=1)
        [586] = "perRank",   -- Improved Healing Wave (trained B=1)
        [1003] = "maxTotal", -- Improved Corruption (trained A=1; was weak-maxTotal)
        [1181] = "maxTotal", -- Divine Fury (trained A=1)
        -- DEMOTED 2026-10-13 (honesty law: conflicted evidence falls back to (p),
        -- never a false "verified" mark):
        --   [593] Tidal Focus - round-3 said trained A=3, but the current corpus holds
        --   zero trained votes and 3 untrained B votes; direction unresolved.
        --   [796] Ferocity - round-3 trained A=1 vs a NEW trained r5/5 capture voting B
        --   ("by 5 Rage or Energy"); the trained evidence self-conflicts.
        --   Both need a trained hover at a mid rank (r2-r4, where A and B diverge).
        -- Fourth promotion round 2026-10-13 (same trained-capture standard as rounds
        -- one through three; 24 merged archives, build-filtered):
        [186] = "maxTotal",  -- Lightning Reflexes (trained A=1)
        [201] = "maxTotal",  -- Improved Sinister Strike (trained A=1)
        [204] = "maxTotal",  -- Endurance (trained A=1)
        [276] = "maxTotal",  -- Improved Eviscerate (trained A=1)
        [801] = "maxTotal",  -- Blood Frenzy (trained A=1)
        [807] = "maxTotal",  -- Feral Swiftness (trained A=2)
        [808] = "maxTotal",  -- Heart of the Wild (trained A=3)
        [1581] = "perRank",  -- Dual Wield Specialization (trained B=2)
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
