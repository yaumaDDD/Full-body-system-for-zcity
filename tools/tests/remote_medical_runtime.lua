-- Offline behavioral harness for cl/sv_zcity_woundsystem_compat_remote.lua.
-- Loaded by test_wszc_regression.py with REMOTE_SOURCE and MODE supplied.
unpack = unpack or table.unpack -- GMod provides this globally; Lua 5.4 does not.
local tests = {}
local function Test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function Assert(value, message)
    if not value then error(message or "assertion failed", 2) end
end
local function Equal(actual, expected, message)
    Assert(actual == expected, (message or "not equal") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

if MODE == "server" then
    SERVER, CLIENT = true, false
    local now = 100
    CurTime = function() return now end
    math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    NULL = {}
    util = { AddNetworkString = function() end }
    hook = { Add = function() end }
    IsValid = function(v)
        return v ~= nil and v ~= false and (type(v) ~= "table" or v.valid ~= false)
    end

    local simpleTimers, namedTimers = {}, {}
    timer = {
        Simple = function(delay, fn, ...)
            simpleTimers[#simpleTimers + 1] = { fn = fn, args = { ... } }
            return #simpleTimers
        end,
        Create = function(name, _, _, fn) namedTimers[name] = fn end,
        Remove = function(name) namedTimers[name] = nil end,
    }
    local function RunSimple()
        local pending = simpleTimers
        simpleTimers = {}
        for _, entry in ipairs(pending) do entry.fn(unpack(entry.args)) end
    end

    local function Vec(x)
        return { x = x, Distance = function(self, other) return math.abs(self.x - other.x) end }
    end
    local function Player(name, x)
        local p = { name = name, x = x, alive = true, valid = true }
        function p:IsPlayer() return true end
        function p:Alive() return self.alive end
        function p:GetPos() return Vec(self.x) end
        function p:EyePos() return Vec(self.x) end
        function p:WorldSpaceCenter() return Vec(self.x) end
        function p:Nick() return self.name end
        function p:GetNWFloat(key, fallback) return self[key] or fallback end
        return p
    end
    op, patient, other = Player("medic", 0), Player("patient", 20), Player("other", 30)

    local incoming, incomingIndex = {}, 0
    local function ReadNext()
        incomingIndex = incomingIndex + 1
        return incoming[incomingIndex]
    end
    local sent, currentMessage = {}, nil
    net = { Receivers = {} }
    net.Receive = function(name, fn) net.Receivers[name] = fn end
    net.Start = function(name) currentMessage = name end
    net.Send = function(recipient)
        sent[#sent + 1] = { message = currentMessage, recipient = recipient }
    end
    net.WriteEntity = function() end
    net.WriteTable = function() end
    net.WriteString = function() end
    net.WriteFloat = function() end
    net.WriteUInt = function() end
    net.WriteBool = function() end
    for _, key in ipairs({ "ReadEntity", "ReadString", "ReadUInt", "ReadFloat", "ReadBool", "ReadInt", "ReadType" }) do
        net[key] = ReadNext
    end
    net.BytesLeft = function() return 0, 0 end

    local function Open(target, operator)
        incoming, incomingIndex = { target }, 0
        net.Receivers.WSZC_RemoteMedicalOpen(0, operator or op)
    end
    local function Action(target, action, values, operator)
        incoming, incomingIndex = { target, action, #values }, 0
        for i = 1, #values do incoming[3 + i] = values[i] end
        net.Receivers.WSZC_RemoteMedicalAction(0, operator or op)
    end
    local function RawAction(target, action, count, values, operator)
        incoming, incomingIndex = { target, action, count }, 0
        for i = 1, count do incoming[3 + i] = values[i] end
        net.Receivers.WSZC_RemoteMedicalAction(0, operator or op)
    end
    local function LastSend()
        return sent[#sent]
    end
    local function CountSends(message)
        local result = 0
        for _, packet in ipairs(sent) do if packet.message == message then result = result + 1 end end
        return result
    end

    local applied, statuses, inputs, externalApplied, stopped = {}, {}, {}, {}, {}
    local externalStarts, aedCallbacks = 0, 0
    local aedSawBorrowed = false
    local inventories, limbs, bodies = {}, {}, {}
    local function Tool(name, durability) return { type = "tool", toolName = name, durability = durability } end
    local function Empty() return { type = "empty", durability = 0 } end

    H = {
        GetInventory = function(p) return inventories[p] end,
        GetLimbs = function(p) return limbs[p] end,
        GetBody = function(p) return bodies[p] end,
        SyncInventoryToClient = function(p)
            net.Start("WoundSystem_SyncInventory")
            net.WriteTable(inventories[p])
            net.Send(p)
        end,
        ApplyItemToBody = function(p, itemId, limbId, cost)
            externalApplied[#externalApplied + 1] = { p = p, item = itemId, limb = limbId, cost = cost }
            return true
        end,
        StartExternalMinigame = function(p, data)
            externalStarts = externalStarts + 1
            if WSZC.MinigameSessions[p] then return true end
            WSZC.MinigameSessions[p] = {
                target = patient, onProgress = data.onProgress, onClose = data.onClose,
                kind = data.kind, itemId = data.itemId,
            }
            return true
        end,
        StopExternalMinigame = function(p, reason)
            stopped[#stopped + 1] = { p = p, reason = reason }
            local session = WSZC.MinigameSessions[p]
            WSZC.MinigameSessions[p] = nil
            if session and session.onClose then session.onClose(p, session, reason) end
        end,
    }

    WSZC = {
        Ready = true, H = H,
        RemoteMedicalSessions = {}, RemoteNativeSessions = {}, MinigameSessions = {},
        CUSessions = { Shrapnel = {}, Dislocation = {}, Aed = {} },
        NormalizeItemId = function(v) return string.upper(tostring(v or "")) end,
        SnapshotMedical = function() return {} end,
        ApplyMedicalDelta = function() end,
        Warn = function() end,
    }
    WoundSystem = { Items = {} }
    local itemDefs = {
        MORPHINE = { use = { cost = 10 } }, ERROR = { use = { cost = 1 } },
        BANDAGE = { use = { minigame = "bandage" } },
        SYRINGE = { use = { minigame = "syringe" } },
        AED = { use = { minigame = "aed" } },
    }
    WoundSystem.Items.Get = function(id) return itemDefs[string.upper(tostring(id or ""))] end
    WoundSystem.Items.GetMax = function() return 100 end
    WoundSystem.Items.ShouldRemoveOnDepleted = function() return true end

    assert(load(REMOTE_SOURCE))()

    local closers = {}
    WSZC.Upvalue = function(_, name) return closers[name] end
    H.TryUseInventoryMedicalItem = function(p, slotIdx, itemId, limbId)
        if itemId == "ERROR" then error("intentional native failure") end
        local inventory = H.GetInventory(p)
        local slot = inventory[slotIdx]
        if not slot or slot.toolName ~= itemId then return false end
        applied[#applied + 1] = { p = p, slot = slotIdx, item = itemId, limb = limbId }
        slot.durability = math.max(0, slot.durability - 10)
        -- This deliberately mirrors C:U SetInventorySlot: only the table
        -- currently visible as p's inventory is replaced on depletion.
        if slot.durability == 0 then inventory[slotIdx] = Empty() end
        H.SyncInventoryToClient(p)
        return true
    end
    net.Receivers.WoundSystem_UseMedicalItem = function(_, p)
        local slotIdx, itemId, limbId = net.ReadUInt(8), net.ReadString(), net.ReadString()
        H.TryUseInventoryMedicalItem(p, slotIdx, itemId, limbId)
    end
    net.Receivers.WoundSystem_RemoveLimbStatus = function(_, p)
        statuses[#statuses + 1] = {
            p = p, limb = net.ReadString(), status = net.ReadString(),
            returnRecipient = WSZC.RemoteMedicalReturnRecipient,
        }
    end

    local function InstallNative(kind, networkKind)
        local startName = "WoundSystem_" .. networkKind .. "Start"
        local inputName = "WoundSystem_" .. networkKind .. "Input"
        local closeName = "WoundSystem_" .. networkKind .. "Close"
        closers["Close" .. kind .. "Session"] = function(p, reason)
            WSZC.CUSessions[kind][p] = nil
            net.Start(closeName) net.WriteString(reason or "closed") net.Send(p)
        end
        net.Receivers[startName] = function(_, p)
            local limbId, slotIdx = net.ReadString(), net.ReadUInt(3)
            WSZC.CUSessions[kind][p] = { id = 1, limbId = limbId, slotIdx = slotIdx }
            net.Start("WoundSystem_" .. networkKind .. "Open") net.WriteString(limbId) net.Send(p)
            if kind == "Aed" then
                timer.Simple(0.1, function()
                    aedCallbacks = aedCallbacks + 1
                    local slot = H.GetInventory(p)[slotIdx]
                    aedSawBorrowed = slot and slot.toolName == "AED" or false
                    if slot then slot.durability = slot.durability - 5 end
                    net.Start("WoundSystem_AEDState") net.WriteUInt(1, 24) net.Send(p)
                    H.SyncInventoryToClient(p)
                end)
            end
        end
        net.Receivers[inputName] = function(_, p)
            local count = kind == "Shrapnel" and 10 or (kind == "Dislocation" and 14 or 3)
            local values = {}
            for i = 1, count do values[i] = ReadNextThroughReplay(i) end
            inputs[#inputs + 1] = { kind = kind, p = p, values = values }
            net.Start("WoundSystem_" .. networkKind .. "State") net.Send(p)
            if kind == "Aed" then
                timer.Simple(0.1, function() aedCallbacks = aedCallbacks + 1 end)
            end
        end
        net.Receivers[closeName] = function(_, p)
            local sessionId, reason = net.ReadUInt(24), net.ReadString()
            Equal(sessionId, 1)
            closers["Close" .. kind .. "Session"](p, reason)
        end
    end
    -- Replay replaces all native readers with one value reader. Keeping this
    -- dispatch explicit makes the fixture resemble the native Read* calls.
    function ReadNextThroughReplay(which)
        if which == 1 then return net.ReadUInt(24) end
        local nativeTypes = {
            Shrapnel = { "float", "float", "float", "bool", "bool", "bool", "float", "float", "float" },
            Dislocation = { "float", "float", "float", "float", "bool", "bool", "float", "float", "float", "float", "float", "float", "uint" },
            Aed = { "uint", "uint" },
        }
        local kind = nativeTypes._current
        local kindName = kind or "Shrapnel"
        local valueType = nativeTypes[kindName] and nativeTypes[kindName][which - 1] or "float"
        if valueType == "bool" then return net.ReadBool() end
        if valueType == "uint" then return net.ReadUInt(24) end
        return net.ReadFloat()
    end
    -- Simpler native fixtures: each receiver uses its actual reader types.
    InstallNative("Shrapnel", "Shrapnel")
    InstallNative("Dislocation", "Dislocation")
    InstallNative("Aed", "AED")
    net.Receivers.WoundSystem_ShrapnelInput = function(_, p)
        if not WSZC.CUSessions.Shrapnel[p] then return end
        local values = { net.ReadUInt(24), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(),
            net.ReadBool(), net.ReadBool(), net.ReadBool(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat() }
        inputs[#inputs + 1] = { kind = "Shrapnel", p = p, values = values }
        net.Start("WoundSystem_ShrapnelState") net.Send(p)
    end
    net.Receivers.WoundSystem_DislocationInput = function(_, p)
        if not WSZC.CUSessions.Dislocation[p] then return end
        local values = { net.ReadUInt(24), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(),
            net.ReadBool(), net.ReadBool(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(), net.ReadFloat(),
            net.ReadFloat(), net.ReadFloat(), net.ReadUInt(24) }
        inputs[#inputs + 1] = { kind = "Dislocation", p = p, values = values }
        net.Start("WoundSystem_DislocationState") net.Send(p)
    end
    net.Receivers.WoundSystem_AEDInput = function(_, p)
        if not WSZC.CUSessions.Aed[p] then return end
        local values = { net.ReadUInt(24), net.ReadUInt(3), net.ReadUInt(24) }
        inputs[#inputs + 1] = { kind = "Aed", p = p, values = values }
        net.Start("WoundSystem_AEDState") net.Send(p)
        timer.Simple(0.1, function() aedCallbacks = aedCallbacks + 1 end)
    end

    local function Reset()
        if WSZC.RemoteMedicalSessions[op] then WSZC.CloseRemoteMedical(op, "test_reset") end
        if WSZC.RemoteMedicalSessions[other] then WSZC.CloseRemoteMedical(other, "test_reset") end
        for target, byKind in pairs(WSZC.RemoteNativeSessions) do
            for kind in pairs(byKind) do byKind[kind] = nil end
            WSZC.RemoteNativeSessions[target] = nil
        end
        for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed" }) do
            WSZC.CUSessions[kind] = {}
        end
        WSZC.MinigameSessions = {}
        inventories = {
            [op] = { Tool("MORPHINE", 10), Tool("AED", 10), Tool("BANDAGE", 20), Tool("SYRINGE", 20), Tool("ERROR", 10) },
            [patient] = { Tool("BANDAGE", 77), Tool("SPLINT", 66) },
            [other] = {},
        }
        limbs = { [op] = { thorax = { pain = 1 } }, [patient] = { thorax = { pain = 88 } }, [other] = {} }
        bodies = { [op] = { bloodVolume = 100 }, [patient] = { bloodVolume = 42 }, [other] = {} }
        op.x, op.alive, op.valid = 0, true, true
        patient.x, patient.alive, patient.valid = 20, true, true
        other.x, other.alive, other.valid = 30, true, true
        sent, applied, statuses, inputs, externalApplied, stopped = {}, {}, {}, {}, {}, {}
        simpleTimers, externalStarts, aedCallbacks, aedSawBorrowed = {}, 0, 0, false
        now = 100
    end

    Test("M01 open sends patient snapshot; self/dead/range are rejected", function()
        Reset(); Open(patient)
        Assert(WSZC.RemoteMedicalSessions[op] ~= nil)
        Equal(LastSend().message, "WSZC_RemoteMedicalState")
        Equal(LastSend().recipient, op)
        Reset(); Open(op); Assert(WSZC.RemoteMedicalSessions[op] == nil)
        patient.alive = false; Open(patient); Assert(WSZC.RemoteMedicalSessions[op] == nil)
        patient.alive = true; patient.x = 500; Open(patient); Assert(WSZC.RemoteMedicalSessions[op] == nil)
    end)

    Test("M02 unknown, malformed, nil-hole and wrong-session packets do nothing", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_NotMedical", {})
        Action(patient, "WoundSystem_UseMedicalItem", { 1, 2, "thorax" })
        RawAction(patient, "WoundSystem_UseMedicalItem", 3, { [1] = 1, [3] = "thorax" })
        Action(patient, "WoundSystem_UseMedicalItem", { 1, "MORPHINE", "thorax" }, other)
        Action(other, "WoundSystem_UseMedicalItem", { 1, "MORPHINE", "thorax" })
        Action(patient, "WoundSystem_UseMedicalItem", { math.huge, "MORPHINE", "thorax" })
        Equal(#applied, 0)
        Equal(inventories[op][1].durability, 10)
    end)

    Test("M03 depleted native item empties medic slot and restores patient slot", function()
        Reset(); Open(patient)
        local patientSlot = inventories[patient][1]
        Action(patient, "WoundSystem_UseMedicalItem", { 1, "MORPHINE", "thorax" })
        Equal(#applied, 1); Equal(applied[1].p, patient)
        Equal(inventories[op][1].type, "empty")
        Assert(inventories[patient][1] == patientSlot)
        Equal(inventories[patient][1].durability, 77)
        Equal(CountSends("WoundSystem_SyncInventory"), 2)
        local recipients = {}
        for _, packet in ipairs(sent) do
            if packet.message == "WoundSystem_SyncInventory" then recipients[packet.recipient] = true end
        end
        Assert(recipients[op] and recipients[patient])
    end)

    Test("M04 partial native charge mutates only the medic's real slot", function()
        Reset(); Open(patient); inventories[op][1].durability = 25
        Action(patient, "WoundSystem_UseMedicalItem", { 1, "MORPHINE", "thorax" })
        Equal(inventories[op][1].durability, 15)
        Equal(inventories[patient][1].durability, 77)
    end)

    Test("M05 status removal treats patient and returns tourniquet to medic", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_RemoveLimbStatus", { "arm_R", "TOURNIQUET" })
        Equal(#statuses, 1); Equal(statuses[1].p, patient); Equal(statuses[1].status, "TOURNIQUET")
        Equal(statuses[1].returnRecipient, op)
        Equal(WSZC.RemoteMedicalReturnRecipient, nil, "recipient override must be restored")
    end)

    Test("M06 shrapnel Start/Input/Close and asynchronous state use patient session + medic UI", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_ShrapnelStart", { "hand_R", 0 })
        Assert(WSZC.CUSessions.Shrapnel[patient] ~= nil)
        Equal(LastSend().message, "WoundSystem_ShrapnelOpen"); Equal(LastSend().recipient, op)
        Action(patient, "WoundSystem_ShrapnelInput", { 1, 2, 3, 4, true, false, true, 5, 6, 7 })
        Equal(#inputs, 1); Equal(inputs[1].p, patient); Equal(inputs[1].values[10], 7)
        Equal(LastSend().recipient, op)
        net.Start("WoundSystem_ShrapnelState") net.Send(patient)
        Equal(LastSend().recipient, op, "asynchronous native packet must redirect")
        Action(patient, "WoundSystem_ShrapnelClose", { 1, "done" })
        Assert(WSZC.CUSessions.Shrapnel[patient] == nil)
        Equal(LastSend().message, "WoundSystem_ShrapnelClose"); Equal(LastSend().recipient, op)
        net.Start("WoundSystem_ShrapnelState") net.Send(patient)
        Equal(LastSend().recipient, patient, "closed sessions must not remain redirected")
    end)

    Test("M07 dislocation optional sequence payload survives replay", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_DislocationStart", { "arm_L", 0 })
        Action(patient, "WoundSystem_DislocationInput", { 1, 2, 3, 4, 5, true, false, 6, 7, 8, 9, 10, 11, 12 })
        Equal(#inputs, 1); Equal(inputs[1].kind, "Dislocation"); Equal(inputs[1].values[14], 12)
        Action(patient, "WoundSystem_DislocationClose", { 1, "done" })
        Assert(WSZC.CUSessions.Dislocation[patient] == nil)
    end)

    Test("M08 AED delayed work re-borrows medic slot and stops out of range", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_AEDStart", { "thorax", 2 })
        RunSimple()
        Equal(aedCallbacks, 1); Assert(aedSawBorrowed)
        Equal(inventories[op][2].durability, 5)
        Equal(inventories[patient][2].toolName, "SPLINT")
        Equal(LastSend().recipient, patient, "last explicit inventory sync belongs to patient")
        Action(patient, "WoundSystem_AEDInput", { 1, 1, 1 })
        patient.x = 1000; RunSimple()
        Equal(aedCallbacks, 1, "out-of-range timer must not fire")
        patient.x = 20
        Action(patient, "WoundSystem_AEDClose", { 1, "done" })
        Assert(WSZC.CUSessions.Aed[patient] == nil)
    end)

    Test("M09 native/external games cannot overlap or hijack an existing session", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_ShrapnelStart", { "hand_R", 0 })
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        Equal(externalStarts, 0)
        Action(patient, "WoundSystem_ShrapnelClose", { 1, "done" })
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        Equal(externalStarts, 1)
        Action(patient, "WoundSystem_AEDStart", { "thorax", 2 })
        Assert(WSZC.CUSessions.Aed[patient] == nil)
        Reset(); Open(patient)
        WSZC.MinigameSessions[op] = { target = op }
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        Equal(externalStarts, 0); Assert(WSZC.MinigameSessions[op].remote ~= true)
    end)

    Test("M10 external bandage/syringe apply to patient and consume medic once per progress", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        local session = WSZC.MinigameSessions[op]
        Assert(session and session.remote and session.target == patient)
        session.onProgress(op, session, 5)
        Equal(#externalApplied, 1); Equal(externalApplied[1].p, patient)
        Equal(inventories[op][3].durability, 15); Equal(inventories[patient][1].durability, 77)
        session.onClose(op, session, "done")
        Equal(#externalApplied, 1); Equal(inventories[op][3].durability, 15)
        H.StopExternalMinigame(op, "done")
        Action(patient, "WoundSystem_SyringeStart", { "thorax", 4 })
        session = WSZC.MinigameSessions[op]
        Assert(session and session.remote)
        session.onProgress(op, session, 20)
        Equal(inventories[op][4].type, "empty"); Equal(#externalApplied, 2)
    end)

    Test("M11 zero-charge external item and failed native call are atomic", function()
        Reset(); Open(patient); inventories[op][3].durability = 0
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        Equal(externalStarts, 0); Equal(#externalApplied, 0)
        local savedReadString = net.ReadString
        Action(patient, "WoundSystem_UseMedicalItem", { 5, "ERROR", "thorax" })
        Assert(net.ReadString == savedReadString, "native readers must be restored")
        Equal(inventories[op][5].durability, 10); Equal(inventories[patient][1].durability, 77)
    end)

    Test("M12 watchdog closes native and external sessions when pair becomes invalid", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_ShrapnelStart", { "hand_R", 0 })
        patient.x = 1000
        namedTimers.WSZC_RemoteMedicalWatchdog()
        Assert(WSZC.RemoteMedicalSessions[op] == nil)
        Assert(WSZC.CUSessions.Shrapnel[patient] == nil)
        Reset(); Open(patient)
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        patient.alive = false
        namedTimers.WSZC_RemoteMedicalWatchdog()
        Assert(WSZC.MinigameSessions[op] == nil)
        Assert(#stopped > 0)
    end)

    Test("M13 missing AED slot and disconnect still close the patient session", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_AEDStart", { "thorax", 2 })
        RunSimple()
        inventories[op][2] = Empty()
        Action(patient, "WoundSystem_AEDInput", { 1, 1, 1 })
        Assert(WSZC.CUSessions.Aed[patient] == nil)
        inventories[op][2] = Tool("AED", 10)
        Action(patient, "WoundSystem_AEDStart", { "thorax", 2 })
        Assert(WSZC.CUSessions.Aed[patient] ~= nil)
        op.valid = false
        namedTimers.WSZC_RemoteMedicalWatchdog()
        Assert(WSZC.CUSessions.Aed[patient] == nil)
        Assert(WSZC.RemoteMedicalSessions[op] == nil)
    end)

    Test("M14 wrong native close id cannot orphan the patient session", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_ShrapnelStart", { "hand_R", 0 })
        Action(patient, "WoundSystem_ShrapnelClose", { 999, "bad_id" })
        Assert(WSZC.CUSessions.Shrapnel[patient] == nil)
        Assert(WSZC.RemoteNativeSessions[patient] == nil)
    end)

    Test("M15 patient self-input cannot hijack an active remote native session", function()
        Reset(); Open(patient)
        Action(patient, "WoundSystem_ShrapnelStart", { "hand_R", 0 })
        incoming = { 1, 2, 3, 4, true, false, true, 5, 6, 7 }; incomingIndex = 0
        net.Receivers.WoundSystem_ShrapnelInput(0, patient)
        Equal(#inputs, 0)
        Action(patient, "WoundSystem_ShrapnelClose", { 1, "done" })
        incoming = { 1, 2, 3, 4, true, false, true, 5, 6, 7 }; incomingIndex = 0
        net.Receivers.WoundSystem_ShrapnelInput(0, patient)
        Equal(#inputs, 0, "closed native session must reject input normally")
        incoming = { "hand_R", 0 }; incomingIndex = 0
        net.Receivers.WoundSystem_ShrapnelStart(0, patient)
        Assert(WSZC.CUSessions.Shrapnel[patient] ~= nil)
        incoming = { 1, 2, 3, 4, true, false, true, 5, 6, 7 }; incomingIndex = 0
        net.Receivers.WoundSystem_ShrapnelInput(0, patient)
        Equal(#inputs, 1, "ordinary patient self-treatment must recover after close")
        incoming = { 1, "done" }; incomingIndex = 0
        net.Receivers.WoundSystem_ShrapnelClose(0, patient)
        Assert(WSZC.CUSessions.Shrapnel[patient] == nil)
    end)

    Test("M16 real main minigame accepts remote data and treats patient with medic item", function()
        Reset()
        WSZC._MinigameServerLoaded = nil
        Assert(MINIGAME_SOURCE and load(MINIGAME_SOURCE))
        assert(load(MINIGAME_SOURCE))()
        WSZC.BridgeEnabled = function() return true end
        WSZC.Bridged = function() return true end
        WSZC.OrganismAuthority = function() return true end
        WoundSystem.Health = { Constants = {} }
        limbs[patient].arm_R = { bleed = 6, pain = 0, shrapnel = 0 }
        H.GetLimbState = function(p, limbId)
            return limbs[p] and limbs[p][limbId] or nil
        end
        Assert(WSZC.InstallMinigameAPI(H))
        Open(patient)
        Action(patient, "WoundSystem_BandageStart", { "arm_R", 3 })
        local session = WSZC.MinigameSessions[op]
        Assert(session and session.remote and session.owner == op)
        Equal(session.target, patient)
        Equal(session.spec.item, "BANDAGE")
        Equal(session.nativeBandage, nil)
        incoming, incomingIndex = { session.id, 360, 1 }, 0
        net.Receivers.WSZC_BandageInput(0, op)
        Equal(#externalApplied, 1)
        Equal(externalApplied[1].p, patient)
        Equal(externalApplied[1].cost, 2)
        Equal(inventories[op][3].durability, 18)
        Equal(inventories[patient][1].durability, 77)
        Assert(WSZC.MinigameSessions[op] == session)
        patient.x = 1000
        incoming, incomingIndex = { session.id, 360, 2 }, 0
        net.Receivers.WSZC_BandageInput(0, op)
        Equal(#externalApplied, 1, "out-of-range input must not apply another dose")
        Equal(inventories[op][3].durability, 18)
        Assert(WSZC.MinigameSessions[op] == nil)
    end)
else
    CLIENT, SERVER = true, false
    local now = 100
    CurTime = function() return now end
    ScrW, ScrH = function() return 1000 end, function() return 800 end
    TEXT_ALIGN_CENTER = 1
    Color = function(...) return { ... } end
    draw = { SimpleText = function() end }
    concommand = { Add = function() end }
    ErrorNoHalt = function() end
    NULL = {}
    IsValid = function(v)
        return v ~= nil and v ~= false and (type(v) ~= "table" or v.valid ~= false)
    end
    math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    table.Copy = function(value)
        if type(value) ~= "table" then return value end
        local result = {}
        for k, v in pairs(value) do result[k] = type(v) == "table" and table.Copy(v) or v end
        return result
    end
    local function Vec(x)
        return { x = x, Distance = function(self, other) return math.abs(self.x - other.x) end }
    end
    local function Player(name, x)
        local p = { name = name, x = x, alive = true, valid = true }
        function p:IsPlayer() return true end
        function p:Alive() return self.alive end
        function p:GetPos() return Vec(self.x) end
        function p:EyePos() return Vec(self.x) end
        function p:WorldSpaceCenter() return Vec(self.x) end
        function p:Nick() return self.name end
        function p:GetEyeTrace() return { Entity = self.traceEntity } end
        function p:GetNWEntity() return NULL end
        return p
    end
    op, patient, patient2 = Player("medic", 0), Player("patient", 20), Player("patient2", 30)
    LocalPlayer = function() return op end
    local ragdoll = { valid = true, IsPlayer = function() return false end }
    hg = { radialOptions = {}, RagdollOwner = function(ent) return ent == ragdoll and patient or nil end }

    CreateClientConVar = function() return { GetBool = function() return true end } end
    GetConVar = function() return { GetBool = function() return true end } end
    GetGlobalBool = function() return true end
    local simpleTimers = {}
    timer = { Simple = function(_, fn) simpleTimers[#simpleTimers + 1] = fn end }
    local function RunSimple()
        local pending = simpleTimers; simpleTimers = {}
        for _, fn in ipairs(pending) do fn() end
    end
    local hooks = {}
    hook = { Add = function(event, name, fn) hooks[event .. name] = fn end }

    local outgoing, currentOutgoing = {}, nil
    local incoming, incomingIndex = {}, 0
    local function ReadNext() incomingIndex = incomingIndex + 1; return incoming[incomingIndex] end
    net = { Receivers = {} }
    net.Receive = function(name, fn) net.Receivers[name] = fn end
    net.Start = function(name) currentOutgoing = { name = name, values = {} }; outgoing[#outgoing + 1] = currentOutgoing end
    net.SendToServer = function() end
    net.Send = function() end
    for _, key in ipairs({ "WriteUInt", "WriteInt", "WriteFloat", "WriteString", "WriteBool", "WriteEntity", "WriteType" }) do
        net[key] = function(value) if currentOutgoing then currentOutgoing.values[#currentOutgoing.values + 1] = value end end
    end
    for _, key in ipairs({ "ReadEntity", "ReadTable", "ReadString", "ReadFloat" }) do net[key] = ReadNext end

    local openCalls, closeCalls = 0, 0
    local closeEmits = false
    WoundSystemHealthHUDOpen = false
    WoundSystem = {}
    WoundSystem.OpenHealthHUD = function() openCalls = openCalls + 1; WoundSystemHealthHUDOpen = true end
    WoundSystem.CloseHealthHUD = function()
        closeCalls = closeCalls + 1
        if closeEmits then
            net.Start("WoundSystem_ShrapnelClose") net.WriteUInt(1, 24) net.WriteString("done") net.SendToServer()
        end
        WoundSystemHealthHUDOpen = false
    end
    WoundSystemClientState = {
        PlayerLimbs = { thorax = { pain = 1 }, selfOnly = { kept = true } },
        Cardio = { bloodVolume = 100, consciousness = 99, skills = { STR = 10, RES = 11, INT = 12 } },
        PlayerStats = { STR = 10, RES = 11, INT = 12, consciousness = 99, custom = "self" },
    }
    net.Receivers.WoundSystem_UpdateLimb = function() WoundSystemClientState.PlayerLimbs.thorax.pain = 999 end
    net.Receivers.WoundSystem_UpdateCardio = function() WoundSystemClientState.Cardio.bloodVolume = 999 end
    WSZC = { OpenCUWoundMenu = function() WoundSystem.OpenHealthHUD() end }

    assert(load(REMOTE_SOURCE))()

    local patientLimbs = { thorax = { pain = 88 }, patientOnly = { visible = true } }
    local patientCardio = { bloodVolume = 42, consciousness = 55, skills = { STR = 3, RES = 4, INT = 5 } }
    local function SendState(target, limbsTable, cardioTable)
        incoming, incomingIndex = { target, limbsTable or patientLimbs, cardioTable or patientCardio,
            target.name, 42, 7 }, 0
        net.Receivers.WSZC_RemoteMedicalState()
    end
    local function Begin()
        Assert(WSZC.OpenRemotePatient(patient)); RunSimple(); SendState(patient)
        Assert(WSZC.RemoteMedical.active)
    end
    local function Reset()
        if WSZC.RemoteMedical.active or WSZC.RemoteMedical.pending then WSZC.RemoteMedical.Finish("test_reset") end
        op.x, op.alive, op.valid, op.traceEntity = 0, true, true, patient
        patient.x, patient.alive, patient.valid = 20, true, true
        patient2.x, patient2.alive, patient2.valid = 30, true, true
        local function ResetContents(destination, source)
            for key in pairs(destination) do destination[key] = nil end
            for key, value in pairs(source) do destination[key] = type(value) == "table" and table.Copy(value) or value end
        end
        -- C:U exposes stable table identities. Never replace them in the fixture.
        ResetContents(selfLimbsRef, { thorax = { pain = 1 }, selfOnly = { kept = true } })
        ResetContents(selfCardioRef, { bloodVolume = 100, consciousness = 99, skills = { STR = 10, RES = 11, INT = 12 } })
        ResetContents(selfStatsRef, { STR = 10, RES = 11, INT = 12, consciousness = 99, custom = "self" })
        WoundSystemClientState.PlayerLimbs = selfLimbsRef
        WoundSystemClientState.Cardio = selfCardioRef
        WoundSystemClientState.PlayerStats = selfStatsRef
        outgoing, simpleTimers, closeEmits = {}, {}, false
        WoundSystemHealthHUDOpen = false
    end
    selfLimbsRef = WoundSystemClientState.PlayerLimbs
    selfCardioRef = WoundSystemClientState.Cardio
    selfStatsRef = WoundSystemClientState.PlayerStats

    Test("C01 eye trace accepts another player/ragdoll, never self/dead/out-of-range", function()
        Reset(); Assert(WSZC.RemoteMedical.FindPatient() == patient)
        op.traceEntity = op; Assert(WSZC.RemoteMedical.FindPatient() == nil)
        op.traceEntity = ragdoll; Assert(WSZC.RemoteMedical.FindPatient() == patient)
        patient.alive = false; Assert(WSZC.RemoteMedical.FindPatient() == nil)
        patient.alive = true; patient.x = 500; Assert(WSZC.RemoteMedical.FindPatient() == nil)
    end)

    Test("C02 radial hook adds its own labelled treatment option", function()
        Reset(); hg.radialOptions = {}; op.traceEntity = patient
        hooks.radialOptionsZCity_WoundBridge_RemoteInspect_WSZC()
        Equal(#hg.radialOptions, 1)
        Assert(hg.radialOptions[1]._WSZCRemoteInspect)
        Assert(string.find(hg.radialOptions[1][2], "Лечить игрока", 1, true) ~= nil)
    end)

    Test("C03 snapshot opens native panel with patient limbs/cardio/skills", function()
        Reset(); Begin()
        Equal(openCalls, 1)
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 88)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 42)
        Equal(WoundSystemClientState.PlayerStats.STR, 3)
        Equal(WoundSystemClientState.PlayerStats.RES, 4)
        Equal(WoundSystemClientState.PlayerStats.INT, 5)
        Equal(WoundSystemClientState.PlayerStats.consciousness, 55)
        Assert(WoundSystemClientState.PlayerLimbs.selfOnly == nil)
    end)

    Test("C04 self limb/cardio updates are deferred only during remote mode", function()
        Reset(); Begin()
        net.Receivers.WoundSystem_UpdateLimb(); net.Receivers.WoundSystem_UpdateCardio()
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 88)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 42)
        WSZC.RemoteMedical.Finish("done")
        net.Receivers.WoundSystem_UpdateLimb(); net.Receivers.WoundSystem_UpdateCardio()
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 999)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 999)
    end)

    Test("C05 whitelisted native action is namespaced with target and typed values", function()
        Reset(); Begin(); outgoing = {}
        net.Start("WoundSystem_UseMedicalItem") net.WriteUInt(1, 8) net.WriteString("MORPHINE") net.WriteString("thorax") net.SendToServer()
        Equal(#outgoing, 1); Equal(outgoing[1].name, "WSZC_RemoteMedicalAction")
        Equal(outgoing[1].values[1], patient); Equal(outgoing[1].values[2], "WoundSystem_UseMedicalItem")
        Equal(outgoing[1].values[3], 3); Equal(outgoing[1].values[4], 1)
        outgoing = {}
        net.Start("WoundSystem_InventoryMove") net.WriteUInt(1, 8) net.SendToServer()
        Equal(outgoing[1].name, "WoundSystem_InventoryMove")
    end)

    Test("C06 finish restores exact self state; authoritative self snapshot still applies", function()
        Reset(); Begin(); WSZC.RemoteMedical.Finish("done")
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 1)
        Assert(WoundSystemClientState.PlayerLimbs.patientOnly == nil)
        Assert(WoundSystemClientState.PlayerLimbs.selfOnly ~= nil)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 100)
        Equal(WoundSystemClientState.PlayerStats.STR, 10)
        Equal(WoundSystemClientState.PlayerStats.custom, "self")
        incoming, incomingIndex = { op, { thorax = { pain = 7 } },
            { bloodVolume = 77, consciousness = 66, skills = { STR = 8, RES = 9, INT = 10 } }, "medic", 77, 0 }, 0
        net.Receivers.WSZC_RemoteMedicalRestoreSelf()
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 7)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 77)
        Equal(WoundSystemClientState.PlayerStats.STR, 8)
    end)

    Test("C07 server close restores self even after patient entity became invalid", function()
        Reset(); Begin(); patient.valid = false
        incoming, incomingIndex = { patient, "patient_unavailable" }, 0
        net.Receivers.WSZC_RemoteMedicalClose()
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 1)
        Equal(WoundSystemClientState.Cardio.bloodVolume, 100)
        Assert(not WSZC.RemoteMedical.active)
    end)

    Test("C08 pending timeout notifies server instead of leaking an inspection", function()
        Reset(); Assert(WSZC.OpenRemotePatient(patient)); RunSimple(); outgoing = {}
        now = now + 2; hooks.ThinkWSZC_RemoteMedicalWatchdog()
        Assert(WSZC.RemoteMedical.pending == nil)
        Equal(outgoing[1].name, "WSZC_RemoteMedicalClose")
    end)

    Test("C09 replacing pending target closes previous request", function()
        Reset(); Assert(WSZC.OpenRemotePatient(patient)); RunSimple()
        Assert(WSZC.OpenRemotePatient(patient2))
        Equal(WSZC.RemoteMedical.pending, patient2)
        local foundClose = false
        for _, packet in ipairs(outgoing) do if packet.name == "WSZC_RemoteMedicalClose" then foundClose = true end end
        Assert(foundClose)
    end)

    Test("C10 native panel close is captured before self restoration", function()
        Reset(); Begin(); closeEmits = true; outgoing = {}
        WoundSystem.CloseHealthHUD()
        Equal(outgoing[1].name, "WSZC_RemoteMedicalAction")
        Equal(outgoing[1].values[2], "WoundSystem_ShrapnelClose")
        Equal(outgoing[2].name, "WSZC_RemoteMedicalClose")
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 1)
    end)

    Test("C11 ordinary self-inspection entry point closes remote and opens self", function()
        Reset(); Begin(); local before = openCalls
        WSZC.OpenCUWoundMenu()
        Assert(not WSZC.RemoteMedical.active)
        Equal(openCalls, before + 1)
        Equal(WoundSystemClientState.PlayerLimbs.thorax.pain, 1)
    end)

    Test("C12 stale close for old target cannot cancel a replacement pending open", function()
        Reset(); Begin()
        Assert(WSZC.OpenRemotePatient(patient2))
        Equal(WSZC.RemoteMedical.pending, patient2)
        incoming, incomingIndex = { patient, "client_close" }, 0
        net.Receivers.WSZC_RemoteMedicalClose()
        Assert(not WSZC.RemoteMedical.active)
        Equal(WSZC.RemoteMedical.pending, patient2)
    end)

    Test("C13 invalid-patient native action is swallowed, never sent as self-treatment", function()
        Reset(); Begin(); patient.valid = false; outgoing = {}
        net.Start("WoundSystem_UseMedicalItem")
        net.WriteUInt(1, 8) net.WriteString("MORPHINE") net.WriteString("thorax")
        net.SendToServer()
        Equal(#outgoing, 0)
    end)
end

return tests
