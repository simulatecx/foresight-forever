-- Foresight secret-value guard layer. ALL reads of game state that can be secret in
-- restricted contexts (instances, PvP) go through here, so the rest of the codebase
-- never branches on a value that might explode. Headless-safe: issecretvalue does not
-- exist outside the client, so everything degrades to plain passthrough in tests.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Guards = {}
HM.Guards = Guards

local issecret = _G.issecretvalue or function() return false end

-- Returns the value if it is a plain readable number, else nil + "secret"/"missing".
function Guards.number(v)
    if v == nil then return nil, "missing" end
    if issecret(v) then return nil, "secret" end
    if type(v) ~= "number" then return nil, "not-a-number" end
    return v
end

-- Call fn safely; returns nil on error or secret result instead of propagating.
function Guards.call(fn, ...)
    if type(fn) ~= "function" then return nil, "missing-api" end
    local ok, result = pcall(fn, ...)
    if not ok then return nil, "error" end
    if issecret(result) then return nil, "secret" end
    return result
end

-- Call fn safely and return its n-th result (APIs like UnitArmor return several
-- values; which position means what is shape-verified on beta). Guarded like call().
function Guards.select(n, fn, ...)
    if type(fn) ~= "function" then return nil, "missing-api" end
    local results = { pcall(fn, ...) }
    if not results[1] then return nil, "error" end
    local v = results[n + 1]
    if issecret(v) then return nil, "secret" end
    return v
end

-- True when we are in a context where combat values may be secret. Conservative:
-- if the detection APIs are themselves unavailable, assume unrestricted (open world).
function Guards.inRestrictedContext()
    local C_Secrets = _G.C_Secrets
    if C_Secrets and C_Secrets.ShouldUnitHealthMaxBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldUnitHealthMaxBeSecret, "player")
        if ok then return secret and true or false end
    end
    return false
end

-- True when aura data may be secret in this context. spellId itself is NeverSecret,
-- but aura values (duration, stacks) aren't - buff features degrade to display-only.
function Guards.aurasSecret()
    local C_Secrets = _G.C_Secrets
    if C_Secrets and C_Secrets.ShouldAurasBeSecret then
        local ok, secret = pcall(C_Secrets.ShouldAurasBeSecret)
        if ok then return secret and true or false end
    end
    return false
end

return Guards
