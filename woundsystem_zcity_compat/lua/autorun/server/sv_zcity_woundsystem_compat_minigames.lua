-- ZCity <-> Casualties: Unknown external minigames (server part)
--
-- ZCity's WB.StartMinigame() calls WoundSystem.Health.StartExternalMinigame()
-- only for specs that carry `spec.mg`.  After the project owner's correction,
-- a minigame is opened ONLY for bandages and continuous syringe drugs.
-- One-dose specs are applied instantly by the original WB.SwepHeal fallback,
-- even though ZCity declares `spec.mg` for them:
--   weapon_naloxone, weapon_needle, weapon_adrenaline, weapon_betablock,
--   weapon_mannitol, weapon_thiamine, medkit modes 2/3/5.
-- The general rule is `oneDose`: spec.oneshot, mg.vehicle, kind=apply/body.
-- Instant specs without `mg` (tourniquet, painkillers, medkit mode 4, blood
-- bag, ...) never reach this API at all.
--
-- The supplied C:U build has no external-minigame API, so this file implements
-- it on top of namespaced copies of C:U's own bandage/syringe client minigames.
-- The native C:U inventory protocol is left completely untouched.

WSZC = WSZC or {}

if not SERVER then return end
if WSZC._MinigameServerLoaded then return end
WSZC._MinigameServerLoaded = true

WSZC.MinigameSessions = WSZC.MinigameSessions or {}
WSZC.NextMinigameId = WSZC.NextMinigameId or 1

local MINIGAME_SLOT = 6 -- outside C:U's InventorySlots = 5, fits net.WriteUInt(..., 3)
local ACK_BANDAGE = 1
local ACK_SYRINGE = 2
local SESSION_TIMEOUT = 300

local NET_STRINGS = {
    "WSZC_MinigameOpen",
    "WSZC_MinigameSlot",
    "WSZC_MinigameClose",
    "WSZC_MinigameForceClose",
    "WSZC_MinigameAck",
    "WSZC_BandageStart",
    "WSZC_BandageOpen",
    "WSZC_BandageClose",
    "WSZC_BandageInput",
    "WSZC_BandageState",
    "WSZC_SyringeStart",
    "WSZC_SyringeOpen",
    "WSZC_SyringeState",
    "WSZC_SyringeClose",
    "WSZC_SyringeInput",
    "WSZC_DislocationVisualComplete",
}

if util and util.AddNetworkString then
    for _, name in ipairs(NET_STRINGS) do util.AddNetworkString(name) end
end

local cvOwnMinigames = CreateConVar and CreateConVar(
    "zc_woundsystem_compat_minigames", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Enable the ZCity/C:U compatibility bandage and syringe minigames"
) or nil

-- ZCity's WB.StartMinigame() defines a LOCAL Nothing() closure in onClose
-- (sv_woundbridge.lua) which prints "Not completed - nothing was applied" to
-- HUD_PRINTCENTER when a minigame is closed before a dose landed.  The owner
-- asked for that notice to be removed.  Filtering this ONE exact message at
-- runtime is safer than editing the ZIP addon and covers both WSZC sessions
-- and any native C:U external minigame.  zc_woundsystem_compat_hide_empty_notice 0
-- restores it.
local cvHideEmptyNotice = CreateConVar and CreateConVar(
    "zc_woundsystem_compat_hide_empty_notice", "1",
    { FCVAR_ARCHIVE, FCVAR_NOTIFY },
    "Suppress the 'Not completed - nothing was applied' centre-screen notice", 0, 1
) or nil

do
    local PLAYER = FindMetaTable and FindMetaTable("Player")
    if PLAYER and type(PLAYER.PrintMessage) == "function" and not WSZC._PrintMessagePatched then
        WSZC._PrintMessagePatched = true
        local originalPrintMessage = PLAYER.PrintMessage
        PLAYER.PrintMessage = function(self, kind, msg, ...)
            if cvHideEmptyNotice and cvHideEmptyNotice:GetBool()
                and kind == HUD_PRINTCENTER and type(msg) == "string"
                and (string.find(msg, "Not completed", 1, true)
                    or string.find(msg, "nothing was applied", 1, true)) then
                return
            end
            return originalPrintMessage(self, kind, msg, ...)
        end
    end
end

local function Debug(fmt, ...)
    if WSZC.Debug then WSZC.Debug("[minigame] " .. fmt, ...) end
end

local function Warn(msg)
    if WSZC.Warn then WSZC.Warn("[minigame] " .. tostring(msg)) end
end

local function OwnMinigamesEnabled()
    if cvOwnMinigames and not cvOwnMinigames:GetBool() then return false end
    if WSZC.ExternalMinigameMode == "wszc" and WSZC.Supports
        and not WSZC.Supports("external_minigames") then return false end
    local cv = GetConVar and GetConVar("zc_woundsystem_minigames") or nil
    if cv and not cv:GetBool() then return false end
    return true
end

local function HealthEnabled()
    if type(WoundSystemHealthEnabled) ~= "function" then return true end
    local ok, enabled = pcall(WoundSystemHealthEnabled)
    return not ok or enabled ~= false
end

local function BridgeEnabled()
    if WSZC.BridgeEnabled then return WSZC.BridgeEnabled() end
    return false
end

local function Bridged(ply)
    if WSZC.Bridged then return WSZC.Bridged(ply) end
    return false
end

local function Upvalue(fn, wanted)
    if WSZC.Upvalue then return WSZC.Upvalue(fn, wanted) end
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    local i = 1
    while true do
        local ok, name, value = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        if name == wanted then return value end
        i = i + 1
    end
    return nil
end

local function ClosureValue(data, name)
    -- Native ZCity WB.StartMinigame keeps these values in closure upvalues.
    -- Remote treatment has no SWEP closure, so it supplies the SAME contract
    -- explicitly in data. Prefer that public form when present; native bridge
    -- behaviour and its appliedLive upvalue sharing remain unchanged.
    if type(data) == "table" and data[name] ~= nil then return data[name] end
    local value = Upvalue(data.onProgress, name)
    if value ~= nil then return value end
    return Upvalue(data.onClose, name)
end

local function ClosureUpvalueIndex(fn, wanted)
    if type(fn) ~= "function" or not debug or not debug.getupvalue then return nil end
    local i = 1
    while true do
        local ok, name = pcall(debug.getupvalue, fn, i)
        if not ok or not name then break end
        if name == wanted then return i end
        i = i + 1
    end
    return nil
end

--- Native WB.StartMinigame converts every C:U durability point back to a fixed
--- fraction of the SWEP.  That is NOT ZCity's bandage economy: native
--- weapon_bandage_sh spends exactly the severity it removes from org.wounds.
--- Keep the physical SWEP/index/capacity and native appliedLive upvalue so the
--- namespaced session can use that rule while WB's original onClose/AfterUse
--- still runs unchanged.
local function NativeBandageContext(data, maxDur)
    if not (WSZC.OrganismAuthority and WSZC.OrganismAuthority()) then return nil end
    if type(WSZC.BandageSeverityPerFullEffect) ~= "function"
        or type(WSZC.BandageSeverityOnLimb) ~= "function" then return nil end
    local setAppliedLive = type(data._WSZCSetAppliedLive) == "function"
        and data._WSZCSetAppliedLive or nil
    if not setAppliedLive and (not debug or type(debug.setupvalue) ~= "function") then return nil end
    local swep = ClosureValue(data, "swep")
    local idx = tonumber(ClosureValue(data, "idx")) or 1
    local appliedLiveIdx = not setAppliedLive
        and ClosureUpvalueIndex(data.onProgress, "appliedLive") or nil
    if not IsValid(swep) or type(swep.modeValues) ~= "table"
        or not (setAppliedLive or appliedLiveIdx) then return nil end
    local def = swep.modeValuesdef and swep.modeValuesdef[idx]
    if type(def) == "table" then def = def[1] end
    def = tonumber(def)
    if not def or def <= 0 then return nil end -- unsafe custom SWEP: keep native onProgress
    return {
        swep = swep, idx = idx, def = def, maxDur = maxDur,
        appliedLiveIdx = appliedLiveIdx, setAppliedLive = setAppliedLive,
    }
end

