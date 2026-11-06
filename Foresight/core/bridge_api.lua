-- Foresight -> RUN bridge (the sibling living-world addon, _G.RunAdvisor).
-- READ-ONLY, addon-to-addon: Foresight publishes a character combat profile
-- (survivability + offense, off the live sheet) so RUN can compute honest
-- odds-vs-creature WITHOUT reading the player's live health - which Forever
-- hides as a secret value on PvP realms / restricted contexts.
--
-- THE CONNECTION IS DESIGNED TO GROW. Each field is optional + additive; RUN
-- reads them defensively (if present), so as Foresight exposes more of what it
-- models - offense (dps), mitigation (armor/avoidance), and later sustain /
-- burst / schools - RUN's odds math deepens on its own, no lockstep release.
-- Bump API_VERSION when the shape grows so both sides can negotiate.
--
-- Laws: nothing leaves the client, no backend, no T&Cs/privacy impact (two
-- addons sharing a table in memory). ADDITIVE only. Guards: missing/secret
-- values land as 0, never an error.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local BridgeAPI = {}
HM.BridgeAPI = BridgeAPI

local API_VERSION = 2   -- v2: added dps (offense from Foresight's engine)

local function num(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 then return 0 end
    return v
end

-- Pure: a sustained-DPS estimate from the live weapon + power reads. Rough
-- (white-swing + AP scaling + a spell-power contribution) and clearly presumed;
-- Foresight's real sim can refine this later without changing the contract.
function BridgeAPI.estimateDPS(weaponMin, weaponMax, weaponSpeed, attackPower, spellPower)
    local speed = num(weaponSpeed)
    if speed <= 0 then speed = 2.0 end
    local avg = (num(weaponMin) + num(weaponMax)) / 2
    local white = avg / speed + num(attackPower) / 14   -- classic white-damage shape
    local caster = num(spellPower) * 0.3                -- rough over a cast cycle
    return white + caster
end

-- Pure: shape raw reads into the STABLE profile RUN consumes. Every numeric
-- field is non-negative (0 = unknown/secret). GROWS additively - new optional
-- fields append here and RUN picks them up when present.
function BridgeAPI.profileFrom(fields)
    fields = fields or {}
    local lvl = num(fields.level)
    return {
        v = API_VERSION,
        level = lvl >= 1 and lvl or 1,
        stamina = num(fields.stamina),
        attackPower = num(fields.attackPower),
        spellPower = num(fields.spellPower),
        armor = num(fields.armor),
        avoidancePct = num(fields.avoidancePct),
        maxHealth = num(fields.maxHealth),     -- 0 when the client hides it (secret)
        dps = num(fields.dps),                 -- v2: offense estimate (0 when unknown)
        class = type(fields.class) == "string" and fields.class or "?",
        source = "foresight",
    }
end

-- Client-only below: the live read + the published API.
if not _G.CreateFrame then return BridgeAPI end

local Guards = HM.Guards
local SPELL_SCHOOLS = { 2, 3, 4, 5, 6, 7 }   -- holy/fire/nature/frost/shadow/arcane

local function bestSpellPower()
    local best = 0
    if _G.GetSpellBonusDamage then
        for _, idx in ipairs(SPELL_SCHOOLS) do
            local v = Guards.number(Guards.call(_G.GetSpellBonusDamage, idx)) or 0
            if v > best then best = v end
        end
    end
    return best
end

-- A light live read (no full Snapshot.capture - this is called on RUN's target
-- changes). Every read is guarded; secret/missing values land as 0.
function BridgeAPI.liveProfile()
    if not _G.UnitStat then return nil end
    local ok, p = pcall(function()
        local _, classToken = _G.UnitClass("player")
        local ap = Guards.number(Guards.call(_G.UnitAttackPower, "player"))
        local sp = bestSpellPower()
        local wMin = Guards.number(Guards.select(1, _G.UnitDamage, "player"))
        local wMax = Guards.number(Guards.select(2, _G.UnitDamage, "player"))
        local speed = Guards.number(Guards.call(_G.UnitAttackSpeed, "player"))
        return BridgeAPI.profileFrom({
            level = Guards.number(Guards.call(_G.UnitLevel, "player")),
            stamina = Guards.number(Guards.call(_G.UnitStat, "player", 3)),
            attackPower = ap,
            spellPower = sp,
            armor = Guards.number(Guards.select(2, _G.UnitArmor, "player")),
            avoidancePct = (Guards.number(Guards.call(_G.GetDodgeChance)) or 0)
                + (Guards.number(Guards.call(_G.GetParryChance)) or 0),
            maxHealth = Guards.number(Guards.call(_G.UnitHealthMax, "player")),
            dps = BridgeAPI.estimateDPS(wMin, wMax, speed, ap, sp),
            class = classToken,
        })
    end)
    if ok then return p end
    return nil
end

-- The public bridge RUN calls. Plain table or nil; never throws at the caller.
_G.ForesightAPI = _G.ForesightAPI or {}
_G.ForesightAPI.addon = "Foresight"
_G.ForesightAPI.version = API_VERSION
function _G.ForesightAPI.GetCombatProfile()
    local ok, p = pcall(BridgeAPI.liveProfile)
    if ok then return p end
    return nil
end

return BridgeAPI
