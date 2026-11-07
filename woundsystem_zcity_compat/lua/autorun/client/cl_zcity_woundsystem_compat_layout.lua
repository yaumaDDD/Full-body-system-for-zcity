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
local cvZoom = CreateClientConVar("zc_woundsystem_compat_minigame_zoom", "0.85", true, false,
    "Extra size multiplier for the WSZC minigames (0.7 .. 1.8)", 0.7, 1.8)
local cvClamp = CreateClientConVar("zc_woundsystem_compat_clamp_adrenaline", "1", true, false,
    "1 = clamp the shadow organism's adrenaline/painkiller so ZCity camera FX stay sane")
local cvNativeZoom = CreateClientConVar("zc_woundsystem_compat_native_minigame_zoom", "0.85", true, false,
    "Size of native C:U minigames when fullscreen_native is 0 (0.4 .. 1.2)", 0.4, 1.2)
-- Live regression (Screenshot_2-8): fullscreen_native=1 multiplied Clip.Scale()
-- by NativeFullscreenK, so a 26x138 shrapnelpiece.png was stretched into a
-- cropped black/orange vertical slab and the wound's lower half was pushed
-- off-screen ("I'm giving birth to a shrapnel, where's the bottom part?").
-- Keep C:U's own board geometry by default; fullscreen stays available for the
-- two WSZC minigames that were authored for it.
local cvFullscreenNative = CreateClientConVar("zc_woundsystem_compat_fullscreen_native", "0", true, false,
    "0 = keep native C:U shrapnel / dislocation / AED at their authored 760 px size; 1 = stretch them fullscreen")
local cvHandScale = CreateClientConVar("zc_woundsystem_compat_hand_cursor_scale", "0.55", true, false,
    "Shared minigame hand scale; 0.55 = compact human hand (0.2 .. 1)", 0.2, 1)
local cvHideMinigameText = CreateClientConVar("zc_woundsystem_compat_hide_minigame_text", "1", true, false,
    "1 = remove every header / instruction / exit-hint text and dark panel in all minigames")
local cvCloseEmptyClick = CreateClientConVar("zc_woundsystem_compat_close_on_empty_click", "1", true, false,
    "1 = close WoundView when left-clicking an empty area outside the doll, slots and action point")

--- Shared visual multiplier for the huge C:U hand sprites (512x1260).
--- WSZC applies it in HandCursorScale(); the native override applies the SAME
--- value in HandDrawSize(), so bandage, syringe and extraction stay identical.
function WSZC.HandCursorScale()
    return cvHandScale and cvHandScale:GetFloat() or 0.55
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
        -- Do NOT force `opts.maxLength` here.  The old 45 (vs C:U's 75) was
        -- a second cap on how far the hand could travel per step - combined
        -- with the zeroed mouse delta it made the bandage hand feel frozen.
        -- C:U's own maxLength/scale now governs the spring normally.
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
    if ply and ply.Alive then
        local ok, alive = pcall(ply.Alive, ply)
        if ok and alive == false then return false end
    end
    if ply then
        if ply.GetNWBool then
            local ok, unconscious = pcall(ply.GetNWBool, ply, "WoundSystemUnconscious", false)
            if ok and unconscious == true then return false end
        end
        -- FakeRagdoll / org.fake describe BODY posture, not operator
        -- incapacity.  ZCity also supports conscious ragdoll movement and
        -- medical use; treating those flags as unconscious closed every game.
        local org = ply.organism
        if type(org) == "table" then
            if org.otrub == true or org.needotrub == true then return false end
            local consciousness = tonumber(org.consciousness)
            if consciousness and consciousness < 0.4 then return false end
        end
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
        "WoundSystemSyringeMinigame", "WoundSystemSelfHarmMinigame",
    }
    for _, name in ipairs(list) do
        local mg = _G[name]
        if type(mg) == "table" and mg.active == true then return true end
    end
    return false
end

--- True only while a minigame is actually running.  Used by the text filter
--- so ZCity/C:U HUD text outside minigames is never touched.
function WSZC.MinigameTextHidden()
    if not cvHideMinigameText:GetBool() then return false end
    if WSZC.WSZCMinigameActive and WSZC.WSZCMinigameActive() then return true end
    if WSZC.NativeMinigameActive and WSZC.NativeMinigameActive() then return true end
    return false
end

--- All text belonging to a minigame is suppressed: the three CHROME fonts
--- (header / guide / exit hint) plus AED's own WoundSystemAEDStatus status
--- label, which the owner explicitly included in "text = all".
--- Everything else is preserved: ZCity notifications use BerserkFont /
--- HuyFont / SmallHuyFont / ZB_ProotOSMedium, C:U status labels use
--- TechScanner* / CrunchyTech*, the red death text uses its own font.
--- The wrapper additionally checks MinigameTextHidden(), so no HUD text
--- outside an active minigame can ever be swallowed.
--- WoundSystemGetFont() appends "_<scale>" to these base names at runtime,
--- so we strip that suffix before matching.
local MINIGAME_TEXT_BASES = {
    RetroTooltipTitle = true, RetroTooltipDesc = true,
    RetroMinigameGuide = true,
    WoundSystemAEDStatus = true,
}
function WSZC.IsMinigameTextFont(font)
    if type(font) ~= "string" then return false end
    local base = font:match("^(.-)_%d+$") or font
    return MINIGAME_TEXT_BASES[base] == true
end

