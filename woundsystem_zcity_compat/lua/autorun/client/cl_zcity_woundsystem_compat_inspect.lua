-- ZCity <-> Casualties: Unknown: injury-inspection button (client part)
--
-- ZCity already ships an "Examine Body" option in its radial selector
-- (lua/homigrad/woundbridge/cl_woundbridge.lua).  This file makes that option
-- open the native C:U health/wound panel, gives it the requested Russian
-- label, and adds the option itself when the stock ZCity hook is missing.
-- No original ZIP addon is edited and no second HUD/menu is drawn: the button
-- only calls WoundSystem.OpenHealthHUD() from Casualties: Unknown.

if not CLIENT then return end

WSZC = WSZC or {}

if WSZC._InspectClientLoaded then return end
WSZC._InspectClientLoaded = true

local BUTTON_LABEL = "Проверить травмы"
local OPEN_DELAY = 0.12 -- let the radial menu fade out before C:U grabs the mouse

local cvButton
if CreateClientConVar then
    cvButton = CreateClientConVar(
        "zc_woundsystem_compat_inspect_button", "1", true, false,
        "Show the injury-inspection button in the ZCity radial menu (opens the C:U health panel)"
    )
end
if not cvButton and GetConVar then
    cvButton = GetConVar("zc_woundsystem_compat_inspect_button")
end

local function ConVarAllows(name)
    if not GetConVar then return true end
    local cv = GetConVar(name)
    if not (cv and cv.GetBool) then return true end
    return cv:GetBool() ~= false
end

local function CompatInspectEnabled()
    if cvButton and cvButton.GetBool and not cvButton:GetBool() then return false end
    if not ConVarAllows("zc_woundsystem_bridge") then return false end
    if not ConVarAllows("woundsys_enabled") then return false end
    if GetGlobalBool and GetGlobalBool("WSZC_Ready", false) ~= true then return false end
    if WSZC.Supports and not WSZC.Supports("inspection") then return false end
    if not (WoundSystem and WoundSystem.Health) then return false end
    if not (WoundSystem.OpenHealthHUD or WoundSystem.ToggleHealthHUD) then return false end

    -- Do NOT gate this on WB.IsEnabled(): in organism-authority mode the client
    -- deliberately reports the bridge as off so ZCity keeps its stock HUD, yet
    -- the C:U panel is still the requested injury-inspection surface.  The
    -- networked WSZC_Ready flag above is the authoritative readiness check.
    local WB = hg and hg.WoundBridge
    if not WB then return false end
    return true
end

local function OpenCUHealthPanel()
    -- Open (not toggle): pressing the radial button must never close an already
    -- open C:U panel.  ToggleHealthHUD / woundsys_open_panel are fallbacks for
    -- a future C:U build that only exposes the older entry points.
    if WSZC.OpenHealthHUDForInspection then
        WSZC.OpenHealthHUDForInspection()
    elseif WoundSystem.OpenHealthHUD then
        WoundSystem.OpenHealthHUD()
    elseif WoundSystem.ToggleHealthHUD then
        WoundSystem.ToggleHealthHUD()
    else
        RunConsoleCommand("woundsys_open_panel")
    end
end

local function DismissInspectRadialMenu(forceRemove)
    local panel = _G and _G.MENUPANELHUYHUY or MENUPANELHUYHUY
    if not IsValid(panel) then return end
    if panel.SetMouseInputEnabled then pcall(panel.SetMouseInputEnabled, panel, false) end
    if forceRemove then
        if panel.Remove then pcall(panel.Remove, panel) end
        MENUPANELHUYHUY = nil
    elseif panel.Close then
        pcall(panel.Close, panel)
    end
end

function WSZC.OpenCUWoundMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    DismissInspectRadialMenu(false)

    timer.Simple(OPEN_DELAY, function()
        if not IsValid(ply) or not ply:Alive() then return end
        if not (WoundSystem and WoundSystem.Health) then return end
        DismissInspectRadialMenu(true)
        OpenCUHealthPanel()
    end)
end