-- The project owner explicitly asked for these ZCity items to stay instant.
local INSTANT_SWEP_CLASSES = {
    weapon_naloxone = true,
    weapon_needle = true,
    weapon_adrenaline = true,
    weapon_betablock = true,
    weapon_mannitol = true,
    weapon_thiamine = true,
}
-- Same one-dose logic applies to the corresponding medkit modes.
local INSTANT_MEDKIT_MODES = { [2] = true, [3] = true, [5] = true }

local function ShouldBeInstant(data, spec, swep, idx)
    if IsValid(swep) and swep.GetClass then
        local ok, class = pcall(swep.GetClass, swep)
        if ok and INSTANT_SWEP_CLASSES[class] then return true end
        if ok and class == "weapon_medkit_sh"
            and INSTANT_MEDKIT_MODES[tonumber(idx) or 0] then return true end
    end

    -- ZCity's own `oneDose` rule: oneshot, SALINE vehicle, apply/body.
    if ClosureValue(data, "oneDose") == true then return true end
    if type(spec) == "table" then
        if spec.oneshot == true then return true end
        if type(spec.mg) == "table" and spec.mg.vehicle then return true end
        if spec.kind == "apply" or spec.kind == "body" then return true end
    end
    return false
end

local function NormalizeItemId(itemId)
    if WSZC.NormalizeItemId then return WSZC.NormalizeItemId(itemId) end
    return string.upper(tostring(itemId or ""))
end

local function Constants()
    return (WoundSystem and WoundSystem.Health and WoundSystem.Health.Constants) or {}
end

local function BandageProfile(itemId, item)
    if WSZC.BandageProfile then return WSZC.BandageProfile(itemId, item) end

    local use = item and item.use or {}
    local bandage = type(use.bandage) == "table" and use.bandage or {}
    local const = Constants()
    return {
        mode = bandage.mode or use.bandageMode or "gauze",
        durabilityPerWrap = tonumber(bandage.durabilityPerWrap or use.durabilityPerWrap)
            or const.BandageDurabilityPerWrap or 2,
    }
end

local function SyringeProfile(itemId, item)
    if WSZC.SyringeProfile then return WSZC.SyringeProfile(itemId, item) end

    local use = item and item.use or {}
    local syringe = type(use.syringe) == "table" and use.syringe or {}
    local const = Constants()
    return {
        durabilityPerSecond = tonumber(syringe.durabilityPerSecond or use.syringeDurabilityPerSecond)
            or const.SyringeDurabilityPerSecond or 18,
    }
end

local function ReadOptionalUInt(bits, fallback)
    if not net.BytesLeft then return fallback end
    local bytesLeft, bitsLeft = net.BytesLeft()
    if (bitsLeft or 0) >= bits or (bytesLeft or 0) * 8 >= bits then
        return net.ReadUInt(bits)
    end
    return fallback
end

local function Send(name, ply, writer)
    if not IsValid(ply) or not net or not net.Start then return end
    net.Start(name)
    writer()
    if net.Send then net.Send(ply) end
end

local function SendOpenSlot(ply, session)
    Send("WSZC_MinigameOpen", ply, function()
        net.WriteUInt(session.slotIdx, 3)
        net.WriteString(session.itemId)
        net.WriteFloat(session.startAmount)
        net.WriteFloat(session.maxDur)
    end)
end

local function SendSlot(ply, session)
    Send("WSZC_MinigameSlot", ply, function()
        net.WriteUInt(session.slotIdx, 3)
        net.WriteFloat(math.max(session.startAmount - session.deferredUsed, 0))
        net.WriteFloat(session.maxDur)
    end)
end

local function SendAck(ply, session, gameId, ackSeq)
    Send("WSZC_MinigameAck", ply, function()
        net.WriteUInt(gameId, 3)
        net.WriteUInt(session.id, 24)
        net.WriteUInt(ackSeq or session.lastAckSeq or 0, 24)
    end)
end

local function CurrentBandageBleeding(session)
    if WSZC.GetBandageBleeding then
        local ok, value = pcall(WSZC.GetBandageBleeding, session.target, session.limbId)
        if ok then return math.max(tonumber(value) or 0, 0) end
    end
    local h = WSZC.H
    local state = h and h.GetLimbState and h.GetLimbState(session.target, session.limbId)
    return type(state) == "table" and math.max(tonumber(state.bleed) or 0, 0) or 0
end

local function CurrentArterialBleeding(session)
    if not WSZC.GetArterialBleeding then return 0 end
    local ok, value = pcall(WSZC.GetArterialBleeding, session.target, session.limbId)
    return ok and math.max(tonumber(value) or 0, 0) or 0
end

local function SendBandageState(ply, session)
    if session.kind ~= "bandage" then return end
    if session.mode == "unwrap" then
        local required = math.max(tonumber(session.unwrapRequired) or 360, 1)
        local unwrapped = math.Clamp(tonumber(session.unwrapProgress) or 0, 0, required)
        local progress = unwrapped / required
        session.lastBleed = required - unwrapped
        session.lastArterialBleed = 0
        session.lastBleedProgress = progress
        Send("WSZC_BandageState", ply, function()
            net.WriteUInt(session.id, 24)
            net.WriteFloat(required)
            net.WriteFloat(required - unwrapped)
            net.WriteFloat(progress)
            net.WriteFloat(0)
        end)
        return
    elseif session.mode == "fracture" then
        local required = math.max(tonumber(session.fractureRequired) or 1440, 1)
        local wrapped = math.Clamp(tonumber(session.fractureProgress) or 0, 0, required)
        local progress = wrapped / required
        session.lastBleed = required - wrapped
        session.lastArterialBleed = 0
        session.lastBleedProgress = progress
        Send("WSZC_BandageState", ply, function()
            net.WriteUInt(session.id, 24)
            net.WriteFloat(required)
            net.WriteFloat(required - wrapped)
            net.WriteFloat(progress)
            net.WriteFloat(0)
        end)
        return
    end
    local initial = math.max(tonumber(session.initialBleed) or 0, 0)
    local current = CurrentBandageBleeding(session)
    local arterial = CurrentArterialBleeding(session)
    local progress
    if initial > 0.0001 then
        progress = math.Clamp((initial - current) / initial, 0, 1)
    else
        progress = current <= 0.0001 and 1 or 0
    end
    session.lastBleed = current
    session.lastArterialBleed = arterial
    session.lastBleedProgress = progress

    Send("WSZC_BandageState", ply, function()
        net.WriteUInt(session.id, 24)
        net.WriteFloat(initial)
        net.WriteFloat(current)
        net.WriteFloat(progress)
        net.WriteFloat(arterial)
    end)
end

local function SendSyringeState(ply, session, ackSeq)
    local condition = math.Clamp(
        math.max(session.startAmount - session.deferredUsed, 0) / math.max(session.maxDur, 0.0001),
        0, 1
    )
    Send("WSZC_SyringeState", ply, function()
        net.WriteUInt(session.id, 24)
        net.WriteFloat(condition)
        net.WriteUInt(ackSeq or session.lastAckSeq or 0, 24)
    end)
end

local function SendClose(ply, session, reason)
    local closeName = session.kind == "bandage" and "WSZC_BandageClose" or "WSZC_SyringeClose"

    Send(closeName, ply, function()
        net.WriteUInt(session.id, 24)
        net.WriteString(reason or "closed")
    end)

    Send("WSZC_MinigameClose", ply, function()
        net.WriteUInt(session.slotIdx, 3)
    end)
end

local function CUSessionActive(ply)
    local sessions = WSZC.CUSessions
    if type(sessions) ~= "table" then return false end
    if sessions.Bandage and sessions.Bandage[ply] then return true end
    if sessions.Syringe and sessions.Syringe[ply] then return true end
    return false
end

local function IsRemoteOwnedNativeSession(ply, kind)
    local remote = WSZC.RemoteNativeSessions
    local byKind = type(remote) == "table" and remote[ply] or nil
    local meta = type(byKind) == "table" and byKind[kind] or nil
    return type(meta) == "table" and IsValid(meta.operator) and meta.operator ~= ply
end

