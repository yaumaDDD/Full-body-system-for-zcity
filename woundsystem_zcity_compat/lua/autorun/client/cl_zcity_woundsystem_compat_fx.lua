-- WSZC: leave ONLY ZCity visuals.  (client part)
--
-- The owner wants the Casualties: Unknown health system to remain as the injury
-- panel / minigames / shrapnel protocol, but NOT to draw any of its own screen
-- effects, overlays, moodles, static, vignettes, shaders, camera shake,
-- unconscious eye view, decorative blood or alien "fur blood" on models.
-- ZCity (+ Hemogen / Gore V2) owns every visual effect instead.
--
-- Nothing inside the original ZIP addons is edited.  Every C:U hook listed
-- below is removed at runtime; the original callback is kept in WSZC.CUFxSaved
-- so `zc_woundsystem_compat_disable_cu_fx 0` can restore it.  C:U re-registers
-- some hooks (EYEVIEW_CalcView) from its own Think, so Apply() is repeated.

if not CLIENT then return end

WSZC = WSZC or {}
if WSZC._ClientFXLoaded then return end
WSZC._ClientFXLoaded = true

local cvDisableFX = CreateClientConVar("zc_woundsystem_compat_disable_cu_fx", "1", true, false,
    "1 = remove all C:U screen/camera/UI effects, leaving only ZCity effects")
local cvDisableBlood = CreateClientConVar("zc_woundsystem_compat_disable_cu_blood", "1", true, false,
    "1 = remove C:U decorative blood, blood stains, trails and alien model blood")

-- { event, hook name }.  Deliberately NOT included:
--   WoundDollAndPanel / WoundSystem_UIRegistry / WoundSystem_WorldItemDraw
--   ToggleHUDInput / CacheVitals / WoundSystem_ScreenClickerWatchdog
--   (the injury panel, its input handling and the cursor owner must survive).
--
--   WoundSystem_DeathScreenDisplay is NOT in the list either any more:
--   besides drawing the death screen it is the ONLY client handler that sends
--   "WoundSystem_PlayerRespawnRequest" on left click.  The server hook
--   "WoundSystem_BlockRespawn" blocks ordinary respawn until that message
--   arrives, so removing the display hook made respawning impossible.  It is
--   wrapped (draws suppressed, input preserved) by WrapCUDeathScreen() below.
local FX_HOOKS = {
    -- Full-screen post-processing (pain shader, bloom, sharpen, motion blur,
    -- tunnel vision, chromatic aberration, drug/withdrawal visuals, ...).
    { "RenderScreenspaceEffects", "WoundSystem_PostProcess" },
    { "RenderScreenspaceEffects", "WoundSystem_StaminaEffects" },
    { "RenderScreenspaceEffects", "WoundSystem_BlindEffects" },
    { "RenderScreenspaceEffects", "WoundSystem_ChromaticAberration" },
    { "RenderScreenspaceEffects", "WoundSystem_SpinNauseaRenderFX" },
    { "RenderScreenspaceEffects", "WoundSystem_LobotomyVisualEffects" },
    { "RenderScreenspaceEffects", "WoundSystem_BrainReverseScreenFlip" },
    -- HUD-space overlays: static, vignettes, death screen, moodles, self-talk.
    { "HUDPaintBackground", "WoundSystem_DrawManualStatic" },
    { "HUDPaintBackground", "WoundSystem_FullStatic" },
    { "HUDPaintBackground", "WoundSystem_BlindVignette" },
    { "HUDPaintBackground", "WoundSystem_VignetteVisuals" },
    { "PostDrawHUD", "WoundSystem_MoodlesPaint" },
    { "PostDrawHUD", "zz_WoundSystem_UnconsciousCircleForeground" },
    { "HUDPaint", "WoundSystem_SelfTalkHUDPaint" },
    { "HUDPaint", "WoundSystem_DrawMoodIcon" },
    -- Camera / view manipulation.
    { "CalcView", "00_WoundSystem_UnconsciousEyeView" },
    { "CalcView", "zz_WoundSystem_UnconsciousEyeView" },
    { "CalcView", "EYEVIEW_CalcView" },
    { "CalcView", "WoundSystem_SpinNauseaCalcView" },
    { "CalcView", "WoundSystem_BrainDamageShakeView" },
    { "PostDrawSkyBox", "WoundSystem_BlackSkybox" },
    { "SetupWorldFog", "WoundSystem_WorldFog" },
    { "SetupSkyboxFog", "WoundSystem_SkyFog" },
    { "ShouldDrawLocalPlayer", "WoundSystem_HideUnconsciousBody" },
    { "PrePlayerDraw", "WoundSystem_HideUnconsciousBody" },
    { "PrePlayerDraw", "WoundSystem_HideUnconsciousPlayerModel" },
    { "PreDrawViewModel", "WoundSystem_HideUnconsciousViewModel" },
    { "SetupMove", "WoundSystem_ClientUnconsciousPin" },
    -- Input distortion (aim kick, inverted/slippery controls).
    { "CreateMove", "WoundSystem_BallisticAimKick" },
    { "CreateMove", "WoundSystem_LobotomyInputDelay" },
    { "CreateMove", "WoundSystem_LobotomySlipperyAim" },
    { "CreateMove", "WoundSystem_LobotomyInvertControls" },
    -- State tickers that only feed the effects above.
    { "Think", "WoundSystem_SpinNauseaThink" },
    { "Think", "WoundSystem_MoodlesThink" },
    { "Think", "WoundSystem_BrainReverseClientState" },
    { "Think", "WoundSystem_DismembermentVisualsThink" },
    { "Think", "WoundSystem_FacialExpressionsThink" },
    -- Looping medical audio / music / tinnitus / asystole / self-talk.
    { "InitPostEntity", "HealthSystem_InitAudio" },
    { "Think", "HealthSystem_AudioCrossfade" },
    { "Think", "WoundSystem_AsystoleSound" },
    { "Think", "WoundSystem_SelfTalkPendingInterruptThink" },
    { "Think", "WoundSystem_MultiplayerFeedbackDecay" },
    { "OnPlayerChat", "WoundSystem_DistanceChatDistortion" },
}

