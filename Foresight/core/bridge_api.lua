-- Foresight -> RUN bridge (the sibling living-world addon, _G.RunAdvisor).
-- READ-ONLY, addon-to-addon: Foresight publishes a LIGHT character combat
-- profile (survivability + offense, straight off the live sheet) so RUN can
-- compute honest odds-vs-creature WITHOUT reading the player's live health -
-- which Forever hides as a secret value on PvP realms / restricted contexts.
--
-- Laws honored: nothing leaves the client, no backend, no T&Cs/privacy impact
-- (this is the same wall as any two addons talking in-memory). ADDITIVE only -
-- a new file + two .toc lines; no existing Foresight behaviour changes. RUN
-- probes _G.ForesightAPI defensively, so absent/old Foresight simply means RUN
-- falls back to its own coarse model. The numbers are the live sheet reads
-- Foresight already trusts (Guards: missing/secret values land as 0).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local BridgeAPI = {}
HM.BridgeAPI = BridgeAPI

local API_VERSION = 1

-- Pure: shape raw sheet reads into the STABLE profile RUN consumes. Kept pure
-- so Foresight's gate covers the contract headlessly; every field is a
-- non-negative number (0 = unknown/secret) or a class token.
function BridgeAPI.profileFrom(level, stamina, attackPower, spellPower, armor,
                               avoidancePct, maxHealth, classToken)
    local function num(v)
        v = tonumber(v)
        if not v or v ~= v or v < 0 then return 0 end
        return v
    end
    local lvl = num(level)
    return {
        v = API_VERSION,
        level = lvl >= 1 and lvl or 1,
        stamina = num(stamina),
        attackPower = num(attackPower),
        spellPower = num(spellPower),
        armor = num(armor),
        avoidancePct = num(avoidancePct),
        maxHealth = num(maxHealth),        -- 0 when the client hides it (secret)
        class = type(classToken) == "string" and classToken or "?",
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

-- A light live read (no full Snapshot.capture - this is called on RUN's
-- target changes). Every read is guarded; secret/missing values land as 0.
function BridgeAPI.liveProfile()
    if not _G.UnitStat then return nil end
    local ok, p = pcall(function()
        local _, classToken = _G.UnitClass("player")
        return BridgeAPI.profileFrom(
            Guards.number(Guards.call(_G.UnitLevel, "player")),
            Guards.number(Guards.call(_G.UnitStat, "player", 3)),       -- stamina
            Guards.number(Guards.call(_G.UnitAttackPower, "player")),
            bestSpellPower(),
            Guards.number(Guards.select(2, _G.UnitArmor, "player")),
            (Guards.number(Guards.call(_G.GetDodgeChance)) or 0)
                + (Guards.number(Guards.call(_G.GetParryChance)) or 0),
            Guards.number(Guards.call(_G.UnitHealthMax, "player")),
            classToken)
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
