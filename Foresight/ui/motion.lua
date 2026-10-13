-- Foresight motion spine (S33): the ONE home for dynamic visuals - tweened value
-- transitions, accent pulses, connector lines with traveling light, radial gauges,
-- and the radar polygon fill. Both panels consume this; neither forks animation code.
--
-- LAWS BOUND HERE:
-- - uiMotion setting (S30 spine) gates everything: off = callers keep the static
--   render (helpers no-op to an instant set); subtle = transitions + gentle pulses;
--   full = subtle plus traveling pulses.
-- - Throttle law: ONE OnUpdate driver that unregisters itself the moment no tween is
--   active; continuous accents are AnimationGroups (GPU-side, no per-frame Lua);
--   panels cancel their tweens on hide/relayout (cancelOwner).
-- - Taint law: every region drawn here is parented to OUR frames (the compliance
--   taint-law lint enforces the class).
-- - Honesty laws: motion never edits content - fill bases, (p) marks, and grammar
--   lines are the caller's text and stay exactly as the model wrote them.
--
-- Split (the S32 lesson): pure geometry/state above the CreateFrame guard so the
-- headless harness tests it; widget work below.

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Motion = {}
HM.Motion = Motion

-- The validated motion level (off|subtle|full); unknown/missing degrades to subtle.
function Motion.level()
    local v = HM.Settings and HM.Settings.get and HM.Settings.get("uiMotion")
    if v == "off" or v == "full" then return v end
    return "subtle"
end

function Motion.ease(t) -- easeOutCubic
    local u = 1 - t
    return 1 - u * u * u
end

-- Previous-value store for change detection across pooled-widget relayouts: pooled
-- regions are re-acquired every refresh, so animation continuity keys on STABLE row
-- identity ("mx:bar:meleeDps"), never on widget identity.
local lastValues = {}
function Motion.trackValue(key, value)
    local prev = lastValues[key]
    lastValues[key] = value
    return prev
end