local BLOOD_HOOKS = {
    { "Think", "WoundSystem_BloodEffects_Think" },
    { "PostDrawTranslucentRenderables", "WoundSystem_BloodEffects_Draw" },
    { "PostDrawTranslucentRenderables", "WoundSystem_FurBloodRagdollOverlay" },
    { "PostPlayerDraw", "WoundSystem_FurBloodModelOverlay" },
}

-- Client convars of C:U that also drive visuals outside the hooks above.
-- Applied ONCE per session; set zc_woundsystem_compat_disable_cu_fx 0 and
-- zc_woundsystem_compat_disable_cu_blood 0 to opt out.
local CU_VISUAL_CVARS = {
    woundsys_blood_effects = "0",
    woundsys_blood_stains = "0",
    woundsys_blood_trails = "0",
    woundsys_blood_bodyflow = "0",
    woundsys_blood_quality = "0",
    woundsys_fur_blood_models = "0",
    woundsys_moodles_enabled = "0",
    woundsys_nausea_enabled = "0",
    woundsys_pain_shader_enabled = "0",
    woundsys_pain_visual_strength = "0",
    woundsys_visual_quality = "0",
    woundsys_brain_ui_text_corruption = "0",
    woundsys_self_talk_enabled = "0",
    -- C:U audio effects (ZCity owns its own soundscape).
    woundsys_audio_master = "0",
    woundsys_music_enabled = "0",
    woundsys_music_sadness_distortion = "0",
    woundsys_tinnitus_volume = "0",
    woundsys_pain_sounds_enabled = "0",
    woundsys_death_sounds_enabled = "0",
    woundsys_growl_sounds_enabled = "0",
    woundsys_chat_distortion_enabled = "0",
    woundsys_gunshot_hearing_enabled = "0",
    woundsys_hev_enabled = "0",
}

WSZC.CUFxSaved = WSZC.CUFxSaved or {}
local cvarsApplied = false