local function HasAnyRemoteOwnedNativeSession(ply)
    for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed" }) do
        if IsRemoteOwnedNativeSession(ply, kind) then return true end
    end
    return false
end

local function HasActiveRemoteOperatorSession(ply)
    local remote = WSZC.RemoteMedicalSessions
    return type(remote) == "table" and remote[ply] ~= nil
end

local function StopCUSessions(ply, reason)
    local sessions = WSZC.CUSessions
    if type(sessions) ~= "table" then return end
    reason = reason or "disabled"
    local keepRemoteOwned = IsValid(ply) and ply:Alive()

    if sessions.Bandage and sessions.Bandage[ply] and WSZC.CUCloseBandageSession then
        pcall(WSZC.CUCloseBandageSession, ply, reason)
    end
    if sessions.Syringe and sessions.Syringe[ply] and WSZC.CUCloseSyringeSession then
        pcall(WSZC.CUCloseSyringeSession, ply, reason)
    end
    if sessions.Shrapnel and sessions.Shrapnel[ply]
        and not (keepRemoteOwned and IsRemoteOwnedNativeSession(ply, "Shrapnel")) then
        if WSZC.CUCloseShrapnelSession then
            pcall(WSZC.CUCloseShrapnelSession, ply, reason)
        else
            sessions.Shrapnel[ply] = nil
        end
    end
    if sessions.Dislocation and sessions.Dislocation[ply]
        and not (keepRemoteOwned and IsRemoteOwnedNativeSession(ply, "Dislocation")) then
        if WSZC.CUCloseDislocationSession then
            pcall(WSZC.CUCloseDislocationSession, ply, reason)
        else
            sessions.Dislocation[ply] = nil
        end
    end
    if sessions.Aed and sessions.Aed[ply]
        and not (keepRemoteOwned and IsRemoteOwnedNativeSession(ply, "Aed")) then
        if WSZC.CUCloseAedSession then
            pcall(WSZC.CUCloseAedSession, ply, reason)
        else
            sessions.Aed[ply] = nil
        end
    end
end

local function HasNativeSession(ply)
    local sessions = WSZC.CUSessions
    if type(sessions) ~= "table" then return false end
    for _, kind in ipairs({ "Bandage", "Syringe", "Shrapnel", "Dislocation", "Aed" }) do
        if type(sessions[kind]) == "table" and sessions[kind][ply]
            and not IsRemoteOwnedNativeSession(ply, kind) then
            return true
        end
    end
    return false
end

--- The operator, not an unconscious PATIENT being treated by somebody else,
--- must be conscious and able to control the minigame.  Check every ZCity
--- representation because otrub/fake/NWBool arrive in a different order on
--- different builds.
local function PlayerIncapacitated(ply)
    if not IsValid(ply) or not ply:Alive() then return true end
    if ply.GetNWBool and ply:GetNWBool("WoundSystemUnconscious", false) then return true end
    -- A FakeRagdoll / org.fake is posture, NOT loss of operator capacity.
    -- The patient may be ragdolled too; only the medic's own death/otrub or
    -- genuinely low consciousness may force-close this session.
    local org = ply.organism
    if type(org) == "table" then
        if org.otrub == true or org.needotrub == true then return true end
        local consciousness = tonumber(org.consciousness)
        if consciousness and consciousness < 0.4 then return true end
    end
    return false
end
WSZC.PlayerMinigameIncapacitated = PlayerIncapacitated

local function ValidSession(ply)
    local session = WSZC.MinigameSessions[ply]
    if not session then return nil end

    if not IsValid(ply) or not ply:IsPlayer() then
        WSZC.MinigameSessions[ply] = nil
        return nil
    end
    return session
end

local function StopMinigame(ply, reason)
    local session = WSZC.MinigameSessions[ply]
    if not session then return false end

    -- Remove first: bridge onClose/onProgress may call Stop() reentrantly.
    WSZC.MinigameSessions[ply] = nil
    session.closed = true
    reason = tostring(reason or "client_close")

    if type(session.onClose) == "function" then
        local ok, err = pcall(session.onClose, ply, session, reason)
        if not ok then Warn("onClose failed: " .. tostring(err)) end
    end

    if IsValid(ply) then SendClose(ply, session, reason) end
    Debug("closed %s session %s reason=%s used=%.2f/%.2f",
        session.kind, tostring(session.id), reason,
        session.deferredUsed or 0, session.startAmount or 0)
    return true
end

local function StopAllMinigames(ply, reason, forceClient)
    if not IsValid(ply) then return false end
    reason = tostring(reason or "disabled")
    local hadRemoteOp = HasActiveRemoteOperatorSession(ply)
    local had = WSZC.MinigameSessions[ply] ~= nil or HasNativeSession(ply) or hadRemoteOp
    if hadRemoteOp and type(WSZC.CloseRemoteMedical) == "function" then
        pcall(WSZC.CloseRemoteMedical, ply, reason)
    end
    StopMinigame(ply, reason)
    StopCUSessions(ply, reason)
    if not (ply:Alive() and HasAnyRemoteOwnedNativeSession(ply)) then
        local health = WSZC.H or (WoundSystem and WoundSystem.Health)
        if health and type(health.CancelActiveMedicalSessions) == "function" then
            pcall(health.CancelActiveMedicalSessions, ply, reason)
        elseif type(WoundSystemCloseAllMedicalSessions) == "function" then
            pcall(WoundSystemCloseAllMedicalSessions, ply, reason)
        end
    end
    -- This is also a safety net for a native session whose private close
    -- upvalue could not be captured: the client must never keep its overlay,
    -- cursor or movement lock after the operator falls unconscious.
    if had or forceClient then
        Send("WSZC_MinigameForceClose", ply, function() net.WriteString(reason) end)
    end
    return had
end
WSZC.StopAllMinigames = StopAllMinigames

local function HasMinigame(ply)
    if not OwnMinigamesEnabled() then return false end
    if WSZC.MinigameSessions[ply] then return true end
    return CUSessionActive(ply)
end

local function StartResult(ok, reason)
    WSZC.LastMinigameStartResult = tostring(reason)
    if not ok then Debug("start rejected: %s", tostring(reason)) end
    return ok
end

