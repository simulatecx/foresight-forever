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

-- The allow-list contract is single-sourced in data/crowd-schema.json and generated into
-- HM.gen.crowdSchema (data/generated/crowd_schema.lua, loaded before this file) alongside
-- the web sanitize + Firestore rules. Reading the version + forbidden list from there means
-- the builder below can never drift from the server gate. The literal fallbacks keep the
-- pure builder working if the generated table is somehow absent (e.g. a standalone load).
local SCHEMA = HM.gen and HM.gen.crowdSchema
Crowd.SCHEMA = (SCHEMA and SCHEMA.version) or 1

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

    -- Race token (anon GAME data, like class - "Orc", "Scourge", "NightElf"). Racials shift
    -- hit/stat baselines, so it's useful context on the ladders. Letters only, capped; never
    -- identity. Absent on older submissions (added S34, 2026-10-15).
    local race = type(inp.race) == "string" and inp.race:match("^%a+$")
    if race then out.race = race:sub(1, 24) end

    -- CHALLENGE METRICS (the gamified layer): concrete, non-identifying numbers we can
    -- rank into challenges ("Most Armor", "Most Frost Spell Damage", and - once ability
    -- hits are added - "Biggest Earth Shock"). A GENERIC key->number map so a new
    -- challenge is just a new key, never a schema change. Short string keys, numbers.
    -- key cap 48: fits "ability:<spell name>" (e.g. "ability:Greater Healing Wave").
    for k, val in pairs(type(inp.metrics) == "table" and inp.metrics or {}) do
        if type(k) == "string" and #k <= 48 then
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

    -- OPT-IN SHOW-OFF TIER (S34c): the player may CHOOSE to appear on the public named
    -- leaderboards. This is the ONLY path identifying fields (a chosen handle + optional
    -- armory URL) ever enter the payload, and ONLY when inp.named == true (the explicit
    -- opt-in). A payload built without opt-in can never carry them - the exact mirror of
    -- the Firestore rule (name/armory require named==true). The handle is a nickname, NOT
    -- a real name; no realm/account/guild ever travels (still forbidden).
    if inp.named == true then
        out.named = true
        if type(inp.name) == "string" then
            local h = inp.name:gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 32)
            if #h > 0 then out.name = h end
        end
        if type(inp.armory) == "string" then
            local a = inp.armory:gsub("%s", ""):sub(1, 200)
            -- https only + the exact allow-listed charset the Firestore rule enforces, so an
            -- armory the addon accepts is never rejected server-side (no injection chars).
            if a:match("^https://[%w%._~:/%?#@!%$&%*%+,;=%%%(%)%-]+$") then out.armory = a end
        end
    end

    -- BUFF PROVENANCE (anon game data): active buff spellId -> short name, capped at 40, so
    -- a record can show "with: Flask of ..., Blessing of ..." ("buffed send" honesty). Names
    -- are game strings (not user text); capped and the web escapes them on render.
    local buffs, nb = {}, 0
    for id, name in pairs(type(inp.buffs) == "table" and inp.buffs or {}) do
        local sid = clampInt(id, 1)
        if sid and nb < 40 and type(name) == "string" and #name > 0 then
            buffs[sid] = name:sub(1, 40)
            nb = nb + 1
        end
    end
    if nb > 0 then out.buffs = buffs end

    return out
end

