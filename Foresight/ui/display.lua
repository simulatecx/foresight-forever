-- Foresight display grammar (UI-display-grammar, S27): ONE voice for every number.
-- Six claim shapes + the honesty ladder + THE color table. Pure and headless-tested;
-- dimension VALUES delegate to dimensions.D.display (the v0.36.0 law) - this module
-- never re-renders a lens value. Block order law everywhere a block is composed:
-- Verdict -> Magnitudes -> Translation -> Comparison -> Honesty footer.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Display = {}
HM.Display = Display

-- THE color table: one semantic = one color, everywhere (migrating drift cases).
Display.COLORS = {
    brand = "33ff99",    -- Foresight identity
    gain = "4ade80",     -- gains / verified
    loss = "f87171",     -- losses
    neutral = "9d9d9d",  -- meta / presumed / basis text
    identity = "ffd24d", -- the focused/named thing (gold)
    indirect = "59a6ff", -- indirect / feeder (blue)
}

function Display.color(sem, text)
    return ("|cff%s%s|r"):format(Display.COLORS[sem] or Display.COLORS.neutral,
        tostring(text))
end

-- FORGED FRAME chrome (0.53.0, the WoW-esque skin pass): the planner's corner treatment -
-- a diamond stud + an L of gold bars at each corner - as ONE shared drawer so every panel
-- carries the same forged identity (starts the UI-display-consolidation). Draws on the
-- frame's BORDER layer with code-drawn textures only (no art files - skin/flavor proof).
-- In-game only; headless harness never calls it (frames don't exist there).
function Display.forge(frame, r, g, b, alpha)
    r, g, b, alpha = r or 0.78, g or 0.64, b or 0.30, alpha or 0.6
    local function tex(w, h, point, x, y)
        local t = frame:CreateTexture(nil, "BORDER", nil, 2)
        t:SetSize(w, h)
        t:SetPoint(point, frame, point, x, y)
        t:SetColorTexture(r, g, b, alpha)
        return t
    end
    for _, c in ipairs({ { "TOPLEFT", 1, -1, 1, 1 }, { "TOPRIGHT", -1, -1, -1, 1 },
                         { "BOTTOMLEFT", 1, 1, 1, -1 }, { "BOTTOMRIGHT", -1, 1, -1, -1 } }) do
        local point, x, y = c[1], c[2], c[3]
        tex(14, 2, point, x, y)            -- horizontal bar of the L
        tex(2, 14, point, x, y)            -- vertical bar of the L
        local stud = frame:CreateTexture(nil, "BORDER", nil, 3)
        stud:SetSize(5, 5)
        stud:SetPoint(point, frame, point, x + 2 * c[4], y + 2 * c[5])
        stud:SetColorTexture(r * 1.2 > 1 and 1 or r * 1.2, g * 1.2 > 1 and 1 or g * 1.2,
            b * 1.2 > 1 and 1 or b * 1.2, 0.9)
    end
end

local function num(v)
    v = v or 0
    if v % 1 == 0 then return ("%d"):format(v) end
    return ("%.1f"):format(v)
end

-- 1. MAGNITUDE: "+24 Attack Power" (integers stay integers, else one decimal).
function Display.magnitude(value, unit)
    local v = value or 0
    local body = (v % 1 == 0) and ("%+d"):format(v) or ("%+.1f"):format(v)
    return unit and (body .. " " .. unit) or body
end

-- 2. TRANSLATION: the derived consequence, indented; "~" ONLY when model-derived.
function Display.translation(text, basis, derived)
    return "-> " .. (derived and "~" or "") .. text
        .. (basis and (" (" .. basis .. ")") or "")
end

-- 3. COMPARISON: "17.7 -> 20.7 DPS (+3.0, +17.0%)".
function Display.comparison(before, after, unit)
    local d = (after or 0) - (before or 0)
    local pct = (before and before ~= 0) and (d / math.abs(before) * 100) or 0
    return ("%s -> %s%s (%+.1f, %+.1f%%)"):format(num(before), num(after),
        unit and (" " .. unit) or "", d, pct)
end

-- 4. VERDICT: fixed vocabulary only - anything else degrades to Sidegrade.
local VERDICT_WORDS = { Upgrade = "gain", Downgrade = "loss", Sidegrade = "neutral" }
function Display.verdict(word, goalLabel, pct)
    local sem = VERDICT_WORDS[word]
    if not sem then word, sem = "Sidegrade", "neutral" end
    local pctText = (word == "Sidegrade" or pct == nil)
        and "" or (" (%+.1f%%)"):format(pct)
    return ("%s for %s%s"):format(Display.color(sem, word), goalLabel or "?", pctText)
end

-- 5. CASCADE: "[+12 Strength] -> [+24 AP] -> [+21 per hit]". Brackets appear in NO
-- other shape (exclusivity law).
function Display.cascade(segments)
    local chips = {}
    for _, seg in ipairs(segments or {}) do
        chips[#chips + 1] = Display.color("brand", "[") .. seg
            .. Display.color("brand", "]")
    end
    return table.concat(chips, " -> ")
end

-- 6. ATTRIBUTION (the Gemini-ratified addition): "(via 1 Str = 2 AP)" - neutral meta.
function Display.attribution(text)
    return Display.color("neutral", "(via " .. tostring(text) .. ")")
end

-- HONESTY LADDER (cross-cutting): five steps, rendered at line end; composed values
-- inherit the WEAKEST input (the abilityHit presumed-flag pattern generalized).
local LADDER = { ["play-verified"] = 5, datamined = 4, ["crowd-verified"] = 3,
                 presumed = 2, none = 1 }
Display.LADDER = LADDER

function Display.weakest(a, b)
    local ra, rb = LADDER[a or "none"] or 1, LADDER[b or "none"] or 1
    return ra <= rb and (a or "none") or (b or "none")
end

function Display.mark(level, detail)
    if level == "play-verified" then
        return " " .. Display.color("gain", "play-verified" .. (detail and (" " .. detail) or ""))
    elseif level == "datamined" then
        return " " .. Display.color("gain", "datamined" .. (detail and (" " .. detail) or ""))
    elseif level == "crowd-verified" then
        return " " .. Display.color("gain", "crowd-verified")
    elseif level == "presumed" then
        return " " .. Display.color("neutral", "(p)")
    end
    return "" -- none: silence
end

return Display