local function StartMinigame(ply, data)
    if not WSZC.Ready then return StartResult(false, "connector not ready") end
    if not BridgeEnabled() then
        return StartResult(false, "bridge disabled (zc_woundsystem_bridge/woundsys_enabled)")
    end
    if not OwnMinigamesEnabled() then
        return StartResult(false, "minigames disabled by convar/capability")
    end
    if not HealthEnabled() then return StartResult(false, "C:U health disabled") end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then
        return StartResult(false, "invalid/dead operator")
    end
    if PlayerIncapacitated(ply) then return StartResult(false, "operator incapacitated") end
    if HasMinigame(ply) then return StartResult(true, "already active") end
    if type(data) ~= "table" then return StartResult(false, "missing data") end

    local kind = data.kind
    if kind ~= "bandage" and kind ~= "syringe" then
        return StartResult(false, "unsupported kind=" .. tostring(kind))
    end
    if type(data.onProgress) ~= "function" or type(data.onClose) ~= "function" then
        return StartResult(false, "missing callbacks")
    end

    -- `spec` is an upvalue of the bridge closures.  `spec.mg` is ZCity's
    -- minigame-capable marker, but after the owner's correction it is not
    -- sufficient by itself: one-dose specs still stay instant.
    local spec = ClosureValue(data, "spec")
    if type(spec) ~= "table" or type(spec.mg) ~= "table" or spec.mg.kind ~= kind then
        return StartResult(false, "invalid spec/minigame marker")
    end

    -- The owner explicitly wants one-dose / vehicle / body items to stay
    -- instant.  Returning false sends WB.StartMinigame() to its instant path.
    local swep = ClosureValue(data, "swep")
    local idx = ClosureValue(data, "idx")
    if ShouldBeInstant(data, spec, swep, idx) then
        local className = spec.item or kind
        if IsValid(swep) and swep.GetClass then
            local ok, class = pcall(swep.GetClass, swep)
            if ok then className = class end
        end
        Debug("instant fallback for %s (one-dose ZCity item)", tostring(className))
        return StartResult(false, "intentional instant item=" .. tostring(className))
    end

    local H = WSZC.H
    local authorityDirect = WSZC.OrganismAuthority and WSZC.OrganismAuthority()
        and (data._WSZCZCityDirect == true
            or (kind == "bandage" and type(WSZC.ApplyBandageToOrganism) == "function"))
    if type(H) ~= "table" or (not authorityDirect and type(H.ApplyItemToBody) ~= "function") then
        return StartResult(false, "ApplyItemToBody unavailable")
    end

    local target = ClosureValue(data, "target")
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then
        return StartResult(false, "invalid/dead target")
    end
    if not Bridged(target) then return StartResult(false, "target not bridged") end

    local limbId = data.limbId
    if type(limbId) ~= "string" or limbId == "" then
        return StartResult(false, "missing limb")
    end
    if H.InitPlayer and H.GetLimbs and not H.GetLimbs(target) then pcall(H.InitPlayer, target) end
    if limbId ~= "body" and H.GetLimbState and not H.GetLimbState(target, limbId) then
        return StartResult(false, "unknown limb=" .. tostring(limbId))
    end

    local Items = WoundSystem and WoundSystem.Items
    local itemId = NormalizeItemId(data.itemId)
    local item = Items and Items.Get and Items.Get(itemId)
    if not item then return StartResult(false, "unknown item=" .. tostring(itemId)) end

    local maxDur = tonumber(ClosureValue(data, "maxDur"))
    if not maxDur or maxDur <= 0 then
        maxDur = (Items.GetMax and Items.GetMax(itemId)) or item.max or 100
    end
    maxDur = math.max(tonumber(maxDur) or 100, 0.0001)

    local startAmount = tonumber(data.amount)
    if not startAmount or startAmount <= 0 then startAmount = maxDur end
    startAmount = math.Clamp(startAmount, 0.0001, maxDur)

    local live = ClosureValue(data, "live")
    if live == nil then live = (kind == "bandage") end
    local oneDose = ClosureValue(data, "oneDose")
    if oneDose == nil then oneDose = false end

    local id = WSZC.NextMinigameId or 1
    WSZC.NextMinigameId = id + 1
    if WSZC.NextMinigameId > 16000000 then WSZC.NextMinigameId = 1 end

    local now = CurTime and CurTime() or 0
    local frozenAngles
    if ply.EyeAngles then
        local okAng, ang = pcall(ply.EyeAngles, ply)
        if okAng then frozenAngles = ang end
    end
    local bandageMode = data.bandageMode
    local initialBleed = (kind == "bandage" and bandageMode ~= "fracture")
        and CurrentBandageBleeding({ target = target, limbId = limbId }) or 0
    local session = {
        id = id,
        kind = kind,
        mode = bandageMode,
        itemId = itemId,
        item = item,
        limbId = limbId,
        slotIdx = MINIGAME_SLOT,
        owner = ply,
        target = target,
        spec = spec,
        live = live == true,
        oneDose = oneDose == true,
        maxDur = maxDur,
        amount = startAmount,
        startAmount = startAmount,
        deferredUsed = 0,
        initialBleed = initialBleed,
        lastBleed = initialBleed,
        lastBleedProgress = 0,
        fractureRequired = bandageMode == "fracture" and (tonumber(data.fractureRequired) or 1440) or nil,
        fractureProgress = bandageMode == "fracture" and 0 or nil,
        fractureCost = bandageMode == "fracture" and (tonumber(data.fractureCost) or 25) or nil,
        onFractureComplete = bandageMode == "fracture" and data.onFractureComplete or nil,
        nativeBandage = (kind == "bandage" and bandageMode ~= "fracture" and live)
            and NativeBandageContext(data, maxDur) or nil,
        onProgress = data.onProgress,
        onClose = data.onClose,
        data = data,
        startedAt = now,
        -- Freeze the camera for the whole session.  The client also freezes
        -- ViewAngles; this server copy defeats a modified/legacy client.
        frozenAngles = frozenAngles,
        lastInputAt = now,
        lastAckSeq = 0,
        closed = false,
    }

    WSZC.MinigameSessions[ply] = session

    SendOpenSlot(ply, session)

    if kind == "bandage" then
        local profile = BandageProfile(itemId, item)
        Send("WSZC_BandageOpen", ply, function()
            net.WriteUInt(session.id, 24)
            net.WriteString(session.limbId)
            net.WriteString(session.mode or profile.mode or "gauze")
            net.WriteUInt(session.slotIdx, 3)
        end)
        SendBandageState(ply, session)
    else
        Send("WSZC_SyringeOpen", ply, function()
            net.WriteUInt(session.id, 24)
            net.WriteString(session.limbId)
            net.WriteUInt(session.slotIdx, 3)
            net.WriteString(session.itemId)
            net.WriteFloat(math.Clamp(session.startAmount / session.maxDur, 0, 1))
        end)
    end

    Debug("opened %s session %s owner=%s target=%s item=%s limb=%s amount=%.2f live=%s oneDose=%s",
        kind, tostring(id), tostring(ply), tostring(target), itemId, limbId,
        startAmount, tostring(session.live), tostring(session.oneDose))
    return StartResult(true, "opened " .. kind .. " #" .. tostring(id))
end

--- Covered shrapnel cannot be exposed by a click.  Start the SAME client
--- bandage minigame in reverse mode, with a virtual roll that costs no item.
--- ProcessBandageInput() is the only path that may remove this dressing.
function WSZC.StartShrapnelUnwrap(ply, limbId, target)
    target = target or ply
    if not (WSZC.Ready and OwnMinigamesEnabled() and HealthEnabled()) then return false end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
    if PlayerIncapacitated(ply) or not Bridged(target) then return false end
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then return false end
    if target ~= ply then
        local inspection = WSZC.RemoteMedicalSessions and WSZC.RemoteMedicalSessions[ply]
        if not (inspection and inspection.target == target and WSZC.RemoteMedicalValidPair
            and WSZC.RemoteMedicalValidPair(ply, target)) then return false end
    end
    if not (WSZC.IsShrapnelBandaged and WSZC.IsShrapnelBandaged(target, limbId)) then return false end

    local existing = WSZC.MinigameSessions[ply]
    if existing then
        return existing.kind == "bandage" and existing.mode == "unwrap"
            and existing.limbId == limbId and existing.target == target
    end
    if HasMinigame(ply) then return false end

    local id = WSZC.NextMinigameId or 1
    WSZC.NextMinigameId = id + 1
    if WSZC.NextMinigameId > 16000000 then WSZC.NextMinigameId = 1 end
    local now = CurTime and CurTime() or 0
    local frozenAngles
    if ply.EyeAngles then
        local okAng, ang = pcall(ply.EyeAngles, ply)
        if okAng then frozenAngles = ang end
    end
    local session = {
        id = id, kind = "bandage", mode = "unwrap",
        itemId = "WSZC_UNWRAP", limbId = limbId, slotIdx = MINIGAME_SLOT,
        owner = ply, target = target, remote = target ~= ply,
        maxDur = 360, amount = 360, startAmount = 360, deferredUsed = 0,
        initialBleed = 360, lastBleed = 360, lastBleedProgress = 0,
        unwrapRequired = 360, unwrapProgress = 0,
        live = false, oneDose = false,
        startedAt = now, lastInputAt = now, lastAckSeq = 0,
        frozenAngles = frozenAngles, closed = false,
    }
    WSZC.MinigameSessions[ply] = session
    SendOpenSlot(ply, session)
    Send("WSZC_BandageOpen", ply, function()
        net.WriteUInt(session.id, 24)
        net.WriteString(session.limbId)
        net.WriteString("unwrap")
        net.WriteUInt(session.slotIdx, 3)
    end)
    SendBandageState(ply, session)
    Debug("opened reverse-bandage session %s owner=%s limb=%s", tostring(id), tostring(ply), limbId)
    return true
end

local function StopExternal(ply, reason)
    local had = StopMinigame(ply, reason)
    StopCUSessions(ply)
    return had
end

WSZC.HasExternalMinigameImpl = HasMinigame
WSZC.StartExternalMinigameImpl = StartMinigame
WSZC.StopExternalMinigameImpl = StopExternal
WSZC.StopMinigame = StopMinigame

