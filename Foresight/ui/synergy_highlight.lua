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

if not _G.CreateFrame then return Highlight end -- headless: pure selector only

local BRAND = { r = 0.2, g = 1, b = 0.6 }
local overlays = {} -- [button] = our overlay frame (pooled per button, reused)

local function overlayFor(button)
    local o = overlays[button]
    if o then return o end
    o = _G.CreateFrame("Frame", nil, button)
    o:SetAllPoints()
    o:SetFrameLevel((button.GetFrameLevel and button:GetFrameLevel() or 1) + 5)
    local fill = o:CreateTexture(nil, "OVERLAY", nil, -1)
    fill:SetAllPoints()
    fill:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.12)
    for _, e in ipairs({ { "TOPLEFT", "TOPRIGHT", nil, 2 }, { "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
                         { "TOPLEFT", "BOTTOMLEFT", 2, nil }, { "TOPRIGHT", "BOTTOMRIGHT", 2, nil } }) do
        local t = o:CreateTexture(nil, "OVERLAY")
        t:SetPoint(e[1])
        t:SetPoint(e[2])
        if e[3] then t:SetWidth(e[3]) else t:SetHeight(e[4]) end
        t:SetColorTexture(BRAND.r, BRAND.g, BRAND.b, 0.9)
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

local dimmed = {} -- buttons we lowered; restored on clear (visual-only, taint-free)

function Highlight.clear()
    for _, o in pairs(overlays) do
        if o.pulse then o.pulse:Stop() end
        o:Hide()
    end
    for _, b in ipairs(dimmed) do
        pcall(b.SetAlpha, b, 1)
    end
    dimmed = {}
end

local function applySets(ids, names, dimOthers)
    local buttons, others = collectButtons(ids, names, dimOthers)
    for _, b in ipairs(buttons) do
        local o = overlayFor(b)
        o:Show()
        if o.pulse then o.pulse:Play() end
    end
    if dimOthers then
        for _, b in ipairs(others) do
            pcall(b.SetAlpha, b, 0.35)
            dimmed[#dimmed + 1] = b
        end
    end
    return #buttons
end

-- Apply a theme's glow to whatever talent buttons exist right now. Returns the
-- number of buttons lit (0 when the talent UI is closed) + the resolved label.
function Highlight.apply(query)
    Highlight.clear()
    local ids, names, label = Highlight.traitMembers(query, Highlight.playerContext())
    if not ids then return nil end
    return applySets(ids, names, false), label
end

-- Skill-centric mode (S7b): the tree DIMS and the ability's modifier talents glow.
-- Transient by design (not saved) - a look, not a mode you get stuck in.
function Highlight.applyAbility(query)
    Highlight.clear()
    local ids, names, spell = Highlight.abilityMembers(query)
    if not ids then return nil end
    return applySets(ids, names, true), spell
end

function Highlight.playerContext()
    local snap = HM.Snapshot and HM.Snapshot.capture()
    if not snap then return nil end
    return { raceId = snap.raceId, classToken = snap.classToken,
             buffs = HM.Snapshot.captureActiveBuffs() }
end

-- Saved theme (per character, validated on read - untrusted-input law).
local function synergySettings()
    local db = HM.charDb and HM.charDb()
    if not db then return nil end
    if type(db.settings.synergy) ~= "table" then db.settings.synergy = {} end
    return db.settings.synergy
end

function Highlight.savedTheme()
    local s = synergySettings()
    local t = s and s.theme
    return (type(t) == "string" and t ~= "" and #t <= 40) and t or nil
end

function Highlight.setTheme(query) -- nil clears
    local s = synergySettings()
    if s then s.theme = query end
end

-- Re-apply the saved theme whenever the talent UI opens (it is load-on-demand, so
-- hook once Blizzard_PlayerSpells exists); clear our overlays when it hides.
local hooked
local function hookTalentUI()
    if hooked then return end
    local psf = _G.PlayerSpellsFrame
    if not (psf and psf.HookScript) then return end
    hooked = true
    psf:HookScript("OnShow", function()
        local theme = Highlight.savedTheme()
        if theme and _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0.3, function() pcall(Highlight.apply, theme) end)
        end
    end)
    psf:HookScript("OnHide", function() pcall(Highlight.clear) end)
end

local boot = _G.CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, event, addon)
    if event == "PLAYER_LOGIN" or addon == "Blizzard_PlayerSpells" then hookTalentUI() end
end)

return Highlight
