-- ZCity <-> Casualties: Unknown remote inspection/treatment (server part)
--
-- The native C:U panel and net protocol are self-only.  This module adds a
-- namespaced operator -> patient protocol without changing those native self
-- receivers.  Native shrapnel/dislocation/AED sessions still belong to the
-- patient; only their minigame traffic is redirected to the operator.  An
-- operator inventory slot is borrowed for the synchronous native call and the
-- patient's slot is restored immediately afterwards.  Bandage/syringe use the
-- existing WSZC operator -> target external-minigame implementation.

WSZC = WSZC or {}
if not SERVER then return end
if WSZC._RemoteMedicalServerLoaded then return end
WSZC._RemoteMedicalServerLoaded = true

local RANGE = 256
local STATE_INTERVAL = 0.35
local MAX_PAYLOAD = 16

local NET_STRINGS = {
    "WSZC_RemoteMedicalOpen",
    "WSZC_RemoteMedicalClose",
    "WSZC_RemoteMedicalState",
    "WSZC_RemoteMedicalRestoreSelf",
    "WSZC_RemoteMedicalAction",
}
if util and util.AddNetworkString then
    for _, name in ipairs(NET_STRINGS) do util.AddNetworkString(name) end
end

WSZC.RemoteMedicalSessions = WSZC.RemoteMedicalSessions or {}
WSZC.RemoteNativeSessions = WSZC.RemoteNativeSessions or {}
local inspections = WSZC.RemoteMedicalSessions
local nativeSessions = WSZC.RemoteNativeSessions

local NATIVE_KIND = {
    WoundSystem_ShrapnelStart = "Shrapnel", WoundSystem_ShrapnelInput = "Shrapnel", WoundSystem_ShrapnelClose = "Shrapnel",
    WoundSystem_DislocationStart = "Dislocation", WoundSystem_DislocationInput = "Dislocation", WoundSystem_DislocationClose = "Dislocation",
    WoundSystem_AEDStart = "Aed", WoundSystem_AEDInput = "Aed", WoundSystem_AEDClose = "Aed",
}
local START_ACTION = {
    WoundSystem_ShrapnelStart = true, WoundSystem_DislocationStart = true, WoundSystem_AEDStart = true,
}
local CLOSE_ACTION = {
    WoundSystem_ShrapnelClose = true, WoundSystem_DislocationClose = true, WoundSystem_AEDClose = true,
}
local REDIRECT_MESSAGES = {
    WoundSystem_ShrapnelOpen = true, WoundSystem_ShrapnelState = true, WoundSystem_ShrapnelClose = true,
    WoundSystem_DislocationOpen = true, WoundSystem_DislocationState = true,
    WoundSystem_DislocationClose = true, WoundSystem_DislocationDebug = true,
    WoundSystem_AEDOpen = true, WoundSystem_AEDState = true, WoundSystem_AEDClose = true,
    WoundSystem_BandageOpen = true, WoundSystem_BandageClose = true,
    WoundSystem_SyringeOpen = true, WoundSystem_SyringeState = true, WoundSystem_SyringeClose = true,
    WoundSystem_MinigameAck = true, WoundSystem_MinigameSound_Client = true,
}

local function H()
    return WSZC.H or (WoundSystem and WoundSystem.Health) or nil
end

local function Warn(msg)
    if WSZC.Warn then WSZC.Warn("[remote-medical] " .. tostring(msg)) end
end

local function Debug(fmt, ...)
    if WSZC.Debug then WSZC.Debug("[remote-medical] " .. fmt, ...) end
end

local function HealthReady()
    local h = H()
    if WSZC.Supports and not WSZC.Supports("remote") then return false end
    return WSZC.Ready == true and type(h) == "table"
        and type(h.GetLimbs) == "function" and type(h.GetBody) == "function"
end

local function PatientEntity(ply)
    if not IsValid(ply) then return nil end
    if IsValid(ply.FakeRagdoll) then return ply.FakeRagdoll end
    if ply.GetNWEntity then
        for _, key in ipairs({ "FakeRagdoll", "WoundSystemUnconsciousRagdoll" }) do
            local ok, ragdoll = pcall(ply.GetNWEntity, ply, key, NULL)
            if ok and IsValid(ragdoll) then return ragdoll end
        end
    end
    return ply