--- `minigameshrapnel.png` is NOT a black UI panel: cl_shrapnel.lua:421 and
--- cl_syringe.lua:540 draw it as the FRONT LAYER OF THE WOUND, over the lower
--- half of the tweezers / shrapnel piece.  Suppressing it in 6e2196f deleted
--- "the bottom part the shard comes out of" from the live screenshot.  It is
--- now a PROTECTED gameplay sprite, never a filtered board.
local MINIGAME_WOUND_MARKER = "minigameshrapnel"
function WSZC.IsMinigameWoundLayer(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower():gsub("\\", "/"):gsub("%.png$", "")
    return lower:find(MINIGAME_WOUND_MARKER, 1, true) ~= nil
end
WSZC.IsMinigameBoardMaterial = WSZC.IsMinigameWoundLayer -- compatibility alias

--- Every texture that belongs to minigame PLAY must survive the HUD filter:
--- wound front layer, shrapnel pieces, hand, tweezers, bandage circle, blood
--- drops, white status icons.  `text=all` may only remove headers, guides,
--- counters and dark chrome panels - never gameplay sprites or the hand.
local MINIGAME_GAMEPLAY_MARKERS = {
    "minigameshrapnel", "shrapnelpiece", "bandageouter", "bandagecircle",
    "bandagestick", "bandageroll", "handgrasp", "tweezers", "pin",
    "casunknown-images/icons/", "uipoint", "minigame",
}
function WSZC.IsMinigameGameplaySprite(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower():gsub("\\", "/"):gsub("%.png$", "")
    for i = 1, #MINIGAME_GAMEPLAY_MARKERS do
        if lower:find(MINIGAME_GAMEPLAY_MARKERS[i], 1, true) then return true end
    end
    return false
end

--- Every C:U / WSZC minigame draws its chrome through three shared Clip
--- functions.  We do NOT edit any addon file:
---   * DrawHeader -> re-called with an empty title / value / guide and
---     panelAlpha 0.  That removes "Shrapnel extraction (1/5)", the three
---     instruction lines and the black top bar, while KEEPING the minigame
---     icon (the owner explicitly forbade deleting icons).
---   * DrawExitGuide -> no-op ("Press RMB/ESC to exit").
---   * DrawBackdrop  -> KEPT.  The owner explicitly wants the dark backdrop
---     behind every minigame again ("во всех мини играх было затемнение
---     заднего фона как раньше").  It is wrapped ONLY to (a) stamp the frame
---     as "a minigame is painting" and (b) whitelist its draw.RoundedBox
---     calls past HiddenRegionRaw(), which otherwise eats them as WoundView
---     chrome.  Suppressing it here was the reason the world stayed bright.
--- The shrapnel pieces, wound board, bone, white fracture icons, red drops,
--- status labels and ZCity notifications are all drawn by other calls and stay.
---
--- A font-scoped text wrapper is the second line of defence: AED's local
--- DrawCenteredStatusText calls draw.SimpleText directly with
--- WoundSystemAEDStatus, which is now also a suppressed minigame font.
--- Only MINIGAME fonts are swallowed, and only while a minigame is active;
--- ZCity notifications, the red death text and all other HUD text survive.
local clipTextWrapped, drawTextWrapped = false, false
function WSZC.InstallMinigameTextFilter()
    local clip = WoundSystem and WoundSystem.MinigameClip
    if type(clip) == "table" and not clipTextWrapped then
        if type(clip.DrawHeader) == "function" then
            local orig = clip.DrawHeader
            clip._WSZCOrigDrawHeader = orig
            clip.DrawHeader = function(data)
                if not WSZC.MinigameTextHidden() then return orig(data) end
                local clean = {}
                if type(data) == "table" then
                    for k, v in pairs(data) do clean[k] = v end
                end
                clean.title, clean.value, clean.guide = "", "", ""
                clean.panelAlpha = 0
                return orig(clean)
            end
        end
        for _, name in ipairs({"DrawExitGuide"}) do
            if type(clip[name]) == "function" then
                local orig = clip[name]
                clip["_WSZCOrig" .. name] = orig
                clip[name] = function(...)
                    if WSZC.MinigameTextHidden() then return end
                    return orig(...)
                end
            end
        end
        -- Restore the shared dark backdrop.  Every C:U minigame (bandage,
        -- syringe, shrapnel, dislocation, AED, selfharm) calls it; our old
        -- no-op made the world visible behind the board.  The flag also lets
        -- HiddenRegionRaw() pass its draw.RoundedBox through untouched.
        if type(clip.DrawBackdrop) == "function" and not clip._WSZCBackdropWrapped then
            local origBackdrop = clip.DrawBackdrop
            clip._WSZCOrigDrawBackdrop = origBackdrop
            clip._WSZCBackdropWrapped = true
            clip.DrawBackdrop = function(data)
                WSZC._LastMinigameDraw = (CurTime and CurTime()) or 0
                WSZC._MinigameBackdropDrawing = true
                local ok, a, b = pcall(origBackdrop, data)
                WSZC._MinigameBackdropDrawing = false
                if not ok then
                    ErrorNoHalt("[ZCity/CU compat] minigame backdrop failed: " .. tostring(a) .. "\n")
                    return
                end
                return a, b
            end
        end
        clipTextWrapped = true
    end
    if type(draw) == "table" and not drawTextWrapped then
        for _, name in ipairs({"SimpleText", "SimpleTextOutlined", "DrawText"}) do
            if type(draw[name]) == "function" then
                local orig = draw[name]
                draw[name] = function(text, font, ...)
                    if WSZC.MinigameTextHidden() and WSZC.IsMinigameTextFont(font) then return end
                    return orig(text, font, ...)
                end
            end
        end
        drawTextWrapped = true
    end
    return clipTextWrapped
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
            if WSZC.NativeMinigameActive() and not WSZC.MinigameFullscreenNative() then
                -- GetRect() above shrinks the clipping frame.  Scale the game
                -- coordinate system too, otherwise only the border gets smaller
                -- while sprites and ScreenToSim hitboxes keep the old size.
                return base * math.Clamp(cvNativeZoom:GetFloat(), 0.4, 1.2)
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
local cvHideWoundBackdrop = CreateClientConVar("zc_woundsystem_compat_hide_woundview_backdrop", "1", true, false,
    "1 = remove C:U's dark full-screen WoundView backdrop; 0 = keep it")

WSZC.CUHudFiltered = false
-- Set by WrapCUDeathScreen() only while C:U's death-screen HUDPaint hook runs:
-- every wrapped draw primitive becomes a no-op for that one call, while the
-- hook's respawn input handling keeps working.
WSZC.CUDeathVisualsHidden = false

-- The owner asked for the dark backdrop "как раньше" in EVERY minigame.
-- C:U draws it through WoundSystem.MinigameClip.DrawBackdrop(), which our
-- WoundView region filter used to swallow.  These two fields are the single
-- source of truth shared by the backdrop wrapper, the region whitelist and
-- the cursor watchdog: if a minigame painted a backdrop in the last 0.35 s,
-- it is running even when our IsActive() probes miss it (ZCity SWEP games,
-- hot-reloaded C:U tables, a lost open packet).
WSZC._MinigameBackdropDrawing = false
WSZC._LastMinigameDraw = -10
WSZC._HoldMinigameCursor = false
WSZC._AllowClickerRelease = false

function WSZC.MinigameDrawnRecently()
    local now = (CurTime and CurTime()) or 0
    return (now - (WSZC._LastMinigameDraw or -10)) < 0.35
end

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

--- Only the archive doll's FILL sprites need a white draw colour: C:U
--- multiplies the middle sprite by `finalMiddle` (normally pure black), so a
--- slate `_fill.png` would otherwise render pure black.  The owner explicitly
--- asked to keep the doll's colour and NOT to introduce new colour overrides.
---
--- The outline sprites (`*_edge.png`) are deliberately NOT in this list: C:U
--- must keep full control of `finalOutline` (white -> black on hover), so the
--- ORIGINAL white outline and the native hover reaction stay exactly as they
--- were.  C:U's alpha is preserved in both cases.
local function IsDollLimbMaterial(name)
    if type(name) ~= "string" then return false end
    local lower = name:lower():gsub("\\", "/"):gsub("%.png$", "")
    return lower:find("wszc/unitmenu/limbs/", 1, true) ~= nil
        and lower:find("_fill", 1, true) ~= nil
end
WSZC.IsDollLimbMaterial = IsDollLimbMaterial

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
    -- C:U's shared minigame backdrop is a rounded box drawn from Clip.DrawBackdrop.
    -- It overlaps the "left scanner" and even the full-screen region, so the
    -- WoundView filter would otherwise erase exactly the darkening the owner
    -- asked to bring back.  Only WoundView chrome is filtered, never this.
    if WSZC._MinigameBackdropDrawing == true then return false end
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

    -- A genuinely full-screen quad is C:U's shared dark WoundView backdrop
    -- (mats.woundbg / DrawConsciousnessBlackout / unconscious vignette), not
    -- the scanner.  The live screenshots showed an almost black screen behind
    -- the doll; the owner asked for the world to stay visible.  Only suppress
    -- it while WoundView is really open - the unconscious blackout must keep
    -- working when the HUD is closed.
    if w >= sw * 0.9 and h >= sh * 0.9 then
        return cvHideWoundBackdrop:GetBool() and WoundSystemHealthHUDOpen == true
    end

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
    -- Minigame PLAY sprites are never hidden, even though WoundView can stay
    -- open behind a ZCity SWEP minigame (the radial button opens it).
    if WSZC.IsMinigameGameplaySprite(WSZC._DrawMaterialName) then return false end
    return HiddenRegionRaw(x, y, w, h)
end
WSZC.CUHudHiddenRegion = HiddenRegion -- exported for headless tests
WSZC.CUHudHiddenRegionRaw = HiddenRegionRaw

---------------------------------------------------------------------------
-- C:U has NO "click outside to close": CloseHealthHUD() is only called from
-- the key toggle, the death screen and respawn.  The owner expects a click
-- on an empty part of WoundView to dismiss it, so add that behaviour here
-- without editing the addon.  `WSZC.WoundViewEmptyClick(mx, my, s)` is a
-- pure predicate (headless-testable); the Think hook owns the input edge.
---------------------------------------------------------------------------
--- @return true when (mx, my) is genuinely EMPTY: outside the doll, the five
--- inventory slots, the tool row, the action point, the tooltips and the
--- left UNI-HEALTH scanner.  `s` is the C:U UI scale (ScrH()/1080*uiScale).
function WSZC.WoundViewEmptyClick(mx, my, s)
    if type(mx) ~= "number" or type(my) ~= "number" then return false end
    s = tonumber(s) or 1
    local sw, sh = ScrW(), ScrH()
    local cx, cy = sw / 2, sh / 2 + 20 * s

    local function Inside(x, y, w, h)
        return mx >= x and mx <= x + w and my >= y and my <= y + h
    end

    -- Left UNI-HEALTH / scanner panel (even when visually hidden, C:U still
    -- handles clicks there).
    if Inside(0, 0, 560 * s, 900 * s) then return false end

    -- The doll itself plus a margin for limb labels / hover targets.  C:U
    -- lays out the body around (cx, cy) with dollScale ~1.5*s, so +/-430*s
    -- horizontally and +/-520*s vertically covers head, T-pose arms, legs
    -- and feet without swallowing the whole screen.
    if Inside(cx - 430 * s, cy - 520 * s, 860 * s, 1040 * s) then return false end

    -- Five inventory slots (3 lower, 2 upper) and the three tool buttons.
    local size = 80 * s
    local startX = cx - 137 * s
    for i = 0, 2 do
        if Inside(startX + i * 97 * s - 24 * s, cy + 275 * s - 24 * s,
                  size + 48 * s, size + 48 * s) then return false end
    end
    if Inside(cx - 255 * s - size - 24 * s, cy - 285 * s - 24 * s,
              size + 48 * s, size + 48 * s) then return false end
    if Inside(cx + 255 * s - 24 * s, cy - 285 * s - 24 * s,
              size + 48 * s, size + 48 * s) then return false end
    local toolW = 3 * size + 2 * (17 * s)
    if Inside(cx - toolW / 2 - 24 * s, cy + 275 * s - 24 * s,
              toolW + 48 * s, size + 48 * s) then return false end

    -- REMOVE SHRAPNEL / FIX DISLOCATION action point: C:U lerps its position
    -- into the global WoundSystemActionButtonPos.  A generous box also covers
    -- the label drawn to its right.
    local ap = _G.WoundSystemActionButtonPos
    if type(ap) == "table" and type(ap.x) == "number" and type(ap.y) == "number" then
        if Inside(ap.x - 60 * s, ap.y - 60 * s, 300 * s, 120 * s) then return false end
    end
    return true
end

local woundViewClickArmed = false
hook.Add("Think", "WSZC_WoundViewEmptyClickClose", function()
    if not cvCloseEmptyClick:GetBool() then return end
    if WoundSystemHealthHUDOpen ~= true then
        woundViewClickArmed = false
        return
    end
    -- Never fight an active minigame, a drag, the pause menu, a text entry or
    -- C:U's own external menus (radial / inventory).
    if WSZC.MinigameActive and WSZC.MinigameActive() then return end
    if WoundSystemDragState and WoundSystemDragState.active then return end
    if WoundSystemWorldDrag and WoundSystemWorldDrag.active then return end
    if vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus() then return end
    if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return end
    local hg = WoundSystem and WoundSystem.HealthGUI
    if hg and type(hg.IsExternalMenuOpen) == "function" and hg.IsExternalMenuOpen() then return end

    local pressed = input and input.IsMouseDown and input.IsMouseDown(MOUSE_LEFT) or false
    if pressed and not woundViewClickArmed then
        woundViewClickArmed = true
        local mx, my = gui.MousePos()
        local s = ScrH() / 1080
        local cv = GetConVar and GetConVar("woundsys_ui_scale") or nil
        if cv then s = s * math.Clamp(cv:GetFloat(), 0.6, 1.6) end
        if WSZC.WoundViewEmptyClick(mx, my, s) and WoundSystem
            and type(WoundSystem.CloseHealthHUD) == "function" then
            WoundSystem.CloseHealthHUD()
        end
    elseif not pressed then
        woundViewClickArmed = false
    end
end)

local savedHudFn, hudWrapper
local cvUnitmenuDoll -- declared below with the other doll convars
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

-- C:U owns disinfectTime as a real infection-resistance timer.  Do not zero
-- it and do not replace the whole medical icon layer: wrap ONLY the native
-- AddHudIcon upvalue and skip the single Icons.disinfected entry.  Consequently
-- the slot is not even appended (other icons keep their native spread), while
-- server disinfection and infection_up/down/neutral continue unchanged.
local disinfectedFilterFns = setmetatable({}, { __mode = "k" })
local disinfectedFilterWrappers = setmetatable({}, { __mode = "k" })

local function IsDisinfectedMaterial(mat, icons)
    -- Icons is LOCAL in cl_health_gui.lua.  Looking only at _G.Icons made the
    -- old filter a no-op in the real game even though its synthetic test passed.
    icons = icons or _G.Icons
    if type(icons) == "table" and mat == icons.disinfected then return true end

    -- Identity is the primary check.  The exact native path also covers a
    -- padded/recreated IMaterial and builds where Icons cannot be inspected.
    local name = MaterialName(mat)
    if type(name) ~= "string" then return false end
    name = name:lower():gsub("\\", "/")
    return name:find("casunknown-images/icons/disinfected", 1, true) ~= nil
end

local function PatchDisinfectedIcon(fn)
    if type(fn) ~= "function" or disinfectedFilterFns[fn] then
        return disinfectedFilterFns[fn] == true
    end
    if not (debug and debug.getupvalue and debug.setupvalue) then return false end

    -- Some C:U revisions keep AddHudIcon in a closure below WoundDollAndPanel.
    -- Walk function upvalues only (never arbitrary tables), inherit the native
    -- Icons table and retain the old direct-upvalue fast path.
    local visited = {}
    local function walk(candidate, depth, inheritedIcons)
        if type(candidate) ~= "function" or visited[candidate] then return false end
        visited[candidate] = true
        if disinfectedFilterFns[candidate] then return true end

        local icons, addIndex, addHudIcon = inheritedIcons, nil, nil
        for i = 1, 96 do
            local name, value = debug.getupvalue(candidate, i)
            if not name then break end
            if name == "Icons" and type(value) == "table" then
                icons = value
            elseif name == "AddHudIcon" and type(value) == "function" then
                addIndex, addHudIcon = i, value
            end
        end

        if addHudIcon then
            if disinfectedFilterWrappers[addHudIcon] then
                disinfectedFilterFns[candidate] = true
                return true
            end
            local nativeIcons = icons
            local wrapped = function(items, mat, ...)
                if IsDisinfectedMaterial(mat, nativeIcons) then return end
                return addHudIcon(items, mat, ...)
            end
            disinfectedFilterWrappers[wrapped] = true
            debug.setupvalue(candidate, addIndex, wrapped)
            disinfectedFilterFns[candidate] = true
            return true
        end

        if depth >= 6 then return false end
        for i = 1, 96 do
            local name, value = debug.getupvalue(candidate, i)
            if not name then break end
            if type(value) == "function" and walk(value, depth + 1, icons) then
                disinfectedFilterFns[candidate] = true
                return true
            end
        end
        return false
    end

    local installed = walk(fn, 0, nil)
    if installed then disinfectedFilterFns[fn] = true end
    return installed
end

function WSZC.InstallDisinfectedIconFilter()
    local hooks = hook.GetTable and hook.GetTable() or nil
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    local fn = type(hud) == "table" and hud.WoundDollAndPanel or nil
    if fn == hudWrapper or type(fn) ~= "function" then fn = savedHudFn end
    return PatchDisinfectedIcon(fn)
end

-- A previous HUD/minigame can leave point sampling active.  The generated
-- contour now carries a small source-alpha fringe; LINEAR sampling resolves it
-- instead of turning that fringe back into stair steps.  Scope the override to
-- C:U's native WoundView call and always restore both filter stacks, including
-- when the native draw errors.
local function BeginUnitmenuSmoothing()
    if not cvUnitmenuDoll:GetBool() then return false end
    local linear = TEXFILTER and TEXFILTER.LINEAR
    if not linear or not render or not render.PushFilterMag or not render.PushFilterMin
        or not render.PopFilterMag or not render.PopFilterMin then
        return false
    end
    render.PushFilterMag(linear)
    render.PushFilterMin(linear)
    return true
end

local function EndUnitmenuSmoothing(active)
    if not active then return end
    render.PopFilterMin()
    render.PopFilterMag()
end

local function InstallHudFilter()
    local hooks = hook.GetTable and hook.GetTable() or nil
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    if type(hud) ~= "table" then return false end
    local fn = hud.WoundDollAndPanel
    if type(fn) ~= "function" then return false end
    PatchDisinfectedIcon(fn == hudWrapper and savedHudFn or fn)
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
        local smoothing = BeginUnitmenuSmoothing()
        local ok, a, b, c = pcall(fn, ...)
        EndUnitmenuSmoothing(smoothing)
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
    -- Register the client half of the stump status after C:U's shared status
    -- module has loaded.  The server syncs only this extra customStatus key;
    -- native Statuses.GetActive() draws it before every arterial bleed icon.
    if WSZC.InstallAmputationStatus then WSZC.InstallAmputationStatus() end
    WSZC.InstallMinigameTextFilter()
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
-- The repository archive ships 15 pre-positioned 1500x1500 RGBA limb layers;
-- the generator splits the source head into independent head/neck sprites, so
-- the runtime doll has 16 interactive parts (zcity_delta/unitmenu/limbs),
-- three pixel status icons and nine realistic
-- hand frames (homigrad/handanim).  Stock C:U/ZCity Lua never references them,
-- so this connector installs them at runtime:
--   * C:U's `Limbs` upvalue (WoundDollAndPanel) is MUTATED IN PLACE: new
--     fill/outline materials + ox/oy/size/sourceW/sourceH.  Hover hitboxes,
--     limb selection, status icons, "FIX DISLOCATION" and the shrapnel action
--     point keep working because they all read the same Limbs table.
--   * Icons.fracture / fracture2 / dislocate / *bleed* are swapped for the
--     archive's pixel icons (Icons is a global table).
--   * WSZC bandage/syringe use generated human hand_idle.png / hand_click.png
--     (real palm/fist, C:U vertical pose) instead of the 512x1260 silhouettes;
--     native C:U minigames get the same swap through a narrow material wrapper.
-- The cropped PNGs are generated by tools/build_unitmenu_materials.py and live
-- in materials/wszc/unitmenu/.  Nothing inside the original ZIPs is modified.

cvUnitmenuDoll = CreateClientConVar("zc_woundsystem_compat_unitmenu_doll", "1", true, false,
    "1 = rebuild the WoundView doll from the repository unitmenu limb layers")
-- 0.25 is the EXACT 2222.png reference at 1365x1079.  The placement helper
-- below compensates C:U's saved woundsys_ui_scale instead of letting it enlarge
-- the doll a second time.  Other values remain proportional user overrides.
local cvDollScale = CreateClientConVar("zc_woundsystem_compat_unitmenu_scale", "0.25", true, false,
    "Doll size; 0.25 = exact 2222.png reference (native UI scale compensated)", 0.1, 0.8)
-- Owner (2026-11-06): restore the C:U hand pointer, but use a real human hand.
-- tools/build_minigame_hand.py rotates the bundled palm/fist into C:U's
-- fingertips-up / sleeve-down pose.  The hand keeps C:U HandPhysics inertia,
-- click frame and rotation; the OS arrow is hidden only while a game is active.
local cvHandanim = CreateClientConVar("zc_woundsystem_compat_handanim", "1", true, false,
    "1 = human C:U-style hand; 0 = original C:U hand frames")
local cvHandanimScale = CreateClientConVar("zc_woundsystem_compat_handanim_scale", "1", true, false,
    "Additional human hand scale; 1 = no extra multiplier beyond shared scale (0.2 .. 1.5)", 0.2, 1.5)
-- Exact native C:U grip fractions in its original 512x1260 rectangle.
local cvHandPivotX = CreateClientConVar("zc_woundsystem_compat_hand_pivot_x", "0.4", true, false,
    "Grip point inside the hand sprite, X fraction 0..1", 0, 1)
local cvHandPivotY = CreateClientConVar("zc_woundsystem_compat_hand_pivot_y", "0.1", true, false,
    "Grip point inside the hand sprite, Y fraction 0..1", 0, 1)
local cvHandMaxScreen = CreateClientConVar("zc_woundsystem_compat_hand_max_screen", "0.34", true, false,
    "Legacy unused option: the compact hand is scaled, not screen-capped")
local cvHideCursor = CreateClientConVar("zc_woundsystem_compat_hide_minigame_cursor", "1", true, false,
    "1 = hide the OS arrow only while the drawn minigame hand is active")
local cvHideHand = CreateClientConVar("zc_woundsystem_compat_hide_minigame_hand", "0", true, false,
    "1 = hide the hand and use the standard OS arrow instead")
local cvHandPinCursor = CreateClientConVar("zc_woundsystem_compat_hand_pin_cursor", "1", true, false,
    "1 = pin the gameplay hand and its visible grip to the real cursor; 0 = C:U inertia + developer offsets")
-- Archived 0/1 values from the former no-hand build survive a default change.
-- Migrate them once; afterwards every convar above remains user-configurable.
local cvHandModeRevision = CreateClientConVar("zc_woundsystem_compat_hand_mode_revision", "0", true, false,
    "Internal one-time migration revision for hand and minigame layout defaults")
function WSZC.MigrateHumanHandDefaults()
    -- Revision 6 makes the hand a real cursor replacement.  Revision 5 only
    -- corrected the rotated sprite pivot: WSZC still added C:U's 100/400
    -- developer offset and used spring inertia, so the palm stayed far below
    -- the mouse in the live bandage screenshot.  Migrate archived revision 5
    -- once; hand_pin_cursor 0 remains available for the legacy C:U behaviour.
    if cvHandModeRevision:GetFloat() >= 6 then return false end
    local defaults = {
        { cvHandScale, 0.55 }, { cvHandanim, 1 }, { cvHandanimScale, 1 },
        { cvHandPivotX, 0.4 }, { cvHandPivotY, 0.1 },
        { cvHideCursor, 1 }, { cvHideHand, 0 }, { cvHandPinCursor, 1 },
        { cvZoom, 0.85 }, { cvNativeZoom, 0.85 },
    }
    for _, entry in ipairs(defaults) do
        local cv, value = entry[1], entry[2]
        if cv.SetFloat then pcall(cv.SetFloat, cv, value) end
    end
    if cvHandModeRevision.SetInt then pcall(cvHandModeRevision.SetInt, cvHandModeRevision, 6) end
    return true
end
WSZC.MigrateHumanHandDefaults()
local cvDollTint = CreateClientConVar("zc_woundsystem_compat_unitmenu_tint", "1", true, false,
    "1 = draw the slate limbs with a white tint so they do not render pure black")

WSZC.UnitmenuHandSrcW = 512
WSZC.UnitmenuHandSrcH = 1260

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
            -- hoverW/hoverH are the VISIBLE inner silhouette boxes.  The png
            -- itself is power-of-two sized (C:U sizes by mat:Width()), so the
            -- padded sprite must NOT be used as the hover hit rectangle.
            built[id] = { fill = fill, edge = edge, cx = g.cx, cy = g.cy,
                          w = g.w, h = g.h,
                          hoverW = g.hoverW or g.w, hoverH = g.hoverH or g.h }
            count = count + 1
        end
    end
    if count < 16 then return nil end
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

--- The C:U-posed human frames are bundled into THIS addon under
--- materials/wszc/minigame/.  tools/build_minigame_hand.py derives them from
--- the real homigrad/handanim palm/fist; no WIP addon, Workshop content or
--- manual copying is required.  Missing frames fall back to C:U's own hand.
local function UnitmenuHandMaterials()
    if not cvHandanim:GetBool() then return nil end
    if handMatsChecked then return handIdleMat end
    if not (file and file.Exists) then return nil end
    if not file.Exists("materials/wszc/minigame/hand_idle.png", "GAME") then return nil end
    local idle = Material("wszc/minigame/hand_idle.png", "smooth noclamp")
    local click = Material("wszc/minigame/hand_click.png", "smooth noclamp")
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
    -- C:U/other addons may reset the VGUI cursor after our 0.15 s Think sync.
    -- Reapply it on EVERY actual hand draw so no ordinary arrow flickers or
    -- remains visible alongside the C:U hand pointer.
    if WSZC.SyncMinigameCursor then WSZC.SyncMinigameCursor() end
    return clicked and handClickMat or idle
end

--- Geometry for OUR bandage/syringe copies.  `scale` already contains the
--- per-minigame handScale.  The generated human hand uses the same vertical
--- orientation and almost the same fingertip pivot as the native C:U sprite.
function WSZC.UnitmenuHandGeometry(srcW, srcH, scale)
    scale = tonumber(scale) or 1
    if UnitmenuHandMaterials() then
        local k = math.Clamp(cvHandanimScale:GetFloat(), 0.2, 1.5)
        return (WSZC.UnitmenuHandSrcW * scale * k),
               (WSZC.UnitmenuHandSrcH * scale * k),
               math.Clamp(cvHandPivotX:GetFloat(), 0, 1),
               math.Clamp(cvHandPivotY:GetFloat(), 0, 1)
    end
    return (srcW * scale), (srcH * scale), 0.4, 0.1
end

--- Return a draw centre whose rotated artwork pivot lands exactly on cx/cy.
--- This is the same local-vector rotation used by C:U DrawPivotedRect():
--- x*c-y*s, x*s+y*c.  Keeping the centre fixed while shrinking a tall hand
--- leaves its fingertips far below the cursor, so the pivot must be the anchor.
function WSZC.HandRectAtPivot(cx, cy, w, h, rot, px, py)
    px, py = tonumber(px) or 0.4, tonumber(py) or 0.1
    local lx, ly = (0.5 - px) * w, (0.5 - py) * h
    local angle = math.rad(tonumber(rot) or 0)
    local c, s = math.cos(angle), math.sin(angle)
    return cx + lx * c - ly * s, cy + lx * s + ly * c, w, h
end

--- Shared by native C:U, WSZC bandage and WSZC syringe.  Pinning only the
--- sprite is not enough: grab/orbit/injection hitboxes read handScreenX/Y.
--- Update that gameplay state and clear the spring accumulator/velocity in the
--- same call, then the visible pivot can use the very same real cursor point.
function WSZC.MinigameHandPinned()
    return cvHandPinCursor and cvHandPinCursor:GetBool() or false
end

function WSZC.PinMinigameHandToCursor(mg)
    if not WSZC.MinigameHandPinned() or type(mg) ~= "table" then return nil, nil end
    if type(gui) ~= "table" or type(gui.MousePos) ~= "function" then return nil, nil end
    local ok, mx, my = pcall(gui.MousePos)
    if not ok or type(mx) ~= "number" or type(my) ~= "number" then return nil, nil end
    -- (0,0) is a valid screen corner, not a "mouse unavailable" sentinel.
    mg.handScreenX, mg.handScreenY = mx, my
    mg.handScreenVelX, mg.handScreenVelY = 0, 0
    mg._hp_acc = 0
    return mx, my
end

-- Native C:U keeps HandPhysics in a PRIVATE upvalue of each Think hook.  Wrap
-- that exact Step function: pinning later in Paint alone would still let the
-- spring/collision position drive extraction/dislocation gameplay for a frame.
-- The once-a-second installer also covers C:U autorefresh replacing its hooks.
local NATIVE_HAND_PHYSICS_HOOKS = {
    "WoundSystem_BandageInput", "WoundSystem_SyringeInput",
    "WoundSystem_ShrapnelInput", "WoundSystem_DislocationInput",
    "WoundSystem_AEDInput", "WoundSystem_SelfHarmInput",
}
function WSZC.InstallNativeHandPhysicsPin()
    if type(hook) ~= "table" or type(hook.GetTable) ~= "function" then return false end
    if not debug or type(debug.getupvalue) ~= "function" then return false end
    local ok, hooks = pcall(hook.GetTable)
    if not ok or type(hooks) ~= "table" or type(hooks.Think) ~= "table" then return false end
    local installed = false
    for _, hookName in ipairs(NATIVE_HAND_PHYSICS_HOOKS) do
        local fn = hooks.Think[hookName]
        if type(fn) == "function" then
            for i = 1, 80 do
                local okUp, name, hp = pcall(debug.getupvalue, fn, i)
                if not okUp or not name then break end
                if name == "HandPhysics" and type(hp) == "table"
                    and type(hp.Step) == "function" and not hp._WSZCCursorPinned then
                    local original = hp.Step
                    hp.Step = function(mg, dt, opts)
                        if WSZC.MinigameHandPinned() then
                            local mx = WSZC.PinMinigameHandToCursor(mg)
                            if mx ~= nil then return end
                        end
                        return original(mg, dt, opts)
                    end
                    hp._WSZCCursorPinned = true
                    installed = true
                end
            end
        end
    end
    return installed
end

function WSZC.UnitmenuHandAlpha(fallback)
    -- With the standard cursor as the pointer there must be NO hand picture
    -- at all.  Returning alpha 0 keeps every C:U/WSZC draw call and hitbox
    -- intact (no code path changes) while making the sprite invisible.
    if cvHideHand:GetBool() then return 0 end
    return UnitmenuHandMaterials() and 255 or (fallback or 153)
end

--- True only in the opt-in "drawn hand" mode.  Native games use this to
--- suppress their handgrasp* sprites when the arrow is the pointer.
function WSZC.ShowMinigameHand()
    return not cvHideHand:GetBool()
end

--- The replacement has C:U's vertical pose, so preserve its native rotation
--- exactly.  Zeroing/reducing it made tools visibly detached during a drag.
function WSZC.UnitmenuHandAngle(angle)
    return tonumber(angle) or 0
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
--- hudWrapper, C:U may re-register its hook under a different identifier, or
--- an admin HUD addon may wrap it again.  Walk the upvalue chain (bounded,
--- cycle-safe) of EVERY HUD hook to reach the C:U closure that owns `Limbs`.
--- The result is cached: C:U builds `Limbs` once at load time, so re-walking
--- every frame would be pure overhead.
local cachedCULimbs
local cachedCUGUIState

--- GUIState is private too.  The native draw loop calls math.Approach on
--- HoverAnims[limb.id] for EVERY entry, so inserting neck without initializing
--- these two tables would turn the first non-hovered frame into a Lua error.
local function FindCUGUIState()
    if type(cachedCUGUIState) == "table"
        and type(cachedCUGUIState.HoverAnims) == "table"
        and type(cachedCUGUIState.LastHoverStates) == "table" then
        return cachedCUGUIState
    end
    if not (debug and debug.getupvalue and hook and hook.GetTable) then return nil end
    local seen = {}
    local function walk(fn, depth)
        if type(fn) ~= "function" or depth > 4 or seen[fn] then return nil end
        seen[fn] = true
        local i = 1
        while true do
            local name, value = debug.getupvalue(fn, i)
            if not name then break end
            if name == "GUIState" and type(value) == "table"
                and type(value.HoverAnims) == "table"
                and type(value.LastHoverStates) == "table" then
                cachedCUGUIState = value
                return value
            end
            if type(value) == "function" then
                local found = walk(value, depth + 1)
                if found then return found end
            end
            i = i + 1
        end
        return nil
    end
    local hud = hook.GetTable().HUDPaint
    if type(hud) == "table" then
        if type(hud.WoundDollAndPanel) == "function" then
            local found = walk(hud.WoundDollAndPanel, 0)
            if found then return found end
        end
        for _, fn in pairs(hud) do
            local found = walk(fn, 0)
            if found then return found end
        end
    end
    if type(savedHudFn) == "function" then return walk(savedHudFn, 0) end
    return nil
end

local function FindCULimbs()
    if cachedCULimbs and IsCULimbsTable(cachedCULimbs) then return cachedCULimbs end
    if not (debug and debug.getupvalue and hook and hook.GetTable) then return nil end
    local hooks = hook.GetTable()
    if type(hooks) ~= "table" then return nil end
    local seen = {}
    local function walk(f, depth)
        if type(f) ~= "function" or depth > 4 or seen[f] then return nil end
        seen[f] = true
        local i = 1
        while true do
            local name, value = debug.getupvalue(f, i)
            if not name then break end
            if type(value) == "table" and IsCULimbsTable(value) then return value end
            if type(value) == "table" then
                -- Some C:U builds keep `Limbs` inside a GUI/state namespace.
                -- pcall: a third-party table may expose a broken __pairs.
                local nestedFound
                pcall(function()
                    for _, nested in pairs(value) do
                        if type(nested) == "table" and IsCULimbsTable(nested) then
                            nestedFound = nested
                            break
                        end
                    end
                end)
                if nestedFound then return nestedFound end
            end
            if type(value) == "function" then
                local found = walk(value, depth + 1)
                if found then return found end
            end
            i = i + 1
        end
        return nil
    end
    local hud = hooks.HUDPaint
    -- The named hook first (cheap, and it is the one our hudWrapper replaces).
    if type(hud) == "table" and type(hud.WoundDollAndPanel) == "function" then
        local found = walk(hud.WoundDollAndPanel, 0)
        if found then cachedCULimbs = found return found end
    end
    -- Fallback: C:U re-registered the hook, or another addon sits in front.
    for _, event in ipairs({"HUDPaint", "HUDPaintBackground", "PreDrawHUD"}) do
        local bucket = hooks[event]
        if type(bucket) == "table" then
            for _, fn in pairs(bucket) do
                local found = walk(fn, 0)
                if found then cachedCULimbs = found return found end
            end
        end
    end
    -- Last resort: some C:U builds publish their state namespaces globally
    -- (WoundSystemClientState / WoundSystem.HealthGUI).  `Limbs` is normally
    -- private, but a copy or a GUI-table reference may be reachable here.
    local roots = {
        _G.WoundSystemClientState,
        type(_G.WoundSystem) == "table" and _G.WoundSystem.HealthGUI or nil,
        type(_G.WoundSystem) == "table" and _G.WoundSystem.ClientState or nil,
    }
    for i = 1, #roots do
        local root = roots[i]
        if type(root) == "table" then
            if IsCULimbsTable(root) then cachedCULimbs = root return root end
            for _, nested in pairs(root) do
                if type(nested) == "table" and IsCULimbsTable(nested) then
                    cachedCULimbs = nested return nested
                end
            end
        end
    end
    -- Broadest fallback: C:U may have moved the doll into a non-HUD hook.
    -- `seen` keeps the walk cycle-safe; only reached when all fast paths fail.
    for _, bucket in pairs(hooks) do
        if type(bucket) == "table" then
            for _, fn in pairs(bucket) do
                local found = walk(fn, 0)
                if found then cachedCULimbs = found return found end
            end
        end
    end
    return nil
end
WSZC.FindCULimbs = FindCULimbs
WSZC.ClearCULimbsCache = function()
    cachedCULimbs = nil
    cachedCUGUIState = nil
end

local dollPatched = false

--- Fresh C:U-compatible state for the sixteenth limb.  Copy unknown future
--- fields from head, but never copy its CURRENT damage into the new neck.
local function EnsureNeckClientState()
    local states = type(WoundSystemClientState) == "table"
        and WoundSystemClientState.PlayerLimbs or nil
    if type(states) ~= "table" then return nil end
    if type(states.neck) == "table" then return states.neck end

    local state = type(states.head) == "table" and table.Copy(states.head) or {}
    state.skin, state.muscle, state.muscleStrength = 100, 100, 1
    state.pain, state.bleed = 0, 0
    state.infection, state.infectionSpeed = 0, 0
    state.shrapnel, state.disinfectTime = 0, 0
    state.broken, state.dislocated = false, false
    state.boneHealTimer, state.dislocationTimer = 0, 0
    state.temperature, state.oxygen, state.stress = 37, 100, 0
    state.isBandaged, state.hasInjection = false, false
    state.dismembered, state.furBloodAmount = false, 0
    state.bandageMinigameSpeedMult = 1
    state.eyes = 2
    state.customStatuses = {}
    states.neck = state
    return state
end
WSZC.EnsureNeckClientState = EnsureNeckClientState

--- The source doll has a real abdomen/pelvis seam, but stock C:U merges both
--- into `abdomen`.  Create a fresh native-compatible pelvis state; never copy
--- the abdomen's CURRENT wounds into a second injury container.
local function EnsurePelvisClientState()
    local states = type(WoundSystemClientState) == "table"
        and WoundSystemClientState.PlayerLimbs or nil
    if type(states) ~= "table" then return nil end
    if type(states.pelvis) == "table" then return states.pelvis end

    local state = type(states.abdomen) == "table" and table.Copy(states.abdomen) or {}
    state.skin, state.muscle, state.muscleStrength = 100, 100, 1
    state.pain, state.bleed = 0, 0
    state.infection, state.infectionSpeed = 0, 0
    state.shrapnel, state.disinfectTime = 0, 0
    state.broken, state.dislocated = false, false
    state.boneHealTimer, state.dislocationTimer = 0, 0
    state.temperature, state.oxygen, state.stress = 37, 100, 0
    state.isBandaged, state.hasInjection = false, false
    state.dismembered, state.furBloodAmount = false, 0
    state.bandageMinigameSpeedMult = 1
    state.eyes = 2
    state.customStatuses = {}
    states.pelvis = state
    return state
end
WSZC.EnsurePelvisClientState = EnsurePelvisClientState

--- Add neck immediately after head in C:U's OWN Limbs array.  Consequently
--- all native rendering, fracture icons, action points and net updates use the
--- same entry; this is not a second doll or a head texture with another label.
local function EnsureNeckLimb(limbs)
    if type(limbs) ~= "table" then return nil end
    EnsureNeckClientState()
    local head, headIndex, neck
    for i, limb in ipairs(limbs) do
        if limb.id == "head" then head, headIndex = limb, i end
        if limb.id == "neck" then neck = limb end
    end
    if neck then return neck end
    if not head then return nil end

    local guiState = FindCUGUIState()
    if not guiState then return nil end
    guiState.HoverAnims.neck = tonumber(guiState.HoverAnims.neck) or 0
    guiState.LastHoverStates.neck = guiState.LastHoverStates.neck == true

    neck = {}
    for key, value in pairs(head) do neck[key] = value end
    neck.id = "neck"
    neck._WSZCNeck = true
    neck._WSZCUnitmenuOriginal = nil
    table.insert(limbs, headIndex + 1, neck)
    return neck
end
WSZC.EnsureNeckLimb = EnsureNeckLimb

--- Insert pelvis immediately after abdomen in the SAME native Limbs array.
--- Native hover, action points, status icons and net updates therefore use the
--- new id directly; this is not a decorative overlay or a second doll.
local function EnsurePelvisLimb(limbs)
    if type(limbs) ~= "table" then return nil end
    EnsurePelvisClientState()
    local abdomen, abdomenIndex, pelvis
    for i, limb in ipairs(limbs) do
        if limb.id == "abdomen" then abdomen, abdomenIndex = limb, i end
        if limb.id == "pelvis" then pelvis = limb end
    end
    if pelvis then return pelvis end
    if not abdomen then return nil end

    local guiState = FindCUGUIState()
    if not guiState then return nil end
    guiState.HoverAnims.pelvis = tonumber(guiState.HoverAnims.pelvis) or 0
    guiState.LastHoverStates.pelvis = guiState.LastHoverStates.pelvis == true

    pelvis = {}
    for key, value in pairs(abdomen) do pelvis[key] = value end
    pelvis.id = "pelvis"
    pelvis._WSZCPelvis = true
    pelvis._WSZCUnitmenuOriginal = nil
    table.insert(limbs, abdomenIndex + 1, pelvis)
    return pelvis
end
WSZC.EnsurePelvisLimb = EnsurePelvisLimb

-- Canonical screen geometry measured directly from the owner's 2222.png.
-- Native C:U applies BOTH dollScale=1.5*UI and our limb.size to sprites and
-- offsets.  Passing the convar through unchanged therefore produced S=0.469
-- on the live 1111.png (UI=1.25) instead of the reference S=0.4155.  Solve
-- limb.size and a shared oy correction so the final SCREEN transform is fixed:
--   spriteScale = REF_S * resolutionScale * userMultiplier
--   centreY     = ScrH()/2 + REF_CY_OFFSET * resolutionScale
-- This also keeps hitboxes/action points exact because native code reads the
-- same compensated ox/oy/size values.
local UnitmenuUIScale
local REF_DOLL_S, REF_DOLL_CY = 0.4155, 18.7
local REF_DOLL_HEIGHT, REF_DOLL_CONVAR = 1079, 0.25
function WSZC.UnitmenuReferenceDollTransform(k)
    local userMultiplier = math.Clamp((tonumber(k) or REF_DOLL_CONVAR)
        / REF_DOLL_CONVAR, 0.4, 3.2)
    local nativeScale = (ScrH() / 1080) * UnitmenuUIScale()
    local nativeDollScale = 1.5 * nativeScale
    local resolutionScale = ScrH() / REF_DOLL_HEIGHT
    local targetScale = REF_DOLL_S * resolutionScale * userMultiplier
    local targetCY = ScrH() / 2 + REF_DOLL_CY * resolutionScale
    local nativeCY = ScrH() / 2 + 20 * nativeScale
    if nativeDollScale <= 0 then return k or REF_DOLL_CONVAR, 0, targetScale, targetCY end
    return targetScale / nativeDollScale,
        (targetCY - nativeCY) / nativeDollScale, targetScale, targetCY
end

local function ApplyDoll(limbs, mats, k)
    local dollSize, centreOY = WSZC.UnitmenuReferenceDollTransform(k)
    EnsureNeckLimb(limbs)
    EnsurePelvisLimb(limbs)
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
            limb.ox = (g.cx - 750) * dollSize
            limb.oy = (g.cy - 750) * dollSize + centreOY
            limb.size = dollSize
            limb.sourceW = g.hoverW or g.w
            limb.sourceH = g.hoverH or g.h
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
    for i = #limbs, 1, -1 do
        local limb = limbs[i]
        if limb._WSZCNeck or limb._WSZCPelvis then
            -- Native C:U has no neck/pelvis materials.  Keep their server
            -- states, but never leave duplicate sprites in the stock doll.
            table.remove(limbs, i)
        else
            local orig = limb._WSZCUnitmenuOriginal
            if orig then
                for key, value in pairs(orig) do limb[key] = value end
                limb._WSZCUnitmenuOriginal = nil
            end
        end
    end
    dollPatched = false
    return true
end

---------------------------------------------------------------------------
-- Source-screenshot limb tooltip (the stock C:U doll has no such hover card).
---------------------------------------------------------------------------
local UNITMENU_LIMB_NAMES = {
    head = "Head", neck = "Neck", thorax = "Thorax", abdomen = "Abdomen",
    pelvis = "Pelvis",
    arm_R = "Right upper arm", arm_L = "Left upper arm",
    forearm_R = "Right forearm", forearm_L = "Left forearm",
    hand_R = "Right hand", hand_L = "Left hand",
    thigh_R = "Right thigh", thigh_L = "Left thigh",
    crus_R = "Right shin", crus_L = "Left shin",
    foot_R = "Right foot", foot_L = "Left foot",
}

UnitmenuUIScale = function()
    local value = 1
    local cv = GetConVar and GetConVar("woundsys_ui_scale") or nil
    if cv then value = math.Clamp(cv:GetFloat(), 0.6, 1.6) end
    if ScrH() <= 600 then return value * 0.72 end
    if ScrH() <= 768 then return value * 0.86 end
    return value
end

--- Reproduce C:U's own rectangle hit test, including its order (a later limb
--- wins an overlap) and pain shake.  The tooltip therefore names the SAME part
--- that a click/action point selects, rather than maintaining a second layout.
function WSZC.UnitmenuHover(mx, my)
    if type(mx) ~= "number" or type(my) ~= "number" then return nil end
    local limbs = FindCULimbs()
    local states = type(WoundSystemClientState) == "table"
        and WoundSystemClientState.PlayerLimbs or nil
    if not (limbs and states) then return nil end

    local scale = (ScrH() / 1080) * UnitmenuUIScale()
    local dollScale = 1.5 * scale
    local centerX, centerY = ScrW() / 2, ScrH() / 2 + 20 * scale
    local guiState = FindCUGUIState()
    local shakes = guiState and guiState.HudLimbShakeScratch or nil
    local openTime = guiState and guiState.openTime or 0
    local hovered

    for _, limb in ipairs(limbs) do
        local state = states[limb.id]
        local alpha = math.Clamp((CurTime() - (openTime + (limb.order or 0) * 0.03)) * 8, 0, 1)
        if state and not state.dismembered and alpha > 0 then
            local scaleMult = dollScale * (limb.size or 1)
            local shake = shakes and shakes[limb.id] or nil
            local cx = centerX + limb.ox * dollScale + (shake and shake.x or 0)
            local cy = centerY + limb.oy * dollScale + (shake and shake.y or 0)
            local matW = limb.matO and limb.matO.Width and limb.matO:Width() or 0
            local matH = limb.matO and limb.matO.Height and limb.matO:Height() or 0
            local w = (limb.sourceW or matW) * scaleMult
            local h = (limb.sourceH or matH) * scaleMult
            if mx > cx - w / 2 and mx < cx + w / 2
                and my > cy - h / 2 and my < cy + h / 2 then
                hovered = { id = limb.id, state = state, x = cx, y = cy,
                            w = w, h = h, alpha = alpha }
            end
        end
    end
    return hovered
end

function WSZC.UnitmenuTooltipLines(id, state)
    local title = UNITMENU_LIMB_NAMES[id] or tostring(id or "Limb")
    local skin = math.Clamp(math.Round(tonumber(state and state.skin) or 0), 0, 100)
    local muscle = math.Clamp(math.Round(tonumber(state and state.muscle) or 0), 0, 100)
    return title, string.format("Skin: %d%%", skin), string.format("Muscle: %d%%", muscle)
end

hook.Add("PostDrawHUD", "WSZC_UnitmenuLimbTooltip", function()
    if WoundSystemHealthHUDOpen ~= true or not cvUnitmenuDoll:GetBool() then return end
    if WSZC.WSZCMinigameActive() or WSZC.NativeMinigameActive() then return end
    local ply = LocalPlayer()
    if IsValid(ply) and ply.Alive and not ply:Alive() then return end

    local mx, my = gui.MousePos()
    local hovered = WSZC.UnitmenuHover(mx, my)
    if not hovered then return end
    local title, skinLine, muscleLine = WSZC.UnitmenuTooltipLines(hovered.id, hovered.state)

    local scale = ScrH() / 1080
    local font = "ZB_ProotOSMedium"
    surface.SetFont(font)
    local titleW = surface.GetTextSize(title)
    local skinW = surface.GetTextSize(skinLine)
    local muscleW = surface.GetTextSize(muscleLine)
    local padX, padTop = 18 * scale, 18 * scale
    local lineStep = 34 * scale
    local w = math.max(160 * scale, math.max(titleW, skinW, muscleW) + 2 * padX)
    local h = 126 * scale
    local x, y = mx + 28 * scale, my + 20 * scale
    if x + w > ScrW() - 8 * scale then x = mx - w - 28 * scale end
    if y + h > ScrH() - 8 * scale then y = ScrH() - h - 8 * scale end
    x, y = math.max(8 * scale, x), math.max(8 * scale, y)

    -- PostDrawHUD is outside WoundView.  Do not let its hidden-scanner filter
    -- eat a perfectly valid tooltip when hovering the left arm/hand.
    local filtered = WSZC.CUHudFiltered
    WSZC.CUHudFiltered = false
    surface.SetDrawColor(0, 0, 0, 200 * (hovered.alpha or 1))
    surface.DrawRect(x, y, w, h)
    local textColor = Color(255, 255, 255, 255 * (hovered.alpha or 1))
    draw.SimpleText(title, font, x + padX, y + padTop, textColor,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(skinLine, font, x + padX, y + padTop + lineStep, textColor,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.SimpleText(muscleLine, font, x + padX, y + padTop + lineStep * 2, textColor,
        TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    WSZC.CUHudFiltered = filtered
end)

local function ApplyUnitmenuIcons()
    local icons = _G.Icons
    if type(icons) ~= "table" or icons._WSZCUnitmenuPatched then return false end
    local built = BuildUnitmenuIcons()
    if not built then return false end
    for key, mat in pairs(built) do icons[key] = mat end
    -- Do NOT replace Icons.disinfected with infection.png: that still leaves a
    -- processing slot on the hand and confuses it with a real infection.  The
    -- native AddHudIcon filter above removes exactly that one entry instead.
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
local nativeHandInstalled, handSwap, handHide = false, false, false
local materialTrackerInstalled = false
local origSetMaterial, origRectRotated, origTexturedRect, origSetDrawColor

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

    -- NO DrawTexturedRect suppression here.  The previous build skipped
    -- `minigameshrapnel.png` while a minigame was active, mistaking the wound
    -- FRONT LAYER for a black UI panel.  Live result: the lower half of the
    -- wound vanished and only an oversized shard was left on screen.  Chrome
    -- is removed by the Clip.DrawHeader / DrawExitGuide / DrawBackdrop hooks
    -- and the font filter instead; gameplay sprites always draw.

    -- C:U multiplies the doll's middle sprite by `finalMiddle`, normally
    -- pure black.  Our `_fill.png` is the standard black of the archive
    -- layers, so it needs a white tint to stay visible.  Only the fills are
    -- overridden; the `_edge.png` contours keep C:U's `finalOutline`, so the
    -- white outline and its hover reaction (white -> black) are preserved.
    -- C:U's alpha is preserved.
    if type(surface.SetDrawColor) == "function" then
        origSetDrawColor = surface.SetDrawColor
        surface.SetDrawColor = function(r, g, b, a)
            if cvDollTint:GetBool() and IsDollLimbMaterial(WSZC._DrawMaterialName) then
                return origSetDrawColor(255, 255, 255, a or 255)
            end
            return origSetDrawColor(r, g, b, a)
        end
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
        local clicked = CUHandKind(mat)
        -- Clear the pending flags only when a DIFFERENT material is bound, so
        -- a second SetMaterial between the hand's bind and its draw call does
        -- not accidentally re-enable the sprite.
        if clicked == nil then handSwap, handHide = false, false end
        if clicked ~= nil and WSZC.NativeMinigameActive
            and WSZC.NativeMinigameActive() then
            -- Standard cursor mode: no drawn hand at all, native games too.
            if not WSZC.ShowMinigameHand() then
                handHide = true
                return nil
            end
            if cvHandanim:GetBool() and UnitmenuHandMaterials() then
                local repl = WSZC.UnitmenuHandMat(clicked)
                if repl then
                    handSwap = true
                    return repl
                end
            end
        end
        return nil
    end

    local function HandDrawSize(w, h)
        -- The native and WSZC paths must not disagree: both now include the
        -- shared 0.55 cursor scale exactly once, then the optional human-hand
        -- multiplier (1 by default).  Only this DRAW rectangle shrinks;
        -- MG.handDrawW/H and every extraction/dislocation hitbox stay native.
        local k = math.Clamp(cvHandScale:GetFloat() * cvHandanimScale:GetFloat(), 0.04, 1.5)
        local nw = w * (WSZC.UnitmenuHandSrcW / 512) * k
        local nh = h * (WSZC.UnitmenuHandSrcH / 1260) * k
        return nw, nh
    end
    WSZC.HandDrawSize = HandDrawSize

    local function HandPivot()
        return math.Clamp(cvHandPivotX:GetFloat(), 0, 1),
               math.Clamp(cvHandPivotY:GetFloat(), 0, 1)
    end
    WSZC.HandPivot = HandPivot

    local NATIVE_HAND_MG = {
        "WoundSystemDislocationMinigame", "WoundSystemShrapnelMinigame",
        "WoundSystemAEDMinigame", "WoundSystemBandageMinigame",
        "WoundSystemSyringeMinigame",
    }

    --- C:U's HandPhysics eases handScreenX/Y toward the mouse and adds a pain
    --- shake, so the drawn hand always lagged behind the real cursor.  Read
    --- the actual cursor and push it into the MINIGAME STATE too, otherwise
    --- the grab hitboxes would disagree with the picture.
    function WSZC.NativeHandCursorPos()
        if type(gui) ~= "table" or type(gui.MousePos) ~= "function" then return nil, nil end
        local ok, mx, my = pcall(gui.MousePos)
        if not ok or type(mx) ~= "number" or type(my) ~= "number" then return nil, nil end
        return mx, my
    end

    function WSZC.PinNativeHandToCursor()
        if not WSZC.MinigameHandPinned() then return nil, nil end
        local mx, my = WSZC.NativeHandCursorPos()
        if not mx then return nil, nil end
        for _, name in ipairs(NATIVE_HAND_MG) do
            local mg = _G[name]
            if type(mg) == "table" and mg.active == true then
                WSZC.PinMinigameHandToCursor(mg)
            end
        end
        return mx, my
    end

    --- handScreenX/Y is C:U's grip point, not its rectangle centre.  Preserve
    --- that point while applying the one shared scale and exact native rotation.
    --- Default pin mode changes both gameplay state and target to the cursor.
    function WSZC.HandRectForCursor(cx, cy, w, h, rot)
        local mx, my = WSZC.PinNativeHandToCursor()
        if mx then cx, cy = mx, my end
        local nw, nh = HandDrawSize(w, h)
        local px, py = HandPivot()
        return WSZC.HandRectAtPivot(cx, cy, nw, nh, rot, px, py)
    end

    surface.DrawTexturedRectRotated = function(x, y, w, h, rot, ...)
        if handHide then
            handHide = false
            return
        end
        if handSwap then
            local nx, ny, nw, nh = WSZC.HandRectForCursor(x, y, w, h, rot)
            handSwap = false
            -- Vertical human artwork follows the exact native C:U rotation.
            return origRectRotated(nx, ny, nw, nh, rot, ...)
        end
        return origRectRotated(x, y, w, h, rot, ...)
    end
    surface.DrawTexturedRect = function(x, y, w, h, ...)
        if handHide then
            handHide = false
            return
        end
        if handSwap then
            -- Non-rotated C:U calls are top-left based and use pivot (0.4,0.1).
            -- Preserve that gameplay point while substituting the human rect.
            local gripX, gripY = x + 0.4 * w, y + 0.1 * h
            local mx, my = WSZC.PinNativeHandToCursor()
            if mx then gripX, gripY = mx, my end
            local nw, nh = HandDrawSize(w, h)
            local px, py = HandPivot()
            handSwap = false
            return origTexturedRect(gripX - px * nw, gripY - py * nh, nw, nh, ...)
        end
        return origTexturedRect(x, y, w, h, ...)
    end
    nativeHandInstalled = true
    return true
end

---------------------------------------------------------------------------
-- The OS cursor must not be visible in a minigame: the drawn hand IS the
-- pointer.  C:U calls gui.EnableScreenClicker(true), which shows the arrow;
-- a blank VGUI cursor keeps mouse input working while hiding the arrow.
---------------------------------------------------------------------------
local cursorHidden, savedCursor, nextCursorSync = false, "arrow", 0

local function WorldPanel()
    if type(vgui) ~= "table" or type(vgui.GetWorldPanel) ~= "function" then return nil end
    local ok, panel = pcall(vgui.GetWorldPanel)
    if ok and panel and type(panel.SetCursor) == "function" then return panel end
    return nil
end

-- A blank VGUI cursor hides only the OS arrow; mouse input and gui.MousePos()
-- remain enabled.  It is allowed exclusively when the visible hand is the
-- pointer.  hide_minigame_hand 1 is therefore a safe standard-arrow fallback.
function WSZC.BlankMinigameCursor()
    if not cvHideCursor:GetBool() or not WSZC.ShowMinigameHand() then
        WSZC.RestoreMinigameCursor(true)
        return false
    end
    local panel = WorldPanel()
    if not panel then return false end
    if not cursorHidden and panel.GetCursor then
        local ok, value = pcall(panel.GetCursor, panel)
        if ok and value and value ~= "blank" then savedCursor = value end
    end
    pcall(panel.SetCursor, panel, "blank")
    cursorHidden = true
    return true
end

function WSZC.RestoreMinigameCursor(force)
    local panel = WorldPanel()
    -- Force "arrow", not `savedCursor`: that value could itself be "blank"
    -- from a previous session.
    if panel then pcall(panel.SetCursor, panel, "arrow") end
    cursorHidden = false
    return true
end

function WSZC.SyncMinigameCursor()
    local active = (WSZC.MinigameActive and WSZC.MinigameActive())
        or (WSZC.WSZCMinigameActive and WSZC.WSZCMinigameActive())
        or (WSZC.NativeMinigameActive and WSZC.NativeMinigameActive())
    if active and cvHideCursor:GetBool() and WSZC.ShowMinigameHand() then
        return WSZC.BlankMinigameCursor()
    end
    WSZC.RestoreMinigameCursor(true)
    return false
end

--- Hard cleanup after a minigame closes.  C:U's ScreenClickerWatchdog only
--- releases the clicker when WoundSystemHealthHUDOpen == false AND its own
--- IsAnyWoundMinigameActive() says false; a stale flag on either side used to
--- leave the arrow visible forever and kept `IN_ATTACK` zeroed, so fentanyl
--- and the other ZCity medical SWEPs could not be applied afterwards.
function WSZC.ForceReleaseMinigameCursor()
    WSZC._HoldMinigameCursor = false
    WSZC._MinigameBackdropDrawing = false
    WSZC._LastMinigameDraw = -10
    WSZC._NextCursorFix = 0
    WSZC._MinigameForceOffUntil = (CurTime and CurTime() or 0) + 0.4
    WSZC.RestoreMinigameCursor(true)      -- standard OS arrow, always
    if WoundSystemHealthHUDOpen == true then return true end
    WSZC._AllowClickerRelease = true
    local hg = WoundSystem and WoundSystem.HealthGUI
    if hg and type(hg.ForceReleaseScreenClicker) == "function" then
        pcall(hg.ForceReleaseScreenClicker, false, "wszc_minigame_closed")
    elseif hg and type(hg.SetScreenClickerOwned) == "function" then
        pcall(hg.SetScreenClickerOwned, false, "wszc_minigame")
    end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
    WSZC._AllowClickerRelease = false
    return true
end

hook.Add("Think", "WSZC_MinigameCursor", function()
    local now = CurTime and CurTime() or 0
    if now < nextCursorSync then return end
    nextCursorSync = now + 0.15
    WSZC.SyncMinigameCursor()
    -- Ground truth: vgui.CursorVisible().  A stale watchdog must not disable
    -- mouse input.  Re-enable the clicker, then restore the HAND pointer (or
    -- the arrow in fallback mode); hiding the OS cursor is not hiding input.
    local active = (WSZC.MinigameActive and WSZC.MinigameActive())
        or (WSZC.WSZCMinigameActive and WSZC.WSZCMinigameActive())
        or (WSZC.NativeMinigameActive and WSZC.NativeMinigameActive())
    if active and vgui and vgui.CursorVisible and not vgui.CursorVisible() then
        if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(true) end
        WSZC.SyncMinigameCursor()
    end
end)

-- Enabling the screen clicker resets the cursor image on some GMod builds.
if type(gui) == "table" and type(gui.EnableScreenClicker) == "function" then
    local origEnableScreenClicker = gui.EnableScreenClicker
    gui.EnableScreenClicker = function(on, ...)
        -- C:U's WoundSystem_ScreenClickerWatchdog calls ForceReleaseScreenClicker
        -- whenever its own IsAnyWoundMinigameActive() probe says false, and the
        -- ZCity radial menu closing can release the clicker a frame later.
        -- Both used to leave gui.MousePos() frozen at (0,0), so the bandage /
        -- syringe hand could not be steered.  Refuse such releases while a
        -- minigame is actually painting its board; DisableMinigameClicker()
        -- explicitly opts out via _AllowClickerRelease when the game closes.
        if not on and WSZC._HoldMinigameCursor == true
            and WSZC._AllowClickerRelease ~= true then
            return
        end
        local res = origEnableScreenClicker(on, ...)
        -- Enabling the clicker resets the VGUI cursor on some GMod builds.
        if on then WSZC.SyncMinigameCursor() end
        return res
    end
end

--- Screenshot_9.png: the "FIX DISLOCATION" / "REMOVE SHRAPNEL" label sat a
--- whole limb ABOVE the injured limb.  C:U computes
---   targetCenterY = limbScreenPoint.y + OffsetY * dollScale
--- with OffsetY = -60 authored for its own 1500x1500 doll.  Our POT doll is
--- packed into k = 0.24, so dollScale (~1.73) turns -60 into ~-104 SCREEN px
--- instead of the intended ~-25.  Re-author the offset in the global config
--- (never editing C:U) so the label stays next to the limb it belongs to.
local function PatchActionButtonOffset()
    local cfg = _G.WoundSystemLimbUIConfig
    local point = cfg and cfg.ShrapnelPoint
    if type(point) ~= "table" or point._WSZCOffsetPatched then return false end
    point._WSZCOffsetPatched = true
    point.OffsetY = -14
    if type(point.Actions) == "table" then
        for _, a in pairs(point.Actions) do
            if type(a) == "table" then a.OffsetY = -14 end
        end
    end
    -- The global position is lerped; reset it once so the correction applies
    -- immediately instead of sliding down over a second.
    local pos = _G.WoundSystemActionButtonPos
    if type(pos) == "table" then pos.x, pos.y = nil, nil end
    return true
end
WSZC.PatchActionButtonOffset = PatchActionButtonOffset

--- C:U's stock brokenneck moodle reads head.broken.  The native ZCity skull
--- fracture is now owned by the independent neck state, so re-register ONLY
--- that public definition; all other moodles and their layout stay untouched.
function WSZC.InstallNeckMoodle()
    local moodles = WoundSystem and WoundSystem.Moodles or nil
    if type(moodles) ~= "table" or type(moodles.Register) ~= "function" then return false end
    local current = moodles.DefById and moodles.DefById.brokenneck or nil
    if current and current._WSZCNeckState then return true end
    moodles.Register("brokenneck", {
        icon = "brokenneck",
        chippedOnly = true,
        _WSZCNeckState = true,
        condition = function(ctx)
            local limbs = ctx and ctx.limbs or nil
            local state = limbs and (limbs.neck or limbs.head) or nil
            if not state and type(WoundSystemClientState) == "table"
                and type(WoundSystemClientState.PlayerLimbs) == "table" then
                local playerLimbs = WoundSystemClientState.PlayerLimbs
                state = playerLimbs.neck or playerLimbs.head
            end
            if type(state) ~= "table" or not state.broken then return nil end
            local timerValue = tonumber(state.boneHealTimer) or 0
            return {
                intensity = math.Clamp(math.Round(timerValue * 0.03), 0, 3),
                title = "Broken neck",
                desc = "The neck is fractured.",
            }
        end,
    })
    if moodles.RebuildNow then moodles.RebuildNow() end
    return true
end

WSZC.NextUnitmenuInstall = 0
hook.Add("Think", "WSZC_UnitmenuVisuals", function()
    local now = CurTime and CurTime() or 0
    if now < (WSZC.NextUnitmenuInstall or 0) then return end
    WSZC.NextUnitmenuInstall = now + 1
    WSZC.InstallMaterialTracker()
    if WSZC.InstallInternalBleedingStatus then WSZC.InstallInternalBleedingStatus() end
    WSZC.InstallDisinfectedIconFilter()
    PatchActionButtonOffset()
    WSZC.InstallNeckMoodle()

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
    -- Install the gameplay pin independently of the selected hand artwork.
    WSZC.InstallNativeHandPhysicsPin()
    -- Install in both modes: substitute the human hand by default, or suppress
    -- every handgrasp* sprite when the player explicitly selects arrow-only.
    if cvHandanim:GetBool() or cvHideHand:GetBool() then
        WSZC.InstallNativeHandOverride()
    end
end)

-- First-life bootstrap: do not wait for a respawn or for the player to open
-- WoundView before neck/pelvis exist in client state and native Limbs.
hook.Add("InitPostEntity", "WSZC_UnitmenuNeckFirstLife", function()
    EnsureNeckClientState()
    EnsurePelvisClientState()
    WSZC.InstallNeckMoodle()
    WSZC.NextUnitmenuInstall = 0
    if not cvUnitmenuDoll:GetBool() then return end
    local mats, limbs = BuildUnitmenuMaterials(), FindCULimbs()
    if mats and limbs then
        ApplyDoll(limbs, mats, math.Clamp(cvDollScale:GetFloat(), 0.1, 0.8))
        dollPatched = true
    end
end)

-- C:U registers `WoundDollAndPanel` at file load; on some clients another HUD
-- addon (or an autorefresh) installs the hook AFTER our first Think.  Re-try the
-- doll patch immediately before the HUD is drawn, but at most once a second and
-- only while the patch has not yet taken.  ApplyDoll is idempotent (it saves
-- _WSZCUnitmenuOriginal once), so replaying it cannot drift the geometry.
WSZC.NextDollRetry = 0
hook.Add("PreDrawHUD", "WSZC_UnitmenuDollRetry", function()
    if dollPatched or not cvUnitmenuDoll:GetBool() then return end
    local now = CurTime and CurTime() or 0
    if now < (WSZC.NextDollRetry or 0) then return end
    WSZC.NextDollRetry = now + 1
    local mats = BuildUnitmenuMaterials()
    if not mats then return end
    local limbs = FindCULimbs()
    if limbs then
        ApplyDoll(limbs, mats, math.Clamp(cvDollScale:GetFloat(), 0.1, 0.8))
        dollPatched = true
    end
end)
