-- ZCity <-> Casualties: Unknown remote inspection/treatment (client part)
--
-- Adds a second radial option when another living player is under the
-- crosshair.  The native C:U panel is reused, but its exposed limb/cardio
-- tables temporarily display authoritative snapshots of that patient.  Only
-- the whitelisted native medical messages produced while this mode is active
-- are redirected through WSZC_RemoteMedicalAction.  Ordinary self-treatment
-- packets and the original "Проверить травмы" button are untouched.

if not CLIENT then return end
WSZC = WSZC or {}
if WSZC._RemoteMedicalClientLoaded then return end
WSZC._RemoteMedicalClientLoaded = true

local RANGE = 256
local OPEN_DELAY = 0.12
local OPEN_TIMEOUT = 1.25
local BUTTON_LABEL = "Лечить игрока"

local Remote = {
    target = nil,
    pending = nil,
    pendingAt = 0,
    active = false,
    selfLimbs = nil,
    selfCardio = nil,
    selfStats = nil,
    internalOpen = false,
    patientName = "",
    blood = 100,
    happiness = 0,
}
WSZC.RemoteMedical = Remote

local cvButton = CreateClientConVar and CreateClientConVar(
    "zc_woundsystem_compat_remote_inspect_button", "1", true, false,
    "Show 'Treat player' in the radial menu when another living player is under the crosshair"
) or nil
if not cvButton and GetConVar then cvButton = GetConVar("zc_woundsystem_compat_remote_inspect_button") end

local function ConVarAllows(name)
    local cv = GetConVar and GetConVar(name)
    return not (cv and cv.GetBool) or cv:GetBool() ~= false
end

local function Ready()
    if cvButton and cvButton.GetBool and not cvButton:GetBool() then return false end
    if not ConVarAllows("zc_woundsystem_bridge") or not ConVarAllows("woundsys_enabled") then return false end
    if GetGlobalBool and GetGlobalBool("WSZC_Ready", false) ~= true then return false end
    if WSZC.Supports and not WSZC.Supports("remote") then return false end
    return WoundSystem and WoundSystemClientState
        and type(WoundSystemClientState.PlayerLimbs) == "table"
        and type(WoundSystemClientState.Cardio) == "table"
        and WoundSystem.OpenHealthHUD ~= nil
end

local function AsPlayer(owner)
    return owner ~= NULL and IsValid(owner) and owner:IsPlayer() and owner or nil
end

local function PlayerFromEntity(ent)
    if not IsValid(ent) then return nil end
    if ent:IsPlayer() then return ent end

    -- ZCity's client resolver accepts only one exact representation:
    -- ragdoll:GetNWEntity("ply") AND player:GetNWEntity("FakeRagdoll").
    -- Some server builds set ragdoll.ply only in Lua, so that resolver returns
    -- nil even though every player can see the ragdoll. Try all native links,
    -- then the reverse player -> ragdoll relation before giving up.
    if hg and hg.RagdollOwner then
        local ok, owner = pcall(hg.RagdollOwner, ent)
        if ok and AsPlayer(owner) then return owner end
    end
    local entOrg = ent.organism
    local owner = type(entOrg) == "table" and AsPlayer(entOrg.owner) or nil
    if owner then return owner end
    owner = AsPlayer(ent.ply)
    if owner then return owner end

    if ent.GetNWEntity then
        for _, key in ipairs({ "ply", "Owner", "RagdollOwner", "WoundSystemOwner", "WoundSystemPlayer" }) do
            local ok, candidate = pcall(ent.GetNWEntity, ent, key, NULL)
            if ok and AsPlayer(candidate) then return candidate end
        end
    end
    if ent.GetOwner then
        local ok, candidate = pcall(ent.GetOwner, ent)
        if ok and AsPlayer(candidate) then return candidate end
    end

    if player and player.GetAll then
        for _, candidate in ipairs(player.GetAll()) do
            if candidate.FakeRagdoll == ent or candidate.DeathRagdoll == ent or candidate.Ragdoll == ent then
                return candidate
            end
            if candidate.GetNWEntity then
                for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" }) do
                    local ok, ragdoll = pcall(candidate.GetNWEntity, candidate, key, NULL)
                    if ok and ragdoll == ent then return candidate end
                end
            end
        end
    end
    return nil
