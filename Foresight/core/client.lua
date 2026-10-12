-- Foresight client adapter: THE swap point for client-API namespacing. 12.x moved
-- classic globals into C_ namespaces (GetItemInfo was the live ambush, 2026-10-12) -
-- every module resolves these through HM.Client, so a game fork (or a client build
-- moving an API) edits THIS file, never the callers. Resolution happens per call
-- (cheap lookups) so a namespace that appears later in the session still wins.
-- Companion tripwire: Collect.apiWatch journals presence of every path per login.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Client = {}
HM.Client = Client

local function resolve(ns, name)
    local t = _G[ns]
    local fn = (type(t) == "table") and t[name] or nil
    return fn or _G[name]
end

function Client.getItemInfo(...)
    local fn = resolve("C_Item", "GetItemInfo")
    if not fn then return nil end
    return fn(...)
end

function Client.getItemInfoInstant(...)
    local fn = resolve("C_Item", "GetItemInfoInstant")
    if not fn then return nil end
    return fn(...)
end

function Client.getItemStats(...)
    local fn = resolve("C_Item", "GetItemStats")
    if not fn then return nil end
    return fn(...)
end

return Client