-- Connector-owned medical entrypoint.  Unlike both WB.SwepHeal adapters this
-- path does not depend on any Workshop SWEP:Heal implementation.  The physical
-- weapon only supplies owner/capacity; the session, treatment and consumption
-- are created directly here.  It is exposed as weapon_wszc_bandage so the
-- original ZCity class hierarchy remains untouched.
local STANDALONE_BANDAGE_SPEC = {
    kind = "bandage", item = "GAUZE", rate = 25, mg = { kind = "bandage" },
}

local function StandaloneBandageReject(owner, reason)
    WSZC.LastMedicalHealRoute = "weapon_wszc_bandage -> standalone (" .. tostring(reason) .. ")"
    WSZC.LastMinigameStartResult = "standalone: " .. tostring(reason)
    if IsValid(owner) and owner.PrintMessage then
        pcall(owner.PrintMessage, owner, HUD_PRINTCENTER or 2, tostring(reason))
    end
    return false
end

function WSZC.UseStandaloneBandage(swep, target, opts)
    local owner = IsValid(swep) and swep.GetOwner and swep:GetOwner() or nil
    if not (IsValid(owner) and owner:IsPlayer() and owner:Alive()) then
        return StandaloneBandageReject(owner, "invalid operator")
    end
    if not WSZC.Ready then return StandaloneBandageReject(owner, "connector not ready") end
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then
        return StandaloneBandageReject(owner, "no living patient")
    end
    if target ~= owner and (type(WSZC.RemoteMedicalValidPair) ~= "function"
        or not WSZC.RemoteMedicalValidPair(owner, target)) then
        return StandaloneBandageReject(owner, "patient is too far away")
    end

    swep.modeValues = type(swep.modeValues) == "table" and swep.modeValues or { 40 }
    swep.modeValuesdef = type(swep.modeValuesdef) == "table" and swep.modeValuesdef or { { 40, true } }
    local def = swep.modeValuesdef[1]
    if type(def) == "table" then def = def[1] end
    def = tonumber(def) or 40
    local remaining = math.max(tonumber(swep.modeValues[1]) or 0, 0)
    if remaining <= 0.0005 then return StandaloneBandageReject(owner, "bandage is empty") end

    local preferred = type(opts) == "table" and opts.preferredLimb or nil
    local forceFracture = type(opts) == "table" and opts.forceFracture == true
    local forceWound = type(opts) == "table" and opts.forceWound == true
    local strictLimb = type(opts) == "table" and opts.strictLimb == true and preferred ~= nil

    local limbId = nil
    if not forceFracture and WSZC.BestBandageLimb then
        limbId = WSZC.BestBandageLimb(target, STANDALONE_BANDAGE_SPEC, preferred, strictLimb)
    end
    local fractureMode, fractureCost = false, 0
    if not limbId and not forceWound and WSZC.BestZCityFractureLimb and WSZC.ZCityFractureBandageCost then
        fractureCost = WSZC.ZCityFractureBandageCost(owner)
        if remaining >= fractureCost - 0.0001 then
            limbId = WSZC.BestZCityFractureLimb(target, preferred, strictLimb)
            if limbId then fractureMode = true end
        end
    end
    if not limbId then return StandaloneBandageReject(owner, "no treatable wound or fracture") end

    local items = WoundSystem and WoundSystem.Items
    local maxDur = (items and items.GetMax and items.GetMax("GAUZE")) or 100
    local amount = remaining / math.max(def, 0.0001) * maxDur
    local appliedLive = 0
    local health = WSZC.H
    local data
    data = {
        kind = "bandage", itemId = "GAUZE", limbId = limbId, amount = amount,
        bandageMode = fractureMode and "fracture" or nil,
        fractureRequired = fractureMode and 1440 or nil,
        fractureCost = fractureMode and fractureCost or nil,
        swep = swep, idx = 1, spec = STANDALONE_BANDAGE_SPEC, target = target,
        maxDur = maxDur, live = true, oneDose = false,
        _WSZCZCityDirect = true,
        _WSZCSetAppliedLive = function(value)
            appliedLive = math.max(tonumber(value) or 0, 0)
        end,
        onFractureComplete = fractureMode and function()
            if WSZC.StabilizeZCityFracture
                and WSZC.StabilizeZCityFracture(target, limbId, owner, swep) then
                appliedLive = math.max(appliedLive, 1)
                if WSZC.SyncOrganismShadow and type(target.organism) == "table" then
                    target._WSZCShadowNext = 0
                    pcall(WSZC.SyncOrganismShadow, target, target.organism)
                end
                if WSZC.NotifyRemotePatientUpdated then
                    pcall(WSZC.NotifyRemotePatientUpdated, target)
                end
            end
        end or nil,
        onProgress = function(ply, session, durCost)
            -- Used only outside the organism-authority native-cost path.  The
            -- authoritative path consumes exact ZCity severity in
            -- ProcessNativeBandageInput and deliberately never calls this.
            if not IsValid(swep) or not IsValid(target) then return end
            local start = math.max(session.startAmount or amount, 0.0001)
            durCost = math.min(tonumber(durCost) or 0, math.max(start - appliedLive, 0))
            if durCost <= 0 then return end
            local H = WSZC.H or health
            if not (H and H.ApplyItemToBody) then return end
            local ok = H.ApplyItemToBody(target, "GAUZE", limbId, durCost)
            if not ok then return end
            appliedLive = appliedLive + durCost
            swep.modeValues[1] = math.max(remaining * (1 - appliedLive / start), 0)
            if swep.SetNetVar then pcall(swep.SetNetVar, swep, "modeValues", swep.modeValues) end
        end,
        onClose = function()
            -- Keep the native appliedLive closure reachable and remove only a
            -- genuinely exhausted physical item, never an unused bandage.
            local _ = appliedLive
            if not IsValid(swep) or (tonumber(swep.modeValues[1]) or 0) > 0.0005 then return end
            if IsValid(owner) and owner.SelectWeapon then pcall(owner.SelectWeapon, owner, "weapon_hands_sh") end
            swep:Remove()
        end,
    }

    local started = StartMinigame(owner, data)
    WSZC.LastMedicalHealRoute = "weapon_wszc_bandage -> standalone (" .. tostring(started) .. ")"
    if started and WSZC.MinigameSessions[owner] then
        WSZC.MinigameSessions[owner].remote = target ~= owner
    end
    if not started then
        -- StartMinigame already recorded the precise gate/rejection reason.
        return false
    end
    return true
end

-- Namespaced remote sessions have no physical ZCity SWEP in the patient's
-- hands. Revalidate operator -> patient range/alive state for every input,
-- exactly as the native-session/AED timer paths do.
local function RemoteSessionValid(ply, session)
    if not session.remote then return true end
    local validator = WSZC.RemoteMedicalValidPair
    return type(validator) == "function" and validator(ply, session.target) == true
end

function WSZC.InstallMinigameAPI(H)
    if type(H) ~= "table" then return false end

    local caps = WSZC.RefreshCapabilities and WSZC.RefreshCapabilities() or nil
    if (not WSZC.PreferNativeAPI or WSZC.PreferNativeAPI())
        and caps and caps.cu_native_api and WSZC.HasNativeExternalMinigameAPI(H) then
        -- Modern C:U already owns the external protocol and its client UI.
        -- Replacing it with the legacy WSZC copies would break that build.
        WSZC.ExternalMinigameMode = "native"
        WSZC.H = H
        return true
    end
    if WSZC.Supports and not WSZC.Supports("external_minigames") then return false end

    H.HasExternalMinigame = HasMinigame
    H.StopExternalMinigame = StopExternal
    H.StartExternalMinigame = StartMinigame
    H._WSZCOwnsExternalMinigameAPI = true
    WSZC.ExternalMinigameMode = "wszc"
    WSZC.H = H
    return true
end

