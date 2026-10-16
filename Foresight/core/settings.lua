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
    spellImpact = {
        group = "Tooltips", type = "toggle", kind = "show", default = true,
        label = "Show which spells an item lifts",
        desc = "On an item tooltip, list the few of YOUR top abilities this item changes the most, ranked (e.g. 'Frostbolt +3.2%'). Works for gear and weapons alike. Off = just the dimension verdict.",
    },
    panelAlpha = {
        group = "Layout", type = "slider", default = 0.92, min = 0.2, max = 1.0,
        label = "Panel opacity",
        desc = "Background opacity for the Foresight panels.",
    },
    actionTrigger = {
        group = "Synergy Matrix", type = "enum", default = "alt",
        values = { "off", "alt", "shift" },
        label = "Action-bar trace modifier",
        desc = "Hold this while hovering an action button (talent frame open) to light the talents that feed it. off disables it.",
    },
    uiMotion = {
        group = "Layout", type = "enum", default = "subtle",
        values = { "off", "subtle", "full" },
        label = "UI motion",
        desc = "Dynamic visuals on the panels: bars sweep, the ecosystem renders as a connected diagram, the radar draws its shape. off = the static text render; full adds traveling pulses.",
    },
    growthView = {
        group = "General", type = "toggle", default = false,
        label = "Show growth vs. floor",
        desc = "Show the caster/ranged/heal lenses as '+X% vs base' - how far your bonuses lift you above a no-gear floor. Off (default) shows the plain current index; the real decision numbers are always diffs from your current character.",
    },
    panelScale = {
        group = "Layout", type = "slider", default = 1.0, min = 0.7, max = 1.3,
        label = "Panel scale",
        desc = "Scale the Foresight panels up or down so they fit alongside your other UI addons.",
    },
    peerReadout = {
        group = "General", type = "toggle", default = true,
        label = "Show crowd comparison",
        desc = "On the Matrix: how your lenses and challenge numbers rank among players of your spec, plus today's featured challenge. Shows a prompt when your spec has no crowd data yet.",
    },
    autoVerify = {
        group = "General", type = "toggle", default = true,
        label = "Auto-verify on talent open",
        desc = "When you open your talents, Foresight scans the ones you've trained so their rank rules verify themselves - no hover, no command. Off = verify only on hover or /foresight verify.",
    },
    plannerOverlay = {
        group = "Synergy Matrix", type = "toggle", default = true,
        label = "Show planned-build overlay",
        desc = "When you have a planned build (from /foresight planner or an imported code), glow the planned path on your live talent tree - blue where points remain, gold once allocated. Off = plan in the planner only, no overlay.",
    },
    -- Opt-in SHOW-OFF tier (S34c). OFF by default; your numbers feed the anonymous crowd
    -- averages either way. On = when you Contribute, your chosen handle (+ optional armory)
    -- rides along and can appear on the public "champions" ladders. Revocable: turn it off.
    named = {
        group = "Character", type = "toggle", default = false,
        label = "Show me on public leaderboards",
        desc = "Opt in to appear by your chosen handle on the public champion ladders (Biggest Armor, etc.) when you Contribute. Off = you stay anonymous (your numbers still feed the crowd averages). Set your handle below.",
    },
    handle = {
        group = "Character", type = "text", default = "", max = 32,
        label = "Leaderboard handle",
        desc = "The display name shown on the public ladders when the opt-in above is on. A nickname you choose - not your real name. Up to 32 characters.",
    },
    armory = {
        group = "Character", type = "text", default = "", max = 200,
        pattern = "^https://[%w%._~:/%?#@!%$&%*%+,;=%%%(%)%-]+$",
        label = "Armory link (optional)",
        desc = "Optional https:// link to your armory/character page, shown beside your handle on the ladders. Leave blank for none.",
    },
}

-- The ordered group list for the GUI (a group renders only if it owns >= 1 key).
-- Character (identity/armory) leads; Layout (size/opacity/motion + reset actions) trails.
Settings.GROUPS = { "Character", "General", "Tooltips", "Synergy Matrix", "Layout" }

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
    elseif spec.type == "text" then
        -- Heal a stored value: strip control chars, trim, cap, pattern-or-default. Empty is
        -- always valid (unset). A non-matching stored value degrades to the default ("").
        local s = tostring(raw or ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if spec.max and #s > spec.max then s = s:sub(1, spec.max) end
        if s == "" then return "" end
        if spec.pattern and not s:match(spec.pattern) then return spec.default or "" end
        return s
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
    elseif spec.type == "text" then
        -- Slash input is strict: empty clears it; a non-empty value that fails the pattern
        -- is rejected (nil) so the user gets the usage line, not a silent wipe to default.
        local s = tostring(text or ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return "" end
        if spec.max and #s > spec.max then s = s:sub(1, spec.max) end
        if spec.pattern and not s:match(spec.pattern) then return nil end
        return s
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
    elseif spec.type == "slider" then return ("%s %.1f-%.1f"):format(key, spec.min, spec.max)
    elseif spec.type == "text" then return key .. " <text>" end
    return key
end

return Settings
