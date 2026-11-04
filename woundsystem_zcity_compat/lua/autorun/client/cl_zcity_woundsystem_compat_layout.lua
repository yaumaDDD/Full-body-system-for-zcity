-- WSZC full-screen minigame layout + visual safety clamps (client side).
--
-- The C:U minigame chrome (WoundSystem.MinigameClip) draws a rounded 760x760
-- square in the middle of the screen.  Both WSZC minigames already own a
-- full-screen DPanel, so the only thing making them look like a small window is
-- Clip.GetRect() (used by DrawBackdrop / DrawHeader / Clip.Begin's stencil).
-- We override that ONE function at runtime, keeping the original for any
-- non-WSZC minigame and for `zc_woundsystem_compat_fullscreen_minigame 0`.
--
-- Nothing inside the original ZIP addons is modified: this is a runtime wrapper.

if not CLIENT then return end

WSZC = WSZC or {}
if WSZC._ClientLayoutLoaded then return end
WSZC._ClientLayoutLoaded = true

local cvFullscreen = CreateClientConVar("zc_woundsystem_compat_fullscreen_minigame", "1", true, false,
    "1 = stretch the bandage / syringe minigames over the whole screen")
local cvZoom = CreateClientConVar("zc_woundsystem_compat_minigame_zoom", "1", true, false,
    "Extra size multiplier for the WSZC minigames (0.7 .. 1.8)", 0.7, 1.8)
local cvClamp = CreateClientConVar("zc_woundsystem_compat_clamp_adrenaline", "1", true, false,
    "1 = clamp the shadow organism's adrenaline/painkiller so ZCity camera FX stay sane")
local cvNativeZoom = CreateClientConVar("zc_woundsystem_compat_native_minigame_zoom", "0.75", true, false,
    "Size of native C:U minigames when fullscreen_native is 0 (0.4 .. 1.2)", 0.4, 1.2)
local cvFullscreenNative = CreateClientConVar("zc_woundsystem_compat_fullscreen_native", "1", true, false,
    "1 = also stretch native C:U shrapnel / dislocation / AED minigames over the whole screen")
local cvHandScale = CreateClientConVar("zc_woundsystem_compat_hand_cursor_scale", "0.45", true, false,
    "Size of the on-screen hand in WSZC bandage/syringe minigames (0.2 .. 1)", 0.2, 1)

--- Multiplier for the huge C:U hand sprites (512x1260 source images).
function WSZC.HandCursorScale()
    return cvHandScale and cvHandScale:GetFloat() or 1
end

--- sh_handphysics.lua adds a pain-driven pseudo-noise offset to the mouse
--- target (up to +-120 px * scale).  With ZCity pain values that makes the
--- hand jitter wildly and the roll/syringe impossible to grab.  Called on the
--- private HandPhysics table that each WSZC minigame includes.
function WSZC.StabilizeHandPhysics(hp)
    if type(hp) ~= "table" or type(hp.Step) ~= "function" then return hp end
    if hp._WSZCStabilized then return hp end
    local original = hp.Step
    hp.Step = function(mg, dt, opts)
        opts = opts or {}
        opts.pain = 0
        opts.shakeX = 0
        opts.shakeY = 0
        -- A shorter maximum step keeps the spring from overshooting on low FPS.
        if not opts.maxLength then opts.maxLength = 45 end
        return original(mg, dt, opts)
    end
    hp._WSZCStabilized = true
    return hp
end

--- A dead/unconscious player must never be considered "in a minigame":
--- otherwise a session left open at death keeps the cursor, movement lock and
--- bind block alive forever and the player cannot respawn.  Headless tests
--- return a bare LocalPlayer() table with no Alive(), so default to true.
function WSZC.MinigameContextOK()
    local ply = LocalPlayer and LocalPlayer() or nil
    if type(ply) == "table" and type(ply.Alive) == "function" then
        local ok, alive = pcall(ply.Alive, ply)
        if ok and alive == false then return false end
    end
    return true
end

--- Only OUR namespaced WSZC bandage/syringe sessions get the full-screen
--- clip.  Native C:U games (shrapnel, dislocation, AED) use their own
--- 760 px clip; stretching it to the whole screen made their bone/hand
--- sprites ~2x too large and pushed the bone off the top of the screen.
function WSZC.WSZCMinigameActive()
    if not WSZC.MinigameContextOK() then return false end
    if WSZC.MinigameHUDOpen == true then return true end
    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    if bandage and bandage.IsActive and bandage.IsActive() then return true end
    if syringe and syringe.IsActive and syringe.IsActive() then return true end
    return false
end

function WSZC.NativeMinigameActive()
    if not WSZC.MinigameContextOK() then return false end
    -- Explicit checks: ipairs() stops at the first nil in a sparse table.
    local list = {
        "WoundSystemDislocationMinigame", "WoundSystemShrapnelMinigame",
        "WoundSystemAEDMinigame", "WoundSystemBandageMinigame",
        "WoundSystemSyringeMinigame",
    }
    for _, name in ipairs(list) do
        local mg = _G[name]
        if type(mg) == "table" and mg.active == true then return true end
    end
    return false
end

--- Is the full-screen layout requested, and is the render context ready?
function WSZC.MinigameFullscreen()
    return cvFullscreen:GetBool() == true and ScrW ~= nil and ScrH ~= nil and ScrW() > 0 and ScrH() > 0
end

--- Full-screen for C:U's own games too.  The old build deliberately kept
--- them in a 760 px square (and even shrank it 0.75x); the owner explicitly
--- asked for EVERY minigame to stretch to the whole screen on selection.
function WSZC.MinigameFullscreenNative()
    return WSZC.MinigameFullscreen() and cvFullscreenNative:GetBool() == true
end

--- Scale factor that makes the native board (820 px clip at 1080p) cover the
--- shorter screen edge.  Both C:U shrapnel and dislocation derive every draw
--- rect, SimToScreen/ScreenToSim and hitbox from Clip.Scale(), so scaling that
--- ONE value keeps the game playable instead of merely enlarging the backdrop.
function WSZC.NativeFullscreenK(base)
    base = math.max(tonumber(base) or 1, 0.01)
    local edge = math.min(ScrW(), ScrH())
    return math.Clamp(edge / (820 * base), 1, 2.2)
end

--- One scale used by BOTH minigames (replaces the many `Clip.Scale()` copies).
function WSZC.MinigameScale()
    local clip = WoundSystem and WoundSystem.MinigameClip
    local base = (clip and clip.Scale) and clip.Scale() or (ScrH() / 1080)
    return math.Clamp(tonumber(base) or 1, 0.1, 8) * (cvZoom and cvZoom:GetFloat() or 1)
end

local patchedClip, patchedOriginal, clipWrapper
local patchedScaleOriginal, scaleWrapper

--- Idempotent, re-applyable: C:U may rebuild its MinigameClip table on hot reload.
function WSZC.ApplyFullscreenClip()
    local clip = WoundSystem and WoundSystem.MinigameClip
    if type(clip) ~= "table" or type(clip.GetRect) ~= "function" then return false end
    if clip == patchedClip and clip.GetRect == clipWrapper
        and (type(clip.Scale) ~= "function" or clip.Scale == scaleWrapper) then return true end

    local original = (clip == patchedClip and patchedOriginal) or clip.GetRect
    if original == clipWrapper then return true end -- nothing to do
    patchedClip, patchedOriginal = clip, original

    clipWrapper = function()
        if WSZC.MinigameFullscreen()
            and (WSZC.WSZCMinigameActive()
                or (WSZC.MinigameFullscreenNative() and WSZC.NativeMinigameActive())) then
            -- x, y, w, h, corner radius.  Radius 0 makes Clip.Begin() fall back
            -- to a full-screen scissor rect instead of a stencil-masked square.
            return 0, 0, ScrW(), ScrH(), 0
        end
        local x, y, w, h, radius = original()
        if WSZC.NativeMinigameActive() and not WSZC.MinigameFullscreenNative() then
            -- Only when fullscreen_native is OFF: their bone and hand sprites
            -- are authored for a 760 px square, so keep the old shrink.
            local z = math.Clamp(cvNativeZoom:GetFloat(), 0.4, 1.2)
            local nw, nh = w * z, h * z
            return x + (w - nw) * 0.5, y + (h - nh) * 0.5, nw, nh, radius * z
        end
        return x, y, w, h, radius
    end
    clip.GetRect = clipWrapper

    -- C:U shrapnel / dislocation build their board, sprites, SimToScreen and
    -- ScreenToSim from Clip.Scale().  Growing ONLY the clip would leave a
    -- tiny game in the middle of a big black screen; growing this value too
    -- keeps every hitbox in step with what the player sees.
    if type(clip.Scale) == "function" and clip.Scale ~= scaleWrapper then
        patchedScaleOriginal = clip.Scale
        scaleWrapper = function()
            local base = patchedScaleOriginal()
            if WSZC.MinigameFullscreenNative() and WSZC.NativeMinigameActive() then
                return base * WSZC.NativeFullscreenK(base)
            end
            return base
        end
        clip.Scale = scaleWrapper
    end
    return true
end

-- C:U's client files may load after us.  Retry until the table exists, then
-- stop; EnsureOverlay() in both minigames also calls ApplyFullscreenClip().
hook.Add("Think", "WSZC_FullscreenClipInit", function()
    if WSZC.ApplyFullscreenClip() then
        hook.Remove("Think", "WSZC_FullscreenClipInit")
    end
end)

---------------------------------------------------------------------------
-- Adrenaline / painkiller visual clamp
---------------------------------------------------------------------------
-- C:U stores body.adrenaline as 0..100 and sets it to 100 on a gunshot.
-- ZCity's organism uses 0..2 and cl_camera.lua multiplies it by 5 when it
-- computes the FOV offset.  A raw 100 therefore produces a -500 FOV "tunnel"
-- with radial streaks and violent camera shake (the adrenaline screenshot).
-- The server-side delta is now scaled too; this client clamp also protects
-- organisms that were already written by an older build of the connector.
local ADRENALINE_MAX = 2
local PAINKILLER_MAX = 1

hook.Add("Think", "WSZC_ClampAdrenalineVisual", function()
    if not (cvClamp and cvClamp:GetBool()) then return end
    -- Only in organism-authoritative mode; in bridge mode C:U owns the shadow.
    if GetGlobalBool and GetGlobalBool("WSZC_OrganismAuthority", true) == false then return end
    local ply = LocalPlayer and LocalPlayer()
    if not (IsValid and IsValid(ply)) then return end
    local org = ply.organism
    if type(org) ~= "table" then return end

    local a = tonumber(org.adrenaline)
    if a and (a < 0 or a > ADRENALINE_MAX) then
        org.adrenaline = math.Clamp(a, 0, ADRENALINE_MAX)
    end
    local p = tonumber(org.painkiller)
    if p and (p < 0 or p > PAINKILLER_MAX) then
        org.painkiller = math.Clamp(p, 0, PAINKILLER_MAX)
    end
end)

---------------------------------------------------------------------------
-- C:U inventory + UNI-HEALTH ("unit") panel removal
---------------------------------------------------------------------------
-- The user runs ZCity SWEPs on the native ZCity inventory binds.  C:U draws
-- its own five slot panel inside WoundView, plus a 475x810 "UNI-HEALTH v2.03"
-- scanner on the left.  Both are suppressed at DRAW time only: WoundView
-- itself (the body doll, limb icons, FIX DISLOCATION / REMOVE SHRAPNEL action
-- button, tooltips and the cursor) stays fully functional.  Slot 6 is our
-- hidden virtual tool slot for ZCity SWEP minigames and is left intact.

local cvHideInventory = CreateClientConVar("zc_woundsystem_compat_hide_cu_inventory", "1", true, false,
    "1 = hide C:U's 5 inventory slots in WoundView (ZCity SWEPs own the slots); virtual slot 6 stays")
local cvHideUnitPanel = CreateClientConVar("zc_woundsystem_compat_hide_unit_panel", "1", true, false,
    "1 = hide the UNI-HEALTH / unit scanner panel inside C:U WoundView")

WSZC.CUHudFiltered = false
-- Set by WrapCUDeathScreen() only while C:U's death-screen HUDPaint hook runs:
-- every wrapped draw primitive becomes a no-op for that one call, while the
-- hook's respawn input handling keeps working.
WSZC.CUDeathVisualsHidden = false

--- Materials that belong to the DOLL, its status icons and the shrapnel /
--- dislocation action point.  The hidden regions below were sized for C:U's
--- original 760 px square; the unitmenu doll is wider, so its left arm, feet
--- and the "REMOVE SHRAPNEL" callout overlap them.  Hiding those draw calls
--- produced the chopped-off doll from the live screenshots.  We remember the
--- material set by surface.SetMaterial (see InstallMaterialTracker) and let
--- these specific textures through the filter.  Everything else - the green
--- scanner, UNI-HEALTH panel and the 5 inventory slots - stays hidden.
local DOLL_DRAW_MARKERS = {
    "wszc/unitmenu/limbs/", "wszc/unitmenu/status/",
    "casunknown-images/middle/", "casunknown-images/outlines/",
    "casunknown-images/icons/", "casunknown-images/screen/uipoint",
}
local function IsDollDrawMaterial(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower():gsub("\\", "/"):gsub("%.png$", "")
    for i = 1, #DOLL_DRAW_MARKERS do
        if lower:find(DOLL_DRAW_MARKERS[i], 1, true) then return true end
    end
    return false
end
WSZC.IsDollDrawMaterial = IsDollDrawMaterial

local function MaterialName(mat)
    if not mat or not mat.GetName then return nil end
    local ok, name = pcall(mat.GetName, mat)
    if ok and type(name) == "string" then return name end
    return nil
end
WSZC.MaterialName = MaterialName

--- Geometry copied from cl_health_gui.lua (WoundDollAndPanel, 1080p base).
--- Everything is expressed in ScrH()/1080 so it follows the game's own scale.
local function HiddenRegionRaw(x, y, w, h)
    if WSZC.CUDeathVisualsHidden == true then return true end
    if not WSZC.CUHudFiltered then return false end
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    w = tonumber(w) or 0
    h = tonumber(h) or 0
    local sw, sh = ScrW(), ScrH()
    -- cl_health_gui.lua uses (ScrH()/1080) * UIScale(), where UIScale() is
    -- woundsys_ui_scale clamped to 0.6..1.6.  Reading the same convar keeps
    -- the hidden regions aligned on non-default UI scales.
    local uiScale = 1
    local cvUIScale = GetConVar and GetConVar("woundsys_ui_scale") or nil
    if cvUIScale then uiScale = math.Clamp(cvUIScale:GetFloat(), 0.6, 1.6) end
    local s = (sh / 1080) * uiScale
    if sh <= 600 then s = s * 0.72 elseif sh <= 768 then s = s * 0.86 end

    -- A genuinely full-screen quad is the shared dark WoundView backdrop, not
    -- the scanner.  Keep it so the doll stays readable over the world.
    if w >= sw * 0.9 and h >= sh * 0.9 then return false end

    local function Overlap(bx, by, bw, bh)
        return x <= bx + bw and x + w >= bx and y <= by + bh and y + h >= by
    end

    -- Left scanner: panelX=20*s, panelW=475*s, panelY=20*s, panelH=810*s.
    -- Extra margin also covers the small "NANO" header above it.
    if cvHideUnitPanel:GetBool() and Overlap(0, 0, 560 * s, 900 * s) then
        return true
    end
    if not cvHideInventory:GetBool() then return false end

    -- The three lower slots, then the two upper (slot 4 = ZCity weapon) slots.
    local cx = sw / 2
    local cy = sh / 2 + 20 * s
    local size = 80 * s
    local startX = cx - 137 * s
    local margin = 24 * s
    local lowerY = cy + 275 * s
    local upperY = cy - 285 * s
    for i = 0, 2 do
        if Overlap(startX + i * 97 * s - margin, lowerY - margin,
                size + margin * 2, size + margin * 2) then return true end
    end
    if Overlap(cx - 255 * s - size - margin, upperY - margin,
            size + margin * 2, size + margin * 2) then return true end
    if Overlap(cx + 255 * s - margin, upperY - margin,
            size + margin * 2, size + margin * 2) then return true end
    return false
end

--- Textured primitives and text use the material whitelist: C:U sets the
--- material right before drawing a limb / status icon / uiPoint, and the
--- "REMOVE SHRAPNEL" label is drawn immediately after uiPoint with no new
--- SetMaterial.  Outline / filled-rect / line / poly primitives must NOT use
--- it: the five inventory slot frames are DrawOutlinedRect calls with NO
--- SetMaterial at all, so with a whitelist they inherited the last limb
--- texture and became visible again as empty white squares.  The action-point
--- black backing is also a filled rect -> hidden, while its text stays.
local function HiddenRegion(x, y, w, h)
    if WSZC.CUDeathVisualsHidden == true then return true end
    if IsDollDrawMaterial(WSZC._DrawMaterialName) then return false end
    return HiddenRegionRaw(x, y, w, h)
end
WSZC.CUHudHiddenRegion = HiddenRegion -- exported for headless tests
WSZC.CUHudHiddenRegionRaw = HiddenRegionRaw

local savedHudFn, hudWrapper
local drawWrappersInstalled = false
local localeWrapped, directWrapped = false, false

local function InstallDrawWrappers()
    if type(draw) ~= "table" or type(surface) ~= "table" then return false end

    -- Do NOT gate this on a C:U global (the previous build required
    -- WoundSystemQueueLocaleTooltip): on some C:U builds that helper is not
    -- exported, which left every draw wrapper uninstalled and the whole
    -- UNI-HEALTH panel / inventory visible.
    if not drawWrappersInstalled then
        local origText = draw.SimpleText
        draw.SimpleText = function(text, font, x, y, ...)
            if HiddenRegion(x, y) then return end
            return origText(text, font, x, y, ...)
        end

        local origTex = surface.DrawTexturedRect
        surface.DrawTexturedRect = function(x, y, w, h, ...)
            if HiddenRegion(x, y, w, h) then return end
            return origTex(x, y, w, h, ...)
        end

        if type(surface.DrawTexturedRectRotated) == "function" then
            local origRot = surface.DrawTexturedRectRotated
            surface.DrawTexturedRectRotated = function(x, y, w, h, ...)
                if HiddenRegion(x, y, w, h) then return end
                return origRot(x, y, w, h, ...)
            end
        end

        local origRect = surface.DrawRect
        surface.DrawRect = function(x, y, w, h, ...)
            if HiddenRegionRaw(x, y, w, h) then return end
            return origRect(x, y, w, h, ...)
        end

        -- The five slot FRAMES are outlines (cl_health_gui.lua:4899).  The
        -- previous release only wrapped filled rects/textures, so the empty
        -- squares stayed visible even with the inventory proxy installed.
        if type(surface.DrawOutlinedRect) == "function" then
            local origOutline = surface.DrawOutlinedRect
            surface.DrawOutlinedRect = function(x, y, w, h, ...)
                if HiddenRegionRaw(x, y, w, h) then return end
                return origOutline(x, y, w, h, ...)
            end
        end

        if type(draw.RoundedBox) == "function" then
            local origRound = draw.RoundedBox
            draw.RoundedBox = function(r, x, y, w, h, ...)
                if HiddenRegionRaw(x, y, w, h) then return end
                return origRound(r, x, y, w, h, ...)
            end
        end

        -- cl_health_gui.lua draws the green scanner bars / lung icons through
        -- DrawRectUVInt() -> surface.DrawTexturedRectUV(), the ECG through
        -- surface.DrawLine() and arcs through surface.DrawPoly().  Those three
        -- were NOT wrapped in the previous release, which is exactly why the
        -- green bars, lungs, bicep and ECG stayed on the left of WoundView
        -- while the panel background and its text disappeared.
        if type(surface.DrawTexturedRectUV) == "function" then
            local origUV = surface.DrawTexturedRectUV
            surface.DrawTexturedRectUV = function(x, y, w, h, ...)
                if HiddenRegion(x, y, w, h) then return end
                return origUV(x, y, w, h, ...)
            end
        end

        if type(surface.DrawLine) == "function" then
            local origLine = surface.DrawLine
            surface.DrawLine = function(x1, y1, x2, y2, ...)
                x1, y1 = tonumber(x1) or 0, tonumber(y1) or 0
                x2, y2 = tonumber(x2) or 0, tonumber(y2) or 0
                if HiddenRegionRaw(x1, y1) or HiddenRegionRaw(x2, y2)
                    or HiddenRegionRaw((x1 + x2) * 0.5, (y1 + y2) * 0.5) then return end
                return origLine(x1, y1, x2, y2, ...)
            end
        end

        if type(surface.DrawPoly) == "function" then
            local origPoly = surface.DrawPoly
            surface.DrawPoly = function(verts, ...)
                if type(verts) == "table" then
                    local minX, minY, maxX, maxY
                    for _, v in pairs(verts) do
                        if type(v) == "table" and type(v.x) == "number" and type(v.y) == "number" then
                            minX = (minX == nil) and v.x or math.min(minX, v.x)
                            minY = (minY == nil) and v.y or math.min(minY, v.y)
                            maxX = (maxX == nil) and v.x or math.max(maxX, v.x)
                            maxY = (maxY == nil) and v.y or math.max(maxY, v.y)
                        end
                    end
                    if minX and HiddenRegionRaw(minX, minY, maxX - minX, maxY - minY) then return end
                end
                return origPoly(verts, ...)
            end
        end

        -- Coordinate-less primitives: only suppressed while the C:U death
        -- screen hook is running; the ZCity HUD is untouched otherwise.
        if type(surface.DrawText) == "function" then
            local origDrawText = surface.DrawText
            surface.DrawText = function(...)
                if WSZC.CUDeathVisualsHidden == true then return end
                return origDrawText(...)
            end
        end
        if type(draw.SimpleTextOutlined) == "function" then
            local origOutlinedText = draw.SimpleTextOutlined
            draw.SimpleTextOutlined = function(text, font, x, y, ...)
                if HiddenRegion(x, y) then return end
                return origOutlinedText(text, font, x, y, ...)
            end
        end

        drawWrappersInstalled = true
    end

    -- These two globals belong to C:U and can arrive after us.  Retry them on
    -- every installer tick with their own flags, so a late C:U load still gets
    -- the tooltip filter without wrapping draw/surface twice.
    if not localeWrapped and type(WoundSystemQueueLocaleTooltip) == "function" then
        local origLocale = WoundSystemQueueLocaleTooltip
        WoundSystemQueueLocaleTooltip = function(key, x, y, w, h, ...)
            if HiddenRegion(x, y, w, h) then return end
            return origLocale(key, x, y, w, h, ...)
        end
        localeWrapped = true
    end

    if not directWrapped and type(WoundSystemQueueDirectTooltip) == "function" then
        local origDirect = WoundSystemQueueDirectTooltip
        WoundSystemQueueDirectTooltip = function(key, ...)
            if cvHideInventory:GetBool() and type(key) == "string"
                and string.sub(key, 1, 5) == "slot_" then return end
            return origDirect(key, ...)
        end
        directWrapped = true
    end

    return true
end
WSZC.InstallCUHudDrawWrappers = InstallDrawWrappers

local function InstallHudFilter()
    local hooks = hook.GetTable and hook.GetTable() or nil
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    if type(hud) ~= "table" then return false end
    local fn = hud.WoundDollAndPanel
    if type(fn) ~= "function" then return false end
    if fn == hudWrapper then return true end

    savedHudFn = fn
    hudWrapper = function(...)
        -- A minigame draws its own overlay.  Leaving WoundView behind it made
        -- the doll, FIX DISLOCATION label and tooltips appear stacked over the
        -- bone/hand ("too many reductions, all too high to click").
        if WSZC.WSZCMinigameActive() or WSZC.NativeMinigameActive() then return end
        if not (cvHideUnitPanel:GetBool() or cvHideInventory:GetBool()) then
            return fn(...)
        end
        local prevFiltered = WSZC.CUHudFiltered
        WSZC.CUHudFiltered = true
        local ok, a, b, c = pcall(fn, ...)
        WSZC.CUHudFiltered = prevFiltered
        if not ok then error(a, 0) end
        return a, b, c
    end
    -- hook.Add with the SAME event+identifier is the supported way to replace
    -- a hook.  Writing directly into the table returned by hook.GetTable()
    -- silently did nothing on builds where that table is a defensive copy,
    -- which is why UNI-HEALTH and the slots survived the previous release.
    hook.Add("HUDPaint", "WoundDollAndPanel", hudWrapper)
    return true
end
WSZC.InstallCUHudFilter = InstallHudFilter

-- Independent second line of defence: even if C:U re-registers its HUDPaint
-- hook under another identifier, the draw wrappers stay active for the whole
-- HUD frame while WoundView is open.  PostDrawHUD always clears the flag so
-- ZCity's own HUD is never affected.
local function CUHudFilterEnabled()
    -- Only used when the C:U hook could not be wrapped.  A whole-HUD-frame
    -- filter would otherwise also swallow ZCity HUD elements that happen to
    -- sit in the same screen regions.
    if WSZC.CUHudUseFallback ~= true then return false end
    if not (cvHideUnitPanel:GetBool() or cvHideInventory:GetBool()) then return false end
    if WoundSystemHealthHUDOpen ~= true then return false end
    if WSZC.WSZCMinigameActive() or WSZC.NativeMinigameActive() then return false end
    return true
end
WSZC.CUHudFilterEnabled = CUHudFilterEnabled

hook.Add("PreDrawHUD", "WSZC_CUHudFilterPre", function()
    if CUHudFilterEnabled() then WSZC.CUHudFiltered = true end
end)
hook.Add("PostDrawHUD", "WSZC_CUHudFilterPost", function()
    WSZC.CUHudFiltered = false
end)

local function InstallInventoryProxy()
    if type(WoundSystemInventorySlots) ~= "table" then return false end
    if WoundSystemInventorySlots == WSZC._CUInventoryProxy then return true end

    local real = WoundSystemInventorySlots
    local proxy = setmetatable({}, {
        __index = function(_, key)
            if key == 6 then return rawget(real, 6) end
            if type(key) == "number" and key >= 1 and key <= 5 then
                -- A fresh table per lookup: C:U must never mutate a shared
                -- placeholder or write a tool back into a hidden slot.
                return { type = "empty" }
            end
            return rawget(real, key)
        end,
        __newindex = function(_, key, value)
            if type(key) == "number" and key >= 1 and key <= 5 then return end
            rawset(real, key, value)
        end,
    })
    WoundSystemInventorySlots = proxy
    WSZC._CUInventoryProxy = proxy
    WSZC._CURealInventory = real
    return true
end
WSZC.InstallCUInventoryProxy = InstallInventoryProxy

local REMOVED_INVENTORY_HOOKS = {
    { "PlayerBindPress", "WoundSystem_WorldItemInput" },
    { "Think", "WoundSystem_WorldItemCheck" },
    { "DrawOverlay", "WoundSystem_WorldItemDraw" },
    { "Think", "WoundSystem_BodyUseHeldItemInput" },
}

local function DisableCUInventoryInput()
    if not cvHideInventory:GetBool() then return end
    if WoundSystem and WoundSystem.Client then
        WoundSystem.Client.RequestInventoryMove = function() end
    end
    for _, entry in ipairs(REMOVED_INVENTORY_HOOKS) do
        hook.Remove(entry[1], entry[2])
    end
    if WoundSystemDragState then WoundSystemDragState.active = false end
    if WoundSystemWorldDrag then WoundSystemWorldDrag.active = false end
end
WSZC.DisableCUInventoryInput = DisableCUInventoryInput

-- C:U client files may load after us, and hot-reload re-registers their hooks.
-- Re-apply idempotently once a second; each installer is a cheap no-op when
-- already done.
WSZC.NextCUInventoryInstall = 0
hook.Add("Think", "WSZC_CUInventoryLayout", function()
    local now = CurTime and CurTime() or 0
    if now < (WSZC.NextCUInventoryInstall or 0) then return end
    WSZC.NextCUInventoryInstall = now + 1
    -- The material tracker must exist even when the hide convars are off: it
    -- is what keeps the doll / status icons out of HiddenRegion().
    WSZC.InstallMaterialTracker()
    if not (cvHideInventory:GetBool() or cvHideUnitPanel:GetBool()) then return end
    InstallDrawWrappers()
    -- If C:U's HUDPaint hook is missing/renamed, fall back to a whole-frame
    -- draw filter instead of leaving the panel visible.
    WSZC.CUHudUseFallback = not InstallHudFilter()
    if cvHideInventory:GetBool() then
        InstallInventoryProxy()
        DisableCUInventoryInput()
    end
end)


---------------------------------------------------------------------------
-- WoundView doll + minigame hand, built from "для переделывания интерфейса.zip"
---------------------------------------------------------------------------
-- The repository archive ships 15 pre-positioned 1500x1500 RGBA limb layers
-- (zcity_delta/unitmenu/limbs), three pixel status icons and nine realistic
-- hand frames (homigrad/handanim).  Stock C:U/ZCity Lua never references them,
-- so this connector installs them at runtime:
--   * C:U's `Limbs` upvalue (WoundDollAndPanel) is MUTATED IN PLACE: new
--     fill/outline materials + ox/oy/size/sourceW/sourceH.  Hover hitboxes,
--     limb selection, status icons, "FIX DISLOCATION" and the shrapnel action
--     point keep working because they all read the same Limbs table.
--   * Icons.fracture / fracture2 / dislocate / *bleed* are swapped for the
--     archive's pixel icons (Icons is a global table).
--   * WSZC bandage/syringe use hand.png (open palm) and 3_3.png (fist) instead
--     of the 512x1260 C:U silhouettes; native C:U minigames get the same swap
--     through a narrow surface.SetMaterial wrapper.
-- The cropped PNGs are generated by tools/build_unitmenu_materials.py and live
-- in materials/wszc/unitmenu/.  Nothing inside the original ZIPs is modified.

local cvUnitmenuDoll = CreateClientConVar("zc_woundsystem_compat_unitmenu_doll", "1", true, false,
    "1 = rebuild the WoundView doll from the repository unitmenu limb layers")
local cvDollScale = CreateClientConVar("zc_woundsystem_compat_unitmenu_scale", "0.24", true, false,
    "Size of the unitmenu doll relative to C:U's dollScale (0.1 .. 0.8)", 0.1, 0.8)
local cvHandanim = CreateClientConVar("zc_woundsystem_compat_handanim", "1", true, false,
    "1 = use the repository handanim frames instead of the 512x1260 C:U hand")
local cvHandanimScale = CreateClientConVar("zc_woundsystem_compat_handanim_scale", "0.55", true, false,
    "Size of the realistic minigame hand (0.2 .. 1.5)", 0.2, 1.5)

WSZC.UnitmenuHandSrcW = 960
WSZC.UnitmenuHandSrcH = 540

local unitmenuMats, unitmenuIcons = nil, nil
local handIdleMat, handClickMat, handMatsChecked = nil, nil, false

--- Materials shipped inside this connector (self-contained; the WIP addon is
--- not required for the doll).
local function BuildUnitmenuMaterials()
    if unitmenuMats then return unitmenuMats end
    local geo = _G.WSZC_UNITMENU_LIMB_GEOMETRY
    if type(geo) ~= "table" then return nil end
    local built = {}
    local count = 0
    for id, g in pairs(geo) do
        if type(id) == "string" and type(g) == "table" and g.cx and g.cy and g.w and g.h then
            local fill = Material("wszc/unitmenu/limbs/" .. id .. "_fill.png", "smooth noclamp")
            local edge = Material("wszc/unitmenu/limbs/" .. id .. "_edge.png", "smooth noclamp")
            if fill:IsError() or edge:IsError() then return nil end
            built[id] = { fill = fill, edge = edge, cx = g.cx, cy = g.cy, w = g.w, h = g.h }
            count = count + 1
        end
    end
    if count < 15 then return nil end
    unitmenuMats = built
    return unitmenuMats
end
WSZC.BuildUnitmenuMaterials = BuildUnitmenuMaterials

local function BuildUnitmenuIcons()
    if unitmenuIcons then return unitmenuIcons end
    local function mat(name)
        local m = Material("wszc/unitmenu/status/" .. name .. ".png")
        if m:IsError() then return nil end
        return m
    end
    local bleeding, dislocation, fracture = mat("bleeding"), mat("dislocation"), mat("fracture")
    if not (bleeding and dislocation and fracture) then return nil end
    unitmenuIcons = {
        fracture = fracture, fracture2 = fracture, dislocate = dislocation,
        smallbleed = bleeding, smallbleed_bandaged = bleeding,
        midbleed = bleeding, midbleed_bandaged = bleeding,
        strongbleed = bleeding, strongbleed_bandaged = bleeding,
        extremebleed = bleeding, extremebleed_bandaged = bleeding,
    }
    return unitmenuIcons
end
WSZC.BuildUnitmenuIcons = BuildUnitmenuIcons

--- The hand frames are bundled into THIS addon under materials/homigrad/
--- handanim/ by tools/pack_ui_materials.py, together with the full
--- casunknown-images/ set.  The connector no longer depends on the WIP
--- addon, on Workshop materials or on files copied in by hand.  If the
--- frames are ever missing we silently keep C:U's original hand sprites.
local function UnitmenuHandMaterials()
    if not cvHandanim:GetBool() then return nil end
    if handMatsChecked then return handIdleMat end
    if not (file and file.Exists) then return nil end
    if not file.Exists("materials/homigrad/handanim/hand.png", "GAME") then return nil end
    local idle = Material("homigrad/handanim/hand.png", "smooth noclamp")
    local click = Material("homigrad/handanim/3_3.png", "smooth noclamp")
    if idle:IsError() then return nil end
    handIdleMat = idle
    handClickMat = (click and not click:IsError()) and click or idle
    handMatsChecked = true
    return handIdleMat
end

--- clicked = true selects the fist frame, false the open palm.
function WSZC.UnitmenuHandMat(clicked)
    local idle = UnitmenuHandMaterials()
    if not idle then return nil end
    return clicked and handClickMat or idle
end

--- Geometry for OUR bandage/syringe copies.  `scale` already contains the
--- per-minigame handScale; the archive hand is horizontal, so its pivot is at
--- the fingertips (left edge, vertical middle) instead of C:U's (0.4, 0.1).
function WSZC.UnitmenuHandGeometry(srcW, srcH, scale)
    scale = tonumber(scale) or 1
    if UnitmenuHandMaterials() then
        local k = math.Clamp(cvHandanimScale:GetFloat(), 0.2, 1.5)
        return (WSZC.UnitmenuHandSrcW * scale * k), (WSZC.UnitmenuHandSrcH * scale * k), 0.12, 0.5
    end
    return (srcW * scale), (srcH * scale), 0.4, 0.1
end

function WSZC.UnitmenuHandAlpha(fallback)
    return UnitmenuHandMaterials() and 255 or (fallback or 153)
end

--- C:U rotates its tall hand by up to 290 degrees.  A horizontal hand only
--- needs the small velocity-driven tilt from HandPhysics.Rotation.
function WSZC.UnitmenuHandAngle(angle)
    angle = tonumber(angle) or 0
    return UnitmenuHandMaterials() and (angle * 0.25) or angle
end
WSZC.UnitmenuHandActive = function() return UnitmenuHandMaterials() ~= nil end

---------------------------------------------------------------------------
-- Locate C:U's private `Limbs` table without editing cl_health_gui.lua.
---------------------------------------------------------------------------
local function IsCULimbsTable(t)
    if type(t) ~= "table" or #t < 10 then return false end
    for i = 1, #t do
        local limb = t[i]
        if type(limb) ~= "table" or type(limb.id) ~= "string"
            or limb.matM == nil or limb.matO == nil
            or type(limb.ox) ~= "number" or type(limb.oy) ~= "number" then
            return false
        end
    end
    return true
end

--- hook.Add("HUDPaint", "WoundDollAndPanel") may have been replaced by our own
--- hudWrapper, so walk the upvalue chain (bounded, cycle-safe) to reach the
--- original C:U closure that owns `Limbs`.
local function FindCULimbs()
    if not (debug and debug.getupvalue and hook and hook.GetTable) then return nil end
    local hooks = hook.GetTable()
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    local fn = type(hud) == "table" and hud.WoundDollAndPanel or nil
    if type(fn) ~= "function" then return nil end
    local seen = {}
    local function walk(f, depth)
        if type(f) ~= "function" or depth > 4 or seen[f] then return nil end
        seen[f] = true
        local i = 1
        while true do
            local name, value = debug.getupvalue(f, i)
            if not name then break end
            if type(value) == "table" and IsCULimbsTable(value) then return value end
            if type(value) == "function" then
                local found = walk(value, depth + 1)
                if found then return found end
            end
            i = i + 1
        end
        return nil
    end
    return walk(fn, 0)
end
WSZC.FindCULimbs = FindCULimbs

local dollPatched = false

local function ApplyDoll(limbs, mats, k)
    for _, limb in ipairs(limbs) do
        local g = mats[limb.id]
        if g then
            if not limb._WSZCUnitmenuOriginal then
                limb._WSZCUnitmenuOriginal = {
                    matM = limb.matM, matO = limb.matO,
                    ox = limb.ox, oy = limb.oy, size = limb.size,
                    sourceW = limb.sourceW, sourceH = limb.sourceH,
                    texturePadding = limb.texturePadding, flip = limb.flip,
                }
            end
            limb.matM = g.fill
            limb.matO = g.edge
            limb.ox = (g.cx - 750) * k
            limb.oy = (g.cy - 750) * k
            limb.size = k
            limb.sourceW = g.w
            limb.sourceH = g.h
            limb.texturePadding = 0
            -- The archive layers are already mirrored; C:U's flip would mirror
            -- them a second time.
            limb.flip = false
        end
    end
end
WSZC.ApplyUnitmenuDoll = ApplyDoll

function WSZC.RestoreUnitmenuDoll()
    local limbs = FindCULimbs()
    if not limbs then return false end
    for _, limb in ipairs(limbs) do
        local orig = limb._WSZCUnitmenuOriginal
        if orig then
            for key, value in pairs(orig) do limb[key] = value end
            limb._WSZCUnitmenuOriginal = nil
        end
    end
    dollPatched = false
    return true
end

local function ApplyUnitmenuIcons()
    local icons = _G.Icons
    if type(icons) ~= "table" or icons._WSZCUnitmenuPatched then return false end
    local built = BuildUnitmenuIcons()
    if not built then return false end
    for key, mat in pairs(built) do icons[key] = mat end
    icons._WSZCUnitmenuPatched = true
    return true
end
WSZC.ApplyUnitmenuIcons = ApplyUnitmenuIcons

---------------------------------------------------------------------------
-- Native C:U minigames (shrapnel / dislocation / AED / C:U bandage+syringe)
-- keep their own code in the untouched ZIP.  Swap only their grasp-hand
-- material and the rectangle it is drawn into; MG.handDrawW/H (and therefore
-- every hitbox) stay exactly as C:U computed them.
---------------------------------------------------------------------------
local nativeHandInstalled, handSwap = false, false
local materialTrackerInstalled = false
local origSetMaterial, origRectRotated, origTexturedRect

--- Installed unconditionally (not only when handanim is enabled): the HUD
--- filter needs the current material to decide whether a draw call belongs to
--- the doll or to the scanner.  C:U's SetGuiMaterial() calls surface.SetMaterial
--- directly, so this one wrapper sees every UI texture.
--- WSZC._OnSetMaterial is an optional hook used by the native hand override;
--- it may return a replacement material.
function WSZC.InstallMaterialTracker()
    if materialTrackerInstalled then return true end
    if type(surface) ~= "table" or type(surface.SetMaterial) ~= "function" then return false end
    origSetMaterial = surface.SetMaterial
    surface.SetMaterial = function(mat)
        WSZC._DrawMaterialName = MaterialName(mat)
        local name = WSZC._DrawMaterialName
        if WSZC._OnSetMaterial then
            local ok, repl = pcall(WSZC._OnSetMaterial, mat, name)
            if ok and repl then
                mat = repl
                WSZC._DrawMaterialName = MaterialName(mat)
            end
        end
        return origSetMaterial(mat)
    end
    materialTrackerInstalled = true
    return true
end
local InstallMaterialTracker = WSZC.InstallMaterialTracker

local function CUHandKind(mat)
    if not mat or not mat.GetName then return nil end
    local ok, name = pcall(mat.GetName, mat)
    if not ok or type(name) ~= "string" then return nil end
    name = name:lower():gsub("%.png$", "")
    if not name:find("handgrasp", 1, true) then return nil end
    if name:find("click", 1, true) then return true end
    if name:find("idle", 1, true) then return false end
    return nil
end
WSZC.CUHandKind = CUHandKind

function WSZC.InstallNativeHandOverride()
    if nativeHandInstalled then return true end
    if not (surface and surface.DrawTexturedRectRotated and surface.DrawTexturedRect) then return false end
    if not InstallMaterialTracker() then return false end
    origRectRotated = surface.DrawTexturedRectRotated
    origTexturedRect = surface.DrawTexturedRect

    WSZC._OnSetMaterial = function(mat)
        handSwap = false
        if cvHandanim:GetBool() and UnitmenuHandMaterials()
            and WSZC.NativeMinigameActive and WSZC.NativeMinigameActive() then
            local clicked = CUHandKind(mat)
            if clicked ~= nil then
                local repl = WSZC.UnitmenuHandMat(clicked)
                if repl then
                    handSwap = true
                    return repl
                end
            end
        end
        return nil
    end

    local function reshape(x, y, w, h)
        if not handSwap then return x, y, w, h end
        local k = math.Clamp(cvHandanimScale:GetFloat(), 0.2, 1.5)
        -- 512x1260 -> 960x540 keeps the same visual scale factor as our own
        -- minigames.  Only the DRAW call changes, never MG.handDrawW/H.
        return x, y, w * (960 / 512) * k, h * (540 / 1260) * k
    end

    surface.DrawTexturedRectRotated = function(x, y, w, h, rot, ...)
        if handSwap then
            local nx, ny, nw, nh = reshape(x, y, w, h)
            handSwap = false
            return origRectRotated(nx, ny, nw, nh, 0, ...)
        end
        return origRectRotated(x, y, w, h, rot, ...)
    end
    surface.DrawTexturedRect = function(x, y, w, h, ...)
        if handSwap then
            local nx, ny, nw, nh = reshape(x, y, w, h)
            handSwap = false
            return origTexturedRect(nx, ny, nw, nh, ...)
        end
        return origTexturedRect(x, y, w, h, ...)
    end
    nativeHandInstalled = true
    return true
end

WSZC.NextUnitmenuInstall = 0
hook.Add("Think", "WSZC_UnitmenuVisuals", function()
    local now = CurTime and CurTime() or 0
    if now < (WSZC.NextUnitmenuInstall or 0) then return end
    WSZC.NextUnitmenuInstall = now + 1
    WSZC.InstallMaterialTracker()

    if cvUnitmenuDoll:GetBool() then
        local mats = BuildUnitmenuMaterials()
        if mats then
            local limbs = FindCULimbs()
            if limbs then
                ApplyDoll(limbs, mats, math.Clamp(cvDollScale:GetFloat(), 0.1, 0.8))
                dollPatched = true
            end
            ApplyUnitmenuIcons()
        end
    elseif dollPatched then
        WSZC.RestoreUnitmenuDoll()
    end
    if cvHandanim:GetBool() then WSZC.InstallNativeHandOverride() end
end)
