-- Foresight character snapshot: captures the live character into the plain-table shape
-- model/loadout.lua consumes. Every game read goes through Guards; missing/secret
-- values land as 0 with a note so downstream math never explodes.
--
-- API-shape caveat: Forever runs the Mainline (12.x) addon API over classic-era
-- mechanics; exact stat API indices need one beta pass (see QA checklist).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Guards = HM.Guards
local Snapshot = {}
HM.Snapshot = Snapshot

local function statIndex(i)
    -- UnitStat indices: 1 Strength, 2 Agility, 3 Stamina, 4 Intellect, 5 Spirit.
    local v = Guards.call(_G.UnitStat, "player", i)
    return Guards.number(v) or 0
end

local SCHOOLS = { holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7 }

local function bestSpellDamage()
    local best = 0
    for _, idx in pairs(SCHOOLS) do
        local v = Guards.number(Guards.call(_G.GetSpellBonusDamage, idx)) or 0
        if v > best then best = v end
    end
    return best
end

function Snapshot.capture()
    if not _G.UnitStat then
        return nil, "not in game client"
    end
    local _, classToken = _G.UnitClass("player")
    local snapshot = {
        classToken = classToken,
        level = Guards.number(Guards.call(_G.UnitLevel, "player")) or 60,
        notes = {},
        stats = {
            strength = statIndex(1),
            agility = statIndex(2),
            stamina = statIndex(3),
            intellect = statIndex(4),
            spirit = statIndex(5),
            spellDamage = bestSpellDamage(),
            healingPower = Guards.number(Guards.call(_G.GetSpellBonusHealing)) or 0,
            attackPower = Guards.number(Guards.call(_G.UnitAttackPower, "player")) or 0,
            rangedAttackPower = Guards.number(Guards.call(_G.UnitRangedAttackPower, "player")) or 0,
            spellCritPct = Guards.number(Guards.call(_G.GetSpellCritChance, SCHOOLS.fire)) or 0,
            meleeCritPct = Guards.number(Guards.call(_G.GetCritChance)) or 0,
            rangedCritPct = Guards.number(Guards.call(_G.GetRangedCritChance)) or 0,
            hastePct = Guards.number(Guards.call(_G.GetHaste)) or 0,
            -- effectiveArmor is return #2 on both the classic and mainline UnitArmor
            -- shapes; #3 exists only on classic (live-verified: #3 read 0 on Forever).
            armor = Guards.number(Guards.select(2, _G.UnitArmor, "player")) or 0,
            avoidancePct = (Guards.number(Guards.call(_G.GetDodgeChance)) or 0)
                + (Guards.number(Guards.call(_G.GetParryChance)) or 0),
            -- Base pools minus stat-derived portion; refined once beta-verified.
            baseHealth = math.max(0, (Guards.number(Guards.call(_G.UnitHealthMax, "player")) or 0)
                - statIndex(3) * 10),
            baseMana = math.max(0, (Guards.number(Guards.call(_G.UnitPowerMax, "player", 0)) or 0)
                - statIndex(4) * 15),
        },
        weaponSpeed = Guards.number(Guards.call(_G.UnitAttackSpeed, "player")) or 2.0,
        talents = Snapshot.captureTalents(),
    }
    return snapshot
end

-- Current talent allocation. On Forever this walks C_Traits and maps each purchased
-- node's spell back to our generated talent id (via spellRanks); on a classic client it
-- falls back to the old globals. All reads route through the TalentAPI adapter.
function Snapshot.captureTalents()
    local talents = {}
    if not (HM.TalentAPI and HM.TalentAPI.available()) then
        return talents -- headless, or no talent surface: verify tracks the API shape
    end
    for _, t in ipairs(HM.TalentAPI.captureSelected() or {}) do
        if (t.rank or 0) > 0 then
            talents[#talents + 1] = {
                talentId = t.talentId, rank = t.rank, maxRank = t.maxRank,
                name = t.name, spellID = t.spellID,
                tier = t.tier, column = t.column, -- present only on the classic fallback
            }
        end
    end
    return talents
end

return Snapshot
