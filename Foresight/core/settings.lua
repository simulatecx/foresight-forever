-- Foresight settings spine (CORE-options, S30): ONE declared key table that the slash
-- commands, the options GUI, and the docs all bind to - slash and GUI are two controls
-- of one validated store (like the eye-icon and the checkbox for the same key). Every
-- read validates (untrusted-input law); a tampered SavedVariables settings table heals
-- on first touch by falling back to the declared default.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Settings = {}
HM.Settings = Settings

-- Each key: group (the GUI tab; only groups with shipped keys render a tab), type
-- (toggle|enum|slider), default, and for toggles kind="show" (stored under
-- settings.show for back-compat with the S27 standing key). label/desc are the one
-- source for the GUI text and the slash usage lines.
Settings.KEYS = {
    standing = {
        group = "General", type = "toggle", kind = "show", default = true,
        label = "Show archetype name",
        desc = "Show the build archetype (Glass Cannon, Threat Anchor...) on the panel and Matrix. Your numbers always show.",
    },
    coaching = {
        group = "General", type = "toggle", kind = "show", default = true,
        label = "Enable stat coaching",
        desc = "Show the one derived line that explains a mechanism-dead stat (e.g. Agility gives a Shaman no Attack Power).",
    },
    panelAlpha = {
        group = "General", type = "slider", default = 0.92, min = 0.2, max = 1.0,
        label = "Panel opacity",
        desc = "Background opacity for the Foresight panels.",
    },
    actionTrigger = {
        group = "Synergy Matrix", type = "enum", default = "alt",
        values = { "off", "alt", "shift" },
        label = "Action-bar trace modifier",
        desc = "Hold this while hovering an action button (talent frame open) to light the talents that feed it. off disables it.",
    },
}

-- The ordered group list for the GUI (a group renders only if it owns >= 1 key).
Settings.GROUPS = { "General", "Tooltips", "Synergy Matrix" }

-- Validate a NATIVE stored value for a key -> clean value or the declared default.
function Settings.validate(key, raw)
    local spec = Settings.KEYS[key]
    if not spec then return nil end
    if spec.type == "toggle" then
        if raw == true or raw == false then return raw end
    elseif spec.type == "enum" then
        for _, v in ipairs(spec.values) do if raw == v then return raw end end
    elseif spec.type == "slider" then
        local n = tonumber(raw)
        if n and n >= spec.min and n <= spec.max then return n end
    end
    return spec.default
end

-- Coerce a RAW SLASH TOKEN (string) to the key's native type -> value or nil (invalid).
function Settings.coerce(key, text)
    local spec = Settings.KEYS[key]
    if not spec then return nil end
    if spec.type == "toggle" then
        if text == "on" then return true elseif text == "off" then return false end
        return nil
    elseif spec.type == "enum" then
        for _, v in ipairs(spec.values) do if text == v then return v end end
        return nil
    elseif spec.type == "slider" then
        local n = tonumber(text)
        if n then return Settings.validate(key, n) end
        return nil
    end
    return nil
end

local function settingsTable()
    local db = HM.charDb and HM.charDb()
    return db and db.settings or nil
end

-- Read a key, always validated (heals tampered stores to the default).
function Settings.get(key)
    local spec = Settings.KEYS[key]
    if not spec then return nil end
    local s = settingsTable()
    local raw
    -- NB: never collapse this with `... or nil` - a stored `false` is a real value and
    -- the and/or idiom would drop it to nil (and thus to the default). Explicit reads.
    if spec.kind == "show" then
        if s and type(s.show) == "table" then raw = s.show[key] end
    elseif s then
        raw = s[key]
    end
    return Settings.validate(key, raw)
end

-- Write a key from a native value (GUI) - validated before store.
function Settings.setValue(key, value)
    local spec = Settings.KEYS[key]
    if not spec then return nil end
    local clean = Settings.validate(key, value)
    local db = HM.charDb and HM.charDb()
    if db then
        if spec.kind == "show" then
            if type(db.settings.show) ~= "table" then db.settings.show = {} end
            db.settings.show[key] = clean
        else
            db.settings[key] = clean
        end
    end
    return clean
end

-- Write a key from a raw slash token - coerce then store; nil return = invalid input.
function Settings.setFromText(key, text)
    local value = Settings.coerce(key, text)
    if value == nil then return nil end
    return Settings.setValue(key, value)
end

-- Usage string for a key (slash help + GUI tooltip), from the declared spec.
function Settings.usage(key)
    local spec = Settings.KEYS[key]
    if not spec then return key end
    if spec.type == "toggle" then return key .. " on|off"
    elseif spec.type == "enum" then return key .. " " .. table.concat(spec.values, "|")
    elseif spec.type == "slider" then return ("%s %.1f-%.1f"):format(key, spec.min, spec.max) end
    return key
end

return Settings