--- Apply one namespaced bandage input with ZCity's native 1 severity = 1
--- modeValues cost.  Returns handled, physicalItemEmpty.  The generic C:U
--- onProgress path remains the fallback for non-authority/custom sessions.
local function ProcessNativeBandageInput(ply, session, profile, perWrap, baseCost, finalAftercare)
    local native = session.nativeBandage
    if type(native) ~= "table" then return false, false end
    local swep, idx = native.swep, native.idx
    if not IsValid(swep) then
        StopMinigame(ply, "target_gone")
        return true, true
    end
    local H = WSZC.H
    local directBandage = WSZC.OrganismAuthority and WSZC.OrganismAuthority()
        and type(WSZC.ApplyBandageToOrganism) == "function"
    if not directBandage and not (H and type(H.ApplyItemToBody) == "function") then
        return false, false
    end
    if type(swep.modeValues) ~= "table" then return false, false end

    local remaining = math.max(tonumber(swep.modeValues[idx]) or 0, 0)
    if remaining <= 0.0005 then return true, true end

    local severityPerFull = WSZC.BandageSeverityPerFullEffect
        and WSZC.BandageSeverityPerFullEffect(profile) or 0
    if severityPerFull <= 0.000001 then return false, false end
    local effectDivisor = math.max(tonumber(profile.effectDivisor) or 12, 1)
    local baseEffectFraction = (baseCost / perWrap) / effectDivisor
    local beforeSeverity = WSZC.BandageSeverityOnLimb
        and WSZC.BandageSeverityOnLimb(session.target, session.limbId)
        or (CurrentBandageBleeding(session) / 2)

    -- Do not heal more than either the real wound or the physical item can
    -- pay for.  Inverting the SAME treatment formula keeps strength 3 and
    -- one-turn lodged-shrapnel treatment, but makes its cost exactly native.
    local desired = math.min(
        math.max(severityPerFull * baseEffectFraction, 0),
        beforeSeverity, remaining
    )
    if desired <= 0.000001 and not finalAftercare then return true, false end
    local applyFraction = desired > 0.000001
        and (desired / severityPerFull)
        or baseEffectFraction
    local applyAmount = desired > 0.000001
        and (applyFraction * perWrap * effectDivisor)
        or baseCost -- zero-bleed aftercare still needs its final dressing input

    if directBandage then
        local limbState = H and H.GetLimbState and H.GetLimbState(session.target, session.limbId) or nil
        local callOk, err = pcall(WSZC.ApplyBandageToOrganism, {
            ply = session.target, limbId = session.limbId, limb = limbState,
        }, profile, applyFraction)
        if not callOk then
            Warn("direct ZCity bandage apply failed: " .. tostring(err))
            return true, false
        end
        if H and H.SendLimbUpdate then pcall(H.SendLimbUpdate, session.target, session.limbId, true) end
        if H and H.SendCardioUpdate then pcall(H.SendCardioUpdate, session.target) end
        if WSZC.NotifyRemotePatientUpdated then
            pcall(WSZC.NotifyRemotePatientUpdated, session.target, not finalAftercare)
        end
    else
        local callOk, ok = pcall(H.ApplyItemToBody,
            session.target, session.itemId, session.limbId, applyAmount)
        if not callOk then
            Warn("native ZCity bandage apply failed: " .. tostring(ok))
            return true, false
        end
        if not ok then return true, false end
    end

    local afterSeverity = WSZC.BandageSeverityOnLimb
        and WSZC.BandageSeverityOnLimb(session.target, session.limbId)
        or (CurrentBandageBleeding(session) / 2)
    local treated = math.Clamp(beforeSeverity - afterSeverity, 0, remaining)
    if desired > 0 then treated = math.min(treated, desired + 0.000001) end

    if treated > 0.000001 then
        local org = session.target and session.target.organism
        if type(org) == "table" then
            if tonumber(org.pain) then
                org.pain = math.max(tonumber(org.pain) - treated * 0.25, 0)
            end
            if swep.poisoned2 then
                org.poison4 = CurTime and CurTime() or 0
                swep.poisoned2 = nil
            end
        end
        local left = math.max(remaining - treated, 0)
        swep.modeValues[idx] = left > 0.0005 and left or 0
        -- Mirror the physical remainder into the virtual slot as well.  This
        -- conversion makes deferredUsed/startAmount the same physical fraction
        -- for a 40-unit bandage, a 150-unit big bandage and medkit mode 1.
        local virtualCost = treated * (native.maxDur / native.def)
        session.deferredUsed = math.min(session.startAmount,
            (session.deferredUsed or 0) + virtualCost)
        if swep.SetNetVar then pcall(swep.SetNetVar, swep, "modeValues", swep.modeValues) end
    end

    if treated > 0.000001 or finalAftercare then
        -- WB's original onClose only needs appliedLive > 0.01 for a live
        -- bandage before it calls native AfterUse.  Share the upvalue with
        -- onProgress; never call that onProgress and consume a second time.
        local applied = math.max(session.deferredUsed or 0, 0.02)
        if native.setAppliedLive then
            pcall(native.setAppliedLive, applied)
        else
            local i = native.appliedLiveIdx
            if i and debug and debug.setupvalue then
                pcall(debug.setupvalue, session.onProgress, i, applied)
            end
        end
    end

    Debug("native bandage cost %s: severity %.4f, modeValues %.4f -> %.4f",
        tostring(session.itemId), treated, remaining, tonumber(swep.modeValues[idx]) or 0)
    return true, (tonumber(swep.modeValues[idx]) or 0) <= 0.0005
end

-- Both connector and embedded C:U bandage receivers spend the same budget.
-- Keeping it on the operator prevents bypass by switching protocols or sessions.
function WSZC.FilterBandageDegrees(ply, degrees, startedAt)
    degrees = tonumber(degrees)
    if not degrees or degrees ~= degrees or degrees == math.huge or degrees == -math.huge then return nil end
    degrees = math.Clamp(degrees, 0, 360)
    if degrees <= 0 then return nil end
    local now = CurTime()
    local last = ply._WSZCBandageBudgetAt or startedAt or now
    local elapsed = math.Clamp(now - last, 0, 1)
    local budget = math.min(360, (ply._WSZCBandageBudget or 144) + elapsed * 720)
    ply._WSZCBandageBudgetAt = now
    degrees = math.min(degrees, budget)
    ply._WSZCBandageBudget = budget - degrees
    return degrees
end

