---
name: wow-ui-ux
description: In-game WoW addon UI/UX conventions - window behavior (ESC-close, raise, clamp, scale, strata), text layout laws (wrapping, measured heights, ellipsis priority), and coexistence with UI overhauls (ElvUI etc.). Use when building or changing ANY in-game frame, panel, tooltip, or overlay in this repo, or when auditing the addon's UI. Distilled from how the big addons (ElvUI, WeakAuras, Details!, Bagnon) behave + the 2026-10-20 UI audit.
---

# WoW in-game UI/UX - the house laws

Players run Foresight NEXT TO ElvUI, WeakAuras, Details!, bag addons, and font/scale
overhauls. Our frames must behave like the frames of those addons - users' muscle memory IS
the spec. Every law below exists because its absence was a real finding in the 2026-10-20
audit or a live incident.

## 1. The window taxonomy - decide which one you're building

- **WINDOW** (planner, options, export): standalone, movable, has a close button, ESC closes
  it, position/size/scale persist.
- **DASHBOARD** (the Matrix): movable, close button, collapse-to-title-bar, deliberately NOT
  ESC-closable. Pinning is OPT-IN (the `matrixPinned` setting): by default a dashboard opened
  alongside a host menu CLOSES with it (owner UX call 2026-10-21 - two windows opened by one
  button must close together); pinned = the Details!-style survivor.
- **FURNITURE** (FS/Share/Options buttons, the talent-frame planner button, hints): anchored
  to a host frame, shown/hidden WITH the host via HookScript, never independently closable.
- **OVERLAY** (talent glows, plan preview): draws over a Blizzard frame; lifecycle bound to
  the host's OnShow/OnHide; strata/level MATCH the host (+level offset), never hard-pinned
  above everything.

## 2. Window laws (every WINDOW gets all of these)

```lua
frame:SetToplevel(true)                -- clicked window raises above siblings
frame:SetClampedToScreen(true)         -- a drag can never strand it off-screen
if type(_G.UISpecialFrames) == "table" then
    table.insert(_G.UISpecialFrames, "GlobalFrameName")  -- ESC closes it (needs a GLOBAL name)
end
-- a close button:
local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
-- the user's one scale slider applies on every show:
frame:SetScale(HM.Settings.get("panelScale") or 1)
```

- **Persist position/size - and VALIDATE on restore.** SavedVariables is user-editable:
  route positions through `PanelModel.normalizePanelPos`, sizes through a normalizer that
  heals nil/NaN/out-of-bounds to defaults (see `options_panel.normalizeSize`). An invalid
  `SetSize`/`SetPoint` during PLAYER_LOGIN bricks the window for that character.
- **Strata ladder**: panels/dashboards `HIGH`; modal dialogs (options, export) `DIALOG`;
  never leave the default (`MEDIUM` sinks under other addons). Siblings that open together
  (stats + Matrix) share a strata.
- **Open/close flows**: every window reachable by slash AND a button; toggles are
  idempotent; furniture tracks its host (no orphans when the host closes).

## 3. Text layout laws (the ElvUI-proofing)

Design for **+20-65% font growth**: ElvUI replaces the virtual Game fonts globally and
users raise font size. UI-scale changes are uniform (safe); FONT growth is what breaks
fixed layouts.

- **Virtual font templates only** (`GameFontNormal`, `NumberFontNormal`...). Never a
  hardcoded font path - templates are what ElvUI reskins, so our text matches the user's UI
  for free.
- **Row heights are MEASURED, not constant**: `rowH = math.max(MIN, fs:GetStringHeight() + pad)`
  after SetText. Reference implementation: the stats panel's rows and `options_panel.renderKey`.
- **Multi-sentence tooltip lines always pass `wrap = true`** (`AddLine(text, r, g, b, true)` /
  `SetText(text, r, g, b, 1, true)`). One unwrapped long line sets the MINIMUM width of the
  whole tooltip - the mile-wide-tooltip bug.
- **Width comes from anchors, not constants**: bound a FontString's RIGHT to the element
  beside it (`points:SetPoint("RIGHT", controls, "LEFT", -8, 0)`), never trust "it fits at
  stock fonts".
- **Row-flow, not fixed offsets**: stack sections by anchoring each to the previous one's
  BOTTOM so grown text pushes content down instead of overlapping it. If a section can wrap,
  grow the window height from the measured text. NEVER anchor to a FontString that can be
  EMPTY (its rect collapses) - keep a space in it.
- **Ellipsis priority**: names/labels may truncate (`SetWordWrap(false)` + width, full text in
  a tooltip); NUMBERS never truncate (value column right-anchored and unconstrained, the
  label yields).
- **Unbounded collections get a cap + pager**: N visible + a "+N more" control (the saved-
  build chips). Children of a frame do NOT clip at its edge - overflow floats over the world.
- **Pooled FontStrings normalize on acquire**: reset `SetWordWrap(true)`/`SetMaxLines(0)` (and
  font/justify) in the acquire function - pool stickiness silently corrupts measured layouts.

## 4. Coexistence facts (what overhaul addons actually do)

- ElvUI **reskins frames in place** (same globals, similar geometry) - anchoring to
  `CharacterFrame`/`PlayerSpellsFrame` keeps working; expect different art + sizes.
- ElvUI/font addons **replace the virtual font objects** - see law 3.
- Other addons' windows live at `MEDIUM`/`HIGH` - win ordering via **frame LEVEL within the
  host's strata** for overlays, not by jumping to a higher strata.
- Blizzard textures can be renamed across client flavors - prefer **code-drawn textures**
  (SetColorTexture, gradients) over art-file paths; they also match any skin.

## 5. Account-safety cross-reference (never regress these)

The taint laws trump any UI nicety (enforced by `pipeline/check_compliance.py`):
- Our frames are UIParent children that ANCHOR to Blizzard frames - never parented into
  them, no key writes, no regions on them (the v0.44.2/v0.45.5 incidents).
- `HookScript` only on Blizzard frames; reads pcall'd; overlay application combat-gated.
- `UISpecialFrames` insertion is a plain global-list append - the one sanctioned "write".

## 6. The audit checklist (re-run after any UI change)

For each frame: taxonomy class? ESC per class? SetToplevel? clamped? scale applied on show?
strata set explicitly? close affordance? pos/size persisted + validated? Then text: any
fixed-height container with dynamic text? any AddLine missing wrap? any fixed x-offset row
that collides when a sibling grows? any unbounded list without a cap? pooled FS normalized?
Then run the gate (`python pipeline/run_tests.py`) and verify in-game at 1280x720 with
0.65 UI scale (the mobile binding) plus one pass at +4pt fonts if testing with ElvUI.

## Reference implementations in this repo

- Window laws, all together: `Foresight/ui/talent_tree.lua` ensureFrame.
- Validated restore: `PanelModel.normalizePanelPos`, `options_panel.normalizeSize`,
  `PanelModel.normalizeWidth`.
- Measured rows: `stats_panel.lua` layout(), `options_panel.renderKey`.
- Row-flow + grown window: planner summary -> button bar -> treeHost chain + refreshHeader.
- Cap + pager: the planner's saved-build chips.
- Overlay strata sync: `synergy_highlight.syncOverlayStrata`.
