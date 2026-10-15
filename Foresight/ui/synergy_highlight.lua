-- Foresight synergy highlight (SYNERGY-highlight): Diablo-paragon-style selection on
-- the talent tree - pick a theme ("intellect", "crit") and every node that pushes that
-- lever glows. Display-only by construction: we draw OUR OWN textures on overlay
-- frames parented to node buttons - no secure methods, no Blizzard glow reuse (the
-- ActionButton overlay taints). LibCustomGlow can replace the house glow at packaging
-- time; the locator/selector stay the same.
--
-- Split: traitMembers() is pure (selftest-covered headless); locating buttons and
-- drawing is in-game only. Locator order: official enumerator probe (names drift
-- across 10.x/11.x/Forever - probe, never hardcode) -> bounded name-match scan
-- (node button frame name = talent name, proven by the tooltip owner-name discovery).

local _, HM = ...
if not HM then HM = _G.Foresight or {}; _G.Foresight = HM end

local Highlight = {}
HM.SynergyHighlight = Highlight

-- Pure: the trait-node members of a theme -> id set + name set (+ resolved label).
-- Racial/buff members have no tree buttons and are excluded from the highlight set.
function Highlight.traitMembers(query, player)
    local r = HM.Synergy and HM.Synergy.query(query, player)
    if not r then return nil end
    local ids, names = {}, {}
    local nodes = (HM.gen and HM.gen.traits and HM.gen.traits.nodes) or {}
    for _, m in ipairs(r.members or {}) do
        if type(m) == "number" then
            ids[m] = true
            local node = nodes[m]
            if node and node.name then names[node.name] = true end
        end
    end
    return ids, names, r.label
end

-- Pure: the trait nodes that MODIFY an ability (skill-centric mode, S7b) - resolved
-- through the impact map, source names matched back to tree nodes.
function Highlight.abilityMembers(query)
    local r = HM.Mapping and HM.Mapping.forSpell(query)
    if not r then return nil end
    local wanted = {}
    for _, s in ipairs(r.sources or {}) do wanted[s.name] = true end
    local ids, names, any = {}, {}, false
    for nid, node in pairs((HM.gen and HM.gen.traits and HM.gen.traits.nodes) or {}) do
        if node.name and wanted[node.name] then
            ids[nid] = true
            names[node.name] = true
            any = true
        end
    end
    if not any then return nil end
    return ids, names, r.spell
end

-- Pure (S22a): the CLASSIFIED member sets for an ability - direct modifiers (gold
-- solid) vs indirect ones (school + stat feeders; blue pulse) - via
-- Mapping.classifiedForSpell. ctx optional { classToken, level } (headless-friendly).
-- Returns directIds, indirectIds, directNames, indirectNames, spellName; nil when the
-- ability is unknown (no false glow).
function Highlight.abilityClassified(query, ctx)
    if not (HM.Mapping and HM.Mapping.classifiedForSpell and HM.Sim) then return nil end
    local sid = HM.Sim.resolveSpellLevelCapped
        and HM.Sim.resolveSpellLevelCapped(query, ctx and ctx.level)
    local c = sid and HM.Mapping.classifiedForSpell(sid, ctx)
    if not c then return nil end
    local dIds, dNames, iIds, iNames, any = {}, {}, {}, {}, false
    for _, e in ipairs(c.direct) do
        dIds[e.nodeId], any = true, true
        if e.name then dNames[e.name] = true end
    end
    for _, list in ipairs({ c.school, c.statFeeders }) do
        for _, e in ipairs(list) do
            if not dIds[e.nodeId] then
                iIds[e.nodeId], any = true, true
                if e.name then iNames[e.name] = true end
            end
        end
    end
    if not any then return nil end
    return dIds, iIds, dNames, iNames, c.spell
end

-- S32 action-bar trigger - the PURE half (headless-testable): a TRANSIENT focus (the
-- hold-ALT trace) that NEVER saves over the user's persistent focus. State is tracked
-- so the restore is exact; applyAbility/clear/restoreSaved exist only in-game, so the
-- transient functions call them defensively (and set/clear the flag either way).
local transientActive = false
function Highlight.isTransient() return transientActive end

