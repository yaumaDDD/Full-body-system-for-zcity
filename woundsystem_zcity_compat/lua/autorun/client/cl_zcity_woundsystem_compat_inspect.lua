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

function WSZC.OpenCUWoundMenu()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    timer.Simple(OPEN_DELAY, function()
        if not IsValid(ply) or not ply:Alive() then return end
        if not (WoundSystem and WoundSystem.Health) then return end
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

local function IsWoundViewKeyDown()
    if not input or type(input.IsKeyDown) ~= "function" then return false end
    local cv = GetConVar and GetConVar("woundsys_woundview_key")
    local keyName = cv and cv.GetString and string.upper(tostring(cv:GetString() or "")) or "T"
    if keyName == "" then keyName = "T" end
    local keyCode = _G["KEY_" .. keyName] or _G[keyName]
    return input.IsKeyDown(keyCode or KEY_T or 30) == true
end

function WSZC.InstallUnconsciousInspectionBridge()
    if type(hook) ~= "table" or type(hook.GetTable) ~= "function" then return false end
    local hooks = hook.GetTable()
    local original = hooks and hooks.Think and hooks.Think.ToggleHUDInput or nil
    if type(original) ~= "function" then return false end
    if original == WSZC._InspectionThinkWrapper and WSZC._InspectionThinkCardio then return true end
    local cardio = FindNamedTable(original, "CardioState")
    if not cardio then return false end
    local guiState = FindNamedTable(original, "GUIState")

    local function wrapped(...)
        local ply = LocalPlayer()
        local keyDown = IsWoundViewKeyDown()
        local wasDown = WSZC._LastInspectKeyDown == true
        WSZC._LastInspectKeyDown = keyDown

        -- Pressing T (woundsys_woundview_key) while aiming at a living or
        -- unconscious patient within medical range opens THAT patient's
        -- WoundView immediately instead of the medic's own healthy body.
        if WoundSystemHealthHUDOpen ~= true and keyDown and not wasDown
            and IsValid(ply) and ply:Alive()
            and not (vgui and vgui.GetKeyboardFocus and vgui.GetKeyboardFocus() ~= nil)
            and not (WoundSystem and WoundSystem.HealthGUI
                and WoundSystem.HealthGUI.IsExternalMenuOpen
                and WoundSystem.HealthGUI.IsExternalMenuOpen()) then
            local remote = WSZC.RemoteMedical
            local patient = remote and type(remote.FindPatient) == "function"
                and remote.FindPatient() or nil
            if IsValid(patient) and WSZC.OpenRemotePatient
                and WSZC.OpenRemotePatient(patient, true) then
                if type(guiState) == "table" then guiState.lastKeyStatus = true end
                return true
            end
        end

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
                option[1] = function() WSZC.OpenCUWoundMenu() end
                option[2] = BUTTON_LABEL
            end
        end
    end
    if kept then return end

    local option = { function() WSZC.OpenCUWoundMenu() end, BUTTON_LABEL }
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
-- WoundView ZCity treatment actions (self + remote patient)
---------------------------------------------------------------------------
local function ClampVal(v, lo, hi)
    v = tonumber(v) or 0
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function RoundVal(v)
    v = tonumber(v) or 0
    return v >= 0 and math.floor(v + 0.5) or math.ceil(v - 0.5)
end

local function ColVal(r, g, b, a)
    if Color then return Color(r, g, b, a or 255) end
    return { r = r, g = g, b = b, a = a or 255 }
end

local EXTREMITY_LIMBS = {
    arm_L = true, arm_R = true, forearm_L = true, forearm_R = true, hand_L = true, hand_R = true,
    thigh_L = true, thigh_R = true, crus_L = true, crus_R = true,
    leg_L = true, leg_R = true, foot_L = true, foot_R = true,
}

local ZCITY_MED_BAR_DEFS = {
    { class = "weapon_bandage_sh",    mode = 1, label = "БИНТ",           defMax = 40 },
    { class = "weapon_bigbandage_sh", mode = 1, label = "БОЛЬШОЙ БИНТ",   defMax = 150 },
    { class = "weapon_wszc_bandage",  mode = 1, label = "БИНТ WSZC",      defMax = 40 },
    { class = "weapon_tourniquet",    mode = 1, label = "ЖГУТ",           defMax = 1, binary = true },
    { class = "weapon_medkit_sh",     mode = 1, label = "АПТЕЧКА: БИНТ",  defMax = 80 },
    { class = "weapon_medkit_sh",     mode = 2, label = "АПТЕЧКА: ОБЕЗБ.", defMax = 1, binary = true },
    { class = "weapon_medkit_sh",     mode = 3, label = "АПТЕЧКА: ШВЫ",   defMax = 60 },
    { class = "weapon_medkit_sh",     mode = 4, label = "АПТЕЧКА: ЖГУТ",  defMax = 1, binary = true },
    { class = "weapon_medkit_sh",     mode = 5, label = "АПТЕЧКА: ДЕКОМПР.", defMax = 1, binary = true },
    { class = "weapon_painkillers",   mode = 1, label = "ОБЕЗБОЛИВАЮЩЕЕ", defMax = 1 },
    { class = "weapon_morphine",      mode = 1, label = "МОРФИН",         defMax = 1 },
    { class = "weapon_fentanyl",      mode = 1, label = "ФЕНТАНИЛ",       defMax = 1 },
    { class = "weapon_adrenaline",    mode = 1, label = "АДРЕНАЛИН",      defMax = 1 },
    { class = "weapon_mannitol",      mode = 1, label = "МАННИТОЛ",       defMax = 1 },
    { class = "weapon_naloxone",      mode = 1, label = "НАЛОКСОН",       defMax = 1 },
    { class = "weapon_betablock",     mode = 1, label = "БЕТА-БЛОКАТОР",  defMax = 1 },
    { class = "weapon_needle",        mode = 1, label = "ИГЛА ДЕКОМПР.",  defMax = 1, binary = true },
    { class = "weapon_bloodbag",      mode = 1, label = "ПАКЕТ КРОВИ",    defMax = 1 },
}

local function WeaponModeRemaining(wep, modeIdx, defMax)
    if not IsValid(wep) then return 0 end
    modeIdx = modeIdx or 1
    local mv = wep.modeValues
    if type(mv) ~= "table" and wep.GetNetVar then
        local ok, netMv = pcall(wep.GetNetVar, wep, "modeValues")
        if ok and type(netMv) == "table" then mv = netMv end
    end
    if type(mv) == "table" and mv[modeIdx] ~= nil then
        return math.max(tonumber(mv[modeIdx]) or 0, 0)
    end
    local mdef = wep.modeValuesdef
    if type(mdef) == "table" and mdef[modeIdx] ~= nil then
        local entry = mdef[modeIdx]
        local v = type(entry) == "table" and entry[1] or entry
        return math.max(tonumber(v) or defMax or 1, 0)
    end
    return defMax or 1
end

local function OperatorCarriedWeapons(ply)
    local out = {}
    if not (IsValid(ply) and ply.GetWeapons) then return out end
    local ok, weps = pcall(ply.GetWeapons, ply)
    if not ok or type(weps) ~= "table" then return out end
    for _, wep in ipairs(weps) do
        if IsValid(wep) and wep.GetClass then
            local okCls, cls = pcall(wep.GetClass, wep)
            if okCls and type(cls) == "string" and cls ~= "" then
                out[#out + 1] = { wep = wep, class = cls }
            end
        end
    end
    return out
end

local function BestOperatorBandageCharge(ply)
    local best = 0
    for _, item in ipairs(OperatorCarriedWeapons(ply)) do
        local cls = item.class
        if cls == "weapon_bandage_sh" or cls == "weapon_wszc_bandage" then
            best = math.max(best, WeaponModeRemaining(item.wep, 1, 40))
        elseif cls == "weapon_bigbandage_sh" then
            best = math.max(best, WeaponModeRemaining(item.wep, 1, 150))
        elseif cls == "weapon_medkit_sh" then
            best = math.max(best, WeaponModeRemaining(item.wep, 1, 80))
        end
    end
    return best
end

local function HasOperatorTourniquet(ply)
    for _, item in ipairs(OperatorCarriedWeapons(ply)) do
        if item.class == "weapon_tourniquet" and WeaponModeRemaining(item.wep, 1, 1) > 0 then
            return true
        elseif item.class == "weapon_medkit_sh" and WeaponModeRemaining(item.wep, 4, 1) > 0 then
            return true
        end
    end
    return false
end

local function CurrentWoundViewPatient()
    local remote = WSZC.RemoteMedical
    if remote and remote.active and IsValid(remote.target) then
        return remote.target, true
    end
    return LocalPlayer and LocalPlayer() or nil, false
end

function WSZC.SendWoundViewTreat(target, limbId, actionKind, weaponClass, modeIdx)
    if not (net and net.Start and net.SendToServer) then return false end
    target = IsValid(target) and target or CurrentWoundViewPatient()
    if not IsValid(target) then return false end
    net.Start("WSZC_WoundViewTreat")
        if net.WriteEntity then net.WriteEntity(target) end
        if net.WriteString then
            net.WriteString(tostring(limbId or ""))
            net.WriteString(tostring(actionKind or ""))
            net.WriteString(tostring(weaponClass or ""))
        end
        if net.WriteUInt then net.WriteUInt(ClampVal(math.floor(tonumber(modeIdx) or 1), 1, 5), 4) end
    net.SendToServer()
    return true
end

local function ScaledFont(baseName, scale)
    if type(WoundSystemGetFont) == "function" then
        local ok, f = pcall(WoundSystemGetFont, baseName, scale or 1)
        if ok and type(f) == "string" and f ~= "" then return f end
    end
    return "DermaDefaultBold"
end

local function DrawTacticalPill(x, y, w, h, label, mx, my, accentCol, enabled)
    local hovered = enabled ~= false and mx >= x and mx <= (x + w) and my >= y and my <= (y + h)
    if surface and surface.SetDrawColor and surface.DrawRect then
        if enabled == false then
            surface.SetDrawColor(18, 22, 20, 185)
        elseif hovered then
            surface.SetDrawColor(28, 56, 40, 238)
        else
            surface.SetDrawColor(12, 24, 18, 218)
        end
        surface.DrawRect(math.floor(x), math.floor(y), math.floor(w), math.floor(h))

        local br = accentCol or ColVal(64, 226, 138, 255)
        local alpha = enabled == false and 95 or (hovered and 255 or 185)
        surface.SetDrawColor(br.r, br.g, br.b, alpha)
        if surface.DrawOutlinedRect then
            surface.DrawOutlinedRect(math.floor(x), math.floor(y), math.floor(w), math.floor(h), 1)
        end
        surface.DrawRect(math.floor(x), math.floor(y), 3, math.floor(h))
    end
    if draw and draw.SimpleText then
        local textCol = enabled == false and ColVal(145, 155, 150, 170)
            or (hovered and ColVal(225, 255, 235, 255) or (accentCol or ColVal(86, 235, 148, 245)))
        local scale = (ScrH and ScrH() or 1080) / 1080
        draw.SimpleText(
            label,
            ScaledFont("CrunchyTechFont", scale),
            math.floor(x + 10),
            math.floor(y + h * 0.5),
            textCol,
            TEXT_ALIGN_LEFT or 0,
            TEXT_ALIGN_CENTER or 1
        )
    end
    return hovered
end

local function HasNativeLimbAction(state)
    if type(state) ~= "table" then return false end
    local statuses = state.customStatuses
    if type(statuses) == "table" and (statuses.TOURNIQUET or statuses.SPLINTED) then return true end
    if (tonumber(state.shrapnel) or 0) > 0 then return true end
    if state.dislocated == true then return true end
    return false
end

local function BuildLimbContextActions(ply, limbId, state)
    local actions = {}
    if not (IsValid(ply) and type(limbId) == "string" and type(state) == "table") then
        return actions
    end
    local statuses = type(state.customStatuses) == "table" and state.customStatuses or {}
    local bleed = tonumber(state.bleed) or 0
    local arterial = statuses.WSZC_ARTERIAL_BLEEDING ~= nil and statuses.WSZC_ARTERIAL_BLEEDING ~= false
    local hasTourniquet = statuses.TOURNIQUET ~= nil and statuses.TOURNIQUET ~= false

    if EXTREMITY_LIMBS[limbId] and not hasTourniquet and (bleed > 0 or arterial)
        and HasOperatorTourniquet(ply) then
        actions[#actions + 1] = {
            kind = "tourniquet",
            label = arterial and "НАЛОЖИТЬ ЖГУТ (АРТЕРИЯ!)" or "НАЛОЖИТЬ ЖГУТ",
            color = arterial and ColVal(255, 92, 92, 255) or ColVal(255, 184, 77, 255),
            enabled = true,
        }
    end

    local bestBandage = BestOperatorBandageCharge(ply)
    if bestBandage > 0.05 and bleed > 0 and state.isBandaged ~= true then
        actions[#actions + 1] = {
            kind = "bandage_wound",
            label = "ПЕРЕВЯЗАТЬ РАНУ",
            color = ColVal(86, 235, 148, 255),
            enabled = true,
        }
    end

    local fractureBandaged = statuses.WSZC_FRACTURE_BANDAGED == true
    if state.broken == true and not fractureBandaged and bestBandage > 0.05 then
        local need = (ply.Profession == "doctor") and 5 or 25
        local enough = bestBandage >= need - 0.001
        actions[#actions + 1] = {
            kind = "bandage_fracture",
            label = enough and "ПЕРЕБИНТОВАТЬ ПЕРЕЛОМ"
                or ("ПЕРЕЛОМ: МАЛО БИНТА (" .. tostring(RoundVal(bestBandage)) .. "/" .. tostring(need) .. ")"),
            color = enough and ColVal(110, 220, 255, 255) or ColVal(150, 160, 165, 190),
            enabled = enough or bestBandage >= 5,
        }
    end

    return actions
end

function WSZC.InstallLimbActionButtons()
    local original = _G.WoundSystemDrawLimbActionPoint
    if type(original) ~= "function" then return false end
    if original == WSZC._LimbActionPointWrapper then return true end

    local function wrapped(limbId, state, pointPos, bX, bY, scale, dollScale, mx, my, isClicking, lastMouseState, minigameActive)
        original(limbId, state, pointPos, bX, bY, scale, dollScale, mx, my, isClicking, lastMouseState, minigameActive)

        local ply = LocalPlayer and LocalPlayer() or nil
        if not (IsValid(ply) and ply:Alive()) then
            WSZC._ActiveLimbTreatRects = nil
            return
        end
        local actions = BuildLimbContextActions(ply, limbId, state)
        if #actions == 0 then
            WSZC._ActiveLimbTreatRects = nil
            return
        end

        local s = tonumber(scale) or 1
        local ds = tonumber(dollScale) or (1.5 * s)
        local hasNative = HasNativeLimbAction(state)
        local targetX = (type(pointPos) == "table" and tonumber(pointPos.x) and (pointPos.x + 34 * ds))
            or ((tonumber(bX) or 400) + 285 * s)
        local targetY = (type(pointPos) == "table" and tonumber(pointPos.y) and (pointPos.y - 60 * ds))
            or ((tonumber(bY) or 300) + 164 * s)
        local anchor = _G.WoundSystemActionButtonPos
        if not hasNative and type(anchor) == "table" then
            anchor.x, anchor.y = targetX, targetY
        end
        local baseX = (hasNative and type(anchor) == "table" and tonumber(anchor.x)) or targetX
        local baseY = (hasNative and type(anchor) == "table" and tonumber(anchor.y)) or targetY

        local startRow = hasNative and 1 or 0
        local pillW = math.max(math.floor(228 * s), 165)
        local pillH = math.max(math.floor(26 * s), 22)
        local rowStep = pillH + math.max(math.floor(6 * s), 4)
        local drawX = baseX - math.floor(14 * s)

        local prevFiltered = WSZC.CUHudFiltered
        WSZC.CUHudFiltered = false
        if render and render.SetScissorRect then
            pcall(render.SetScissorRect, 0, 0, 0, 0, false)
        end

        local limbRects = {}
        local target = CurrentWoundViewPatient()
        for i, act in ipairs(actions) do
            local drawY = baseY + (startRow + i - 1) * rowStep - math.floor(pillH * 0.5)
            limbRects[#limbRects + 1] = { x = drawX, y = drawY, w = pillW, h = pillH }
            local hovered = DrawTacticalPill(drawX, drawY, pillW, pillH, act.label,
                tonumber(mx) or -1, tonumber(my) or -1, act.color, act.enabled and not minigameActive)
            if hovered and act.enabled and isClicking and not lastMouseState and not minigameActive then
                if surface and surface.PlaySound then pcall(surface.PlaySound, "UI/buttonclick.wav") end
                WSZC.SendWoundViewTreat(target, limbId, act.kind, "", 1)
            end
        end
        WSZC._ActiveLimbTreatRects = limbRects

        WSZC.CUHudFiltered = prevFiltered
    end

    WSZC._LimbActionPointOriginal = original
    WSZC._LimbActionPointWrapper = wrapped
    _G.WoundSystemDrawLimbActionPoint = wrapped
    return true
end

local lastBarMouseDown = false

local function CollectMedicineBarEntries(ply)
    local entries = {}
    local byClass = {}
    for _, item in ipairs(OperatorCarriedWeapons(ply)) do
        if not byClass[item.class] then byClass[item.class] = item.wep end
    end
    for _, def in ipairs(ZCITY_MED_BAR_DEFS) do
        local wep = byClass[def.class]
        if IsValid(wep) then
            local rem = WeaponModeRemaining(wep, def.mode, def.defMax)
            if rem > 0.02 then
                local suffix = ""
                if not def.binary and def.defMax > 1 then
                    suffix = " (" .. tostring(ClampVal(RoundVal(rem / def.defMax * 100), 1, 100)) .. "%)"
                end
                entries[#entries + 1] = {
                    class = def.class,
                    mode = def.mode,
                    label = def.label .. suffix,
                }
            end
        end
    end
    return entries
end

local function AnyOverlayMinigameOpen()
    if WSZC.WSZCMinigameActive and WSZC.WSZCMinigameActive() then return true end
    if WSZC.NativeMinigameActive and WSZC.NativeMinigameActive() then return true end
    if type(WoundSystemIsAnyWoundMinigameActive) == "function"
        and WoundSystemIsAnyWoundMinigameActive() then
        return true
    end
    return false
end

hook.Add("PostDrawHUD", "WSZC_WoundViewTreatHUD", function()
    local ply = LocalPlayer and LocalPlayer() or nil
    if not (IsValid(ply) and ply:Alive()) then
        lastBarMouseDown = false
        return
    end
    if not CompatInspectEnabled() then
        lastBarMouseDown = false
        return
    end

    local scrW = ScrW and ScrW() or 1920
    local scrH = ScrH and ScrH() or 1080
    local scale = scrH / 1080

    -- 1) World crosshair prompt when aiming at another player outside WoundView
    if WoundSystemHealthHUDOpen ~= true then
        lastBarMouseDown = false
        WSZC._ActiveLimbTreatRects = nil
        WSZC._ActiveTreatRects = nil
        if IsValid(MENUPANELHUYHUY) then return end
        local remote = WSZC.RemoteMedical
        local patient = remote and type(remote.FindPatient) == "function"
            and remote.FindPatient() or nil
        if not IsValid(patient) then return end

        local pEnt = remote.PatientEntity and remote.PatientEntity(patient) or patient
        local isRagdoll = IsValid(pEnt) and pEnt ~= patient
        local nick = patient.Nick and patient:Nick() or "Игрок"
        local statusTxt = isRagdoll and " • БЕЗ СОЗНАНИЯ" or ""
        local line1 = "[T] ЛЕЧИТЬ: " .. tostring(nick) .. statusTxt
        local cx, cy = math.floor(scrW * 0.5), math.floor(scrH * 0.56)

        local prevFiltered = WSZC.CUHudFiltered
        WSZC.CUHudFiltered = false
        if surface and surface.SetDrawColor and surface.DrawRect then
            local boxW, boxH = math.max(math.floor(290 * scale), 220), math.max(math.floor(32 * scale), 24)
            surface.SetDrawColor(10, 20, 15, 200)
            surface.DrawRect(cx - math.floor(boxW * 0.5), cy - math.floor(boxH * 0.5), boxW, boxH)
            surface.SetDrawColor(72, 226, 140, 190)
            if surface.DrawOutlinedRect then
                surface.DrawOutlinedRect(cx - math.floor(boxW * 0.5), cy - math.floor(boxH * 0.5), boxW, boxH, 1)
            end
        end
        if draw and draw.SimpleText then
            draw.SimpleText(
                line1,
                ScaledFont("CrunchyTechFont", scale),
                cx, cy,
                isRagdoll and ColVal(255, 196, 92, 245) or ColVal(96, 240, 154, 245),
                TEXT_ALIGN_CENTER or 1,
                TEXT_ALIGN_CENTER or 1
            )
        end
        WSZC.CUHudFiltered = prevFiltered
        return
    end

    -- 2) Inside open WoundView (skip while a minigame overlay owns the screen)
    if AnyOverlayMinigameOpen() then
        lastBarMouseDown = input and input.IsMouseDown and input.IsMouseDown(MOUSE_LEFT or 107) == true or false
        return
    end

    local prevFiltered = WSZC.CUHudFiltered
    WSZC.CUHudFiltered = false

    local target, isRemote = CurrentWoundViewPatient()
    local remote = WSZC.RemoteMedical
    if isRemote and IsValid(target) then
        local pName = (remote and remote.patientName) or (target.Nick and target:Nick()) or "Игрок"
        local unc = remote and remote.patientUnconscious == true
        local header = "ПАЦИЕНТ: " .. tostring(pName)
            .. (unc and "  [БЕЗ СОЗНАНИЯ]" or "  [В СОЗНАНИИ]")
            .. "   •   [T] ЗАКРЫТЬ"
        local bw = math.max(math.floor(440 * scale), 320)
        local bh = math.max(math.floor(32 * scale), 24)
        local bx = math.floor((scrW - bw) * 0.5)
        local by = math.max(math.floor(18 * scale), 12)
        if surface and surface.SetDrawColor and surface.DrawRect then
            surface.SetDrawColor(10, 22, 16, 222)
            surface.DrawRect(bx, by, bw, bh)
            local borderCol = unc and ColVal(255, 176, 76, 220) or ColVal(72, 226, 140, 220)
            surface.SetDrawColor(borderCol.r, borderCol.g, borderCol.b, borderCol.a)
            if surface.DrawOutlinedRect then surface.DrawOutlinedRect(bx, by, bw, bh, 1) end
        end
        if draw and draw.SimpleText then
            draw.SimpleText(
                header,
                ScaledFont("CrunchyTechFont", scale),
                math.floor(scrW * 0.5),
                math.floor(by + bh * 0.5),
                unc and ColVal(255, 204, 110, 255) or ColVal(110, 245, 162, 255),
                TEXT_ALIGN_CENTER or 1,
                TEXT_ALIGN_CENTER or 1
            )
        end
    end

    -- 3) Bottom ZCity medicine strip (applies carried SWEPs to selected limb or auto-best limb)
    local entries = CollectMedicineBarEntries(ply)
    local mx, my = -1, -1
    if gui and gui.MousePos then mx, my = gui.MousePos() end
    local clicking = input and input.IsMouseDown and input.IsMouseDown(MOUSE_LEFT or 107) == true or false
    local combinedRects = {}
    if _G.WoundSystemSelectedLimbId and type(WSZC._ActiveLimbTreatRects) == "table" then
        for _, r in ipairs(WSZC._ActiveLimbTreatRects) do
            combinedRects[#combinedRects + 1] = r
        end
    else
        WSZC._ActiveLimbTreatRects = nil
    end

    if #entries > 0 then
        local pillW = math.max(math.floor(168 * scale), 130)
        local pillH = math.max(math.floor(26 * scale), 22)
        local gap = math.max(math.floor(8 * scale), 6)
        local perRow = math.max(math.min(#entries, math.floor((scrW - 80) / (pillW + gap))), 1)
        local totalRows = math.ceil(#entries / perRow)
        local selectedLimb = tostring(_G.WoundSystemSelectedLimbId or "")

        for idx, entry in ipairs(entries) do
            local row = math.floor((idx - 1) / perRow)
            local col = (idx - 1) % perRow
            local colsInRow = math.min(perRow, #entries - row * perRow)
            local rowWidth = colsInRow * pillW + (colsInRow - 1) * gap
            local rx = math.floor((scrW - rowWidth) * 0.5) + col * (pillW + gap)
            local ry = scrH - math.max(math.floor(24 * scale), 18) - (totalRows - row) * (pillH + gap)
            combinedRects[#combinedRects + 1] = { x = rx, y = ry, w = pillW, h = pillH }
            local hovered = DrawTacticalPill(
                rx, ry, pillW, pillH, entry.label, mx, my,
                ColVal(76, 224, 146, 255), true
            )
            if hovered and clicking and not lastBarMouseDown then
                if surface and surface.PlaySound then pcall(surface.PlaySound, "UI/buttonclick.wav") end
                WSZC.SendWoundViewTreat(target, selectedLimb, "swep", entry.class, entry.mode)
            end
        end
    end
    WSZC._ActiveTreatRects = #combinedRects > 0 and combinedRects or nil

    lastBarMouseDown = clicking
    WSZC.CUHudFiltered = prevFiltered
end)

local function TryInstallInspectBridges()
    local a = WSZC.InstallUnconsciousInspectionBridge and WSZC.InstallUnconsciousInspectionBridge()
    local b = WSZC.InstallLimbActionButtons and WSZC.InstallLimbActionButtons()
    return a and b
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

