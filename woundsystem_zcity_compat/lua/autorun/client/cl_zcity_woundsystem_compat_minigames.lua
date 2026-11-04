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
    -- A dead player is never "in a minigame": a stuck MG.active used to keep
    -- the cursor, camera freeze, SetupMove lock and PlayerBindPress block
    -- alive after death, making respawn impossible.
    if WSZC.MinigameContextOK and not WSZC.MinigameContextOK() then return false end
    if WSZC.MinigameHUDOpen == true then return true end
    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    if bandage and bandage.IsActive and bandage.IsActive() then return true end
    if syringe and syringe.IsActive and syringe.IsActive() then return true end
    -- C:U's native manual bone reduction (WoundView -> FIX DISLOCATION).
    -- It owns the cursor and reads gui.MousePos(); include it so the movement
    -- lock, camera freeze and cursor watchdog cover it too.
    local dislocation = WoundSystemDislocationMinigame
    if dislocation and dislocation.active == true then return true end
    -- Also cover the other native C:U games (shrapnel, AED, ...): they use the
    -- same cursor owner and camera/movement lock.  The layout helper is loaded
    -- first alphabetically, but stay defensive for hot reloads.
    if WSZC.NativeMinigameActive and WSZC.NativeMinigameActive() then return true end
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

-- Freeze the VIEW ANGLES, not just the mouse delta.  GMod applies the mouse
-- movement in InputMouseApply / CreateMove and writes cmd:SetViewAngles()
-- BEFORE SetupMove runs, so zeroing MouseX/MouseY in SetupMove alone still
-- lets the player spin the camera during the bandage/syringe minigame.
local function FreezeMinigameView()
    if WSZC.MinigameFrozenAngles then return end
    local ply = LocalPlayer and LocalPlayer() or nil
    if not (IsValid and IsValid(ply) and ply.EyeAngles) then return end
    local ok, ang = pcall(ply.EyeAngles, ply)
    if ok and ang then WSZC.MinigameFrozenAngles = ang end
end

local function ReleaseMinigameView()
    WSZC.MinigameFrozenAngles = nil
end

hook.Add("InputMouseApply", "WSZC_MinigameFreezeMouse", function(cmd)
    if not WSZC.MinigameActive() then return end
    if cmd then
        -- DO NOT zero cmd:SetMouseX / SetMouseY here.  With
        -- gui.EnableScreenClicker(true) GMod drives gui.MousePos() from the
        -- very same CUserCmd mouse delta, so zeroing it pins the cursor at
        -- (0,0): "the hand will not move in the bandage minigame".  The
        -- camera is already frozen by SetViewAngles below and in CreateMove /
        -- SetupMove, so the mouse delta can safely reach the VGUI cursor.
        -- Also never return true here (that would swallow the cursor too).
        local ang = WSZC.MinigameFrozenAngles
        if ang and cmd.SetViewAngles then cmd:SetViewAngles(ang) end
    end
    return nil
end)

hook.Add("CreateMove", "WSZC_MinigameFreezeView", function(cmd)
    if not WSZC.MinigameActive() then return end
    local ang = WSZC.MinigameFrozenAngles
    if ang and cmd and cmd.SetViewAngles then cmd:SetViewAngles(ang) end
end)

-- "Items in hands are still visible": the ZCity SWEP viewmodel (bandage roll,
-- syringe, splint, ...) kept rendering over the 2D minigame.  Returning true
-- from PreDrawViewModel / PreDrawPlayerHands suppresses ONLY the viewmodel,
-- not the world or the player's ragdoll/third-person body.
hook.Add("PreDrawViewModel", "WSZC_MinigameHideViewModel", function(vm, ply, wep)
    if not WSZC.MinigameActive() then return end
    if ply and LocalPlayer and ply ~= LocalPlayer() then return end
    return true
end)
hook.Add("PreDrawPlayerHands", "WSZC_MinigameHideHands", function(hands, ply, wep)
    if not WSZC.MinigameActive() then return end
    if ply and LocalPlayer and ply ~= LocalPlayer() then return end
    return true
end)

-- If ZCity's radial menu is still closing, SetScreenClickerOwned(true) can be
-- refused by C:U ("external menu open").  Keep re-asserting the cursor while a
-- WSZC minigame is live; this also defeats the C:U watchdog described above.
-- Clear every client-side minigame flag on death AND on spawn.  C:U only calls
-- CloseWoundMinigames() from WoundSystem.HealthGUI.ResetLocalRespawnInput(),
-- which is tied to its own PlayerSpawn hook; if that hook is missing or a
-- session object was replaced by a hot reload, MG.active stays true forever.
local function ClearAllMinigameState()
    WSZC.MinigameHUDOpen = false
    WSZC.PendingBandageOpen = nil
    WSZC.PendingSyringeOpen = nil
    WSZC.MinigameFrozenAngles = nil
    WSZC._ViewModelHidden = nil
    local names = {
        "WSZCBandageMinigame", "WSZCSyringeMinigame",
        "WoundSystemDislocationMinigame", "WoundSystemShrapnelMinigame",
        "WoundSystemAEDMinigame", "WoundSystemBandageMinigame",
        "WoundSystemSyringeMinigame",
    }
    for _, name in ipairs(names) do
        local mg = _G[name]
        if type(mg) == "table" then mg.active = false end
    end