end

-- A living ZCity player entity can remain at its pre-ragdoll position. Range
-- must be measured to the body actually under the medic's crosshair.
local function PatientEntity(target)
    if not IsValid(target) then return nil end
    if IsValid(target.FakeRagdoll) then return target.FakeRagdoll end
    if target.GetNWEntity then
        for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" }) do
            local ok, ragdoll = pcall(target.GetNWEntity, target, key, NULL)
            if ok and IsValid(ragdoll) then return ragdoll end
        end
    end
    return target
end
Remote.PatientEntity = PatientEntity

local function ValidPatient(ply, target)
    if not (IsValid(ply) and IsValid(target) and target ~= ply) then return false end
    if not ply:Alive() or not target:Alive() then return false end
    local subject = PatientEntity(target)
    if not IsValid(subject) then return false end
    local from = ply.EyePos and ply:EyePos() or ply:GetPos()
    local to = subject.WorldSpaceCenter and subject:WorldSpaceCenter() or subject:GetPos()
    return from:Distance(to) <= RANGE
end

local function FindPatient()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return nil end

    -- Player:GetEyeTrace() does not use ZCity's fake/ragdoll camera anchor.
    -- The radial menu and every medical SWEP use hg.eyeTrace(), so inspect the
    -- same entity the player actually sees under the ZCity crosshair.
    if hg and hg.eyeTrace then
        local ok, trace = pcall(hg.eyeTrace, ply, RANGE)
        local target = ok and PlayerFromEntity(trace and trace.Entity or nil) or nil
        if ValidPatient(ply, target) then
            Remote.focusTarget = target
            return target
        end
    end
    local trace = ply:GetEyeTrace()
    local target = PlayerFromEntity(trace and trace.Entity or nil)
    if ValidPatient(ply, target) then
        Remote.focusTarget = target
        return target
    end

    -- Lying ZCity ragdolls have thin limb hitboxes; a narrow hull trace along
    -- the medic's aim ray catches patients slightly beside the center pixel.
    if util and util.TraceHull and Vector and ply.EyePos and ply.GetAimVector then
        local startPos = ply:EyePos()
        local hullTrace = util.TraceHull({
            start = startPos,
            endpos = startPos + ply:GetAimVector() * RANGE,
            mins = Vector(-10, -10, -10),
            maxs = Vector(10, 10, 10),
            filter = ply,
        })
        local hullTarget = PlayerFromEntity(hullTrace and hullTrace.Entity or nil)
        if ValidPatient(ply, hullTarget) then
            Remote.focusTarget = hullTarget
            return hullTarget
        end
    end

    -- CreateRadialMenu rebuilds every option four times a second while the
    -- cursor is moving towards a sector. Keep the last genuinely traced body
    -- for that open menu instead of making a narrow ragdoll option vanish
    -- before the click. Range/alive are still checked on every rebuild.
    if IsValid(MENUPANELHUYHUY) and ValidPatient(ply, Remote.focusTarget) then
        return Remote.focusTarget
    end
    Remote.focusTarget = nil
    return nil
end
Remote.FindPatient = FindPatient
Remote.ValidPatient = ValidPatient

-- Outgoing native packet capture.  Values are re-encoded with WriteType only
-- for our namespaced message; the server validates the exact action schema.
local capture
local originalNet = {}
local ACTION_WHITELIST = {
    WoundSystem_UseMedicalItem = true, WoundSystem_RemoveLimbStatus = true,
    WoundSystem_ShrapnelStart = true, WoundSystem_ShrapnelInput = true, WoundSystem_ShrapnelClose = true,
    WoundSystem_DislocationStart = true, WoundSystem_DislocationInput = true, WoundSystem_DislocationClose = true,
    WoundSystem_BandageStart = true, WoundSystem_BandageInput = true, WoundSystem_BandageClose = true,
    WoundSystem_SyringeStart = true, WoundSystem_SyringeInput = true, WoundSystem_SyringeClose = true,
    WoundSystem_AEDStart = true, WoundSystem_AEDInput = true, WoundSystem_AEDClose = true,
}