local function ProcessBandageInput(_, ply)
    local session = ValidSession(ply)
    if not session or session.kind ~= "bandage" then return end

    local sessionId = net.ReadUInt(24)
    local degrees = net.ReadFloat()
    local inputSeq = ReadOptionalUInt(24, 0)
    if sessionId ~= session.id then return end

    if not IsValid(ply) or not ply:Alive() then
        StopMinigame(ply, "dead")
        return
    end
    if not IsValid(session.target) or not session.target:Alive() or not Bridged(session.target) then
        StopMinigame(ply, "target_gone")
        return
    end
    if not RemoteSessionValid(ply, session) then
        StopMinigame(ply, "out_of_range")
        return
    end

    degrees = WSZC.FilterBandageDegrees(ply, degrees, session.startedAt)
    if not degrees then return end
    session.lastAckSeq = inputSeq
    if degrees <= 0.0001 then
        SendBandageState(ply, session)
        SendAck(ply, session, ACK_BANDAGE, inputSeq)
        return
    end

    if session.mode == "unwrap" then
        if not (WSZC.IsShrapnelBandaged
            and WSZC.IsShrapnelBandaged(session.target, session.limbId)) then
            SendAck(ply, session, ACK_BANDAGE, inputSeq)
            StopMinigame(ply, "already_unwrapped")
            return
        end
        local required = math.max(tonumber(session.unwrapRequired) or 360, 1)
        session.unwrapProgress = math.min(required,
            (tonumber(session.unwrapProgress) or 0) + degrees)
        SendBandageState(ply, session)
        SendAck(ply, session, ACK_BANDAGE, inputSeq)
        if session.unwrapProgress >= required then
            local removed = WSZC.RemoveBandageForShrapnel
                and WSZC.RemoveBandageForShrapnel(session.target, session.limbId)
            StopMinigame(ply, removed and "unwrapped" or "unwrap_failed")
        end
        return -- no durability, bleeding treatment or foreign onProgress
    elseif session.mode == "fracture" then
        if WSZC.CanBandageZCityFracture
            and not WSZC.CanBandageZCityFracture(session.target, session.limbId) then
            SendAck(ply, session, ACK_BANDAGE, inputSeq)
            StopMinigame(ply, "completed")
            return
        end
        local swep = ClosureValue(session.data, "swep")
        local idx = tonumber(ClosureValue(session.data, "idx")) or 1
        if not IsValid(swep) or type(swep.modeValues) ~= "table" then
            StopMinigame(ply, "target_gone")
            return
        end
        local required = math.max(tonumber(session.fractureRequired) or 1440, 1)
        local cost = math.max(tonumber(session.fractureCost) or 25, 0)
        local remainingItem = math.max(tonumber(swep.modeValues[idx]) or 0, 0)
        if remainingItem + 0.0001 < cost then
            SendBandageState(ply, session)
            SendAck(ply, session, ACK_BANDAGE, inputSeq)
            StopMinigame(ply, "empty")
            return
        end
        local beforeProgress = math.Clamp(tonumber(session.fractureProgress) or 0, 0, required)
        local deltaDegrees = math.Clamp(math.min(degrees, required - beforeProgress), 0, required)
        if deltaDegrees <= 0.0001 then
            SendBandageState(ply, session)
            SendAck(ply, session, ACK_BANDAGE, inputSeq)
            return
        end
        session.fractureProgress = beforeProgress + deltaDegrees
        SendBandageState(ply, session)
        SendAck(ply, session, ACK_BANDAGE, inputSeq)
        if session.fractureProgress >= required - 0.001 then
            local left = math.max(remainingItem - cost, 0)
            swep.modeValues[idx] = left > 0.0005 and left or 0
            if swep.SetNetVar then pcall(swep.SetNetVar, swep, "modeValues", swep.modeValues) end
            local def = swep.modeValuesdef and swep.modeValuesdef[idx]
            if type(def) == "table" then def = def[1] end
            def = math.max(tonumber(def) or cost or 40, 0.0001)
            session.deferredUsed = math.min(session.startAmount, cost * (session.maxDur / def))
            if type(session.data._WSZCSetAppliedLive) == "function" then
                pcall(session.data._WSZCSetAppliedLive, math.max(session.deferredUsed, 1))
            end
            SendSlot(ply, session)
            if type(session.onFractureComplete) == "function" then
                pcall(session.onFractureComplete, ply, session)
            elseif WSZC.StabilizeZCityFracture then
                pcall(WSZC.StabilizeZCityFracture, session.target, session.limbId, ply, swep)
            end
            StopMinigame(ply, "completed")
        end
        return
    end

    -- An artery is not a bandage target.  Do not spend even a partial roll
    -- when no ordinary bleeding remains; still ACK and refresh the state so
    -- the client can show the persistent blood drop / TOURNIQUET prompt.
    local finalAftercare = WSZC.ShrapnelAftercarePending
        and WSZC.ShrapnelAftercarePending(session.target, session.limbId) or false
    if WSZC.GetBandageBleeding and WSZC.OrganismAuthority
        and WSZC.OrganismAuthority() and type(session.target.organism) == "table"
        and CurrentBandageBleeding(session) <= 0.0001 and not finalAftercare then
        SendBandageState(ply, session)
        SendAck(ply, session, ACK_BANDAGE, inputSeq)
        return
    end

    local profile = BandageProfile(session.itemId, session.item)
    local perWrap = math.max(
        tonumber(profile.durabilityPerWrap) or Constants().BandageDurabilityPerWrap or 2,
        0.0001
    )
    local durCost = degrees / 360 * perWrap
    if durCost <= 0 then
        SendAck(ply, session, ACK_BANDAGE, inputSeq)
        return
    end

    local nativeHandled, physicalEmpty = false, false
    if session.live and session.nativeBandage then
        nativeHandled, physicalEmpty = ProcessNativeBandageInput(
            ply, session, profile, perWrap, durCost, finalAftercare)
        if WSZC.MinigameSessions[ply] ~= session then return end
    end

    if not nativeHandled then
        durCost = math.min(durCost, math.max(session.startAmount - session.deferredUsed, 0))
        if durCost <= 0 then
            SendAck(ply, session, ACK_BANDAGE, inputSeq)
            return
        end
        session.deferredUsed = math.min(session.startAmount, session.deferredUsed + durCost)
        if session.live and type(session.onProgress) == "function" then
            local ok, err = pcall(session.onProgress, ply, session, durCost)
            if not ok then Warn("bandage onProgress failed: " .. tostring(err)) end
            if WSZC.MinigameSessions[ply] ~= session then return end
        end
    end

    SendBandageState(ply, session)
    SendSlot(ply, session)
    SendAck(ply, session, ACK_BANDAGE, inputSeq)

    -- A native ZCity session is complete when the REAL ordinary wounds are
    -- closed (or the required final shrapnel dressing has landed).  Previously
    -- the roll simply stayed open at 100%; further circles were acknowledged
    -- but could neither treat nor consume, looking exactly like a bandage that
    -- did not work.  Close through the normal path so WB.onClose/AfterUse runs,
    -- the virtual slot is removed and the client overlay/cursor are released.
    local aftercareRemaining = WSZC.ShrapnelAftercarePending
        and WSZC.ShrapnelAftercarePending(session.target, session.limbId) or false
    if session.nativeBandage and CurrentBandageBleeding(session) <= 0.0001
        and not aftercareRemaining then
        StopMinigame(ply, "completed")
        return
    end

    if physicalEmpty or session.startAmount - session.deferredUsed <= 0.001 then
        StopMinigame(ply, "empty")
    end
end

local function ProcessSyringeInput(_, ply)
    local session = ValidSession(ply)
    if not session or session.kind ~= "syringe" then return end

    local sessionId = net.ReadUInt(24)
    local depth = net.ReadFloat()
    local brokeNeedle = net.ReadBool()
    local inputSeq = ReadOptionalUInt(24, 0)
    if sessionId ~= session.id then return end

    if not IsValid(ply) or not ply:Alive() then
        StopMinigame(ply, "dead")
        return
    end
    if not IsValid(session.target) or not session.target:Alive() or not Bridged(session.target) then
        StopMinigame(ply, "target_gone")
        return
    end
    if not RemoteSessionValid(ply, session) then
        StopMinigame(ply, "out_of_range")
        return
    end

    if brokeNeedle then
        session.lastAckSeq = inputSeq
        StopMinigame(ply, "needle_break")
        return
    end

    depth = math.Clamp(tonumber(depth) or 0, 0, 1)
    local now = CurTime and CurTime() or 0
    local elapsed = math.Clamp(now - (session.lastInputAt or now), 0, 0.2)
    local hz = math.max(tonumber(Constants().SyringeInputHz) or 20, 1)
    if elapsed < (1 / hz) then return end

    session.lastInputAt = now
    session.lastAckSeq = inputSeq

    if depth <= 0 then
        SendAck(ply, session, ACK_SYRINGE, inputSeq)
        SendSyringeState(ply, session, inputSeq)
        return
    end

    local profile = SyringeProfile(session.itemId, session.item)
    local rate = math.max(
        tonumber(profile.durabilityPerSecond) or Constants().SyringeDurabilityPerSecond or 18,
        0.0001
    )
    local durCost = math.min(
        depth * elapsed * rate,
        math.max(session.startAmount - session.deferredUsed, 0)
    )
    if durCost <= 0 then
        SendAck(ply, session, ACK_SYRINGE, inputSeq)
        SendSyringeState(ply, session, inputSeq)
        return
    end

    session.deferredUsed = math.min(session.startAmount, session.deferredUsed + durCost)

    if session.live and type(session.onProgress) == "function" then
        local ok, err = pcall(session.onProgress, ply, session, durCost)
        if not ok then Warn("syringe onProgress failed: " .. tostring(err)) end
        if WSZC.MinigameSessions[ply] ~= session then return end
    end

    SendSlot(ply, session)
    SendAck(ply, session, ACK_SYRINGE, inputSeq)
    SendSyringeState(ply, session, inputSeq)

    if session.startAmount - session.deferredUsed <= 0.001 then
        StopMinigame(ply, "empty")
    end
end