-- Native C:U rejects OpenHealthHUD() while CardioState.unconscious OR the
-- networked unconscious flag is set, and ToggleHUDInput force-closes an already
-- open panel on every Think.  That makes even READ-ONLY inspection impossible
-- after a brain injury.  Mask those two CLIENT-ONLY inputs only while executing
-- C:U's own open/input functions.  The server organism, real ragdoll, damage
-- and minigame incapacity guards are never changed.
local function FindNamedTable(fn, wanted, seen, depth)
    if type(fn) ~= "function" or not (debug and debug.getupvalue) then return nil end
    seen, depth = seen or {}, depth or 0
    if depth > 4 or seen[fn] then return nil end
    seen[fn] = true
    for i = 1, 64 do
        local ok, name, value = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        if name == wanted and type(value) == "table" then return value end
        if type(value) == "function" then
            local found = FindNamedTable(value, wanted, seen, depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function CallWithInspectionAccess(ply, cardio, fn, ...)
    if type(cardio) ~= "table" or type(fn) ~= "function" then return false end
    if not (ply and ply.GetNWBool and ply.SetNWBool) then return false end
    local oldNW = ply:GetNWBool("WoundSystemUnconscious", false)
    local oldUnconscious = cardio.unconscious
    cardio.unconscious = false
    pcall(ply.SetNWBool, ply, "WoundSystemUnconscious", false)
    local ok, err = pcall(fn, ...)
    cardio.unconscious = oldUnconscious
    pcall(ply.SetNWBool, ply, "WoundSystemUnconscious", oldNW)
    if not ok then
        if WSZC.Warn then WSZC.Warn("inspection input bridge failed: " .. tostring(err)) end
        return false
    end
    return true
end

function WSZC.InstallUnconsciousInspectionBridge()
    if type(hook) ~= "table" or type(hook.GetTable) ~= "function" then return false end
    local hooks = hook.GetTable()
    local original = hooks and hooks.Think and hooks.Think.ToggleHUDInput or nil
    if type(original) ~= "function" then return false end
    if original == WSZC._InspectionThinkWrapper and WSZC._InspectionThinkCardio then return true end
    local cardio = FindNamedTable(original, "CardioState")
    if not cardio then return false end

    local function wrapped(...)
        local ply = LocalPlayer()
        if WSZC._InspectionWhileUnconscious == true and IsValid(ply) and ply:Alive()
            and CompatInspectEnabled() then
            local ok = CallWithInspectionAccess(ply, cardio, original, ...)
            if not ok or WoundSystemHealthHUDOpen ~= true then
                WSZC._InspectionWhileUnconscious = nil
            end
            return ok
        end
        return original(...)
    end
    WSZC._InspectionThinkWrapper = wrapped
    WSZC._InspectionThinkCardio = cardio
    hook.Add("Think", "ToggleHUDInput", wrapped)
    return true
end

function WSZC.OpenHealthHUDForInspection()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return false end
    local opener = WoundSystem and (WoundSystem.OpenHealthHUD or WoundSystem.ToggleHealthHUD) or nil
    if type(opener) ~= "function" then return false end
    local cardio = FindNamedTable(opener, "CardioState")
    local unconscious = (cardio and cardio.unconscious == true)
        or (ply.GetNWBool and ply:GetNWBool("WoundSystemUnconscious", false) == true)
    if not unconscious then
        WSZC._InspectionWhileUnconscious = nil
        opener()
        return WoundSystemHealthHUDOpen == true
    end

    -- Install the Think half BEFORE opening; otherwise native closes the panel
    -- again on the next frame.  Without private-state access, fail back to the
    -- unmodified native function instead of inventing a second health UI.
    if not WSZC.InstallUnconsciousInspectionBridge() then
        opener()
        return false
    end
    local ok = CallWithInspectionAccess(ply, cardio, opener)
    local opened = ok and WoundSystemHealthHUDOpen == true
    WSZC._InspectionWhileUnconscious = opened or nil
    return opened
end

-- Any other code that calls WB.OpenWoundView() should use the same C:U entry point.
local function EnsureBridgeWrapper()
    local WB = hg and hg.WoundBridge
    if not WB then return end
    if WB.OpenWoundView == WSZC.OpenCUWoundMenu then return end

    WSZC.OriginalOpenWoundView = WSZC.OriginalOpenWoundView or WB.OpenWoundView
    WB.OpenWoundView = WSZC.OpenCUWoundMenu
end

local function IsInspectOption(option)
    return type(option) == "table"
        and (option._WSZCInspect or option[2] == "Examine Body" or option[2] == BUTTON_LABEL)
end

local function RemoveInspectOption()
    hg = hg or {}
    if type(hg.radialOptions) ~= "table" then return end

    local options = hg.radialOptions
    for i = #options, 1, -1 do
        if IsInspectOption(options[i]) then table.remove(options, i) end
    end
end

local function RepointOrAddOption()
    hg = hg or {}
    hg.radialOptions = hg.radialOptions or {}

    local options = hg.radialOptions
    local kept = false
    for i = #options, 1, -1 do
        local option = options[i]
        if IsInspectOption(option) then
            if kept then
                table.remove(options, i) -- never show two inspection buttons
            else
                kept = true
                option._WSZCInspect = true
                option[1] = function()
                    WSZC.OpenCUWoundMenu()
                    return 0
                end
                option[2] = BUTTON_LABEL
            end
        end
    end
    if kept then return end

    local option = {
        function()
            WSZC.OpenCUWoundMenu()
            return 0
        end,
        BUTTON_LABEL,
    }
    option._WSZCInspect = true
    options[#options + 1] = option
end

-- ZCity's cl_hud.lua runs radialOptions hooks with SortedPairs().  This id sorts
-- *after* "ZCity_WoundBridge_Inspect", so the stock "Examine Body" entry is
-- relabelled/repointed instead of producing a duplicate button.
hook.Add("radialOptions", "ZCity_WoundBridge_Inspect_WSZC", function()
    if not CompatInspectEnabled() then
        -- The stock ZCity hook may still have added "Examine Body"; hide it too
        -- when the compatibility button is disabled/unavailable.  Most
        -- importantly, do not replace WB.OpenWoundView on an unsupported core.
        RemoveInspectOption()
        return
    end

    EnsureBridgeWrapper()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then
        RemoveInspectOption()
        return
    end

    RepointOrAddOption()
end)

function WSZC.IsLegacyRadialMedicalOption(option)
    if type(option) ~= "table" or option._WSZCInspect or option._WSZCRemoteInspect then
        return false
    end
    local label = string.lower(tostring(option[2] or ""))
    return string.find(label, "dislocation", 1, true) ~= nil
        or string.find(label, "вывих", 1, true) ~= nil
        or string.find(label, "вправ", 1, true) ~= nil
end

-- ZCity's DislocatedJoint/DislocatedJoint2 hooks add the OLD random-chance
-- hg_fixdislocation treatment.  This id sorts after them (and after our two
-- inspection providers), so every 0.25 s radial rebuild is filtered as well.
-- Inspection and remote WSZC treatment remain; non-medical gestures/phrases
-- are untouched.  The server separately blocks the command, so a direct bind
-- or a stale already-open menu cannot bypass this filter.
hook.Add("radialOptions", "zzzz_WSZC_DisableLegacyMedicine", function()
    if not WSZC.LegacyRadialMedicineBlocked or not WSZC.LegacyRadialMedicineBlocked() then return end
    local options = hg and hg.radialOptions
    if type(options) ~= "table" then return end
    for i = #options, 1, -1 do
        if WSZC.IsLegacyRadialMedicalOption(options[i]) then table.remove(options, i) end
    end
end)

-- Handy for binds/diagnostics; uses exactly the same C:U panel as the button.
concommand.Add("wszc_open_wounds", function()
    WSZC.OpenCUWoundMenu()
end)

---------------------------------------------------------------------------
-- WoundView keeps the native C:U limb action point for procedures such as
-- removing shrapnel or a tourniquet and reducing dislocations.  Medicine,
-- bandages and tourniquet application are performed with the held ZCity SWEP,
-- not by adding an inventory strip or duplicate buttons to the panel.
---------------------------------------------------------------------------
local function TryInstallInspectBridges()
    return WSZC.InstallUnconsciousInspectionBridge
        and WSZC.InstallUnconsciousInspectionBridge()
end

TryInstallInspectBridges()
hook.Add("InitPostEntity", "WSZC_InspectBridgesInit", function()
    TryInstallInspectBridges()
end)
if timer and timer.Create then
    timer.Create("WSZC_InspectBridgesRetry", 1, 15, function()
        if TryInstallInspectBridges() and timer.Remove then
            timer.Remove("WSZC_InspectBridgesRetry")
        end
    end)
end

