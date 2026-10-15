-- ForeverTalents "FT2" build-code interop (S35): read + write the share codes used by the
-- CurseForge addon ForeverTalents, so builds cross-compatible between the two addons. PURE
-- codec (headless-testable). Format (their Share.lua, verified): the string is "FT2" + an
-- unpadded Base64 of ( payload .. Adler32(payload) as 4 big-endian bytes ), where payload is
--   "FTB2" | kind(1 byte: 0=build 1=preview) | varuint(classID) | varuint(specID)
--   | varuint(treeID) | varuint(totalPoints) | varuint(interfaceVersion) | varuint(nameLen)
--   | name bytes | varuint(nodeCount) | { varuint(id) varuint(ranks) varuint(entryID)
--     zigzag(posX) zigzag(posY) } * | varuint(orderCount) | { varuint(nodeID) varuint(entryID) } *
-- UNTRUSTED-INPUT LAW: decode is pure byte parsing (never loadstring), fully bounds-checked.
-- ACCOUNT-SAFETY: this only reads/writes strings; it never touches the game.
--
-- Lua 5.1 dialect + the compliance ban on bit operators: all byte math is ARITHMETIC
-- (math.floor / % / *), never band/bor/shift.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local FT2 = {}
HM.FT2 = FT2

FT2.PREFIX = "FT2"
local MAGIC = "FTB2"

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_REV = {}
for i = 1, #B64 do B64_REV[B64:sub(i, i)] = i - 1 end