local function ProcessClose(name, kind)
    return function(_, ply)
        local session = ValidSession(ply)
        if not session or session.kind ~= kind then return end

        local sessionId = net.ReadUInt(24)
        local reason = net.ReadString()
        if sessionId ~= session.id then return end
        StopMinigame(ply, reason ~= "" and reason or "client_close")
    end
end

net.Receive("WSZC_BandageInput", ProcessBandageInput)
net.Receive("WSZC_SyringeInput", ProcessSyringeInput)
net.Receive("WSZC_BandageClose", ProcessClose("WSZC_BandageClose", "bandage"))
net.Receive("WSZC_SyringeClose", ProcessClose("WSZC_SyringeClose", "syringe"))

-- The copies keep MG.RequestStart(); it is not used by ZCity, but the strings
-- must still be accepted so a stray call cannot produce an unpooled-message error.
net.Receive("WSZC_BandageStart", function() end)
net.Receive("WSZC_SyringeStart", function() end)

hook.Add("PlayerDeath", "WSZC_MinigameDeath", function(ply)
    if WSZC.MinigameSessions[ply] then StopMinigame(ply, "dead") end
end)

hook.Add("PlayerSpawn", "WSZC_MinigameSpawn", function(ply)
    -- ZCity sets this GLOBAL only around FakeUp's internal ply:Spawn().  It is
    -- the exact discriminator, unlike Alive()/consciousness after a respawn.
    if OverrideSpawn == true then return end
    -- A genuine spawn is always authoritative cleanup, including native C:U
    -- sessions and a client that missed PlayerDeath.  The force-close packet
    -- also releases WoundView, its cursor and every movement/bind lock.
    StopAllMinigames(ply, "respawn", true)
end)

hook.Add("PlayerDisconnected", "WSZC_MinigameDisconnect", function(ply)
    if WSZC.MinigameSessions[ply] then StopMinigame(ply, "disabled") end
end)

-- Server-side counterpart of the client's WSZC_MinigameLockMovement: even if a
-- client fails to zero its command, the player cannot walk, jump, shoot or
-- turn while bandaging/injecting.  Vertical velocity is preserved so falling
-- is not frozen in mid-air.
hook.Add("SetupMove", "WSZC_MinigameServerLock", function(ply, mv, cmd)
    -- Dead / respawning players must never be pinned by a leftover session
    -- (a C:U Dislocation session can survive death on some builds).  The
    -- engine needs a free CUserCmd to run PlayerDeathThink / respawn.
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then
        if ply then ply._WSZCDislocationAngles = nil end
        return
    end
    local session = WSZC.MinigameSessions and WSZC.MinigameSessions[ply]
    -- C:U's NATIVE manual bone-reduction minigame (WoundView -> FIX
    -- DISLOCATION) has its own sessions table; it must get the same movement /
    -- camera lock as the WSZC bandage and syringe games.
    local cuSessions = WSZC.CUSessions
    local dislocation = type(cuSessions) == "table"
        and type(cuSessions.Dislocation) == "table"
        and cuSessions.Dislocation[ply] or nil
    -- C:U occasionally leaves a Dislocation session behind after the game
    -- closed.  Cap its lifetime so it cannot pin SetupMove forever.
    if dislocation and not session then
        local now = CurTime and CurTime() or 0
        ply._WSZCDislocationSeenAt = ply._WSZCDislocationSeenAt or now
        if now - ply._WSZCDislocationSeenAt > 20 then
            cuSessions.Dislocation[ply] = nil
            dislocation = nil
            ply._WSZCDislocationSeenAt = nil
            ply._WSZCDislocationAngles = nil
        end
    else
        ply._WSZCDislocationSeenAt = nil
    end
    if not session and not dislocation then
        if ply then ply._WSZCDislocationAngles = nil end
        return
    end
    if not (IsValid(ply) and ply:IsPlayer()) then return end

    if mv and mv.SetVelocity and mv.GetVelocity then
        local v = mv:GetVelocity()
        mv:SetVelocity(Vector(0, 0, math.min(v.z or 0, 0)))
    end
    if not cmd then return end
    if cmd.SetForwardMove then cmd:SetForwardMove(0) end
    if cmd.SetSideMove then cmd:SetSideMove(0) end
    if cmd.SetUpMove then cmd:SetUpMove(0) end
    -- Do NOT zero IN_ATTACK for a native C:U Dislocation session.  That kept
    -- ZCity medical SWEPs (fentanyl, morphine, ...) from ever firing after a
    -- minigame, because the reduction session can outlive the game.  Only OUR
    -- bandage/syringe sessions need the full button lock; movement/view stay
    -- frozen for both.
    if session and cmd.SetButtons then cmd:SetButtons(0) end
    if cmd.SetMouseX then cmd:SetMouseX(0) end
    if cmd.SetMouseY then cmd:SetMouseY(0) end
    -- Zeroing the mouse delta is not enough: GMod already applied it to
    -- ViewAngles before SetupMove.  Force the frozen angles back.
    if session and session.frozenAngles and cmd.SetViewAngles then
        cmd:SetViewAngles(session.frozenAngles)
    end
    if dislocation then
        if not ply._WSZCDislocationAngles and ply.EyeAngles then
            local ok, ang = pcall(ply.EyeAngles, ply)
            if ok and ang then ply._WSZCDislocationAngles = ang end
        end
        if ply._WSZCDislocationAngles and cmd.SetViewAngles then
            cmd:SetViewAngles(ply._WSZCDislocationAngles)
        end
    else
        ply._WSZCDislocationAngles = nil
    end
end)

hook.Add("Think", "WSZC_MinigameWatch", function()
    WSZC.NextMinigameWatch = WSZC.NextMinigameWatch or 0
    local now = CurTime and CurTime() or 0
    if now < WSZC.NextMinigameWatch then return end
    WSZC.NextMinigameWatch = now + 0.25

    if not (WSZC.Ready and BridgeEnabled() and OwnMinigamesEnabled() and HealthEnabled()) then
        for ply in pairs(WSZC.MinigameSessions) do StopMinigame(ply, "disabled") end
        return
    end

    for ply, session in pairs(WSZC.MinigameSessions) do
        if not IsValid(ply) or not ply:Alive() then
            StopMinigame(ply, "dead")
        elseif PlayerIncapacitated(ply) then
            StopAllMinigames(ply, "unconscious", true)
        elseif not IsValid(session.target) or not session.target:Alive() or not Bridged(session.target) then
            StopMinigame(ply, "target_gone")
        elseif session.limbId ~= "body" and WSZC.H and WSZC.H.GetLimbState
            and not WSZC.H.GetLimbState(session.target, session.limbId) then
            StopMinigame(ply, "invalid_limb")
        elseif (now - (session.startedAt or now)) > SESSION_TIMEOUT then
            StopMinigame(ply, "disabled")
        end
    end

    -- Native shrapnel/dislocation sessions are not in MinigameSessions, so
    -- sweep players too.  StopAllMinigames only networks when one exists.
    if player and player.GetAll then
        for _, ply in ipairs(player.GetAll()) do
            if PlayerIncapacitated(ply) and (HasNativeSession(ply) or HasActiveRemoteOperatorSession(ply)) then
                StopAllMinigames(ply, "unconscious", true)
            end
        end
    end
end)

net.Receive("WSZC_DislocationVisualComplete", function(_, ply)
    local sessionId = net.ReadUInt(24)
    local x, y = net.ReadFloat(), net.ReadFloat()
    if WSZC.HandleDislocationVisualComplete then
        WSZC.HandleDislocationVisualComplete(ply, sessionId, x, y)
    end
end)

hook.Add("HG_OnOtrub", "WSZC_MinigameUnconscious", function(ply)
    StopAllMinigames(ply, "unconscious", true)
end)
hook.Add("Fake", "WSZC_MinigameUnconscious", function(ply)
    -- HG_OnOtrub is the immediate authoritative unconscious signal.  A plain
    -- Fake transition may be conscious, so close only if the operator's own
    -- organism proves incapacity; re-check next tick for late native flags.
    if PlayerIncapacitated(ply) then
        StopAllMinigames(ply, "unconscious", true)
        return
    end
    timer.Simple(0, function()
        if IsValid(ply) and PlayerIncapacitated(ply) then
            StopAllMinigames(ply, "unconscious", true)
        end
    end)
end)
