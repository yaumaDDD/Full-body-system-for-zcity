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
    "Size of native C:U shrapnel / dislocation minigames (0.4 .. 1.2)", 0.4, 1.2)
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

--- Only OUR namespaced WSZC bandage/syringe sessions get the full-screen
--- clip.  Native C:U games (shrapnel, dislocation, AED) use their own
--- 760 px clip; stretching it to the whole screen made their bone/hand
--- sprites ~2x too large and pushed the bone off the top of the screen.
function WSZC.WSZCMinigameActive()
    if WSZC.MinigameHUDOpen == true then return true end
    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    if bandage and bandage.IsActive and bandage.IsActive() then return true end
    if syringe and syringe.IsActive and syringe.IsActive() then return true end
    return false
end

function WSZC.NativeMinigameActive()
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

--- One scale used by BOTH minigames (replaces the many `Clip.Scale()` copies).
function WSZC.MinigameScale()
    local clip = WoundSystem and WoundSystem.MinigameClip
    local base = (clip and clip.Scale) and clip.Scale() or (ScrH() / 1080)
    return math.Clamp(tonumber(base) or 1, 0.1, 8) * (cvZoom and cvZoom:GetFloat() or 1)
end

local patchedClip, patchedOriginal, clipWrapper

--- Idempotent, re-applyable: C:U may rebuild its MinigameClip table on hot reload.
function WSZC.ApplyFullscreenClip()
    local clip = WoundSystem and WoundSystem.MinigameClip
    if type(clip) ~= "table" or type(clip.GetRect) ~= "function" then return false end
    if clip == patchedClip and clip.GetRect == clipWrapper then return true end

    local original = (clip == patchedClip and patchedOriginal) or clip.GetRect
    if original == clipWrapper then return true end -- nothing to do
    patchedClip, patchedOriginal = clip, original

    clipWrapper = function()
        if WSZC.MinigameFullscreen() and WSZC.WSZCMinigameActive() then
            -- x, y, w, h, corner radius.  Radius 0 makes Clip.Begin() fall back
            -- to a full-screen scissor rect instead of a stencil-masked square.
            return 0, 0, ScrW(), ScrH(), 0
        end
        local x, y, w, h, radius = original()
        if WSZC.NativeMinigameActive() then
            -- C:U's own games additionally get a smaller clip: their bone and
            -- hand sprites are authored for a 760 px square, and at full size
            -- the dislocation bone sits too high to click.
            local z = math.Clamp(cvNativeZoom:GetFloat(), 0.4, 1.2)
            local nw, nh = w * z, h * z
            return x + (w - nw) * 0.5, y + (h - nh) * 0.5, nw, nh, radius * z
        end
        return x, y, w, h, radius
    end
    clip.GetRect = clipWrapper
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

--- Geometry copied from cl_health_gui.lua (WoundDollAndPanel, 1080p base).
--- Everything is expressed in ScrH()/1080 so it follows the game's own scale.
local function HiddenRegion(x, y, w, h)
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
WSZC.CUHudHiddenRegion = HiddenRegion -- exported for headless tests

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
            if HiddenRegion(x, y, w, h) then return end
            return origRect(x, y, w, h, ...)
        end

        -- The five slot FRAMES are outlines (cl_health_gui.lua:4899).  The
        -- previous release only wrapped filled rects/textures, so the empty
        -- squares stayed visible even with the inventory proxy installed.
        if type(surface.DrawOutlinedRect) == "function" then
            local origOutline = surface.DrawOutlinedRect
            surface.DrawOutlinedRect = function(x, y, w, h, ...)
                if HiddenRegion(x, y, w, h) then return end
                return origOutline(x, y, w, h, ...)
            end
        end

        if type(draw.RoundedBox) == "function" then
            local origRound = draw.RoundedBox
            draw.RoundedBox = function(r, x, y, w, h, ...)
                if HiddenRegion(x, y, w, h) then return end
                return origRound(r, x, y, w, h, ...)
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

