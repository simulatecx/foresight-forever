-- Foresight weapon imbues (IMBUE-compare): the "Rockbiter or Flametongue on my 2H
-- axe?" answer. Every imbue's decoded effects (generated weapon_imbues.lua) become
-- per-swing and per-second numbers for YOUR live weapon speed:
--   +AP equips      -> AP / 14 * speed per swing (14 AP = 1 DPS, classic law, (p))
--   speed-scaled    -> basis * speed / 100 per hit (Flametongue; constant DPS, so
--                      slower weapons hit bigger without losing throughput)
--   chance procs    -> chance% x damage expected value; UNKNOWN proc rates are said
--                      out loud, never invented.
-- Pure Lua, selftest-covered; the live rank filter is the only in-game read.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Imbues = {}
HM.Imbues = Imbues

local AP_PER_DPS = 14

-- The imbue spells the player actually knows (in-game; headless returns none).
function Imbues.known()
    local known = {}
    local isKnown = _G.IsPlayerSpell or _G.IsSpellKnown
    if not isKnown then return known end
    for sid in pairs((HM.gen and HM.gen.imbues) or {}) do
        local ok, yes = pcall(isKnown, sid)
        if ok and yes then known[#known + 1] = sid end
    end
    table.sort(known)
    return known
end

-- Compare imbues on a snapshot's weapon. Returns rows sorted by estimated DPS
-- (ranks sharing a name deduped to the strongest) + the weapon speed used.
-- Row: { spellID, name, perSwing, perSec, notes = {...}, needsCuration?, confidence }.
function Imbues.compare(snapshot, ids)
    local gen = (HM.gen and HM.gen.imbues) or {}
    local speed = (snapshot and snapshot.weaponSpeed) or 2.0
    local rows = {}
    for _, sid in ipairs(ids or {}) do
        local e = gen[sid]
        if e then
            local perSwing, perSec, notes, curation = 0, 0, {}, false
            for _, op in ipairs(e.ops or {}) do
                if op.kind == "attackPower" then
                    local ap = op.maxValue or 0
                    perSwing = perSwing + ap / AP_PER_DPS * speed
                    perSec = perSec + ap / AP_PER_DPS
                    notes[#notes + 1] = ("+%g Attack Power while imbued"):format(ap)
                elseif op.kind == "threat" then
                    notes[#notes + 1] = "extra threat (tank-friendly, pulls attention)"
                else
                    curation = true
                end
            end
            if e.flatDamage then
                perSwing = perSwing + e.flatDamage
                perSec = perSec + e.flatDamage / speed
                notes[#notes + 1] = ("+%g weapon damage per hit"):format(e.flatDamage)
            end
            if e.speedDamage then
                local per = e.speedDamage.per100Speed * speed / 100
                perSwing = perSwing + per
                perSec = perSec + e.speedDamage.per100Speed / 100
                notes[#notes + 1] = ("%.1f %s per hit on a %.1fs weapon - slower weapon = bigger hits, same DPS")
                    :format(per, e.speedDamage.school or "bonus", speed)
            end
            for _, p in ipairs(e.procs or {}) do
                if p.chance and p.damage then
                    local ev = p.chance / 100 * p.damage
                    perSwing = perSwing + ev
                    perSec = perSec + ev / speed
                    notes[#notes + 1] = ("%d%% on hit: %g %s (~%.1f per swing; fast weapons proc more)")
                        :format(p.chance, p.damage, p.school or "", ev)
                elseif p.damage then
                    notes[#notes + 1] = ("chance on hit: %g %s - proc rate not in the data (unverified)")
                        :format(p.damage, p.school or "")
                    curation = true
                end
            end
            if e.chance and perSwing == 0 and #notes == 0 then
                notes[#notes + 1] = ("%d%% on hit: extra effect (see the spell tooltip)"):format(e.chance)
                curation = true
            end
            rows[#rows + 1] = {
                spellID = sid, name = e.name, perSwing = perSwing, perSec = perSec,
                notes = notes, needsCuration = curation or nil, confidence = e.confidence,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.perSec ~= b.perSec then return a.perSec > b.perSec end
        return a.spellID < b.spellID
    end)
    local seen, out = {}, {}
    for _, r in ipairs(rows) do
        if not seen[r.name] then
            seen[r.name] = true
            out[#out + 1] = r
        end
    end
    return out, speed
end

return Imbues