end
WSZC.ClearAllMinigameState = ClearAllMinigameState

hook.Add("PlayerDeath", "WSZC_MinigameDeathCleanup", function(ply)
    if LocalPlayer and ply ~= LocalPlayer() then return end
    ClearAllMinigameState()
end)
hook.Add("PlayerSpawn", "WSZC_MinigameSpawnCleanup", function(ply)
    if LocalPlayer and ply ~= LocalPlayer() then return end
    ClearAllMinigameState()
end)

-- PlayerDeath is not guaranteed to fire in every client realm/build; the
-- context check is authoritative and runs every frame anyway.
hook.Add("Think", "WSZC_MinigameDeadCleanup", function()
    if WSZC.MinigameContextOK and WSZC.MinigameContextOK() then
        WSZC._MinigameDeadCleaned = false
        return
    end
    if WSZC._MinigameDeadCleaned then return end
    WSZC._MinigameDeadCleaned = true
    ClearAllMinigameState()
end)

-- Native C:U games (dislocation / shrapnel / AED) do not send our WSZC open
-- packet, so freeze the camera for them too.  The helpers are idempotent.
hook.Add("Think", "WSZC_MinigameViewWatch", function()
    if WSZC.MinigameActive() then
        FreezeMinigameView()
    else
        ReleaseMinigameView()
    end
end)

-- Belt and braces for the viewmodel: some ZCity SWEPs draw their held item
-- through a custom render hook that ignores PreDrawViewModel.  SetNoDraw on
-- the viewmodel entity is applied once on each state change, never per frame.
hook.Add("Think", "WSZC_MinigameViewModelVisibility", function()
    local hidden = WSZC.MinigameActive() and true or false
    if hidden == WSZC._ViewModelHidden then return end
    WSZC._ViewModelHidden = hidden
    local ply = LocalPlayer and LocalPlayer() or nil
    if not (IsValid and IsValid(ply) and ply.GetViewModel) then return end
    local vm = ply:GetViewModel()
    if IsValid(vm) then vm:SetNoDraw(hidden) end
end)

hook.Add("Think", "WSZC_MinigameCursorWatch", function()
    PatchCUMinigameActive()
    if not WSZC.MinigameActive() then return end
    -- Never fight the game/console menu for the cursor, but otherwise keep
    -- re-asserting it unconditionally.  Checking vgui.CursorVisible() here
    -- used to let C:U's watchdog steal it for one frame -> visible flicker.
    if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return end
    if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return end
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
    -- MouseX/MouseY are intentionally NOT zeroed in SetupMove either: the
    -- VGUI cursor still needs that delta while a minigame owns the clicker.
    -- Last line of defence: GMod already applied mouse delta to ViewAngles.
    local ang = WSZC.MinigameFrozenAngles
    if ang and cmd.SetViewAngles then cmd:SetViewAngles(ang) end
end)

-- Keep ZCity binds (radial menu, weapon switch, inventory, ...) from firing
-- behind the minigame.  Mouse buttons MUST pass through: the syringe /
-- bandage minigame reads input.IsMouseDown() to grab its tool, and blocking
-- +attack made the on-screen hand feel frozen.  SetupMove still zeroes the
-- CUserCmd buttons, so no shot / swing reaches the server.
local MINIGAME_ALLOWED_BINDS = {
    toggleconsole = true, screenshot = true, jpeg = true,
    ["+attack"] = true, ["-attack"] = true,
    ["+attack2"] = true, ["-attack2"] = true,
}
hook.Add("PlayerBindPress", "WSZC_MinigameBlockBinds", function(ply, bind, pressed)
    if not WSZC.MinigameActive() then return end
    if MINIGAME_ALLOWED_BINDS[bind] then return end
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
    FreezeMinigameView()
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
    ReleaseMinigameView()
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
        -- Only WSZC_MinigameClose may release the cursor.  Tearing it down
        -- from this watchdog while a session still had a pending open packet
        -- produced the "cursor appears and disappears" flicker.  A much
        -- longer grace is a pure safety net for a lost close packet, and it
        -- only drops the flag -- never the cursor itself.
        local now = CurTime and CurTime() or 0
        if now - (WSZC.MinigameOpenAt or 0) < 5.0 then return end
        WSZC.MinigameHUDOpen = false
    end
end)
