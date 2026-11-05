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
    local value = Upvalue(data.onProgress, name)
    if value ~= nil then return value end
    return Upvalue(data.onClose, name)
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

local function StopCUSessions(ply, reason)
    local sessions = WSZC.CUSessions
    if type(sessions) ~= "table" then return end
    reason = reason or "disabled"

    if sessions.Bandage and sessions.Bandage[ply] and WSZC.CUCloseBandageSession then
        pcall(WSZC.CUCloseBandageSession, ply, reason)
    end
    if sessions.Syringe and sessions.Syringe[ply] and WSZC.CUCloseSyringeSession then
        pcall(WSZC.CUCloseSyringeSession, ply, reason)
    end
    if sessions.Shrapnel and sessions.Shrapnel[ply] then
        if WSZC.CUCloseShrapnelSession then
            pcall(WSZC.CUCloseShrapnelSession, ply, reason)
        else
            sessions.Shrapnel[ply] = nil
        end
    end
    if sessions.Dislocation and sessions.Dislocation[ply] then
        if WSZC.CUCloseDislocationSession then
            pcall(WSZC.CUCloseDislocationSession, ply, reason)
        else
            sessions.Dislocation[ply] = nil
        end
    end
    if sessions.Aed and sessions.Aed[ply] then
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
        if type(sessions[kind]) == "table" and sessions[kind][ply] then return true end
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
    if IsValid(ply.FakeRagdoll) then return true end
    local org = ply.organism
    if type(org) == "table" then
        if org.otrub == true or org.needotrub == true
            or org.fake == true or org.needfake == true then return true end
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
    local had = WSZC.MinigameSessions[ply] ~= nil or HasNativeSession(ply)
    StopMinigame(ply, reason)
    StopCUSessions(ply, reason)
    local health = WSZC.H or (WoundSystem and WoundSystem.Health)
    if health and type(health.CancelActiveMedicalSessions) == "function" then
        pcall(health.CancelActiveMedicalSessions, ply, reason)
    elseif type(WoundSystemCloseAllMedicalSessions) == "function" then
        pcall(WoundSystemCloseAllMedicalSessions, ply, reason)
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

local function StartMinigame(ply, data)
    if not (WSZC.Ready and BridgeEnabled() and OwnMinigamesEnabled() and HealthEnabled()) then return false end
    if not (IsValid(ply) and ply:IsPlayer() and ply:Alive()) then return false end
    if PlayerIncapacitated(ply) then return false end
    if HasMinigame(ply) then return true end
    if type(data) ~= "table" then return false end

    local kind = data.kind
    if kind ~= "bandage" and kind ~= "syringe" then return false end
    if type(data.onProgress) ~= "function" or type(data.onClose) ~= "function" then return false end

    -- `spec` is an upvalue of the bridge closures.  `spec.mg` is ZCity's
    -- minigame-capable marker, but after the owner's correction it is not
    -- sufficient by itself: one-dose specs still stay instant.
    local spec = ClosureValue(data, "spec")
    if type(spec) ~= "table" or type(spec.mg) ~= "table" or spec.mg.kind ~= kind then
        return false
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
        return false
    end

    local H = WSZC.H
    if type(H) ~= "table" or type(H.ApplyItemToBody) ~= "function" then return false end

    local target = ClosureValue(data, "target")
    if not (IsValid(target) and target:IsPlayer() and target:Alive()) then return false end
    if not Bridged(target) then return false end

    local limbId = data.limbId
    if type(limbId) ~= "string" or limbId == "" then return false end
    if H.InitPlayer and H.GetLimbs and not H.GetLimbs(target) then pcall(H.InitPlayer, target) end
    if limbId ~= "body" and H.GetLimbState and not H.GetLimbState(target, limbId) then return false end

    local Items = WoundSystem and WoundSystem.Items
    local itemId = NormalizeItemId(data.itemId)
    local item = Items and Items.Get and Items.Get(itemId)
    if not item then return false end

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
    local initialBleed = kind == "bandage"
        and CurrentBandageBleeding({ target = target, limbId = limbId }) or 0
    local session = {
        id = id,
        kind = kind,
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
            net.WriteString(profile.mode or "gauze")
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

function WSZC.InstallMinigameAPI(H)
    if type(H) ~= "table" then return false end

    H.HasExternalMinigame = HasMinigame
    H.StopExternalMinigame = StopExternal
    H.StartExternalMinigame = StartMinigame
    WSZC.H = H
    return true
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

    degrees = math.Clamp(tonumber(degrees) or 0, 0, 360)
    if degrees <= 0 then return end

    session.lastAckSeq = inputSeq

    -- An artery is not a bandage target.  Do not spend even a partial roll
    -- when no ordinary bleeding remains; still ACK and refresh the state so
    -- the client can show the persistent blood drop / TOURNIQUET prompt.
    if WSZC.GetBandageBleeding and WSZC.OrganismAuthority
        and WSZC.OrganismAuthority() and type(session.target.organism) == "table"
        and CurrentBandageBleeding(session) <= 0.0001 then
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

    SendBandageState(ply, session)
    SendSlot(ply, session)
    SendAck(ply, session, ACK_BANDAGE, inputSeq)

    if session.startAmount - session.deferredUsed <= 0.001 then
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
    if WSZC.MinigameSessions[ply] then StopMinigame(ply, "respawn") end
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
            if PlayerIncapacitated(ply) and HasNativeSession(ply) then
                StopAllMinigames(ply, "unconscious", true)
            end
        end
    end
end)

hook.Add("HG_OnOtrub", "WSZC_MinigameUnconscious", function(ply)
    StopAllMinigames(ply, "unconscious", true)
end)
hook.Add("Fake", "WSZC_MinigameUnconscious", function(ply)
    StopAllMinigames(ply, "unconscious", true)
end)
