-- Foresight crowd-share contract (S13 / CROWD-share): the ONE place that decides what
-- may ever leave a player's machine for the crowd dataset. The WoW addon NEVER networks
-- (account-safety doctrine) - this only BUILDS a sanitized payload that the user
-- voluntarily copies into the companion web app (wow-foresight). The web app + Firebase
-- store it; the pipeline bakes per-spec aggregates back into a shipped table.
--
-- DATA-MINIMIZATION LAW (user, 2026-10-13: "nothing can come to us other than items
-- etc"): the payload is built by an ALLOW-LIST - we copy only the named, non-identifying
-- GAME fields below and nothing else. A deny-list (copy-all-minus) is forbidden here,
-- because a new field added to the collect store elsewhere would silently leak. If a
-- field isn't explicitly whitelisted and shaped, it does not exist in the payload.
--
-- CLASSIFICATION (privacy-by-design): every field is "none" (non-identifying game data)
-- or an explicit pseudonym (clientId). There is NO direct or indirect PII: no character
-- name, realm, account, guild, zone, timestamps, or free text (the /foresight report
-- notes, taint events, and tooltip-owner strings are NEVER included).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Crowd = {}
HM.Crowd = Crowd

Crowd.SCHEMA = 1

-- The lens ids that may be shared (the computed dimension indices - pure numbers, no
-- identity). Derived from the shipped dimension roster so it can't drift.
local function lensIds()
    local ids = {}
    for _, dim in ipairs((HM.dimensions and HM.dimensions.list) or {}) do
        ids[#ids + 1] = dim.id
    end
    return ids
end

local function clampInt(v, lo, hi)
    v = tonumber(v)
    if not v then return nil end
    v = math.floor(v + 0.5)
    if lo and v < lo then return nil end
    if hi and v > hi then return nil end
    return v
end

local function clampNum(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end -- reject nil + NaN
    -- round to 2 dp: these are display-grade indices, extra precision is noise
    return math.floor(v * 100 + 0.5) / 100
end

-- PURE allow-list builder (headless-testable). `inp` carries the raw inputs; the output
-- is constructed field-by-field so only whitelisted, shaped data can appear. Returns
-- nil when the minimum identity-free keys for a useful contribution are absent.
function Crowd.buildPayload(inp)
    inp = inp or {}
    local classToken = type(inp.classToken) == "string" and inp.classToken:match("^%u+$")
    local level = clampInt(inp.level, 1, 200)
    if not (classToken and level) then return nil end

    local out = {
        v = Crowd.SCHEMA,
        build = type(inp.build) == "string" and inp.build:sub(1, 32) or "?",
        class = classToken,
        spec = clampInt(inp.specId, 0, 100000), -- numeric spec id only (no name)
        level = level,
        lenses = {},
        metrics = {},
        talents = {},
        items = {},
        observed = {},
    }

    -- CHALLENGE METRICS (the gamified layer): concrete, non-identifying numbers we can
    -- rank into challenges ("Most Armor", "Most Frost Spell Damage", and - once ability
    -- hits are added - "Biggest Earth Shock"). A GENERIC key->number map so a new
    -- challenge is just a new key, never a schema change. Short string keys, numbers.
    for k, val in pairs(type(inp.metrics) == "table" and inp.metrics or {}) do
        if type(k) == "string" and #k <= 24 then
            local n = clampNum(val)
            if n then out.metrics[k] = n end
        end
    end

    -- Computed dimension indices (numbers only).
    local allowLens = {}
    for _, id in ipairs(lensIds()) do allowLens[id] = true end
    for id, score in pairs(type(inp.lenses) == "table" and inp.lenses or {}) do
        if allowLens[id] then
            local n = clampNum(score)
            if n then out.lenses[id] = n end
        end
    end

    -- Talent build shape: nodeId -> rank (game data, no identity). Keys/values numeric.
    for nodeId, rank in pairs(type(inp.talents) == "table" and inp.talents or {}) do
        local nid, rk = clampInt(nodeId, 1), clampInt(rank, 0, 20)
        if nid and rk then out.talents[nid] = rk end
    end

    -- Item sightings: itemId -> count (the "what items are in game" crowd DB). The
    -- stored entry is { c = count, last = <date> } - we copy ONLY the count; the date
    -- is a timestamp and never leaves. Bare-number entries are tolerated defensively.
    for itemId, entry in pairs(type(inp.items) == "table" and inp.items or {}) do
        local iid = clampInt(itemId, 1)
        local c = clampInt(type(entry) == "table" and entry.c or entry, 1)
        if iid and c then out.items[iid] = c end
    end

    -- Observed buff impacts: spellId -> { n = observations, stats = { statKey -> value } }
    -- (live game facts). The stored entry also has an `.at` timestamp - explicitly
    -- EXCLUDED. Only short string stat keys with numeric values are copied (no free text).
    for spellId, e in pairs(type(inp.observed) == "table" and inp.observed or {}) do
        local sid = clampInt(spellId, 1)
        if sid and type(e) == "table" then
            local src = type(e.stats) == "table" and e.stats or e
            local cleanStats = {}
            for k, val in pairs(src) do
                if type(k) == "string" and #k <= 24 and k ~= "at" and k ~= "n" then
                    local num = clampNum(val)
                    if num then cleanStats[k] = num end
                end
            end
            if next(cleanStats) then
                out.observed[sid] = { n = clampInt(e.n, 1) or 1, stats = cleanStats }
            end
        end
    end

    -- Pseudonymous contributor id (NOT identity): a random token generated once per
    -- install, purely so the backend can count distinct contributors (k-of-n) and dedup
    -- re-uploads without ever knowing who you are. Disclosed in the privacy notice.
    if type(inp.clientId) == "string" and inp.clientId:match("^[%w%-]+$")
            and #inp.clientId <= 40 then
        out.clientId = inp.clientId
    end

    return out
end

-- The explicit DENY list, kept as an assertion the selftest checks: these keys must
-- NEVER appear in a payload. (Belt-and-suspenders on top of the allow-list build.)
Crowd.FORBIDDEN_KEYS = {
    "name", "realm", "account", "guild", "reports", "taintEvents",
    "lastTooltipOwner", "sessions", "notes", "at",
}

-- Minimal JSON encoder (the web app JSON.parse's this directly). All tables encode as
-- objects with stringified, sorted keys (stable output); no arrays are needed in the
-- payload. Lua 5.1-safe escaping ([%c"\\], no %z).
local JSON_ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n',
                   ['\r'] = '\\r', ['\t'] = '\\t' }
function Crowd.toJSON(v)
    local t = type(v)
    if t == "number" then
        if v == math.floor(v) and v == v and v ~= math.huge and v ~= -math.huge then
            return ("%d"):format(v)
        end
        return ("%.4g"):format(v)
    elseif t == "string" then
        return '"' .. v:gsub('[%c"\\]', function(ch)
            return JSON_ESC[ch] or ("\\u%04x"):format(ch:byte())
        end) .. '"'
    elseif t == "boolean" then
        return v and "true" or "false"
    elseif t == "table" then
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = k end
        table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
        local parts = {}
        for _, k in ipairs(keys) do
            parts[#parts + 1] = Crowd.toJSON(tostring(k)) .. ":" .. Crowd.toJSON(v[k])
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end
    return "null"
end

-- The companion site. The share flow hands the user ONE link with their sanitized
-- data packed into the URL fragment (#d=...): they copy it in-game, paste it into their
-- browser, and the site opens pre-filled. The fragment is client-side only - it is not
-- sent to any server until the user explicitly consents and contributes.
Crowd.SITE_URL = "https://wow-foresight.web.app"

-- Percent-encode to RFC-3986 unreserved (A-Z a-z 0-9 - _ . ~); decodeURIComponent
-- reverses it on the web side. Our JSON is ASCII, so byte-wise encoding is exact.
function Crowd.urlEncode(s)
    return (tostring(s):gsub("[^%w%-_%.~]", function(c)
        return ("%%%02X"):format(c:byte())
    end))
end

function Crowd.shareUrl(payload)
    if not payload then return nil end
    return Crowd.SITE_URL .. "/#d=" .. Crowd.urlEncode(Crowd.toJSON(payload))
end

if not _G.CreateFrame then return Crowd end -- headless: pure builder only

-- A stable, non-identifying pseudonym stored in SavedVariables (random; not derived
-- from any character/account fact). math.randomseed off the clock is fine in-client.
local function clientId()
    if not (HM.db and type(HM.db.collect) == "table") then return nil end
    local c = HM.db.collect
    if type(c.clientId) ~= "string" then
        local t = (_G.time and _G.time()) or 0
        if _G.math and math.randomseed then pcall(math.randomseed, t) end
        local id = {}
        for _ = 1, 16 do id[#id + 1] = ("%x"):format(math.random(0, 15)) end
        c.clientId = table.concat(id)
    end
    return c.clientId
end

-- Gather the live inputs and build the sanitized payload (in-game).
function Crowd.payload()
    local snapshot = HM.Snapshot and HM.Snapshot.capture()
    if not snapshot then return nil, "not in game" end
    local lenses = {}
    if HM.Impact and HM.Impact.evaluate then
        local ok, results = pcall(HM.Impact.evaluate, HM.Loadout.fromSnapshot(snapshot))
        if ok and results then
            for id, r in pairs(results) do
                if type(r) == "table" and type(r.score) == "number" then
                    lenses[id] = r.score
                end
            end
        end
    end
    -- Talent build shape (nodeId -> rank) from the snapshot, no identity.
    local talents = {}
    for _, t in ipairs(snapshot.talents or {}) do
        local nid = t.nodeId or t.nodeID
        if nid then talents[nid] = t.rank or 0 end
    end
    -- Challenge metrics from live stats (all non-identifying numbers).
    local st = snapshot.stats or {}
    local metrics = {
        ["stat.armor"] = st.armor,
        ["stat.maxHealth"] = st.maxHealth,
        ["stat.spellDamage"] = st.spellDamage,
    }
    for school, v in pairs(type(st.schoolDamage) == "table" and st.schoolDamage or {}) do
        metrics["school." .. tostring(school)] = v
    end
    local collect = (HM.db and HM.db.collect) or {}
    -- spec id (numeric only) via the guarded API; nil if unavailable.
    local specId
    if _G.C_SpecializationInfo and _G.C_SpecializationInfo.GetSpecialization then
        local ok, s = pcall(_G.C_SpecializationInfo.GetSpecialization)
        if ok then specId = s end
    end
    return Crowd.buildPayload({
        build = HM.gen and HM.gen.build,
        classToken = snapshot.classToken,
        specId = specId,
        level = snapshot.level,
        lenses = lenses,
        metrics = metrics,
        talents = talents,
        items = collect.itemSightings,
        observed = collect.observedImpacts,
        clientId = clientId(),
    })
end

return Crowd
