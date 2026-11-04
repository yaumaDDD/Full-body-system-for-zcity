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
WSZC.MinigameOpenAt = 0

--- True while a WSZC minigame is running (or its open packet has arrived but
--- the client copy has not painted its first frame yet).  Used for the cursor
--- owner, the movement lock and C:U's own minigame-active probe.
function WSZC.MinigameActive()
    if WSZC.MinigameHUDOpen == true then return true end
    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    if bandage and bandage.IsActive and bandage.IsActive() then return true end
    if syringe and syringe.IsActive and syringe.IsActive() then return true end
    return false
end

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
    -- The C:U health/wound panel can be open behind a ZCity minigame (the
    -- radial "Проверить травмы" button opens it).  Do not release the cursor
    -- while that panel is still up; C:U releases it when the panel closes.
    if WoundSystemHealthHUDOpen == true then return end

    if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        pcall(WoundSystem.HealthGUI.SetScreenClickerOwned, false, "wszc_minigame")
    end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
end
WSZC.DisableMinigameClicker = DisableMinigameClicker

-- C:U's WoundSystem_ScreenClickerWatchdog releases the cursor whenever
-- WoundSystemIsAnyWoundMinigameActive() is false.  That global only knows the
-- NATIVE C:U minigames, so it used to steal the cursor from our namespaced
-- copies.  Extend it once, lazily (C:U may load after us).
local function PatchCUMinigameActive()
    if WSZC._CUMinigameActivePatched then return end
    if type(WoundSystemIsAnyWoundMinigameActive) ~= "function" then return end
    WSZC._CUMinigameActivePatched = true
    local original = WoundSystemIsAnyWoundMinigameActive
    WoundSystemIsAnyWoundMinigameActive = function()
        return original() or WSZC.MinigameActive()
    end
end
WSZC.PatchCUMinigameActive = PatchCUMinigameActive

-- If ZCity's radial menu is still closing, SetScreenClickerOwned(true) can be
-- refused by C:U ("external menu open").  Keep re-asserting the cursor while a
-- WSZC minigame is live; this also defeats the C:U watchdog described above.
hook.Add("Think", "WSZC_MinigameCursorWatch", function()
    PatchCUMinigameActive()
    if not WSZC.MinigameActive() then return end
    if not (gui and vgui and vgui.CursorVisible) then return end
    if vgui.CursorVisible() then return end
    local now = CurTime and CurTime() or 0
    if (WSZC._NextCursorFix or 0) > now then return end
    WSZC._NextCursorFix = now + 0.15
    EnableMinigameClicker()
end)

-- While a minigame is up the character must stand still.  SetupMove runs after
-- CreateMove on the client, so zeroing the command here stops walking,
-- strafing, jumping, crouching, attacking AND camera rotation before the
-- command ever reaches the server.  Vertical velocity is kept (falling) so the
-- player does not hang in mid-air.
hook.Add("SetupMove", "WSZC_MinigameLockMovement", function(ply, mv, cmd)
    if not WSZC.MinigameActive() then return end
    if ply ~= LocalPlayer() then return end
    if mv and mv.SetVelocity and mv.GetVelocity then
        local v = mv:GetVelocity()
        mv:SetVelocity(Vector(0, 0, math.min(v.z or 0, 0)))
    end
    if not cmd then return end
    if cmd.SetForwardMove then cmd:SetForwardMove(0) end
    if cmd.SetSideMove then cmd:SetSideMove(0) end
    if cmd.SetUpMove then cmd:SetUpMove(0) end
    if cmd.SetButtons then cmd:SetButtons(0) end
    if cmd.SetMouseX then cmd:SetMouseX(0) end
    if cmd.SetMouseY then cmd:SetMouseY(0) end
end)

-- Keep ZCity binds (radial menu, weapon switch, +use, inventory, ...) from
-- firing behind the minigame.  Console/screenshot stay available.
hook.Add("PlayerBindPress", "WSZC_MinigameBlockBinds", function(ply, bind, pressed)
    if not WSZC.MinigameActive() then return end
    if bind == "toggleconsole" or bind == "screenshot" or bind == "jpeg" then return end
    return true
end)

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
    WSZC.MinigameOpenAt = CurTime and CurTime() or 0
    PatchCUMinigameActive()
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
    WSZC.MinigameOpenAt = 0
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
        -- `WSZC_MinigameOpen` and the minigame's own `WSZC_BandageOpen` /
        -- `WSZC_SyringeOpen` packet can land in different frames.  Releasing
        -- the cursor in that gap was the "cursor never appears" bug, so give
        -- the session 1 second to start before tearing it down.
        local now = CurTime and CurTime() or 0
        if now - (WSZC.MinigameOpenAt or 0) < 1.0 then return end
        WSZC.MinigameHUDOpen = false
        DisableMinigameClicker()
    end
end)
