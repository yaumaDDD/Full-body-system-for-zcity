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
        if WSZC.MinigameFullscreen() then
            -- x, y, w, h, corner radius.  Radius 0 makes Clip.Begin() fall back
            -- to a full-screen scissor rect instead of a stencil-masked square.
            return 0, 0, ScrW(), ScrH(), 0
        end
        return original()
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