-- The explicit DENY list, kept as an assertion the selftest checks: these keys must
-- NEVER appear in a payload. (Belt-and-suspenders on top of the allow-list build.)
-- Single-sourced from the generated schema; the literal is a headless-safe fallback.
Crowd.FORBIDDEN_KEYS = (SCHEMA and SCHEMA.forbidden) or {
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

-- Pick the N most-seen item sightings (highest count first) for the capped contribute.
-- Returns { [itemId] = count }; buildPayload re-clamps and strips the timestamp. Pure
-- utility - defined above the headless guard so the builder/tests can reach it.
function Crowd.topSightings(map, n)
    if type(map) ~= "table" then return nil end
    local arr = {}
    for id, e in pairs(map) do
        local c = (type(e) == "table" and tonumber(e.c)) or tonumber(e) or 1
        arr[#arr + 1] = { id = id, c = c }
    end
    table.sort(arr, function(a, b) return a.c > b.c end)
    local out = {}
    for i = 1, math.min(#arr, n or 100) do out[arr[i].id] = arr[i].c end
    return out
end

-- Take up to N entries of a map, order-agnostic (observed journal is already bounded).
function Crowd.capMap(map, n)
    if type(map) ~= "table" then return nil end
    local out, i = {}, 0
    for k, v in pairs(map) do
        i = i + 1
        if i > (n or 40) then break end
        out[k] = v
    end
    return out
end

if not _G.CreateFrame then return Crowd end -- headless: pure builder only

-- A stable, non-identifying pseudonym stored in SavedVariables (not derived from any
-- character/account fact) so the backend can count distinct contributors + dedup
-- re-uploads. Built WITHOUT math.random / math.randomseed: reseeding the shared Lua RNG
-- from addon code TAINTS it on the classic client, and secure code that later reads the
-- RNG - the gamepad interact path - then gets blocked (ADDON_ACTION_FORBIDDEN). That was
-- the SECOND /foresight share taint vector after the CSI one (both from v0.46.0). A dedup
-- token only needs to be stable + collision-unlikely, so mix the wall clock with the
-- high-res profiler (the exact sub-millisecond of first run differs per install).
local function clientId()
    if not (HM.db and type(HM.db.collect) == "table") then return nil end
    local c = HM.db.collect
    if type(c.clientId) ~= "string" then
        local t = math.floor(((_G.time and _G.time()) or 0)) % 0x100000000
        local prof = math.floor((((_G.debugprofilestop and _G.debugprofilestop()) or 0)) * 1000)
            % 0x100000000
        c.clientId = ("%08x%08x"):format(t, prof)
    end
    return c.clientId
end

-- Active consumable-buff provenance for a contribute: spellId -> short readable name.
-- Reuses the secret-safe Snapshot.captureActiveBuffs (degrades to none in aura-secret
-- contexts); names come from the generated consumable/spell tables. Gathered ONLY for an
-- actual Contribute (not the per-refresh peer readout) - the aura scan isn't free.
local function activeBuffNames()
    local out = {}
    if not (HM.Snapshot and HM.Snapshot.captureActiveBuffs) then return out end
    local ok, active = pcall(HM.Snapshot.captureActiveBuffs)
    if not ok or type(active) ~= "table" then return out end
    local cons = HM.gen and HM.gen.consumables
    local spells = HM.gen and HM.gen.spells
    for _, b in ipairs(active) do
        local sid = b.spellId
        local nm = (cons and b.itemId and cons[b.itemId] and cons[b.itemId].name)
            or (spells and spells[sid] and spells[sid].name)
        if sid and nm then out[sid] = nm end
    end
    return out
end

-- Gather the live inputs and build the sanitized payload (in-game). `opts.contribute`
-- additionally gathers the opt-in show-off fields (handle/armory, only if the player
-- turned the opt-in on) + active buff provenance - skipped for the per-refresh peer
-- readout so the Matrix hot path stays cheap and taint-light.
function Crowd.payload(opts)
    opts = opts or {}
    local snapshot = HM.Snapshot and HM.Snapshot.capture()
    if not snapshot then return nil, "not in game" end
    local collect = (HM.db and HM.db.collect) or {}
    local loadout = HM.Loadout and HM.Loadout.fromSnapshot(snapshot)
    local lenses = {}
    if loadout and HM.Impact and HM.Impact.evaluate then
        local ok, results = pcall(HM.Impact.evaluate, loadout)
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
    -- ABILITY-HIT CHALLENGES (per class, automatically): rank the player's OWN known
    -- abilities by computed hit and share the top few as "ability:<name>" -> hit. Each
    -- class surfaces its own signature spells (Earth Shock, Fireball, …); the backend
    -- ranks them into "Biggest <ability>" challenges. The ability name is game data,
    -- not identity. Guarded + bounded (top 6 damage + top 3 heals).
    if loadout and HM.Spellbook and HM.Spellbook.known and HM.Sim and HM.Sim.topOutputs then
        local okk, known = pcall(HM.Spellbook.known)
        if okk and type(known) == "table" and #known > 0 then
            local okt, tops = pcall(HM.Sim.topOutputs, loadout, known, 6)
            if okt and type(tops) == "table" then
                for _, e in ipairs(tops.damage or {}) do
                    if e.name and e.avg then metrics["ability:" .. e.name] = e.avg end
                end
                local heals = 0
                for _, e in ipairs(tops.heal or {}) do
                    if heals < 3 and e.name and e.avg then
                        metrics["ability:" .. e.name] = e.avg
                        heals = heals + 1
                    end
                end
            end
        end
    end
    -- Spec id is deliberately NOT read here: C_SpecializationInfo calls carry
    -- "Lua Taint: Foresight" (apiWatch-confirmed; the v0.37.1 lead). This payload runs on
    -- /foresight share AND every Matrix refresh (the peer readout), so a tainted CSI call
    -- propagates and the client blocks the next protected action (the 2026-10-14 share
    -- block). Forever uses classic talent trees, not retail specs - buckets are per-class
    -- ("any" spec) until a TAINT-SAFE spec signal exists (e.g. the dominant talent tree).
    local specId = nil
    -- Opt-in show-off fields + buff provenance: only for an actual Contribute, and the
    -- handle/armory only when the player turned the opt-in ON. buildPayload re-checks the
    -- gate (named==true) so nothing identifying can slip through without the opt-in.
    local named, handle, armory, buffs = nil, nil, nil, nil
    if opts.contribute then
        if HM.Settings and HM.Settings.get("named") == true then
            named = true
            local h = HM.Settings.get("handle")
            local a = HM.Settings.get("armory")
            if type(h) == "string" and #h > 0 then handle = h end
            if type(a) == "string" and #a > 0 then armory = a end
        end
        buffs = activeBuffNames()
    end
    -- SCAN -> DB (user 2026-10-14: "anything I scan should go into our DB"). The local
    -- item-sightings and observed-buff journals ride the contribute payload so the crowd
    -- DB receives them alongside the compare fields. They're CAPPED (most-seen items first)
    -- to keep the share link usable - the earlier "huge URL" was an uncapped dump; the
    -- exhaustive, uncapped export stays the job of the future read-only companion app
    -- (reads SavedVariables directly, no URL limit). The browser COMPARE ignores these two
    -- fields entirely; only the backend DB consumes them. buildPayload sanitizes both
    -- (drops timestamps, clamps ids/counts, filters stat keys); the Firestore rules
    -- shape-lock already allow 'items'/'observed' as size-capped maps.
    return Crowd.buildPayload({
        build = HM.gen and HM.gen.build,
        classToken = snapshot.classToken,
        race = snapshot.raceToken,
        specId = specId,
        level = snapshot.level,
        lenses = lenses,
        metrics = metrics,
        talents = talents,
        items = Crowd.topSightings(collect.itemSightings, 100),
        observed = Crowd.capMap(collect.observedImpacts, 40),
        clientId = clientId(),
        named = named, name = handle, armory = armory, buffs = buffs,
    })
end

return Crowd