-- ---- base64 (unpadded) -----------------------------------------------------------------
local function base64_encode(bytes)
    local out, n = {}, #bytes
    local i = 1
    while i <= n do
        local b1 = bytes:byte(i) or 0
        local b2 = bytes:byte(i + 1)
        local b3 = bytes:byte(i + 2)
        local n1 = math.floor(b1 / 4)
        local n2 = (b1 % 4) * 16 + math.floor((b2 or 0) / 16)
        out[#out + 1] = B64:sub(n1 + 1, n1 + 1)
        out[#out + 1] = B64:sub(n2 + 1, n2 + 1)
        if b2 then
            local n3 = ((b2 % 16) * 4) + math.floor((b3 or 0) / 64)
            out[#out + 1] = B64:sub(n3 + 1, n3 + 1)
            if b3 then
                local n4 = b3 % 64
                out[#out + 1] = B64:sub(n4 + 1, n4 + 1)
            end
        end
        i = i + 3
    end
    return table.concat(out)
end

local function base64_decode(str)
    local bytes = {}
    local vals, i, n = {}, 1, #str
    for k = 1, n do
        local v = B64_REV[str:sub(k, k)]
        if v == nil then return nil end
        vals[#vals + 1] = v
    end
    local j = 1
    while j <= #vals do
        local c1, c2, c3, c4 = vals[j], vals[j + 1], vals[j + 2], vals[j + 3]
        if c2 == nil then return nil end
        bytes[#bytes + 1] = string.char(c1 * 4 + math.floor(c2 / 16))
        if c3 ~= nil then
            bytes[#bytes + 1] = string.char((c2 % 16) * 16 + math.floor(c3 / 4))
            if c4 ~= nil then
                bytes[#bytes + 1] = string.char((c3 % 4) * 64 + c4)
            end
        end
        j = j + 4
    end
    return table.concat(bytes)
end

-- ---- varuint (LEB128) + zigzag ---------------------------------------------------------
local function var_encode(n)
    n = math.floor(n or 0)
    if n < 0 then n = 0 end
    local out = {}
    repeat
        local b = n % 128
        n = math.floor(n / 128)
        if n > 0 then b = b + 128 end
        out[#out + 1] = string.char(b)
    until n == 0
    return table.concat(out)
end

-- Returns value, nextOffset or nil on malformed/overlong.
local function var_decode(str, off)
    local result, shift, count = 0, 1, 0
    while true do
        count = count + 1
        if count > 5 then return nil end
        local b = str:byte(off)
        if not b then return nil end
        off = off + 1
        result = result + (b % 128) * shift
        if b < 128 then return result, off end
        shift = shift * 128
    end
end

local function zig_encode(n)
    n = math.floor(n or 0)
    return var_encode(n >= 0 and n * 2 or (-n * 2 - 1))
end

local function zig_decode(str, off)
    local z, nxt = var_decode(str, off)
    if not z then return nil end
    local v = (z % 2 == 0) and (z / 2) or -((z + 1) / 2)
    return v, nxt
end

-- ---- Adler-32 (arithmetic) -------------------------------------------------------------
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return b * 65536 + a
end

local function pack_u32_be(n)
    local b1 = math.floor(n / 16777216) % 256
    local b2 = math.floor(n / 65536) % 256
    local b3 = math.floor(n / 256) % 256
    local b4 = n % 256
    return string.char(b1, b2, b3, b4)
end

-- ---- FT2 encode / decode ---------------------------------------------------------------
-- plan = { kind=0|1, classID, specID, treeID, totalPoints, interfaceVersion, name,
--          nodes = { {id, ranks, entryID, posX, posY}, ... }, order = { {nodeID, entryID} } }
function FT2.encode(plan)
    if type(plan) ~= "table" or type(plan.nodes) ~= "table" then return nil end
    local name = tostring(plan.name or ""):sub(1, 40)
    local parts = {
        MAGIC, string.char(plan.kind == 1 and 1 or 0),
        var_encode(plan.classID or 0), var_encode(plan.specID or 0),
        var_encode(plan.treeID or 0), var_encode(plan.totalPoints or 0),
        var_encode(plan.interfaceVersion or 0), var_encode(#name), name,
        var_encode(#plan.nodes),
    }
    for _, nd in ipairs(plan.nodes) do
        parts[#parts + 1] = var_encode(nd.id or 0)
        parts[#parts + 1] = var_encode(nd.ranks or 0)
        parts[#parts + 1] = var_encode(nd.entryID or 0)
        parts[#parts + 1] = zig_encode(nd.posX or 0)
        parts[#parts + 1] = zig_encode(nd.posY or 0)
    end
    local order = plan.order or {}
    parts[#parts + 1] = var_encode(#order)
    for _, e in ipairs(order) do
        parts[#parts + 1] = var_encode(e.nodeID or 0)
        parts[#parts + 1] = var_encode(e.entryID or 0)
    end
    local payload = table.concat(parts)
    return FT2.PREFIX .. base64_encode(payload .. pack_u32_be(adler32(payload)))
end

function FT2.decode(str)
    if type(str) ~= "string" or str:sub(1, #FT2.PREFIX) ~= FT2.PREFIX then
        return nil, "not an FT2 code"
    end
    local raw = base64_decode(str:sub(#FT2.PREFIX + 1))
    if not raw or #raw < 8 then return nil, "bad base64" end
    local payload = raw:sub(1, #raw - 4)
    local sum = raw:sub(#raw - 3)
    if pack_u32_be(adler32(payload)) ~= sum then return nil, "checksum mismatch" end
    if payload:sub(1, #MAGIC) ~= MAGIC then return nil, "bad magic" end
    local off = #MAGIC + 1
    local kind = payload:byte(off); off = off + 1
    if kind ~= 0 and kind ~= 1 then return nil, "bad kind" end
    local function rv()
        local v; v, off = var_decode(payload, off); return v
    end
    local plan = { kind = kind }
    plan.classID = rv(); plan.specID = rv(); plan.treeID = rv()
    plan.totalPoints = rv(); plan.interfaceVersion = rv()
    local nameLen = rv()
    if not nameLen or nameLen > 40 or off + nameLen - 1 > #payload then return nil, "bad name" end
    plan.name = payload:sub(off, off + nameLen - 1); off = off + nameLen
    local count = rv()
    if not count or count > 1000 then return nil, "bad node count" end
    plan.nodes = {}
    local total, seen = 0, {}
    for _ = 1, count do
        local id = rv(); local ranks = rv(); local entryID = rv()
        local posX, posY
        posX, off = zig_decode(payload, off)
        posY, off = zig_decode(payload, off)
        if not (id and ranks and entryID and posX and posY) then return nil, "truncated node" end
        if seen[id] then return nil, "duplicate node" end
        seen[id] = true
        total = total + ranks
        plan.nodes[#plan.nodes + 1] = { id = id, ranks = ranks, entryID = entryID, posX = posX, posY = posY }
    end
    if plan.totalPoints and plan.totalPoints ~= total then return nil, "point mismatch" end
    local ocount = rv()
    plan.order = {}
    if ocount and ocount <= 1000 then
        for _ = 1, ocount do
            local nodeID = rv(); local entryID = rv()
            if not (nodeID and entryID) then return nil, "truncated order" end
            plan.order[#plan.order + 1] = { nodeID = nodeID, entryID = entryID }
        end
    end
    return plan
end

-- Convenience: a decoded FT2 (or a plan) -> our node plan { nodeId = ranks } for the overlay.
function FT2.nodeRanks(decoded)
    local out = {}
    for _, nd in ipairs(type(decoded) == "table" and decoded.nodes or {}) do
        if nd.id and (nd.ranks or 0) > 0 then out[nd.id] = nd.ranks end
    end
    return out
end

return FT2
