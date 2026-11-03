-- ZCity <-> Casualties: Unknown external minigames (client part)
--
-- The bundled C:U build has bandage/syringe minigames, but their net protocol is
-- hard-wired to the native C:U inventory.  This file loads namespaced copies of
-- those two client minigames and maintains a virtual inventory slot for the
-- ZCity SWEP that is currently being used.  No original C:U file is edited.

WSZC = WSZC or {}

if WSZC._MinigameClientLoaded then return end
WSZC._MinigameClientLoaded = true

WSZC.MinigameHUDOpen = false
WSZC.MinigameClientReady = false
WSZC.MinigameClientAttempts = 0
WSZC.MinigameSlotIdx = 6
WSZC.PendingBandageOpen = nil
WSZC.PendingSyringeOpen = nil

function WSZC.MinigameNextInputSeq(mg)
    if not mg then return 0 end

    mg.inputSeq = ((mg.inputSeq or 0) + 1) % 16777216
    if mg.inputSeq <= 0 then mg.inputSeq = 1 end
    return mg.inputSeq
end

local function ReadOptionalUInt(bits, fallback)
    if not net.BytesLeft then return fallback end

    local bytesLeft, bitsLeft = net.BytesLeft()
    if (bitsLeft or 0) >= bits or (bytesLeft or 0) * 8 >= bits then
        return net.ReadUInt(bits)
    end

    return fallback
end

function WSZC.MinigameReadAck(defaultValue)
    return ReadOptionalUInt(24, defaultValue or 0)
end

function WSZC.MinigameAck(mg, ackSeq)
    if not mg or not ackSeq then return end
    mg.ackSeq = math.max(mg.ackSeq or 0, ackSeq or 0)
end

local function EnsureTables()
    WoundSystemInventorySlots = WoundSystemInventorySlots or {}
    WoundSystemMedToolConfig = WoundSystemMedToolConfig or {}
end

local function EnableMinigameClicker()
    if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        pcall(WoundSystem.HealthGUI.SetScreenClickerOwned, true, "wszc_minigame")
    end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(true) end
end

local function DisableMinigameClicker()
    if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        pcall(WoundSystem.HealthGUI.SetScreenClickerOwned, false, "wszc_minigame")
    end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
end
WSZC.DisableMinigameClicker = DisableMinigameClicker

local function SetVirtualSlot(slotIdx, itemId, durability, maxDur)
    EnsureTables()

    WoundSystemInventorySlots[slotIdx] = {
        type = "tool",
        toolName = itemId,
        durability = math.max(tonumber(durability) or 0, 0),
    }

    local cfg = WoundSystemMedToolConfig[itemId]
    if type(cfg) ~= "table" then
        cfg = {}
        WoundSystemMedToolConfig[itemId] = cfg
    end
    cfg.max = math.max(tonumber(maxDur) or 100, 0.0001)
end

local function ClearVirtualSlot(slotIdx)
    EnsureTables()
    WoundSystemInventorySlots[slotIdx] = { type = "empty" }
end

local function ReadBandageOpen()
    return {
        sessionId = net.ReadUInt(24),
        limbId = net.ReadString(),
        mode = net.ReadString(),
        slotIdx = net.ReadUInt(3),
    }
end

local function ReadSyringeOpen()
    return {
        sessionId = net.ReadUInt(24),
        limbId = net.ReadString(),
        slotIdx = net.ReadUInt(3),
        itemId = net.ReadString(),
        condition = net.ReadFloat(),
    }
end

local function DeliverPending()
    if WSZC.PendingBandageOpen and WSZCBandageMinigame
        and type(WSZCBandageMinigame.OpenFromServer) == "function" then
        local payload = WSZC.PendingBandageOpen
        WSZC.PendingBandageOpen = nil
        WSZCBandageMinigame.OpenFromServer(payload)
    end

    if WSZC.PendingSyringeOpen and WSZCSyringeMinigame
        and type(WSZCSyringeMinigame.OpenFromServer) == "function" then
        local payload = WSZC.PendingSyringeOpen
        WSZC.PendingSyringeOpen = nil
        WSZCSyringeMinigame.OpenFromServer(payload)
    end
end

local function BufferBandageOpen()
    WSZC.PendingBandageOpen = ReadBandageOpen()
    if WSZC.MinigameClientReady then DeliverPending() end
end

