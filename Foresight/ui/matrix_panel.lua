-- Foresight Matrix panel renderer (S7b): the "class ecology" dashboard from
-- mockups/foresight-matrix-2026-10-12.html - standing badge, honest dimension bars,
-- and the Enabler -> Engine -> Payoff ecosystem for the class's loops.
-- Skin: dark translucent card in the house style (code-drawn textures, no art
-- assets, blends with default + reskin UIs). All numbers come from
-- PanelModel.matrixModel - zero computation here, layout only. In-game only.
-- USER-MODIFIABLE (baseline): background opacity via /foresight matrix opacity <v>
-- (validated by PanelModel.normalizeOpacity), position via drag (validated save).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

if not _G.CreateFrame then return end

local WIDTH = 320
local PAD = 12

-- Mockup palette (the brand emerald is the addon's chat color).
local BRAND = { r = 0.20, g = 1.00, b = 0.60 }  -- #33FF99
local BLUE  = { r = 0.30, g = 0.65, b = 1.00 }  -- enablers
local YELLOW = { r = 1.00, g = 0.82, b = 0.40 } -- engines
local MUTED = { r = 0.55, g = 0.55, b = 0.60 }

local panel
local fsPool, texPool = {}, {}

local function classColor()
    local _, token = _G.UnitClass("player")
    local c = token and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[token]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function uiState()
    local db = HM.charDb()
    db.settings.matrix = db.settings.matrix or {}
    return db.settings.matrix
end

local function opacity()
    -- S30: panelAlpha is the unified key both panels read; the per-panel matrix.opacity
    -- is a migration fallback (older saves) honored only if panelAlpha is unset.
    if HM.Settings then
        local a = uiState().opacity
        if a == nil then return HM.Settings.get([[panelAlpha]]) end
        return HM.PanelModel.normalizeOpacity(a)
    end
    return HM.PanelModel.normalizeOpacity(uiState().opacity)
end

local function restorePosition()
    if not panel then return end
    panel:ClearAllPoints()
    local pos = HM.PanelModel.normalizePanelPos(uiState().pos)
    if pos then
        panel:SetPoint(pos.point, _G.UIParent, pos.relPoint, pos.x, pos.y)
    else
        panel:SetPoint("CENTER", _G.UIParent, "CENTER", 220, 40)
    end
end

-- S33: the saved, validated panel width (horizontal-stretch state).
local function restoreWidth()
    if not panel then return end
    panel:SetWidth(HM.PanelModel.normalizeWidth(uiState().width))
end

-- Font-string + texture pools: the panel rebuilds on every refresh/cycle.
local function acquireFS(layer, template)
    for _, f in ipairs(fsPool) do
        if not f.inUse then
            f.inUse = true
            f:SetFontObject(template or "GameFontHighlightSmall")
            f:SetJustifyH("LEFT")
            f:SetJustifyV("TOP")
            f:ClearAllPoints()
            f:SetText("")
            f:Show()
            return f
        end
    end
    local f = panel:CreateFontString(nil, layer or "ARTWORK",
        template or "GameFontHighlightSmall")
    f.inUse = true
    fsPool[#fsPool + 1] = f
    return f
end

local function acquireTex(layer, sublayer)
    for _, t in ipairs(texPool) do
        if not t.inUse then
            t.inUse = true
            t:ClearAllPoints()
            t:Show()
            return t
        end
    end
    local t = panel:CreateTexture(nil, layer or "ARTWORK", nil, sublayer or 0)
    t.inUse = true
    texPool[#texPool + 1] = t
    return t
end

local function releasePools()
    for _, f in ipairs(fsPool) do f.inUse = false; f:Hide() end
    for _, t in ipairs(texPool) do
        t.inUse = false
        t:Hide()
        if HM.Motion then HM.Motion.stopPulse(t) end -- pooled tex may carry an accent
    end
end

local TAG_COLOR = { Enabler = BLUE, Engine = YELLOW, Payoff = BRAND }

local function layout(model)
    releasePools()
    -- S33: in-flight tweens target pooled regions about to be re-acquired - kill them
    -- before relayout, and release the motion-owned pools (lines, gauges).
    if HM.Motion then
        HM.Motion.cancelOwner("matrix")
        HM.Motion.releaseLines(panel)
        HM.Motion.releaseGauges(panel)
    end
    local motion = HM.Motion and HM.Motion.level() or "off"
    local r, g, b = classColor()
    -- S33: the panel is user-resizable (horizontal stretch) - all layout works off the
    -- LIVE width, so widening re-flows the bars, the eco diagram, and the gauges.
    local W = math.floor((panel:GetWidth() or WIDTH) + 0.5)
    local innerW = W - PAD * 2
    local y = -30 -- below the title bar

    -- Character header: name, descriptor, standing badge (mockup component 1).
    local name = acquireFS("ARTWORK", "GameFontNormalLarge")
    name:SetPoint("TOP", panel, "TOP", 0, y)
    name:SetJustifyH("CENTER")
    name:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255,
        (_G.UnitName and _G.UnitName("player")) or model.header.name or "?"))
    y = y - 20
    local desc = acquireFS("ARTWORK", "GameFontDisableSmall")
    desc:SetPoint("TOP", panel, "TOP", 0, y)
    desc:SetJustifyH("CENTER")
    desc:SetText(("Level %s %s %s"):format(model.header.level or "?",
        model.header.raceToken or "", model.header.classToken or ""))
    y = y - 18

    local standing = model.header.standing or {}
    if standing.name then
    local badge = acquireFS("ARTWORK", "GameFontNormalSmall")
    badge:SetPoint("TOP", panel, "TOP", 0, y - 3)
    badge:SetJustifyH("CENTER")
    badge:SetText(("|cff%02x%02x%02x%s|r"):format(r * 255, g * 255, b * 255,
        (standing.name or "?"):upper()))
    local bw = badge:GetStringWidth() + 24
    local badgeBg = acquireTex("BACKGROUND", 2)
    badgeBg:SetPoint("TOP", panel, "TOP", 0, y)
    badgeBg:SetSize(bw, 18)
    badgeBg:SetColorTexture(r, g, b, 0.12)
    for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local line = acquireTex("BORDER")
        line:SetPoint(edge, badgeBg, edge)
        line:SetSize(bw, 1)
        line:SetColorTexture(r, g, b, 0.7)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = acquireTex("BORDER")
        line:SetPoint(side, badgeBg, side)
        line:SetSize(1, 18)
        line:SetColorTexture(r, g, b, 0.7)
    end
    panel.badgeTip = standing.detail
    end
    y = y - 28

    -- SECTION RENDERERS (S33 horizontal layout): each draws into a column rect
    -- {sx, sw} from sy and returns the ending y. Narrow runs them down one cursor
    -- (the mobile binding stays single-column); wide runs bars/pathways/focus in a
    -- left column and eco/gauges in a right one, so stretching the panel turns the
    -- tall strip into a landscape dashboard. Honesty/motion laws are unchanged - only
    -- the x-origin and width vary.
    local function drawBars(sx, sw, sy)
        local y = sy
        for _, bar in ipairs(model.bars.rows) do
            local label = acquireFS("ARTWORK", "GameFontHighlightSmall")
            label:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
            label:SetText(bar.label)
            local value = acquireFS("ARTWORK", "GameFontHighlightSmall")
            value:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
            value:SetWidth(sw)
            value:SetJustifyH("RIGHT")
            local vc = bar.top and BRAND or MUTED
            value:SetText(("|cff%02x%02x%02x%s|r"):format(vc.r * 255, vc.g * 255,
                vc.b * 255, bar.value))
            local prevFill = HM.Motion
                and HM.Motion.trackValue("mx:bar:" .. (bar.id or bar.label), bar.fill)
            if HM.Motion and motion ~= "off" and prevFill
                    and math.abs(prevFill - bar.fill) > 0.002 then
                local fl = acquireTex("ARTWORK", 2)
                fl:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + sw - 64, y + 1)
                fl:SetSize(64, 13)
                HM.Motion.flash("matrix", fl, BRAND.r, BRAND.g, BRAND.b, 0.22)
            end
            y = y - 14
            local track = acquireTex("BACKGROUND", 1)
            track:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
            track:SetSize(sw, 5)
            track:SetColorTexture(0, 0, 0, 0.55)
            local fillW = math.max(1, math.floor(sw * math.min(bar.fill, 1)))
            local fill = acquireTex("BACKGROUND", 2)
            fill:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
            fill:SetSize(fillW, 5)
            local fc = bar.top and BRAND or MUTED
            fill:SetColorTexture(fc.r, fc.g, fc.b, bar.top and 0.95 or 0.55)
            if HM.Motion and motion ~= "off" then
                local prevW = prevFill
                    and math.max(1, math.floor(sw * math.min(prevFill, 1)))
                if prevW and prevW ~= fillW then
                    HM.Motion.sweepWidth("matrix", fill, prevW, fillW)
                end
                if bar.top then HM.Motion.pulse(fill, 1, 0.62, 1.4) end
            end
            y = y - 12
        end
        local basis = acquireFS("ARTWORK", "GameFontDisableSmall")
        basis:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
        basis:SetWidth(sw)
        basis:SetText(model.bars.basis)
        return y - math.max(12, basis:GetStringHeight() + 2) - 8
    end

    -- Goal pathways: your best unspent talent points for the dimension you're
    -- building toward (computed on talent changes, not every refresh).
    local function drawPathways(sx, sw, sy)
        if not model.path then return sy end
        local y = sy
        local ph = acquireFS("ARTWORK", "GameFontNormalSmall")
        ph:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
        ph:SetWidth(sw)
        ph:SetText(("|cff9d9d9dBest next points -|r %s"):format(model.path.label or ""))
        y = y - math.max(14, ph:GetStringHeight() + 2)
        for i, row in ipairs(model.path.rows) do
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 6, y)
            f:SetWidth(sw - 12)
            f:SetText(("%d. %s  |cff4ade80%+.1f%s|r"):format(i, row.label,
                row.pct, row.unit or "%"))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        return y - 8
    end

    -- Skill focus (S22a/S22b): the three modifier classes for the focused ability +
    -- the cascade chip row. Wrapped FontStrings WRAP to extra rows at low
    -- resolution/scale (the mobile binding) - never truncate.
    local function drawFocus(sx, sw, sy)
        if not model.focus then return sy end
        local y = sy
        local CLASS_HEX = { gold = "ffd24d", blue = "59a6ff" }
        local fh = acquireFS("ARTWORK", "GameFontNormalSmall")
        fh:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
        fh:SetWidth(sw)
        fh:SetText(("|cff9d9d9dFocused skill -|r |cffffd24d%s|r  |cff9d9d9d(/foresight focus clear)|r")
            :format(model.focus.spell or ""))
        y = y - math.max(14, fh:GetStringHeight() + 2)
        for _, cl in ipairs(model.focus.classes or {}) do
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 6, y)
            f:SetWidth(sw - 12)
            f:SetText(("|cff%s%s:|r %s"):format(CLASS_HEX[cl.color] or "9d9d9d",
                cl.tag, cl.text))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        if model.focus.pathway then
            local chips = {}
            for _, seg in ipairs(model.focus.pathway.segments or {}) do
                chips[#chips + 1] = ("|cff33ff99[|r%s|cff33ff99]|r"):format(seg)
            end
            local f = acquireFS("ARTWORK", "GameFontHighlightSmall")
            f:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 6, y)
            f:SetWidth(sw - 12)
            f:SetText(table.concat(chips, " -> ")
                .. (model.focus.pathway.presumed and " (p)" or ""))
            y = y - math.max(13, f:GetStringHeight() + 1)
        end
        return y - 8
    end

    -- Ecosystem map (mockup component 2): goal row + the three tagged nodes + insight.
    local function drawEco(sx, sw, sy)
        if not model.eco then return sy end
        local y = sy
        local goal = acquireFS("ARTWORK", "GameFontNormalSmall")
        goal:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
        goal:SetWidth(sw)
        goal:SetText(("|cff9d9d9dGoal:|r %s%s"):format(model.eco.name,
            (model.loopCount or 0) > 1 and "  |cff9d9d9d(click title to cycle)|r" or ""))
        y = y - math.max(14, goal:GetStringHeight() + 2) - 6

        if HM.Motion and motion ~= "off" and panel.CreateLine then
            -- S33 CONNECTED DIAGRAM: the loop as three linked node boxes with real
            -- connector lines (a pulse travels them in full) instead of stacked text
            -- cards. Text REDUCED, not removed: tag + members stay in the box, the
            -- card's explainer sentence moves to the box's hover tooltip, and the
            -- insight box below keeps every computed number and (p) mark.
            local boxes, links = HM.Motion.diagramLayout(#model.eco.nodes, sw, 16)
            local topY = y
            local boxH = 40
            local titleFS = {}
            for i, node in ipairs(model.eco.nodes) do
                local t = acquireFS("ARTWORK", "GameFontHighlightSmall")
                t:SetWidth(boxes[i].w - 10)
                t:SetJustifyH("CENTER")
                t:SetWordWrap(true)
                if t.SetMaxLines then t:SetMaxLines(0) end
                t:SetText("|cffffffff" .. (node.title or "") .. "|r")
                titleFS[i] = t
                local h = 20 + (t:GetStringHeight() or 12) + 8
                if h > boxH then boxH = h end
            end
            panel.ecoHit = panel.ecoHit or {}
            for i, node in ipairs(model.eco.nodes) do
                local c = TAG_COLOR[node.tag] or MUTED
                local bx = sx + boxes[i].x
                local bg = acquireTex("BACKGROUND", 1)
                bg:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, topY)
                bg:SetSize(boxes[i].w, boxH)
                bg:SetColorTexture(c.r, c.g, c.b, 0.07)
                local strip = acquireTex("BACKGROUND", 2)
                strip:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, topY)
                strip:SetSize(boxes[i].w, 2)
                strip:SetColorTexture(c.r, c.g, c.b, 0.9)
                local tag = acquireFS("ARTWORK", "GameFontDisableSmall")
                tag:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, topY - 5)
                tag:SetWidth(boxes[i].w)
                tag:SetJustifyH("CENTER")
                tag:SetText(("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255,
                    c.b * 255, node.tag:upper()))
                titleFS[i]:SetPoint("TOPLEFT", panel, "TOPLEFT", bx + 5, topY - 20)
                local hit = panel.ecoHit[i]
                if not hit then
                    hit = _G.CreateFrame("Frame", nil, panel)
                    hit:EnableMouse(true)
                    hit:SetScript("OnEnter", function(self)
                        if self.tipTitle then
                            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            _G.GameTooltip:SetText(self.tipTitle, 1, 1, 1)
                            if self.tipBody then
                                _G.GameTooltip:AddLine(self.tipBody, 0.8, 0.8, 0.8, true)
                            end
                            _G.GameTooltip:Show()
                        end
                    end)
                    hit:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
                    panel.ecoHit[i] = hit
                end
                hit:ClearAllPoints()
                hit:SetPoint("TOPLEFT", panel, "TOPLEFT", bx, topY)
                hit:SetSize(boxes[i].w, boxH)
                hit.tipTitle = node.tag .. " - " .. (node.title or "")
                hit.tipBody = node.desc
                hit:Show()
            end
            for i = #model.eco.nodes + 1, #panel.ecoHit do panel.ecoHit[i]:Hide() end
            local cyLine = topY - boxH / 2
            for j, lk in ipairs(links) do
                local x1, x2 = sx + lk.x1 + 2, sx + lk.x2 - 2
                HM.Motion.line(panel, "TOPLEFT", x1, cyLine, x2, cyLine,
                    { r = BRAND.r, g = BRAND.g, b = BRAND.b, a = 0.55 }, 2)
                if motion == "full" then
                    local dot = acquireTex("ARTWORK", 1)
                    dot:SetSize(5, 5)
                    dot:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.95)
                    dot:SetPoint("TOPLEFT", panel, "TOPLEFT", x1, cyLine + 2.5)
                    HM.Motion.tween("matrix", 0.9 + j * 0.2, function(e)
                        dot:ClearAllPoints()
                        dot:SetPoint("TOPLEFT", panel, "TOPLEFT",
                            x1 + (x2 - x1 - 5) * e, cyLine + 2.5)
                    end, { loop = function()
                        return dot.inUse and panel:IsShown()
                            and HM.Motion.level() == "full"
                    end })
                end
            end
            y = topY - boxH - 10
        else
            if panel.ecoHit then
                for _, hit in ipairs(panel.ecoHit) do hit:Hide() end
            end
            for _, node in ipairs(model.eco.nodes) do
                local c = TAG_COLOR[node.tag] or MUTED
                local cardTop = y
                local tag = acquireFS("ARTWORK", "GameFontDisableSmall")
                tag:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 8, y - 4)
                tag:SetText(("|cff%02x%02x%02x%s|r"):format(c.r * 255, c.g * 255,
                    c.b * 255, node.tag:upper()))
                y = y - 16
                local title = acquireFS("ARTWORK", "GameFontNormalSmall")
                title:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 8, y - 4)
                title:SetWidth(sw - 16)
                title:SetText("|cffffffff" .. (node.title or "") .. "|r")
                y = y - math.max(13, title:GetStringHeight() + 1)
                local d = acquireFS("ARTWORK", "GameFontDisableSmall")
                d:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 8, y - 4)
                d:SetWidth(sw - 16)
                d:SetText(node.desc or "")
                y = y - math.max(12, d:GetStringHeight() + 1) - 8
                local cardH = cardTop - y - 2
                local cardBg = acquireTex("BACKGROUND", 1)
                cardBg:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, cardTop)
                cardBg:SetSize(sw, cardH)
                cardBg:SetColorTexture(1, 1, 1, 0.04)
                local strip = acquireTex("BACKGROUND", 2)
                strip:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, cardTop)
                strip:SetSize(3, cardH)
                strip:SetColorTexture(c.r, c.g, c.b, 0.9)
                y = y - 6
            end
        end

        -- Actionable insight box: the loop's why + its live computed numbers.
        local boxTop = y
        local insight = acquireFS("ARTWORK", "GameFontHighlightSmall")
        insight:SetPoint("TOPLEFT", panel, "TOPLEFT", sx + 6, y - 6)
        insight:SetWidth(sw - 12)
        local lines = { "|cff33ff99Actionable insight:|r " .. (model.eco.insight or "") }
        for _, line in ipairs(model.eco.computed or {}) do
            lines[#lines + 1] = "|cffbfbfbf" .. line .. "|r"
        end
        insight:SetText(table.concat(lines, "\n"))
        y = y - math.max(16, insight:GetStringHeight() + 12)
        local ibH = boxTop - y
        local box = acquireTex("BACKGROUND", 1)
        box:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, boxTop)
        box:SetSize(sw, ibH)
        box:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.05)
        for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
            local line = acquireTex("BORDER")
            line:SetPoint(edge[1], box, edge[1])
            line:SetPoint(edge[2], box, edge[2])
            line:SetHeight(1)
            line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.25)
        end
        return y - 4
    end

    -- S33 RADIAL GAUGES: rings only where the model found a TRUE fraction (Flurry
    -- uptime / focused-spell OOM) - honest absence otherwise; the printed basis note
    -- and the (p) in each label never animate away. Off = no rings (static render).
    local function drawGauges(sx, sw, sy)
        if not (model.gauges and #model.gauges > 0 and HM.Motion and motion ~= "off") then
            return sy
        end
        local y = sy
        local size = 44
        local n = #model.gauges
        local totalW = n * size + (n - 1) * 36
        local left = sx + math.max(0, (sw - totalW) / 2)
        local gy = y - 8
        for i, gm in ipairs(model.gauges) do
            local gx = left + (i - 1) * (size + 36)
            local gframe = HM.Motion.gauge(panel, "TOPLEFT", gx, gy, size,
                gm.frac, BRAND, gm.text)
            if gframe then
                gframe:EnableMouse(true)
                gframe.tipText = gm.tooltip
                gframe:SetScript("OnEnter", function(self)
                    if self.tipText then
                        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        _G.GameTooltip:SetText(self.tipText, nil, nil, nil, nil, true)
                        _G.GameTooltip:Show()
                    end
                end)
                gframe:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
                local lf = acquireFS("ARTWORK", "GameFontDisableSmall")
                lf:SetPoint("TOP", gframe, "BOTTOM", 0, -2)
                lf:SetJustifyH("CENTER")
                lf:SetText(gm.label)
            end
        end
        y = gy - size - 18
        for _, gm in ipairs(model.gauges) do
            if gm.note then
                local nf = acquireFS("ARTWORK", "GameFontDisableSmall")
                nf:SetPoint("TOPLEFT", panel, "TOPLEFT", sx, y)
                nf:SetWidth(sw)
                nf:SetText("|cff9d9d9d" .. gm.note .. "|r")
                y = y - math.max(12, nf:GetStringHeight() + 2)
            end
        end
        return y - 4
    end

    -- Compose. Wide (stretched past the threshold) = two columns so the context runs
    -- horizontal; narrow = one column (the mobile binding at 1280x720 @ 0.65 holds).
    local TWO_COL_MIN = 500
    if W >= TWO_COL_MIN then
        local gutter = 16
        local leftW = math.floor((innerW - gutter) / 2)
        local rightW = innerW - gutter - leftW
        local leftX, rightX = PAD, PAD + leftW + gutter
        local ly = drawFocus(leftX, leftW, drawPathways(leftX, leftW, drawBars(leftX, leftW, y)))
        local ry = drawGauges(rightX, rightW, drawEco(rightX, rightW, y))
        y = math.min(ly, ry)
    else
        y = drawBars(PAD, innerW, y)
        y = drawPathways(PAD, innerW, y)
        y = drawFocus(PAD, innerW, y)
        y = drawEco(PAD, innerW, y)
        y = drawGauges(PAD, innerW, y)
    end

    panel:SetHeight(math.max(160, -y + PAD))
end

local MatrixPanel = {}
HM.MatrixPanel = MatrixPanel

-- Goal pathways are one graph evaluate PER open talent node - too heavy for every
-- aura tick, so the result is cached and recomputed only when talents change
-- (invalidated by the talent events below) or the panel first shows.
local cachedPath
local function computePathways(loadout)
    if not (HM.TalentAPI and HM.TalentAPI.walkTraits and HM.Sim) then return nil end
    local walk = HM.TalentAPI.walkTraits(false)
    if not walk or #walk == 0 then return nil end
    local candidates = {}
    for _, n in ipairs(walk) do
        if (n.rank or 0) < (n.maxRank or 1) and n.nodeID then
            candidates[#candidates + 1] = {
                label = ("%s %d/%d"):format(n.name or ("node " .. n.nodeID),
                    (n.rank or 0) + 1, n.maxRank or 1),
                what = loadout:withTraitNode(n.nodeID, (n.rank or 0) + 1),
                nodeId = n.nodeID, rank = (n.rank or 0) + 1, -- S28 ability-goal mode
            }
        end
    end
    if #candidates == 0 then return nil end
    local dim = HM.gearGoal and HM.gearGoal() or "auto"
    if dim == "auto" then dim = HM.Impact.primaryDimension(loadout) end
    local ok, path = pcall(HM.Sim.goalPathways, loadout, dim, candidates, 4)
    return (ok and path) or nil
end

function MatrixPanel.invalidatePathways()
    cachedPath = nil
end

function MatrixPanel.refresh()
    if not panel or not panel:IsShown() then return end
    local snapshot = HM.Snapshot.capture()
    if not snapshot then return end
    local loadout = HM.Loadout.fromSnapshot(snapshot)
    if cachedPath == nil then
        cachedPath = computePathways(loadout) or false -- false = computed, none found
    end
    -- Skill focus (S22a): the saved focus feeds the insight block + pathway chips.
    local focusModel
    local focusName = HM.SynergyHighlight and HM.SynergyHighlight.savedFocus
        and HM.SynergyHighlight.savedFocus() or nil
    if focusName then
        local okf, fm = pcall(HM.PanelModel.focusModel, loadout, focusName)
        focusModel = (okf and fm) or nil
    end
    local ok, model = pcall(HM.PanelModel.matrixModel, loadout, uiState().loop,
        cachedPath or nil, focusModel)
    if ok and model then
        -- S33: the gauge model rides along (pure; empty where no true fraction).
        if HM.PanelModel.gaugeModel then
            local okg, gauges = pcall(HM.PanelModel.gaugeModel, loadout, focusName)
            model.gauges = (okg and gauges) or nil
        end
        -- v0.45.8: user-set panel scale (addon coexistence).
        if HM.Settings and HM.Settings.get then
            panel:SetScale(HM.Settings.get("panelScale") or 1)
        end
        panel.model = model
        layout(model)
        panel.bg:SetColorTexture(0.055, 0.055, 0.07, opacity())
    else
        HM.print("matrix refresh failed: " .. tostring(model))
    end
end

function MatrixPanel.toggle()
    if not panel then
        HM.print("matrix panel is in-game only")
        return
    end
    panel:SetShown(not panel:IsShown())
    MatrixPanel.refresh()
end

function MatrixPanel.setOpacity(v)
    -- S30: writes the UNIFIED panelAlpha key (the /foresight matrix opacity alias) and
    -- clears the legacy per-panel value so the one key wins going forward.
    local a = HM.Settings and HM.Settings.setValue([[panelAlpha]], v)
        or HM.PanelModel.normalizeOpacity(v)
    uiState().opacity = nil
    if panel and panel.bg then
        panel.bg:SetColorTexture(0.055, 0.055, 0.07, a)
    end
    return a
end

function MatrixPanel.resetPosition()
    if not panel then return end
    uiState().pos = nil
    restorePosition()
end

-- Cycle the active loop (the mockup's goal dropdown, taint-free).
function MatrixPanel.cycleLoop()
    if not panel or not panel.model then return end
    local snapshot = HM.Snapshot.capture()
    local loops = HM.loopsForClass(snapshot and snapshot.classToken) or {}
    if #loops < 2 then return end
    local cur = uiState().loop
    local idx = 1
    for i, l in ipairs(loops) do
        if l.id == cur then idx = i end
    end
    uiState().loop = loops[(idx % #loops) + 1].id
    MatrixPanel.refresh()
end

local function createPanel()
    panel = _G.CreateFrame("Frame", "ForesightMatrixPanel", _G.UIParent)
    panel:SetWidth(WIDTH)
    panel:SetMovable(true)
    panel:SetResizable(true)
    -- Width-only resize bounds (height is content-driven). SetResizeBounds is the
    -- 11.x API; pcall the older min/max setters as a fallback (degrade law).
    local wmin, wmax = HM.PanelModel.WIDTH_MIN, HM.PanelModel.WIDTH_MAX
    if panel.SetResizeBounds then
        pcall(panel.SetResizeBounds, panel, wmin, 160, wmax, 2000)
    else
        pcall(panel.SetMinResize, panel, wmin, 160)
        pcall(panel.SetMaxResize, panel, wmax, 2000)
    end
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        uiState().pos = { point = point, relPoint = relPoint,
                          x = math.floor(x + 0.5), y = math.floor(y + 0.5) }
    end)
    restorePosition()
    restoreWidth()

    -- Dark card + hairline border; the bg alpha is the user's opacity baseline.
    panel.bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)
    panel.bg:SetAllPoints()
    panel.bg:SetColorTexture(0.055, 0.055, 0.07, opacity())
    for _, edge in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" } }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint(edge[1])
        line:SetPoint(edge[2])
        line:SetHeight(1)
        line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.35)
    end
    for _, side in ipairs({ "LEFT", "RIGHT" }) do
        local line = panel:CreateTexture(nil, "BORDER")
        line:SetPoint("TOP" .. side)
        line:SetPoint("BOTTOM" .. side)
        line:SetWidth(1)
        line:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.25)
    end

    -- Title bar: the brand header doubles as the loop cycler (mockup's dropdown).
    local titleBtn = _G.CreateFrame("Button", nil, panel)
    titleBtn:SetPoint("TOPLEFT")
    titleBtn:SetPoint("TOPRIGHT")
    titleBtn:SetHeight(24)
    local title = titleBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("LEFT", PAD, 0)
    title:SetText("|cff33ff99FORESIGHT MATRIX|r")
    local titleLine = panel:CreateTexture(nil, "BORDER")
    titleLine:SetPoint("TOPLEFT", 0, -24)
    titleLine:SetPoint("TOPRIGHT", 0, -24)
    titleLine:SetHeight(1)
    titleLine:SetColorTexture(1, 1, 1, 0.08)
    titleBtn:SetScript("OnClick", function() MatrixPanel.cycleLoop() end)
    titleBtn:SetScript("OnEnter", function(self)
        if panel.badgeTip then
            _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            _G.GameTooltip:SetText(panel.badgeTip, nil, nil, nil, nil, true)
            _G.GameTooltip:Show()
        end
    end)
    titleBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    local close = _G.CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)

    -- Options gear on the Matrix title bar too (S30), left of the close button.
    local optBtn = _G.CreateFrame("Button", nil, panel)
    optBtn:SetSize(18, 18)
    optBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, -4)
    local cog = optBtn:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cog:SetAllPoints()
    cog:SetText("|TInterface\\Buttons\\UI-OptionsButton:12:12|t")
    optBtn:SetScript("OnClick", function()
        if HM.OptionsPanel and HM.OptionsPanel.toggle then HM.OptionsPanel.toggle() end
    end)
    optBtn:SetScript("OnEnter", function(self)
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:SetText("Foresight options", 0.2, 1, 0.6)
        _G.GameTooltip:Show()
    end)
    optBtn:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)

    -- S33 RESIZE GRIP: drag the bottom-right corner to stretch the panel wider; the
    -- layout re-flows to the new width live and the validated width is saved per char.
    local grip = _G.CreateFrame("Button", nil, panel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:EnableMouse(true)
    local gripTex = grip:CreateTexture(nil, "OVERLAY")
    gripTex:SetAllPoints()
    gripTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetScript("OnMouseDown", function()
        panel:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        panel:StopMovingOrSizing()
        local w = HM.PanelModel.normalizeWidth(panel:GetWidth())
        panel:SetWidth(w) -- clamp back inside bounds
        uiState().width = w
        MatrixPanel.refresh() -- re-flow to the final width
    end)
    -- Live re-flow while the PANEL resizes (throttled so it isn't a per-frame rebuild).
    local sizePending
    panel:SetScript("OnSizeChanged", function()
        if sizePending or not panel:IsShown() then return end
        sizePending = true
        local function run() sizePending = nil; MatrixPanel.refresh() end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.05, run) else run() end
    end)

    panel:Hide()
    -- S33 throttle law: a hidden panel runs zero animation work.
    panel:SetScript("OnHide", function()
        if HM.Motion then HM.Motion.cancelOwner("matrix") end
    end)

    -- Live refresh while visible (same debounced event set as the stats panel).
    local events = _G.CreateFrame("Frame")
    for _, ev in ipairs({ "UNIT_STATS", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA",
                          "TRAIT_CONFIG_UPDATED", "PLAYER_TALENT_UPDATE",
                          "CHARACTER_POINTS_CHANGED" }) do
        pcall(events.RegisterEvent, events, ev)
    end
    local TALENT_EVENTS = { TRAIT_CONFIG_UPDATED = true, PLAYER_TALENT_UPDATE = true,
                            CHARACTER_POINTS_CHANGED = true }
    local pending
    events:SetScript("OnEvent", function(_, event, unit)
        if TALENT_EVENTS[event] then
            -- talent events carry a configID/points arg, not a unit - never unit-gate them
            MatrixPanel.invalidatePathways()
        elseif unit ~= nil and unit ~= "player" then
            return
        end
        if not panel:IsShown() or pending then return end
        pending = true
        local function run() pending = nil; MatrixPanel.refresh() end
        if _G.C_Timer and _G.C_Timer.After then _G.C_Timer.After(0.2, run) else run() end
    end)
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
    if not panel then createPanel() end
end)