-- Radar geometry (pure): polar -> cartesian points for N axes, first axis straight
-- up, clockwise. fills are 0..1 per axis (the model's per-axis-independent law);
-- returns offsets from the chart center.
function Motion.radarPoints(fills, radius)
    local n = #fills
    local pts = {}
    if n == 0 then return pts end
    for i = 1, n do
        local f = fills[i]
        if type(f) ~= "number" or f ~= f then f = 0 end
        if f < 0 then f = 0 elseif f > 1 then f = 1 end
        local a = math.pi / 2 - (i - 1) * 2 * math.pi / n
        pts[i] = { x = radius * f * math.cos(a), y = radius * f * math.sin(a) }
    end
    return pts
end

-- Triangle fan (pure): decompose the radar polygon into center-anchored triangles.
-- Each entry is the two outer vertices; the implicit first vertex is the center
-- (0,0). The renderer collapses a quad's left edge onto the center and offsets the
-- right corners to these points (SetVertexOffset quad-skewing).
function Motion.triangleFan(points)
    local tris = {}
    local n = #points
    if n < 3 then return tris end
    for i = 1, n do
        local a, b = points[i], points[(i % n) + 1]
        tris[#tris + 1] = { x2 = a.x, y2 = a.y, x3 = b.x, y3 = b.y }
    end
    return tris
end

-- Diagram layout (pure): n boxes in a horizontal flow inside innerW, plus the
-- connector segments between adjacent boxes. Offsets are from the row's left edge.
function Motion.diagramLayout(n, innerW, gap)
    gap = gap or 14
    local boxes, links = {}, {}
    if n < 1 or innerW <= 0 then return boxes, links end
    local boxW = (innerW - gap * (n - 1)) / n
    for i = 1, n do
        local x = (i - 1) * (boxW + gap)
        boxes[i] = { x = x, w = boxW }
        if i < n then links[i] = { x1 = x + boxW, x2 = x + boxW + gap } end
    end
    return boxes, links
end

if not _G.CreateFrame then return Motion end -- headless: pure helpers only

-- ---- Tween driver (self-stopping OnUpdate) --------------------------------------

local driver = _G.CreateFrame("Frame")
local tweens = {}
local driving = false

local function onUpdate(_, dt)
    local i = 1
    while i <= #tweens do
        local tw = tweens[i]
        tw.t = tw.t + (dt or 0)
        local p = (tw.dur > 0) and math.min(1, tw.t / tw.dur) or 1
        local ok = pcall(tw.apply, Motion.ease(p), p)
        if ok and p >= 1 and tw.loop and tw.loop() then
            tw.t = 0
            i = i + 1
        elseif not ok or p >= 1 then
            table.remove(tweens, i)
        else
            i = i + 1
        end
    end
    if #tweens == 0 then
        driver:SetScript("OnUpdate", nil)
        driving = false
    end
end

-- Run apply(eased, linear) from 0 to 1 over dur seconds. At uiMotion=off the end
-- state applies instantly (the static render). opts.loop() -> true keeps it
-- repeating (the traveling pulse) - it must return false once its panel hides.
function Motion.tween(owner, dur, apply, opts)
    if Motion.level() == "off" or not dur or dur <= 0 then
        pcall(apply, 1, 1)
        return
    end
    tweens[#tweens + 1] = { owner = owner, dur = dur, t = 0, apply = apply,
                            loop = opts and opts.loop }
    pcall(apply, 0, 0)
    if not driving then
        driving = true
        driver:SetScript("OnUpdate", onUpdate)
    end
end

function Motion.cancelOwner(owner)
    for i = #tweens, 1, -1 do
        if tweens[i].owner == owner then table.remove(tweens, i) end
    end
    if #tweens == 0 and driving then
        driver:SetScript("OnUpdate", nil)
        driving = false
    end
end

-- ---- Common motions --------------------------------------------------------------

-- Sweep a fill texture's width from -> to (the bar transition). Instant at off.
function Motion.sweepWidth(owner, region, fromW, toW, dur)
    if math.abs((fromW or 0) - toW) < 0.5 then
        region:SetWidth(math.max(1, toW))
        return
    end
    local f0 = fromW or 1
    Motion.tween(owner, dur or 0.45, function(e)
        if region.SetWidth then
            region:SetWidth(math.max(1, f0 + (toW - f0) * e))
        end
    end)
end

-- One-shot flash: brighten a texture then fade it out (value-change accent).
function Motion.flash(owner, tex, r, g, b, maxA, dur)
    if Motion.level() == "off" then
        tex:Hide()
        return
    end
    tex:SetColorTexture(r, g, b, maxA or 0.35)
    tex:Show()
    Motion.tween(owner, dur or 0.6, function(e)
        if tex.SetAlpha then tex:SetAlpha((maxA or 0.35) * (1 - e)) end
        if e >= 1 then tex:Hide() end
    end)
end

-- Continuous accent pulse via AnimationGroup (no per-frame Lua). Cached on the
-- region (ours); stopPulse on pool release.
function Motion.pulse(region, fromA, toA, dur)
    if Motion.level() == "off" then return end
    local ag = region.foresightPulseAG
    if not ag then
        ag = region:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local a = ag:CreateAnimation("Alpha")
        ag.foresightAlpha = a
        region.foresightPulseAG = ag
    end
    ag.foresightAlpha:SetFromAlpha(fromA or 1)
    ag.foresightAlpha:SetToAlpha(toA or 0.55)
    ag.foresightAlpha:SetDuration(dur or 1.2)
    ag:Play()
end

function Motion.stopPulse(region)
    local ag = region and region.foresightPulseAG
    if ag then
        ag:Stop()
        if region.SetAlpha then region:SetAlpha(1) end
    end
end

-- ---- Lines (pooled per parent frame; frames are singletons) ----------------------

local linePools = {}

function Motion.acquireLine(frame)
    if not frame.CreateLine then return nil end -- old client: honest degrade
    local pool = linePools[frame]
    if not pool then pool = {}; linePools[frame] = pool end
    for _, l in ipairs(pool) do
        if not l.inUse then
            l.inUse = true
            l:Show()
            return l
        end
    end
    local l = frame:CreateLine(nil, "ARTWORK")
    l.inUse = true
    pool[#pool + 1] = l
    return l
end

function Motion.releaseLines(frame)
    for _, l in ipairs(linePools[frame] or {}) do
        l.inUse = false
        l:Hide()
    end
end

-- Draw a straight line on frame between two offsets from an anchor point.
function Motion.line(frame, anchor, x1, y1, x2, y2, color, thickness)
    local l = Motion.acquireLine(frame)
    if not l then return nil end
    l:SetThickness(thickness or 1)
    l:SetColorTexture(color.r, color.g, color.b, color.a or 0.8)
    l:SetStartPoint(anchor, frame, x1, y1)
    l:SetEndPoint(anchor, frame, x2, y2)
    return l
end

-- ---- Polygon fill (SetVertexOffset triangle fan; pooled per parent) --------------

local triPools = {}

local function acquireTri(frame)
    local pool = triPools[frame]
    if not pool then pool = {}; triPools[frame] = pool end
    for _, t in ipairs(pool) do
        if not t.inUse then
            t.inUse = true
            t:Show()
            return t
        end
    end
    local t = frame:CreateTexture(nil, "ARTWORK", nil, -1)
    t.inUse = true
    pool[#pool + 1] = t
    return t
end

function Motion.releaseTris(frame)
    for _, t in ipairs(triPools[frame] or {}) do
        t.inUse = false
        t:Hide()
    end
end

-- Fill the polygon whose outer vertices sit at `points` (offsets from the chart
-- center at anchor+cx,cy). Degrades to nothing where SetVertexOffset is missing -
-- the caller's outline still reads.
function Motion.drawFan(frame, anchor, cx, cy, points, color)
    local tris = Motion.triangleFan(points)
    for _, tri in ipairs(tris) do
        local tex = acquireTri(frame)
        if not tex.SetVertexOffset then
            tex.inUse = false
            tex:Hide()
            return false
        end
        tex:ClearAllPoints()
        tex:SetPoint("CENTER", frame, anchor, cx, cy)
        tex:SetSize(1, 1)
        tex:SetColorTexture(color.r, color.g, color.b, color.a or 0.22)
        tex:SetVertexOffset(1, 0, 0) -- UL -> center
        tex:SetVertexOffset(2, 0, 0) -- LL -> center
        tex:SetVertexOffset(3, tri.x2, tri.y2) -- UR -> vertex i
        tex:SetVertexOffset(4, tri.x3, tri.y3) -- LR -> vertex i+1
    end
    return true
end

-- ---- Radial gauges (Cooldown swipe over a masked disc; pooled per parent) --------

local gaugePools = {}

local function acquireGauge(frame, size)
    local pool = gaugePools[frame]
    if not pool then pool = {}; gaugePools[frame] = pool end
    local g
    for _, cand in ipairs(pool) do
        if not cand.inUse then g = cand break end
    end
    if not g then
        g = _G.CreateFrame("Frame", nil, frame)
        local disc = g:CreateTexture(nil, "ARTWORK")
        disc:SetAllPoints()
        if g.CreateMaskTexture and disc.AddMaskTexture then
            local mask = g:CreateMaskTexture()
            mask:SetAllPoints(disc)
            mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            disc:AddMaskTexture(mask)
        end
        g.disc = disc
        local cd = _G.CreateFrame("Cooldown", nil, g, "CooldownFrameTemplate")
        cd:SetAllPoints()
        cd:SetDrawEdge(false)
        if cd.SetDrawBling then cd:SetDrawBling(false) end
        if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(true) end
        if cd.SetSwipeTexture then
            cd:SetSwipeTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
        end
        g.cd = cd
        -- Text rides a higher sub-frame so the swipe never covers the number.
        local textFrame = _G.CreateFrame("Frame", nil, g)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(g:GetFrameLevel() + 2)
        g.value = textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        g.value:SetPoint("CENTER", 0, 0)
        pool[#pool + 1] = g
    end
    g.inUse = true
    g:SetSize(size, size)
    g:Show()
    return g
end

function Motion.releaseGauges(frame)
    for _, g in ipairs(gaugePools[frame] or {}) do
        g.inUse = false
        g:Hide()
    end
end

-- A static radial gauge: disc colored, dark swipe covering the UNFILLED remainder,
-- value text centered. frac is a true 0..1 fraction (the model's law). The swipe
-- pins via Pause when the client has it; refreshes re-pin it regardless.
function Motion.gauge(frame, anchor, x, y, size, frac, color, valueText)
    local g = acquireGauge(frame, size)
    g:ClearAllPoints()
    g:SetPoint(anchor, frame, anchor, x, y)
    g.disc:SetColorTexture(color.r, color.g, color.b, 0.85)
    local cd = g.cd
    cd:SetReverse(true)
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.82) end
    local DUR = 100
    local f = frac
    if type(f) ~= "number" or f ~= f then f = 0 end
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
    if _G.GetTime and cd.SetCooldown then
        cd:SetCooldown(_G.GetTime() - f * DUR, DUR)
        if cd.Pause then cd:Pause() end
    end
    g.value:SetText(valueText or "")
    return g
end

return Motion