local function ApplyList(list, enabled)
    local hooks = hook.GetTable and hook.GetTable() or {}
    for _, pair in ipairs(list) do
        local event, name = pair[1], pair[2]
        local key = event .. "/" .. name
        local current = hooks[event] and hooks[event][name]
        if enabled then
            if type(current) == "function" and WSZC.CUFxSaved[key] == nil then
                WSZC.CUFxSaved[key] = current
            end
            if current ~= nil and hook.Remove then hook.Remove(event, name) end
        else
            if WSZC.CUFxSaved[key] ~= nil then
                if current == nil and hook.Add then hook.Add(event, name, WSZC.CUFxSaved[key]) end
                WSZC.CUFxSaved[key] = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- C:U death screen: keep the RESPAWN INPUT, drop the VISUALS
---------------------------------------------------------------------------
-- cl_health_gui.lua:5716 lives inside WoundSystem_DeathScreenDisplay:
--   input.IsMouseDown(MOUSE_LEFT) -> net.Start("WoundSystem_PlayerRespawnRequest")
-- Server-side sv_deathscreen.lua:WoundSystem_BlockRespawn returns false until
-- that message arrives.  Removing the HUDPaint hook (previous releases) killed
-- respawn entirely.  We now replace the hook with a wrapper that calls the
-- original (so SetDeathScreenActive / clickDebounce / the net message / cursor
-- release all still work) while WSZC.CUDeathVisualsHidden makes every wrapped
-- draw primitive a no-op for the duration of that one hook call.
local DEATH_HOOK = "WoundSystem_DeathScreenDisplay"
local DEATH_KEY = "HUDPaint/" .. DEATH_HOOK
local deathWrapper, savedDeathFn

local function RestoreCUDeathScreen()
    WSZC.CUDeathScreenWrapped = false
    if not savedDeathFn then return end
    local hooks = hook.GetTable and hook.GetTable() or {}
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    if type(hud) == "table" and hud[DEATH_HOOK] == deathWrapper and hook.Add then
        hook.Add("HUDPaint", DEATH_HOOK, savedDeathFn)
    end
    savedDeathFn, deathWrapper = nil, nil
end

local function WrapCUDeathScreen()
    if not cvDisableFX:GetBool() then
        RestoreCUDeathScreen()
        return false
    end
    local hooks = hook.GetTable and hook.GetTable() or {}
    local hud = type(hooks) == "table" and hooks.HUDPaint or nil
    if type(hud) ~= "table" then
        WSZC.CUDeathScreenWrapped = false
        return false
    end
    local fn = hud[DEATH_HOOK]
    -- A previous Apply() run (or an older release hot-reload) may have left
    -- the hook removed; restore from the saved callback first.
    if type(fn) ~= "function" and type(WSZC.CUFxSaved[DEATH_KEY]) == "function" then
        fn = WSZC.CUFxSaved[DEATH_KEY]
        WSZC.CUFxSaved[DEATH_KEY] = nil
        if hook.Add then hook.Add("HUDPaint", DEATH_HOOK, fn) end
    end
    if type(fn) ~= "function" then
        WSZC.CUDeathScreenWrapped = false
        return false
    end
    if fn == deathWrapper then
        WSZC.CUDeathScreenWrapped = true
        return true
    end

    savedDeathFn = fn
    deathWrapper = function(...)
        if not cvDisableFX:GetBool() then return fn(...) end
        local prevHidden = WSZC.CUDeathVisualsHidden
        WSZC.CUDeathVisualsHidden = true
        local ok, a, b, c = pcall(fn, ...)
        WSZC.CUDeathVisualsHidden = prevHidden
        if not ok then error(a, 0) end
        return a, b, c
    end
    -- hook.Add with the same identifier is the supported replacement (writing
    -- into hook.GetTable() is a no-op on builds that return a defensive copy).
    hook.Add("HUDPaint", DEATH_HOOK, deathWrapper)
    WSZC.CUDeathScreenWrapped = true
    return true
end
WSZC.WrapCUDeathScreen = WrapCUDeathScreen
WSZC.RestoreCUDeathScreen = RestoreCUDeathScreen