local function InstallCapture()
    if Remote.captureInstalled then return end
    Remote.captureInstalled = true
    for _, key in ipairs({ "Start", "SendToServer", "WriteUInt", "WriteInt", "WriteFloat", "WriteString", "WriteBool", "WriteEntity" }) do
        originalNet[key] = net[key]
    end
    net.Start = function(name, ...)
        if Remote.active and ACTION_WHITELIST[name] then
            -- Never fall back to C:U's self receiver if the patient vanished
            -- between frames.  Such an action is captured, then discarded.
            capture = { action = name, target = Remote.target, values = {} }
            return
        end
        capture = nil
        return originalNet.Start(name, ...)
    end
    local writers = {
        WriteUInt = "number", WriteInt = "number", WriteFloat = "number",
        WriteString = "string", WriteBool = "boolean", WriteEntity = "entity",
    }
    for key in pairs(writers) do
        net[key] = function(value, ...)
            if capture then
                capture.values[#capture.values + 1] = value
                return
            end
            return originalNet[key](value, ...)
        end
    end
    net.SendToServer = function(...)
        if capture then
            local packet = capture
            capture = nil
            if Remote.active and IsValid(packet.target) then
                originalNet.Start("WSZC_RemoteMedicalAction")
                    originalNet.WriteEntity(packet.target)
                    originalNet.WriteString(packet.action)
                    originalNet.WriteUInt(#packet.values, 8)
                    for _, value in ipairs(packet.values) do net.WriteType(value) end
                return originalNet.SendToServer(...)
            end
            return -- swallowed: a remote action must never become self-treatment
        end
        return originalNet.SendToServer(...)
    end
end

-- While a remote snapshot is visible, do not let the local player's ordinary
-- limb/cardio packets overwrite it.  The server sends a fresh self snapshot on
-- close, so these updates are deferred rather than lost.
local selfUpdateOriginals = {}
local function InstallSelfUpdateGuards()
    for _, name in ipairs({ "WoundSystem_UpdateLimb", "WoundSystem_UpdateCardio" }) do
        local current = net.Receivers and net.Receivers[name]
        if type(current) == "function" and current ~= Remote["guard_" .. name] then
            selfUpdateOriginals[name] = current
            local guard = function(len, ...)
                if Remote.active then return end
                return selfUpdateOriginals[name](len, ...)
            end
            Remote["guard_" .. name] = guard
            net.Receivers[name] = guard
        end
    end
end

local function ReplaceContents(destination, source)
    for key in pairs(destination) do destination[key] = nil end
    for key, value in pairs(source or {}) do
        destination[key] = type(value) == "table" and table.Copy(value) or value
    end
end

local function SelfTables()
    return WoundSystemClientState.PlayerLimbs, WoundSystemClientState.Cardio,
        WoundSystemClientState.PlayerStats
end

local function SaveSelfState()
    if Remote.selfLimbs then return end
    local limbs, cardio, stats = SelfTables()
    Remote.selfLimbs = table.Copy(limbs)
    Remote.selfCardio = table.Copy(cardio)
    Remote.selfStats = type(stats) == "table" and table.Copy(stats) or nil
end

local function ApplyStatsSnapshot(cardio)
    local _, _, stats = SelfTables()
    if type(stats) ~= "table" or type(cardio) ~= "table" then return end
    local skills = type(cardio.skills) == "table" and cardio.skills or {}
    stats.STR = tonumber(skills.STR) or stats.STR or 9
    stats.RES = tonumber(skills.RES) or stats.RES or 8
    stats.INT = tonumber(skills.INT) or stats.INT or 7
    stats.consciousness = tonumber(cardio.consciousness) or stats.consciousness or 100
end

local function RestoreSelfState(limbs, cardio)
    local currentLimbs, currentCardio, currentStats = SelfTables()
    ReplaceContents(currentLimbs, limbs or Remote.selfLimbs or {})
    ReplaceContents(currentCardio, cardio or Remote.selfCardio or {})
    if type(currentStats) == "table" and Remote.selfStats then
        ReplaceContents(currentStats, Remote.selfStats)
    end
    if cardio then ApplyStatsSnapshot(cardio) end
    Remote.selfLimbs, Remote.selfCardio, Remote.selfStats = nil, nil, nil
end

local originalOpen, originalClose
local FinishRemote
local function CallNativeOpen()
    Remote.internalOpen = true
    local ok, err = pcall(originalOpen)
    Remote.internalOpen = false
    if not ok then
        if ErrorNoHalt then ErrorNoHalt("[WSZC remote] native open failed: " .. tostring(err) .. "\n") end
        FinishRemote("panel_error")
    end
end

local function EnsurePanelWrappers()
    if not (WoundSystem and WoundSystem.OpenHealthHUD and WoundSystem.CloseHealthHUD) then return false end
    if originalOpen and WoundSystem.OpenHealthHUD == Remote.wrappedOpen
        and WoundSystem.CloseHealthHUD == Remote.wrappedClose then return true end
    local baseOpen = WoundSystem.OpenHealthHUD
    local baseClose = WoundSystem.CloseHealthHUD
    originalOpen = baseOpen
    originalClose = baseClose
    Remote.wrappedOpen = function(...)
        if Remote.active and not Remote.internalOpen then Remote.Finish("self_open") end
        return baseOpen(...)
    end
    Remote.wrappedClose = function(...)
        local wasRemote = Remote.active
        if wasRemote then
            -- Native CloseHealthHUD also closes minigames.  Keep capture active
            -- for that call so those close packets go to the remote server.
            local results = { baseClose(...) }
            Remote.Finish("panel_closed")
            return unpack(results)
        end
        return baseClose(...)
    end
    WoundSystem.OpenHealthHUD = Remote.wrappedOpen
    WoundSystem.CloseHealthHUD = Remote.wrappedClose
    return true
end

local function ApplySnapshot(limbs, cardio, name, blood, happiness)
    local currentLimbs, currentCardio = SelfTables()
    local selfUnconscious = false
    if type(Remote.selfCardio) == "table" and Remote.selfCardio.unconscious ~= nil then
        selfUnconscious = Remote.selfCardio.unconscious == true
    elseif type(currentCardio) == "table" and currentCardio.unconscious ~= nil then
        selfUnconscious = currentCardio.unconscious == true
    end
    ReplaceContents(currentLimbs, limbs)
    ReplaceContents(currentCardio, cardio)
    -- Keep the MEDIC's consciousness flag in WoundSystemClientState.Cardio so
    -- OpenHealthHUD / ToggleHUDInput never abort or auto-close when inspecting
    -- an unconscious/ragdolled patient.  Patient consciousness is tracked separately.
    Remote.patientUnconscious = type(cardio) == "table" and cardio.unconscious == true or false
    if type(currentCardio) == "table" then
        currentCardio.unconscious = selfUnconscious
    end
    ApplyStatsSnapshot(cardio)
    Remote.patientName = name or (IsValid(Remote.target) and Remote.target:Nick() or "player")
    Remote.blood = tonumber(blood) or 100
    Remote.happiness = tonumber(happiness) or 0
end

local BeginRemote
BeginRemote = function(target, limbs, cardio, name, blood, happiness)
    if not (Ready() and ValidPatient(LocalPlayer(), target) and EnsurePanelWrappers()) then
        if Remote.pending == target then FinishRemote("not_ready") end
        return
    end
    if Remote.active and Remote.target ~= target then FinishRemote("replaced") end
    InstallSelfUpdateGuards()
    SaveSelfState()
    Remote.target, Remote.pending, Remote.active = target, nil, true
    InstallCapture()
    ApplySnapshot(limbs, cardio, name, blood, happiness)
    CallNativeOpen()
end

FinishRemote = function(reason)
    local wasPending = Remote.pending ~= nil
    Remote.pending = nil
    capture = nil
    if not Remote.active and not wasPending then return end
    local wasActive = Remote.active
    Remote.active, Remote.target, Remote.patientUnconscious = false, nil, false
    if originalNet.Start then
        originalNet.Start("WSZC_RemoteMedicalClose")
        originalNet.SendToServer()
    else
        net.Start("WSZC_RemoteMedicalClose")
        net.SendToServer()
    end
    if wasActive then
        RestoreSelfState()
        if WoundSystemHealthHUDOpen and originalClose then originalClose() end
    end
    Remote.closedReason = reason or "closed"
end
Remote.Finish = FinishRemote

net.Receive("WSZC_RemoteMedicalState", function()
    local target = net.ReadEntity()
    local limbs, cardio = net.ReadTable(), net.ReadTable()
    local name, blood, happiness = net.ReadString(), net.ReadFloat(), net.ReadFloat()
    if not IsValid(target) then return end
    if Remote.pending == target and not Remote.active then
        BeginRemote(target, limbs, cardio, name, blood, happiness)
    elseif Remote.active and Remote.target == target then
        ApplySnapshot(limbs, cardio, name, blood, happiness)
    end
end)

net.Receive("WSZC_RemoteMedicalRestoreSelf", function()
    net.ReadEntity()
    local limbs, cardio = net.ReadTable(), net.ReadTable()
    net.ReadString(); net.ReadFloat(); net.ReadFloat()
    if not Remote.active then RestoreSelfState(limbs, cardio) end
end)

net.Receive("WSZC_RemoteMedicalClose", function()
    local target, reason = net.ReadEntity(), net.ReadString()
    local matchesActive = Remote.active and (not IsValid(target) or Remote.target == target)
    local matchesPending = Remote.pending and (not IsValid(target) or Remote.pending == target)
    if not (matchesActive or matchesPending) then return end
    if Remote.active then
        Remote.active, Remote.target, Remote.pending, Remote.patientUnconscious = false, nil, nil, false
        capture = nil
        RestoreSelfState()
        if WoundSystemHealthHUDOpen and originalClose then originalClose() end
    else
        Remote.pending = nil
    end
    Remote.closedReason = reason
end)

function WSZC.OpenRemotePatient(target, immediate)
    if not Ready() then return false end
    local ply = LocalPlayer()
    target = target or FindPatient()
    if not ValidPatient(ply, target) then return false end
    if Remote.active and Remote.target == target then return true end
    if Remote.pending == target and not Remote.active then return true end
    if Remote.active or Remote.pending then FinishRemote("replaced") end
    EnsurePanelWrappers()
    Remote.pending, Remote.pendingAt = target, CurTime()
    if immediate or not (timer and timer.Simple) then
        net.Start("WSZC_RemoteMedicalOpen")
            net.WriteEntity(target)
        net.SendToServer()
        return true
    end
    timer.Simple(OPEN_DELAY, function()
        if Remote.pending ~= target or not ValidPatient(LocalPlayer(), target) then return end
        net.Start("WSZC_RemoteMedicalOpen")
            net.WriteEntity(target)
        net.SendToServer()
    end)
    return true
end

-- Preserve the existing self-inspection entry point and make its behaviour
-- explicit when it is used while a remote panel is open.
if type(WSZC.OpenCUWoundMenu) == "function" and not Remote.selfOpenWrapped then
    Remote.selfOpenWrapped = true
    local baseOpen = WSZC.OpenCUWoundMenu
    WSZC.OpenCUWoundMenu = function(...)
        if Remote.active or Remote.pending then FinishRemote("self_open") end
        return baseOpen(...)
    end
end

hook.Add("RadialMenuPressed", "ZCity_WoundBridge_RemoteInspectFocus_WSZC", function()
    Remote.focusTarget = nil
end)

hook.Add("radialOptions", "ZCity_WoundBridge_RemoteInspect_WSZC", function()
    if not Ready() then return end
    local target = FindPatient()
    if not target then return end
    hg.radialOptions = hg.radialOptions or {}
    local option = {
        function() WSZC.OpenRemotePatient(target) end,
        BUTTON_LABEL .. "\n" .. target:Nick(),
    }
    option._WSZCRemoteInspect = true
    hg.radialOptions[#hg.radialOptions + 1] = option
end)

hook.Add("Think", "WSZC_RemoteMedicalWatchdog", function()
    if Remote.pending and CurTime() - Remote.pendingAt > OPEN_TIMEOUT then
        FinishRemote("open_timeout")
    end
    if not Remote.active then return end
    if not Ready() or not ValidPatient(LocalPlayer(), Remote.target) then
        FinishRemote("patient_unavailable")
        return
    end
    if not WoundSystemHealthHUDOpen and not Remote.internalOpen then
        FinishRemote("panel_closed")
    end
end)

concommand.Add("wszc_treat_player", function()
    WSZC.OpenRemotePatient()
end)