-- Pure: an action slot's (type, id) -> the spell name we can trace, or nil (honest
-- skip for macro/item/companion slots - we only trace spells we have data for).
function Highlight.actionToSpellName(actionType, id)
    if actionType == "spell" and id then
        local sp = HM.gen and HM.gen.spells and HM.gen.spells[id]
        return sp and sp.name
    end
    return nil
end

function Highlight.applyTransient(spellName)
    if not spellName then return nil end
    transientActive = true
    if Highlight.applyAbility then return Highlight.applyAbility(spellName) end -- never setFocus
end

function Highlight.endTransient()
    if not transientActive then return false end
    transientActive = false
    if Highlight.clear then Highlight.clear() end
    if Highlight.restoreSaved then Highlight.restoreSaved() end
    return true
end

-- SESSION-ONLY focus/theme (v0.45.1): the highlight is a thing you ASK FOR this
-- session, never a state that resurrects on every login. The old design persisted
-- focus/theme to SavedVariables and auto-re-applied it on talent-UI open, so a focus
-- set once lit the tree forever (the user's "Lightning always highlights when I log
-- in") - and applying overlays to talent buttons at login is exactly the taint class
-- v0.33.2 warned about. Now the value lives in a session upvalue that starts nil on
-- every login; migrateLegacy() wipes the stale persisted keys so nothing lingers.
-- Pure (above the headless guard) so the selftest can prove the no-persist contract.
local sessionFocus, sessionTheme
local legacyMigrated = false

local function validName(v)
    return (type(v) == "string" and v ~= "" and #v <= 40) and v or nil
end

-- One-time per session: clear the legacy persisted focus/theme (the stuck overlay).
local function migrateLegacy()
    if legacyMigrated then return end
    legacyMigrated = true
    local db = HM.charDb and HM.charDb()
    if db and type(db.settings) == "table" and type(db.settings.synergy) == "table" then
        db.settings.synergy.focus = nil
        db.settings.synergy.theme = nil
    end
end
Highlight._migrateLegacy = migrateLegacy -- selftest hook

function Highlight.savedTheme()
    return validName(sessionTheme)
end

function Highlight.setTheme(query) -- nil clears
    migrateLegacy()
    sessionTheme = validName(query)
end

-- Session skill focus (S22a): the ability name the player is studying THIS session.
-- Focus outranks the theme on tree open; both reset to nil on logout/login.
function Highlight.savedFocus()
    return validName(sessionFocus)
end

function Highlight.setFocus(query) -- nil clears
    migrateLegacy()
    sessionFocus = validName(query)
end

if not _G.CreateFrame then return Highlight end -- headless: pure selector only

local BRAND = { r = 0.2, g = 1, b = 0.6 }   -- theme glow (synergy)
local GOLD  = { r = 1, g = 0.82, b = 0.2 }  -- direct modifiers (solid)
local BLUE  = { r = 0.35, g = 0.65, b = 1 } -- indirect: school + stat feeders (pulse)

-- TAINT ISOLATION LAW (hardened 2026-10-12 after a live "blocked from an action only
-- available to the Blizzard UI"): our overlays live on OUR OWN layer parented to
-- UIParent and merely ANCHOR to the node buttons - Foresight never parents a frame
-- into Blizzard's talent-frame tree and never writes a key onto their objects, so no
-- secure talent operation (point spend / config commit) ever walks our frames.
local container
local function overlayLayer()
    if container then return container end
    container = _G.CreateFrame("Frame", "ForesightHighlightLayer", _G.UIParent)
    container:SetAllPoints(_G.UIParent)
    container:SetFrameStrata("HIGH")
    container:Hide()
    return container
end

local overlays = {} -- [button] = our overlay frame (pooled per button, reused)

local function overlayFor(button)
    local o = overlays[button]
    if o then return o end
    o = _G.CreateFrame("Frame", nil, overlayLayer())
    o:SetAllPoints(button) -- anchor to the button, never parent into its tree
    local fill = o:CreateTexture(nil, "OVERLAY", nil, -1)
    fill:SetAllPoints()
    o.fill = fill
    o.edges = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
                         { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        o.edges[#o.edges + 1] = t
    end
    local ag = o:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1)
    a:SetToAlpha(0.45)
    a:SetDuration(0.8)
    o.pulse = ag
    overlays[button] = o
    return o
end

-- Restyle a pooled overlay: color + solid vs pulsing (gold direct / blue indirect /
-- brand theme).
local function styleOverlay(o, c, pulse)
    o.fill:SetColorTexture(c.r, c.g, c.b, 0.12)
    for _, t in ipairs(o.edges) do t:SetColorTexture(c.r, c.g, c.b, 0.9) end
    o:SetAlpha(1)
    if pulse then o.pulse:Play() else o.pulse:Stop() end
end

-- DIM LAW (S22a): dimming is an OVERLAY too - a dark semi-transparent house texture
-- on OUR layer, anchored to the node button. We NEVER mutate Blizzard button
-- properties and never enter their frame tree (taint isolation law above).
local dims = {} -- [button] = our dim frame (pooled, reused)

local function dimFor(button)
    local d = dims[button]
    if d then return d end
    d = _G.CreateFrame("Frame", nil, overlayLayer())
    d:SetAllPoints(button)
    local fill = d:CreateTexture(nil, "OVERLAY", nil, -2)
    fill:SetAllPoints()
    fill:SetColorTexture(0, 0, 0, 0.62)
    dims[button] = d
    return d
end

local function talentFrame()
    local psf = _G.PlayerSpellsFrame
    return psf and (psf.TalentsFrame or psf.TalentFrame or psf) or nil
end

-- Locate the node buttons for a member set. Probe the official enumerator first;
-- fall back to a bounded descendant scan matching frame names against node names.
-- wantOthers: also return non-member node buttons (enumerator path only - the name
-- scan can't tell node buttons from other frames, so dimming degrades off honestly).
local function collectButtons(ids, names, wantOthers)
    local hits, others = {}, {}
    local tf = talentFrame()
    if not tf then return hits, others end
    if type(tf.EnumerateAllTalentButtons) == "function" then
        pcall(function()
            for button in tf:EnumerateAllTalentButtons() do
                local okId, nid = pcall(function() return button:GetNodeID() end)
                if okId and nid then
                    if ids[nid] then
                        hits[#hits + 1] = button
                    elseif wantOthers then
                        others[#others + 1] = button
                    end
                end
            end
        end)
        if #hits > 0 then return hits, others end
    end
    local seen = 0
    local function scan(frame, depth)
        if depth > 8 or seen > 4000 then return end
        for _, child in ipairs({ frame:GetChildren() }) do
            seen = seen + 1
            local name = child.GetName and child:GetName()
            if name and names[name] then hits[#hits + 1] = child end
            scan(child, depth + 1)
        end
    end
    pcall(scan, tf, 1)
    return hits, {}
end

function Highlight.clear()
    for _, o in pairs(overlays) do
        if o.pulse then o.pulse:Stop() end
        o:Hide()
    end
    for _, d in pairs(dims) do d:Hide() end
    if container then container:Hide() end
end

-- S35 TALENT-PLAN OVERLAY: glow a PLANNED build over the LIVE talent tree - blue (pulsing)
-- where points remain, gold (steady) where already allocated. Live delta via ranksPurchased.
-- Its OWN anchored overlay pool: each overlay is a Button that SetAllPoints the real node
-- button but lives on OUR UIParent layer (never parented into Blizzard's tree - the taint-
-- isolation law). In EDIT MODE the overlays are clickable (left +, right -) to plan ANY node
-- incl. Forever-new ones; out of edit mode they are mouse-transparent so your real clicks
-- reach the game. DISPLAY/ADVICE ONLY: it NEVER spends points - you apply them yourself.
local PLANBLUE = { r = 0.25, g = 0.55, b = 1 }
local EDITGREY = { r = 0.6, g = 0.6, b = 0.65 }
local planOverlays = {}
local planEditMode = false
local activePlan

-- Edit one node in the plan (delta +/-1), clamped to its maxRanks (read live). Re-applies.
local function editNode(nodeID, maxRanks, delta)
    if not nodeID then return end
    activePlan = activePlan or {}
    local v = (tonumber(activePlan[nodeID]) or 0) + delta
    if v < 0 then v = 0 end
    if maxRanks and v > maxRanks then v = maxRanks end
    activePlan[nodeID] = v > 0 and v or nil
    Highlight.setPlanPreview(activePlan)
end

local function planOverlayFor(button)
    local o = planOverlays[button]
    if o then return o end
    o = _G.CreateFrame("Button", nil, overlayLayer())
    o:SetAllPoints(button)
    o:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    o.border = {}
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 3 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 3 },
                         { "TOPLEFT", "BOTTOMLEFT", 3, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 3, nil } }) do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetPoint(e[1]); t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        t:SetBlendMode("ADD")
        o.border[#o.border + 1] = t
    end
    o.rankText = o:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    o.rankText:SetPoint("BOTTOM", o, "BOTTOM", 0, 2)
    local ag = o:CreateAnimationGroup(); ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha"); a:SetFromAlpha(1); a:SetToAlpha(0.4); a:SetDuration(0.8)
    o.pulse = ag
    o:SetScript("OnClick", function(self, mouse)
        if not planEditMode then return end  -- display mode never intercepts a real click
        editNode(self.nodeID, self.maxRanks, mouse == "RightButton" and -1 or 1)
    end)
    o:SetScript("OnEnter", function(self)
        if not planEditMode then return end
        _G.GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        _G.GameTooltip:AddLine(self.nodeName or "Talent", 1, 0.82, 0.25)
        _G.GameTooltip:AddLine(("Planned %d/%d"):format(tonumber(activePlan and activePlan[self.nodeID]) or 0, self.maxRanks or 1), 0.7, 0.7, 0.7)
        _G.GameTooltip:AddLine("Left-click +  ·  Right-click -  (plan only)", 0.5, 0.5, 0.55)
        _G.GameTooltip:Show()
    end)
    o:SetScript("OnLeave", function() _G.GameTooltip:Hide() end)
    planOverlays[button] = o
    return o
end

local function clearPlanOverlays()
    for _, o in pairs(planOverlays) do
        if o.pulse then o.pulse:Stop() end
        o:EnableMouse(false)
        o:Hide()
    end
end

-- Re-anchor + recolor the plan overlays to the live tree. In edit mode, decorate EVERY node
-- (clickable); otherwise only the planned ones (mouse-transparent), reading ranksPurchased
-- for the blue->gold delta.
function Highlight.applyPlanPreview()
    clearPlanOverlays()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return 0 end
    if not planEditMode and (type(activePlan) ~= "table" or not next(activePlan)) then return 0 end
    if HM.Settings and HM.Settings.get("plannerOverlay") == false and not planEditMode then return 0 end
    local tf = talentFrame()
    if not (tf and type(tf.EnumerateAllTalentButtons) == "function") then return 0 end
    overlayLayer():Show()
    local lit = 0
    pcall(function()
        for button in tf:EnumerateAllTalentButtons() do
            local okId, nid = pcall(function() return button:GetNodeID() end)
            local target = okId and nid and (activePlan and activePlan[nid])
            if okId and nid and (target or planEditMode) then
                local cur, maxR, name = 0, 1, nil
                local oki, info = pcall(function() return button:GetNodeInfo() end)
                if oki and type(info) == "table" then
                    cur = info.ranksPurchased or 0
                    maxR = info.maxRanks or 1
                end
                local g = HM.gen and HM.gen.traits and HM.gen.traits.nodes and HM.gen.traits.nodes[nid]
                name = g and g.name
                target = target or 0
                local o = planOverlayFor(button)
                o.nodeID, o.maxRanks, o.nodeName = nid, maxR, name
                o:EnableMouse(planEditMode)
                local done = target > 0 and cur >= target
                local c = (target == 0 and planEditMode) and EDITGREY or (done and GOLD or PLANBLUE)
                local alpha = (target == 0 and planEditMode) and 0.4 or 0.95
                for _, t in ipairs(o.border) do t:SetColorTexture(c.r, c.g, c.b, alpha) end
                o.rankText:SetText(target > 0 and ("%d/%d"):format(cur, target) or "")
                o.rankText:SetTextColor(done and 0.45 or 1, 1, done and 0.45 or 1)
                if target > 0 and not done then o.pulse:Play() else o.pulse:Stop(); o:SetAlpha(1) end
                o:Show()
                if target > 0 then lit = lit + 1 end
            end
        end
    end)
    return lit
end

-- Set (and persist per-char) the active plan preview (nodeId -> planned rank). nil/{} clears.
function Highlight.setPlanPreview(nodePlan)
    activePlan = (type(nodePlan) == "table" and next(nodePlan)) and nodePlan or nil
    local db = HM.charDb and HM.charDb()
    if db then
        db.settings = db.settings or {}
        db.settings.planner = db.settings.planner or {}
        db.settings.planner.activePlan = activePlan
    end
    Highlight.applyPlanPreview()
end

function Highlight.activePlan() return activePlan end

-- The classic grid edits only the classic-overlap node set; merge its plan in while PRESERVING
-- any Forever-new nodes (from copy-inspect / FT2 import / the edit overlay) so they survive.
function Highlight.mergeGridPlan(gridNodePlan)
    activePlan = activePlan or {}
    local classicSet = HM.TalentBuild and HM.TalentBuild.classicNodeSet() or {}
    for nid in pairs(classicSet) do activePlan[nid] = nil end
    for nid, rank in pairs(gridNodePlan or {}) do
        if (tonumber(rank) or 0) > 0 then activePlan[nid] = rank end
    end
    if not next(activePlan) then activePlan = nil end
    local db = HM.charDb and HM.charDb()
    if db then
        db.settings = db.settings or {}
        db.settings.planner = db.settings.planner or {}
        db.settings.planner.activePlan = activePlan
    end
    Highlight.applyPlanPreview()
end

-- Edit mode: clickable overlays on EVERY node (plan Forever-new ones too). Toggled via the
-- planner / a slash command; auto-off in combat. Returns the new state.
function Highlight.setPlanEditMode(on)
    planEditMode = on and true or false
    Highlight.applyPlanPreview()
    return planEditMode
end
function Highlight.togglePlanEditMode() return Highlight.setPlanEditMode(not planEditMode) end

-- Copy an inspected SAME-CLASS player's build -> a node plan -> set it as the preview.
-- Reads the inspect config live from the talent frame (the ForeverTalents path), read-only.
function Highlight.copyInspectedPlan()
    local tf = talentFrame()
    if not tf then return nil, "open your talents while inspecting a player" end
    if not (tf.IsInspecting and tf:IsInspecting()) then
        return nil, "inspect a player first (their talents must be showing)"
    end
    local unit = tf.GetInspectUnit and tf:GetInspectUnit()
    local okc, theirClass = pcall(function() return select(2, _G.UnitClass(unit)) end)
    local _, myClass = _G.UnitClass("player")
    if okc and theirClass and myClass and theirClass ~= myClass then
        return nil, "only a same-class build can be copied"
    end
    local configID = tf.GetConfigID and tf:GetConfigID()
    local treeID = tf.GetTalentTreeID and tf:GetTalentTreeID()
    if not (configID and treeID and _G.C_Traits and _G.C_Traits.GetTreeNodes) then
        return nil, "couldn't read the inspected tree"
    end
    local plan = {}
    local okn, nodes = pcall(_G.C_Traits.GetTreeNodes, treeID)
    if okn and type(nodes) == "table" then
        for _, nodeID in ipairs(nodes) do
            local oki, info = pcall(_G.C_Traits.GetNodeInfo, configID, nodeID)
            if oki and type(info) == "table" and (info.ranksPurchased or 0) > 0 then
                plan[nodeID] = info.ranksPurchased
            end
        end
    end
    if not next(plan) then return nil, "that build has no points" end
    Highlight.setPlanPreview(plan)
    return plan
end

local function restorePlanPreview()
    local db = HM.charDb and HM.charDb()
    local saved = db and db.settings and db.settings.planner and db.settings.planner.activePlan
    if type(saved) ~= "table" then return end
    local clean = {}
    for k, v in pairs(saved) do
        local nid, rank = tonumber(k), tonumber(v)
        if nid and rank and rank > 0 then clean[nid] = rank end
    end
    activePlan = next(clean) and clean or nil
end

local function applySets(ids, names, dimOthers, color, pulse)
    -- COMBAT GATE: never enumerate or decorate the talent UI in combat - protected
    -- talent operations must never find us anywhere near their execution window.
    if _G.InCombatLockdown and _G.InCombatLockdown() then return 0 end
    overlayLayer():Show()
    local buttons, others = collectButtons(ids, names, dimOthers)
    for _, b in ipairs(buttons) do
        local o = overlayFor(b)
        styleOverlay(o, color or BRAND, pulse ~= false)
        o:Show()
    end
    if dimOthers then
        for _, b in ipairs(others) do dimFor(b):Show() end
    end
    return #buttons
end

-- Apply a theme's glow to whatever talent buttons exist right now. Returns the
-- number of buttons lit (0 when the talent UI is closed) + the resolved label.
function Highlight.apply(query)
    Highlight.clear()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    local ids, names, label = Highlight.traitMembers(query, Highlight.playerContext())
    if not ids then return nil end
    return applySets(ids, names, false, BRAND, true), label
end

-- Skill-centric mode (S7b/S22a): the tree DIMS (overlay law above) while the
-- ability's DIRECT modifiers glow gold solid and its indirect ones (school damage +
-- stat feeders) pulse blue. Falls back to the single-style member set when the
-- classified lookup can't resolve the ability.
function Highlight.applyAbility(query)
    Highlight.clear()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return nil end
    local ctx
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if snap then ctx = { classToken = snap.classToken, level = snap.level } end
    local dIds, iIds, dNames, iNames, spell = Highlight.abilityClassified(query, ctx)
    if dIds then
        local lit = applySets(dIds, dNames, false, GOLD, false)
        lit = lit + applySets(iIds, iNames, false, BLUE, true)
        -- Dim everything OUTSIDE the union (enumerator path only - honest degrade).
        local union, unionNames = {}, {}
        for k in pairs(dIds) do union[k] = true end
        for k in pairs(iIds) do union[k] = true end
        for k in pairs(dNames) do unionNames[k] = true end
        for k in pairs(iNames) do unionNames[k] = true end
        local _, others = collectButtons(union, unionNames, true)
        for _, b in ipairs(others) do dimFor(b):Show() end
        return lit, spell
    end
    local ids, names, resolved = Highlight.abilityMembers(query)
    if not ids then return nil end
    return applySets(ids, names, true, GOLD, false), resolved
end

function Highlight.playerContext()
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if not snap then return nil end
    return { raceId = snap.raceId, classToken = snap.classToken,
             buffs = HM.Snapshot.captureActiveBuffs() }
end

-- Re-apply the look set THIS session (focus first, then theme) when the talent UI
-- re-opens mid-session. Combat-gated. Fresh login = nothing set = nothing lit.
function Highlight.restoreSaved()
    if _G.InCombatLockdown and _G.InCombatLockdown() then return end
    migrateLegacy()
    local focus = Highlight.savedFocus()
    local theme = Highlight.savedTheme()
    if focus then pcall(Highlight.applyAbility, focus)
    elseif theme then pcall(Highlight.apply, theme) end
end

-- The configured trace modifier is down? (reads the settings spine, S30.)
local function triggerModifierDown()
    local mode = HM.Settings and HM.Settings.get("actionTrigger") or "off"
    if mode == "alt" then return _G.IsAltKeyDown and _G.IsAltKeyDown() end
    if mode == "shift" then return _G.IsShiftKeyDown and _G.IsShiftKeyDown() end
    return false -- off
end

-- Re-apply the saved focus (first) or theme whenever the talent UI opens (it is
-- load-on-demand, so hook once Blizzard_PlayerSpells exists); clear overlays on hide.
local hooked
local function hookTalentUI()
    if hooked then return end
    local psf = _G.PlayerSpellsFrame
    if not (psf and psf.HookScript) then return end
    hooked = true
    -- S32 hint: one corner line when the trace is enabled (settings-driven text).
    -- TAINT ISOLATION LAW: the hint lives on OUR frame parented to UIParent and only
    -- ANCHORS to the talent frame - the v0.44.0 version created it ON PlayerSpellsFrame
    -- (a region in their tree + a key write), and the first live session fired
    -- ADDON_ACTION_FORBIDDEN (SetPreferredGamepadInteractTarget) naming Foresight.
    -- The compliance gate now lints that class; this is the compliant shape.
    local hint
    local function refreshHint()
        local mode = HM.Settings and HM.Settings.get("actionTrigger") or "off"
        if mode == "off" then
            if hint then hint:Hide() end
            return
        end
        if not hint then
            hint = _G.CreateFrame("Frame", nil, _G.UIParent)
            hint:SetFrameStrata("HIGH")
            hint:SetSize(1, 1) -- pure anchor point; the font string overflows it
            hint:SetPoint("BOTTOMLEFT", psf, "BOTTOMLEFT", 12, 10)
            hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            hint.text:SetPoint("BOTTOMLEFT")
        end
        hint.text:SetText(("|cff9d9d9dHold %s + hover an action button to trace it|r")
            :format(mode:upper()))
        hint:Show()
    end
    psf:HookScript("OnShow", function()
        if _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.3, Highlight.restoreSaved)
            _G.C_Timer.After(0.35, Highlight.applyPlanPreview)  -- S35: auto-show the plan path
        end
        refreshHint()
    end)
    psf:HookScript("OnHide", function()
        if hint then hint:Hide() end
        pcall(Highlight.clear)
        clearPlanOverlays()
    end)

    -- S32: hovering an action button fires GameTooltip:SetAction(slot). We read the
    -- slot's spell (GetActionInfo, read-only), check the modifier, and apply a
    -- TRANSIENT trace - all visuals on the talent-tree overlays; we NEVER touch an
    -- action button (the taint law). Combat-gated; only while the talent UI is open.
    local gt = _G.GameTooltip
    if gt and _G.hooksecurefunc and type(gt.SetAction) == "function" then
        _G.hooksecurefunc(gt, "SetAction", function(_, slot)
            if _G.InCombatLockdown and _G.InCombatLockdown() then return end
            if not (psf.IsShown and psf:IsShown()) then return end
            if not triggerModifierDown() then return end
            if not (_G.GetActionInfo and slot) then return end
            local okA, actionType, id = pcall(_G.GetActionInfo, slot)
            local name = okA and Highlight.actionToSpellName(actionType, id)
            if name then pcall(Highlight.applyTransient, name) end
        end)
        gt:HookScript("OnHide", function() pcall(Highlight.endTransient) end)
    end
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
-- S35: live-delta the plan overlay as points are actually spent (blue remaining -> gold done).
pcall(boot.RegisterEvent, boot, "TRAIT_NODE_CHANGED")
pcall(boot.RegisterEvent, boot, "TRAIT_CONFIG_UPDATED")
pcall(boot.RegisterEvent, boot, "PLAYER_TALENT_UPDATE")
boot:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" then
        hookTalentUI()
        restorePlanPreview()  -- a followed plan survives a reload/relog
        -- Wipe any legacy persisted focus/theme at login so a focus set in an old
        -- build never resurrects (the stuck-Lightning report). Nothing lights until
        -- the user asks this session.
        if migrateLegacy then migrateLegacy() end
    elseif event == "ADDON_LOADED" and addon == "Blizzard_PlayerSpells" then
        hookTalentUI()
    elseif event == "TRAIT_NODE_CHANGED" or event == "TRAIT_CONFIG_UPDATED"
            or event == "PLAYER_TALENT_UPDATE" then
        pcall(Highlight.applyPlanPreview)
    end
end)

return Highlight