-- Safety net for builds where C:U's death-screen hook is missing or renamed:
-- reproduce ONLY the respawn request, never any C:U death artwork.  Skipped as
-- soon as the real hook has been wrapped successfully.
local deathAt, deathSent, deathCursor = nil, false, false
hook.Add("Think", "WSZC_CUDeathRespawnFallback", function()
    local ply = LocalPlayer and LocalPlayer() or nil
    if not (ply and IsValid and IsValid(ply)) then return end
    local alive = true
    if type(ply.Alive) == "function" then
        local ok, isAlive = pcall(ply.Alive, ply)
        if ok then alive = isAlive ~= false end
    end
    if alive then
        if deathAt then
            deathAt, deathSent = nil, false
            if deathCursor then
                deathCursor = false
                if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
                if WoundSystem and WoundSystem.HealthGUI
                    and WoundSystem.HealthGUI.SetScreenClickerOwned then
                    pcall(WoundSystem.HealthGUI.SetScreenClickerOwned, false, "wszc_respawn")
                end
            end
        end
        return
    end
    if WSZC.CUDeathScreenWrapped == true then return end
    local now = CurTime and CurTime() or 0
    if not deathAt then deathAt, deathSent = now, false end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(true) end
    deathCursor = true
    if now - deathAt < 1.0 then return end
    local down = input and input.IsMouseDown
        and input.IsMouseDown(MOUSE_LEFT or 107) or false
    if down and not deathSent and net and net.Start and net.SendToServer then
        deathSent = true
        -- pcall: on a build where the net string is not pooled, one failed
        -- request must never throw inside a Think hook.
        pcall(function()
            net.Start("WoundSystem_PlayerRespawnRequest")
            net.SendToServer()
        end)
    end
end)

-- cl_text_corruption.lua corrupts every C:U UI string through two exported
-- functions.  They are not hooks, so neutralise them explicitly.
local savedCorrupt, savedShouldCorrupt
local function ApplyTextCorruption(enabled)
    local tc = WoundSystem and WoundSystem.TextCorruption
    if type(tc) ~= "table" then return end
    if enabled then
        if type(tc.Corrupt) == "function" and not savedCorrupt then savedCorrupt = tc.Corrupt end
        if type(tc.ShouldCorrupt) == "function" and not savedShouldCorrupt then
            savedShouldCorrupt = tc.ShouldCorrupt
        end
        tc.ShouldCorrupt = function() return false end
        tc.Corrupt = function(text) return tostring(text or "") end
    else
        if savedShouldCorrupt then tc.ShouldCorrupt = savedShouldCorrupt; savedShouldCorrupt = nil end
        if savedCorrupt then tc.Corrupt = savedCorrupt; savedCorrupt = nil end
    end
end

local function ApplyCvars()
    if cvarsApplied then return end
    if not (cvDisableFX:GetBool() or cvDisableBlood:GetBool()) then return end
    if not (RunConsoleCommand and ConVarExists) then return end
    -- Wait until C:U has created its convars, otherwise CreateClientConVar in
    -- C:U would later overwrite our values with its defaults.
    if not (ConVarExists("woundsys_blood_effects") or ConVarExists("woundsys_moodles_enabled")
        or ConVarExists("woundsys_audio_master") or ConVarExists("woundsys_pain_shader_enabled")) then return end
    cvarsApplied = true
    for name, value in pairs(CU_VISUAL_CVARS) do
        if ConVarExists(name) then pcall(RunConsoleCommand, name, value) end
    end
end

local function Apply()
    ApplyList(FX_HOOKS, cvDisableFX:GetBool())
    ApplyList(BLOOD_HOOKS, cvDisableBlood:GetBool())
    ApplyTextCorruption(cvDisableFX:GetBool())
    WrapCUDeathScreen()
    ApplyCvars()
end
WSZC.ApplyCUFxFilter = Apply

-- C:U may load after us and re-add EYEVIEW_CalcView from its own Think hook.
local nextApply = 0
hook.Add("Think", "WSZC_CUFxFilter", function()
    local now = CurTime and CurTime() or 0
    if now < nextApply then return end
    nextApply = now + 1.0
    Apply()
end)
hook.Add("InitPostEntity", "WSZC_CUFxFilterInit", Apply)

-- Do not leave C:U hooks removed when the addon is hot-reloaded / map changes.
hook.Add("ShutDown", "WSZC_CUFxFilterRestore", function()
    RestoreCUDeathScreen()
    ApplyList(FX_HOOKS, false)
    ApplyList(BLOOD_HOOKS, false)
    ApplyTextCorruption(false)
end)