end

local function Position(ply)
    local subject = PatientEntity(ply)
    if not IsValid(subject) then return ply:GetPos() end
    if subject.WorldSpaceCenter then
        local ok, pos = pcall(subject.WorldSpaceCenter, subject)
        if ok and pos then return pos end
    end
    return subject:GetPos()
end

local function ValidPair(operator, target)
    if not (IsValid(operator) and IsValid(target)) then return false end
    if operator == target or not operator:IsPlayer() or not target:IsPlayer() then return false end
    if not operator:Alive() or not target:Alive() then return false end
    -- Trace to the actual patient body, including ZCity's fake ragdoll.  Do
    -- not ignore walls, doors or other props; ignore only the two participants
    -- and their own bodies so the patient itself does not obstruct the trace.
    local ok, visible = pcall(function()
        local from = operator.EyePos and operator:EyePos() or operator:GetPos()
        local to = Position(target)
        if from:Distance(to) > RANGE then return false end
        if not (util and util.TraceLine) then return false end
        local filter = { operator, target }
        local operatorBody, targetBody = PatientEntity(operator), PatientEntity(target)
        if IsValid(operatorBody) then filter[#filter + 1] = operatorBody end
        if IsValid(targetBody) then filter[#filter + 1] = targetBody end
        local trace = util.TraceLine({ start = from, endpos = to, filter = filter, mask = MASK_SOLID })
        return type(trace) == "table" and not trace.Hit and not trace.StartSolid
    end)
    return ok and visible == true
end

local function NativeSession(target, kind)
    local sessions = WSZC.CUSessions
    return sessions and sessions[kind] and sessions[kind][target] or nil
end

local function MetaFor(target, kind)
    local byKind = nativeSessions[target]
    return byKind and byKind[kind] or nil
end

local function OperatorBusy(operator)
    if WSZC.MinigameSessions and WSZC.MinigameSessions[operator] then return true end
    for target, byKind in pairs(nativeSessions) do
        for kind, meta in pairs(byKind) do
            if meta.operator == operator and NativeSession(target, kind) then return true end
        end
    end
    return false
end

local function SetMeta(target, kind, meta)
    nativeSessions[target] = nativeSessions[target] or {}
    nativeSessions[target][kind] = meta
    if not meta then
        if next(nativeSessions[target]) == nil then nativeSessions[target] = nil end
    end
end

-- Redirect only minigame/inventory traffic produced inside a remote native
-- call.  Limb/cardio updates still go to the real patient; the operator gets
-- a separate authoritative state snapshot.
local activeNet
local currentNetMessage
local originalStart, originalSend
local nativeReceiverOriginals, nativeReceiverGuards = {}, {}
-- Garry's Mod stores net.Receive handlers under lowercase keys.
local function ReceiverKey(name)
    if not net.Receivers then return string.lower(name) end
    local lower = string.lower(name)
    return net.Receivers[lower] ~= nil and lower or name
end
WSZC.RemoteNativeReceiverGuards = nativeReceiverGuards
function WSZC.RemoteNativeOperator(target)
    return activeNet and activeNet.target == target and activeNet.operator or nil
end
local function InstallNativeReceiverGuards()
    if not net.Receivers then return end
    for action, kind in pairs(NATIVE_KIND) do
        local key = ReceiverKey(action)
        local current = net.Receivers[key]
        if type(current) == "function" and current ~= nativeReceiverGuards[action] then
            nativeReceiverOriginals[action] = current
            nativeReceiverGuards[action] = function(len, ply)
                if not activeNet then
                    local meta = MetaFor(ply, kind)
                    if meta and NativeSession(ply, kind) then
                        return -- this patient's session is owned by the remote operator
                    end
                end
                return nativeReceiverOriginals[action](len, ply)
            end
            net.Receivers[key] = nativeReceiverGuards[action]
        end
    end
end

local function InstallNetRedirect()
    InstallNativeReceiverGuards()
    if WSZC._RemoteMedicalNetPatched then return end
    if type(net) ~= "table" or type(net.Start) ~= "function" or type(net.Send) ~= "function" then return end
    WSZC._RemoteMedicalNetPatched = true
    originalStart, originalSend = net.Start, net.Send
    net.Start = function(name, ...)
        currentNetMessage = name
        local result = originalStart(name, ...)
        if activeNet then activeNet.message = name end
        return result
    end
    net.Send = function(recipient, ...)
        local message = activeNet and activeNet.message or currentNetMessage
        if activeNet and recipient == activeNet.target then
            -- A borrowed slot is transient; never serialize that mixed view.
            -- Both real inventories are synced after native code returns.
            if message == "WoundSystem_SyncInventory" then return end
            if REDIRECT_MESSAGES[message] then
                return originalSend(activeNet.operator, ...)
            end
        elseif not activeNet and REDIRECT_MESSAGES[message] then
            -- Native timeout/state callbacks can run after the invoking call.
            -- Route those packets through the same patient-session ownership.
            local kind = message:match("^WoundSystem_(Shrapnel)")
                or message:match("^WoundSystem_(Dislocation)")
                or (message:match("^WoundSystem_AED") and "Aed" or nil)
            local byKind = nativeSessions[recipient]
            local meta = kind and byKind and byKind[kind] or nil
            if meta and IsValid(meta.operator)
                and inspections[meta.operator] and inspections[meta.operator].target == recipient then
                return originalSend(meta.operator, ...)
            end
        end
        return originalSend(recipient, ...)
    end
end

local READERS = { "ReadString", "ReadUInt", "ReadFloat", "ReadBool", "ReadInt", "ReadEntity" }
local function ReplayNativeCall(receiver, payload, callback)
    local saved = {}
    for _, key in ipairs(READERS) do saved[key] = net[key] end
    local savedBytesLeft = net.BytesLeft
    local index, total = 0, #payload
    local function Read()
        index = index + 1
        return payload[index]
    end
    for _, key in ipairs(READERS) do net[key] = Read end
    net.BytesLeft = function()
        local left = math.max(total - index, 0)
        return left, left * 32
    end
    local results = { xpcall(callback, debug and debug.traceback or tostring) }
    for _, key in ipairs(READERS) do net[key] = saved[key] end
    net.BytesLeft = savedBytesLeft
    if not results[1] then
        Warn("native call failed: " .. tostring(results[2]))
        return false
    end
    return true, unpack(results, 2)
end

local function EmptySlot()
    return { type = "empty", toolName = nil, durability = 0 }
end

local function SyncInventories(operator, target)
    local h = H()
    if not (h and h.SyncInventoryToClient) then return end
    if IsValid(operator) then pcall(h.SyncInventoryToClient, operator) end
    if IsValid(target) then pcall(h.SyncInventoryToClient, target) end
end

-- Run one native function with the operator's real slot temporarily visible in
-- the patient's inventory.  Native consume/apply code therefore mutates the
-- operator's slot object, never the patient's original slot.
local CloseNativeMeta
local function WithNativeContext(operator, target, slotIdx, callback, wrapAedTimers)
    InstallNetRedirect()
    local previousNet = activeNet
    activeNet = { operator = operator, target = target, message = nil }
    local h = H()
    local targetInventory, originalSlot, operatorInventory, operatorSlot
    if slotIdx and slotIdx > 0 and h and h.GetInventory then
        local okInv, targetInv, operatorInv = pcall(function()
            return h.GetInventory(target), h.GetInventory(operator)
        end)
        if okInv and type(targetInv) == "table" and type(operatorInv) == "table" then
            operatorInventory, operatorSlot = operatorInv, operatorInv[slotIdx]
            if type(operatorSlot) ~= "table" or operatorSlot.type ~= "tool" then
                activeNet = previousNet
                return false
            end
            targetInventory = targetInv
            originalSlot = targetInventory[slotIdx]
            targetInventory[slotIdx] = operatorSlot
        else
            activeNet = previousNet
            return false
        end
    end

    -- AED charge/shock callbacks run after this function returns.  Re-enter
    -- the same operator/target/slot context when those timers fire.  Other
    -- native item/session timers must retain their original semantics.
    local originalSimple = timer.Simple
    if wrapAedTimers then
        timer.Simple = function(delay, fn, ...)
            local args = { ... }
            return originalSimple(delay, function()
                local meta = MetaFor(target, "Aed")
                if not meta or meta.operator ~= operator or not ValidPair(operator, target) then return end
                local ok = WithNativeContext(operator, target, meta.slotIdx, function()
                    return fn(unpack(args))
                end, true)
                if not ok and CloseNativeMeta then
                    CloseNativeMeta(target, "Aed", "tool_changed")
                end
            end)
        end
    end

    local ok, err = xpcall(callback, debug and debug.traceback or tostring)
    timer.Simple = originalSimple
    if operatorInventory and operatorInventory[slotIdx] == operatorSlot
        and type(operatorSlot) == "table" and operatorSlot.type == "tool"
        and (tonumber(operatorSlot.durability) or 0) <= 0.001 then
        local remove = not (WoundSystem.Items and WoundSystem.Items.ShouldRemoveOnDepleted)
            or WoundSystem.Items.ShouldRemoveOnDepleted(operatorSlot.toolName)
        if remove then operatorInventory[slotIdx] = EmptySlot() end
    end
    if targetInventory then targetInventory[slotIdx] = originalSlot or EmptySlot() end
    activeNet = previousNet
    if slotIdx and slotIdx > 0 then SyncInventories(operator, target) end
    if not ok then
        Warn("native context failed: " .. tostring(err))
        return false
    end
    return true
end

local function InvokeNative(operator, target, action, payload, slotIdx, callback)
    local receiver = net.Receivers and net.Receivers[ReceiverKey(action)]
    if type(receiver) ~= "function" and not callback then return false end
    return WithNativeContext(operator, target, slotIdx, function()
        if callback then return callback() end
        return ReplayNativeCall(receiver, payload or {}, function()
            return receiver(0, target)
        end)
    end, NATIVE_KIND[action] == "Aed")
end

local function ConsumeSlot(operator, slotIdx, expectedItem, cost, dryRun)
    local h = H()
    local inventory = h and h.GetInventory and h.GetInventory(operator)
    local slot = type(inventory) == "table" and inventory[slotIdx] or nil
    if type(slot) ~= "table" or slot.type ~= "tool" then return false end
    local normalize = WSZC.NormalizeItemId or function(value) return string.upper(tostring(value or "")) end
    if expectedItem and normalize(slot.toolName) ~= normalize(expectedItem) then return false end
    cost = tonumber(cost) or 0
    if (tonumber(slot.durability) or 0) + 0.0001 < cost then return false end
    if dryRun then return true end
    slot.durability = math.max((tonumber(slot.durability) or 0) - cost, 0)
    local remove = not (WoundSystem.Items and WoundSystem.Items.ShouldRemoveOnDepleted)
        or WoundSystem.Items.ShouldRemoveOnDepleted(slot.toolName)
    if remove and slot.durability <= 0.001 then inventory[slotIdx] = EmptySlot() end
    if h.SyncInventoryToClient then pcall(h.SyncInventoryToClient, operator) end
    return true
end

-- Remote sessions use the connector protocol, even when an external C:U
-- exposes its own self-only API. Stop the same implementation we started.
local function StopRemoteExternal(operator, reason)
    if WSZC.MinigameSessions and WSZC.MinigameSessions[operator] and WSZC.StopMinigame then
        return WSZC.StopMinigame(operator, reason)
    end
    local h = H()
    if h and h.StopExternalMinigame then return h.StopExternalMinigame(operator, reason) end
end

local function StartExternal(operator, target, kind, payload)
    local h = H()
    if OperatorBusy(operator) then return false end
    local limbId, slotIdx = payload[1], tonumber(payload[2]) or 0
    if type(limbId) ~= "string" or limbId == "" or slotIdx <= 0 then return false end
    local inventory = h.GetInventory and h.GetInventory(operator)
    local slot = type(inventory) == "table" and inventory[slotIdx] or nil
    if type(slot) ~= "table" or slot.type ~= "tool" then return false end
    local itemId = WSZC.NormalizeItemId and WSZC.NormalizeItemId(slot.toolName)
        or string.upper(tostring(slot.toolName or ""))
    local item = WoundSystem.Items and WoundSystem.Items.Get and WoundSystem.Items.Get(itemId)
    if not item or not item.use or item.use.minigame ~= kind then return false end
    local maxDur = WoundSystem.Items.GetMax and WoundSystem.Items.GetMax(itemId) or item.max or 100
    local durability = tonumber(slot.durability) or 0
    if durability <= 0 then return false end
    local amount = math.Clamp(durability, 0, maxDur)

    -- These locals deliberately are closure upvalues: StartMinigame validates
    -- the same spec/target/maxDur/live/oneDose contract as ZCity's bridge.
    local spec = { item = itemId, kind = "item", mg = { kind = kind } }
    local idx = slotIdx
    local live, oneDose = true, false
    local function onProgress(_, session, cost)
        local _spec, _idx, _maxDur = spec, idx, maxDur
        local _live, _oneDose, _target = live, oneDose, target
        if not ConsumeSlot(operator, idx, itemId, cost, true) then
            StopRemoteExternal(operator, "item_changed")
            return
        end
        -- The connector implementation mirrors the treatment into organism;
        -- an external native API can otherwise mutate only the C:U shadow.
        local apply = WSZC.OrganismAuthority and WSZC.OrganismAuthority()
            and WSZC.ApplyItemToBodyImpl or h.ApplyItemToBody
        if type(apply) ~= "function" then
            StopRemoteExternal(operator, "apply_unavailable")
            return
        end
        local ok, applied = pcall(apply, target, itemId, limbId, cost)
        if not ok or applied == false then
            StopRemoteExternal(operator, "apply_failed")
            return
        end
        -- The dry run above and this consume are synchronous: no free dose and
        -- no charge for a rejected treatment.
        ConsumeSlot(operator, idx, itemId, cost)
    end
    local function onClose()
        local _spec, _idx, _maxDur = spec, idx, maxDur
        local _live, _oneDose, _target = live, oneDose, target
        -- Every live step above is already applied and consumed.  There is no
        -- deferred second dose on close.
    end
    local start = WSZC.StartExternalMinigameImpl or h.StartExternalMinigame
    if type(start) ~= "function" then return false end
    local started = start(operator, {
        kind = kind, itemId = itemId, limbId = limbId, amount = amount,
        target = target, spec = spec, idx = idx, maxDur = maxDur,
        live = live, oneDose = oneDose,
        onProgress = onProgress, onClose = onClose,
    })
    if started and WSZC.MinigameSessions and WSZC.MinigameSessions[operator] then
        WSZC.MinigameSessions[operator].remote = true
    end
    return started == true
end

local function TargetDisplayName(target)
    if not IsValid(target) then return "player" end
    if type(target.GetPlayerName) == "function" then
        local ok, rpName = pcall(target.GetPlayerName, target)
        if ok and type(rpName) == "string" and rpName ~= "" then return rpName end
    end
    if type(target.Nick) == "function" then
        local ok, nick = pcall(target.Nick, target)
        if ok and type(nick) == "string" and nick ~= "" then return nick end
    end
    return "player"
end

local function SendState(operator, target, message)
    if not (IsValid(operator) and IsValid(target) and HealthReady()) then return end
    if WSZC.SyncPatientShadowNow then
        pcall(WSZC.SyncPatientShadowNow, target, true)
    end
    local h = H()
    net.Start(message or "WSZC_RemoteMedicalState")
        net.WriteEntity(target)
        net.WriteTable(h.GetLimbs(target) or {})
        net.WriteTable(h.GetBody(target) or {})
        net.WriteString(TargetDisplayName(target))
        net.WriteFloat(target.GetNWFloat and target:GetNWFloat("BloodAmount", 100) or 100)
        net.WriteFloat(target.GetNWFloat and target:GetNWFloat("WoundSystem_Happiness", 0) or 0)
    net.Send(operator)
end

local CloseRemote
CloseNativeMeta = function(target, kind, reason)
    local meta = MetaFor(target, kind)
    if not meta then return end
    local session = NativeSession(target, kind)
    SetMeta(target, kind, nil)
    if not IsValid(target) then return end
    reason = reason or "remote_closed"
    local closeName = "WoundSystem_" .. (kind == "Aed" and "AED" or kind) .. "Close"
    local receiver = net.Receivers and net.Receivers[ReceiverKey(closeName)]
    local closeSource = nativeReceiverOriginals[closeName] or receiver
    local close = closeSource and WSZC.Upvalue and WSZC.Upvalue(closeSource, "Close" .. kind .. "Session")
    if not close and WSZC.FindUpvalue then close = WSZC.FindUpvalue("Close" .. kind .. "Session") end
    local operatorValid = IsValid(meta.operator)
    if type(close) == "function" then
        if operatorValid then
            -- Closing never needs a tool.  In particular, a moved/depleted AED
            -- slot must not make the patient's native session unclosable.
            WithNativeContext(meta.operator, target, 0, function()
                return close(target, reason)
            end, kind == "Aed")
        else
            local ok, err = xpcall(function() close(target, reason) end,
                debug and debug.traceback or tostring)
            if not ok then Warn("disconnect close failed: " .. tostring(err)) end
        end
    elseif type(receiver) == "function" and session then
        local payload = { session.id or 0, reason }
        if operatorValid then
            InvokeNative(meta.operator, target, closeName, payload, 0)
        else
            ReplayNativeCall(receiver, payload, function() receiver(0, target) end)
        end
    end
    -- A missing/changed upvalue or a disconnect must not leave a stale native
    -- session that blocks the patient from treating themselves afterwards.
    if session and NativeSession(target, kind) == session and WSZC.CUSessions
        and WSZC.CUSessions[kind] then
        WSZC.CUSessions[kind][target] = nil
    end
end

CloseRemote = function(operator, reason)
    local session = inspections[operator]
    if not session then return end
    local target = session.target
    inspections[operator] = nil
    for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed" }) do
        local meta = MetaFor(target, kind)
        if meta and meta.operator == operator then CloseNativeMeta(target, kind, reason) end
    end
    pcall(StopRemoteExternal, operator, reason or "remote_closed")
    if IsValid(operator) then
        net.Start("WSZC_RemoteMedicalClose")
            net.WriteEntity(target)
            net.WriteString(reason or "closed")
        net.Send(operator)
        SendState(operator, operator, "WSZC_RemoteMedicalRestoreSelf")
    end
end
WSZC.CloseRemoteMedical = CloseRemote

-- A patient's explicit reset invalidates every treatment targeting them, not
-- just sessions keyed by that patient. Keep inspections open so they receive
-- the freshly reset snapshot, while closing operator-owned overlays/sessions.
function WSZC.CancelRemotePatientTreatment(target, reason)
    if not IsValid(target) then return end
    reason = reason or "zcity_compat_reset"
    for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed" }) do
        if MetaFor(target, kind) then CloseNativeMeta(target, kind, reason) end
    end
    for operator, session in pairs(WSZC.MinigameSessions or {}) do
        if operator ~= target and session.target == target and WSZC.StopMinigame then
            pcall(WSZC.StopMinigame, operator, reason)
        end
    end
end

local EXPECTED = {
    WoundSystem_UseMedicalItem = { "number", "string", "string" },
    WoundSystem_RemoveLimbStatus = { "string", "string" },
    WoundSystem_ShrapnelStart = { "string", "number" }, WoundSystem_ShrapnelClose = { "number", "string" },
    WoundSystem_DislocationStart = { "string", "number" }, WoundSystem_DislocationClose = { "number", "string" },
    WoundSystem_AEDStart = { "string", "number" }, WoundSystem_AEDClose = { "number", "string" },
    WoundSystem_BandageStart = { "string", "number" }, WoundSystem_BandageClose = { "number", "string" },
    WoundSystem_SyringeStart = { "string", "number" }, WoundSystem_SyringeClose = { "number", "string" },
}
local INPUT_TYPES = {
    WoundSystem_ShrapnelInput = { "number", "number", "number", "number", "boolean", "boolean", "boolean", "number", "number", "number" },
    WoundSystem_DislocationInput = { "number", "number", "number", "number", "number", "boolean", "boolean", "number", "number", "number", "number", "number", "number", "number" },
    WoundSystem_AEDInput = { "number", "number", "number" },
    WoundSystem_BandageInput = { "number", "number", "number" },
    WoundSystem_SyringeInput = { "number", "number", "boolean", "number" },
}

local function ValidPayload(action, payload)
    local expected = EXPECTED[action] or INPUT_TYPES[action]
    local count = type(payload) == "table" and (payload.n or #payload) or 0
    if not expected or count > #expected or count > MAX_PAYLOAD then return false end
    local required = EXPECTED[action] and #expected or math.max(#expected - 1, 1)
    if count < required then return false end
    for i = 1, count do
        local value = payload[i]
        local kind = type(value)
        if kind ~= expected[i] then return false end
        if kind == "number" then
            if value ~= value or value == math.huge or value == -math.huge or math.abs(value) > 1000000 then return false end
        elseif kind == "string" and #value > 128 then return false end
    end
    return true
end

net.Receive("WSZC_RemoteMedicalOpen", function(_, operator)
    if not HealthReady() then return end
    local target = net.ReadEntity()
    if not ValidPair(operator, target) then return end
    if inspections[operator] and inspections[operator].target == target then
        SendState(operator, target)
        return
    end
    CloseRemote(operator, "replaced")
    inspections[operator] = { target = target, nextState = 0 }
    SendState(operator, target)
    Debug("open operator=%s patient=%s", tostring(operator), tostring(target))
end)

net.Receive("WSZC_RemoteMedicalClose", function(_, operator)
    CloseRemote(operator, "client_close")
end)

net.Receive("WSZC_RemoteMedicalAction", function(_, operator)
    if not HealthReady() then return end
    local target = net.ReadEntity()
    local action = net.ReadString()
    local count = net.ReadUInt(8)
    if count > MAX_PAYLOAD then return end
    local payload = { n = count }
    for i = 1, count do payload[i] = net.ReadType() end
    if not ValidPayload(action, payload) then return end
    local inspection = inspections[operator]
    if not inspection or inspection.target ~= target or not ValidPair(operator, target) then return end

    if action == "WoundSystem_BandageStart" or action == "WoundSystem_SyringeStart" then
        StartExternal(operator, target, action == "WoundSystem_BandageStart" and "bandage" or "syringe", payload)
        return
    elseif action == "WoundSystem_BandageClose" or action == "WoundSystem_SyringeClose" then
        StopRemoteExternal(operator, payload[2] or "client_close")
        return
    elseif action == "WoundSystem_BandageInput" or action == "WoundSystem_SyringeInput" then
        return -- live sessions use WSZC_* input after StartExternal answers
    end

    local kind = NATIVE_KIND[action]
    if kind then
        local meta = MetaFor(target, kind)
        if START_ACTION[action] then
            if OperatorBusy(operator) then return end
            if NativeSession(target, kind) and (not meta or meta.operator ~= operator) then return end
            local slotIdx = math.floor(tonumber(payload[2]) or 0)
            if slotIdx < 0 or slotIdx > 5 then return end
            SetMeta(target, kind, { operator = operator, slotIdx = slotIdx })
            InvokeNative(operator, target, action, payload, slotIdx)
            if not NativeSession(target, kind) then SetMeta(target, kind, nil) end
            return
        end
        if not meta or meta.operator ~= operator then return end
        local closing = CLOSE_ACTION[action] == true
        local ok = InvokeNative(operator, target, action, payload, closing and 0 or meta.slotIdx)
        if not ok and not closing and MetaFor(target, kind) then
            CloseNativeMeta(target, kind, "tool_changed")
        elseif closing and NativeSession(target, kind) and MetaFor(target, kind) then
            -- A wrong session id or native error must not orphan the session.
            CloseNativeMeta(target, kind, "close_failed")
        end
        if not NativeSession(target, kind) then SetMeta(target, kind, nil) end
        return
    end

    if action == "WoundSystem_UseMedicalItem" then
        local slotIdx = math.floor(tonumber(payload[1]) or 0)
        if slotIdx <= 0 or slotIdx > 5 then return end
        local item = WoundSystem.Items.Get and WoundSystem.Items.Get(payload[2])
        if item and item.use and item.use.minigame then return end
        local before = WSZC.SnapshotMedical and WSZC.SnapshotMedical(target, payload[3]) or nil
        InvokeNative(operator, target, action, payload, slotIdx)
        if before and WSZC.ApplyMedicalDelta then
            pcall(WSZC.ApplyMedicalDelta, target, payload[3], before)
        end
    elseif action == "WoundSystem_RemoveLimbStatus" then
        -- Native removal still runs as the PATIENT, so it clears exactly the
        -- requested limb.  Only a returned tourniquet changes recipient: the
        -- medic who removed it gets weapon_tourniquet in their ZCity selector.
        local previousRecipient = WSZC.RemoteMedicalReturnRecipient
        WSZC.RemoteMedicalReturnRecipient = operator
        InvokeNative(operator, target, action, payload, 0)
        WSZC.RemoteMedicalReturnRecipient = previousRecipient
        SendState(operator, target)
    end
end)

function WSZC.NotifyRemotePatientUpdated(target, coalesce)
    if not IsValid(target) then return end
    local now = CurTime and CurTime() or 0
    for operator, session in pairs(inspections) do
        if session.target == target and ValidPair(operator, target) then
            if coalesce and now < (session.nextFastState or 0) then
                -- Let the watchdog flush the final coalesced tick shortly.
                session.nextState = math.min(session.nextState or now, now + 0.08)
            else
                session.nextFastState = now + 0.08
                session.nextState = now + STATE_INTERVAL
                SendState(operator, target)
            end
        end
    end
end

-- External C:U takes precedence over the embedded copy and may still expose
-- its playtest spawner to everyone. Guard the registered receiver as well;
-- the embedded receiver has its own independent check at registration time.
local spawnGuard, spawnOriginal
function WSZC.InstallMedicalSpawnerGuard()
    if not (net and net.Receivers) then return end
    local key = net.Receivers.woundsystem_spawnmedicalitem and "woundsystem_spawnmedicalitem"
        or "WoundSystem_SpawnMedicalItem"
    local current = net.Receivers[key]
    if type(current) ~= "function" or current == spawnGuard then return end
    spawnOriginal = current
    spawnGuard = function(len, ply)
        if not IsValid(ply) or not ply.IsAdmin or not ply:IsAdmin() then return end
        return spawnOriginal(len, ply)
    end
    net.Receivers[key] = spawnGuard
end
WSZC.InstallMedicalSpawnerGuard()

timer.Create("WSZC_RemoteMedicalWatchdog", 0.25, 0, function()
    WSZC.InstallMedicalSpawnerGuard()
    local now = CurTime()
    for operator, session in pairs(inspections) do
        if not ValidPair(operator, session.target) then
            CloseRemote(operator, "patient_unavailable")
        elseif now >= (session.nextState or 0) then
            session.nextState = now + STATE_INTERVAL
            SendState(operator, session.target)
        end
    end
    for target, byKind in pairs(nativeSessions) do
        for kind, meta in pairs(byKind) do
            if not NativeSession(target, kind) then
                SetMeta(target, kind, nil)
            elseif not inspections[meta.operator] or inspections[meta.operator].target ~= target
                or not ValidPair(meta.operator, target) then
                CloseNativeMeta(target, kind, "operator_unavailable")
            end
        end
    end
end)

hook.Add("PlayerDisconnected", "WSZC_RemoteMedicalDisconnect", function(ply)
    CloseRemote(ply, "disconnect")
    for target, byKind in pairs(nativeSessions) do
        for kind, meta in pairs(byKind) do
            if meta.operator == ply or target == ply then CloseNativeMeta(target, kind, "disconnect") end
        end
    end
end)

WSZC.RemoteMedicalSessions = inspections
WSZC.RemoteMedicalValidPair = ValidPair
WSZC.RemoteMedicalValidPayload = ValidPayload
WSZC.RemoteMedicalConsumeSlot = ConsumeSlot
WSZC.RemoteMedicalInvokeNative = InvokeNative