local function BufferSyringeOpen()
    WSZC.PendingSyringeOpen = ReadSyringeOpen()
    if WSZC.MinigameClientReady then DeliverPending() end
end

net.Receive("WSZC_MinigameOpen", function()
    local slotIdx = net.ReadUInt(3)
    local itemId = net.ReadString()
    local durability = net.ReadFloat()
    local maxDur = net.ReadFloat()

    WSZC.MinigameSlotIdx = slotIdx
    SetVirtualSlot(slotIdx, itemId, durability, maxDur)
    WSZC.MinigameHUDOpen = true
    EnableMinigameClicker()
end)

net.Receive("WSZC_MinigameSlot", function()
    local slotIdx = net.ReadUInt(3)
    local durability = net.ReadFloat()
    local maxDur = net.ReadFloat()

    EnsureTables()
    local slot = WoundSystemInventorySlots[slotIdx]
    if type(slot) ~= "table" then
        slot = { type = "tool", toolName = "GAUZE" }
        WoundSystemInventorySlots[slotIdx] = slot
    end
    slot.type = "tool"
    slot.durability = math.max(tonumber(durability) or 0, 0)

    local cfg = WoundSystemMedToolConfig[slot.toolName]
    if type(cfg) == "table" then
        cfg.max = math.max(tonumber(maxDur) or 100, 0.0001)
    end
end)

net.Receive("WSZC_MinigameClose", function()
    local slotIdx = net.ReadUInt(3)

    ClearVirtualSlot(slotIdx)
    WSZC.MinigameHUDOpen = false
    WSZC.PendingBandageOpen = nil
    WSZC.PendingSyringeOpen = nil
    DisableMinigameClicker()
end)

net.Receive("WSZC_MinigameAck", function()
    local gameId = net.ReadUInt(3)
    local sessionId = net.ReadUInt(24)
    local ackSeq = net.ReadUInt(24)

    local mg
    if gameId == 1 then
        mg = WSZCBandageMinigame
    elseif gameId == 2 then
        mg = WSZCSyringeMinigame
    end

    if mg and mg.active and mg.sessionId == sessionId then
        WSZC.MinigameAck(mg, ackSeq)
    end
end)

-- Registered early: if the server opens a session before the C:U client files
-- have finished loading, the payload is buffered and delivered by Activate().
net.Receive("WSZC_BandageOpen", BufferBandageOpen)
net.Receive("WSZC_SyringeOpen", BufferSyringeOpen)

local function ClientReady()
    return WoundSystem
        and WoundSystem.MinigameClip
        and WoundSystem.Items
        and WoundSystem.Items.Get
        and WoundSystem.HealthGUI
        and WoundSystemHealthHUDOpen ~= nil
end

local function Activate()
    if WSZC.MinigameClientReady then return end
    WSZC.MinigameClientAttempts = (WSZC.MinigameClientAttempts or 0) + 1

    if not ClientReady() then
        if WSZC.MinigameClientAttempts < 80 then timer.Simple(0.25, Activate) end
        return
    end

    local okBandage, errBandage = pcall(include, "autorun/client/wszc_cl_bandage.lua")
    local okSyringe, errSyringe = pcall(include, "autorun/client/wszc_cl_syringe.lua")
    if not okBandage or not okSyringe then
        ErrorNoHalt("[ZCity/CU compat] minigame client load failed: "
            .. tostring(errBandage) .. " / " .. tostring(errSyringe) .. "\n")
        if WSZC.MinigameClientAttempts < 80 then timer.Simple(0.25, Activate) end
        return
    end

    WSZC.MinigameClientReady = true

    -- The copies register their own open receivers.  Re-register ours last so
    -- every open is buffered and can be delivered to MG.OpenFromServer().
    net.Receive("WSZC_BandageOpen", BufferBandageOpen)
    net.Receive("WSZC_SyringeOpen", BufferSyringeOpen)
    DeliverPending()
end

timer.Simple(0, Activate)
hook.Add("InitPostEntity", "WSZC_MinigameClientInit", Activate)

hook.Add("Think", "WSZC_MinigameClientWatch", function()
    if not WSZC.MinigameHUDOpen then return end

    local bandage = WSZCBandageMinigame
    local syringe = WSZCSyringeMinigame
    if (not bandage or not bandage.active) and (not syringe or not syringe.active) then
        WSZC.MinigameHUDOpen = false
        DisableMinigameClicker()
    end
end)
