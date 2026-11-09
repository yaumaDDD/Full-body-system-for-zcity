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
WSZC.PendingBandageState = nil
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

    -- Short post-close latch.  WSZC_MinigameClose / ForceReleaseMinigameCursor
    -- set it for 0.4 s: during that window a stale MG.active or a lingering
    -- C:U session cannot keep IN_ATTACK zeroed, which is why fentanyl and the
    -- other ZCity medical SWEPs could not be used after a minigame.  It is a
    -- TIMESTAMP, not a boolean: native C:U games (dislocation / shrapnel /
    -- AED) never send WSZC_MinigameOpen, so a permanent latch would disable
    -- their cursor and movement lock on the next game.
    local now = CurTime and CurTime() or 0
    if (WSZC._MinigameForceOffUntil or 0) > now then return false end

    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    local dislocation = WoundSystemDislocationMinigame
    local real = (bandage and bandage.IsActive and bandage.IsActive())
        or (syringe and syringe.IsActive and syringe.IsActive())
        or (dislocation and dislocation.active == true)
        or (WSZC.NativeMinigameActive and WSZC.NativeMinigameActive())
    -- An open packet that has not painted its first frame yet still owns the
    -- cursor; this is the only latch-derived "active" state.
    if WSZC.MinigameHUDOpen == true then return true end
    return real and true or false
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
    -- Do NOT unconditionally restore "arrow" here.  This watchdog runs every
    -- 0.05 s; doing so used to undo BlankMinigameCursor() after the gui wrapper
    -- had just hidden it, producing the visible arrow flicker over the hand.
    -- Sync selects blank for a visible hand and arrow only in fallback mode.
    if WSZC.SyncMinigameCursor then WSZC.SyncMinigameCursor() end
end

local function DisableMinigameClicker()
    -- ALWAYS clear our own state, even when the C:U health/wound panel is
    -- still open behind the game.  The old early return left
    -- _HoldMinigameCursor / ScreenClickerOwned stuck forever ("после мини
    -- игры курсор не пропадает") and kept the movement lock alive.
    WSZC._AllowClickerRelease = true
    WSZC._HoldMinigameCursor = false
    WSZC._MinigameBackdropDrawing = false
    WSZC._LastMinigameDraw = -10
    WSZC._NextCursorFix = 0
    WSZC._MinigameForceOffUntil = (CurTime and CurTime() or 0) + 0.4
    WSZC.RestoreMinigameCursor(true)   -- standard OS arrow again
    if WoundSystemHealthHUDOpen == true then
        -- C:U still needs a cursor for its own HUD, so only drop OUR
        -- ownership.  It releases the clicker itself when the panel closes.
        WSZC._AllowClickerRelease = false
        return
    end
    if WoundSystem and WoundSystem.HealthGUI and WoundSystem.HealthGUI.SetScreenClickerOwned then
        pcall(WoundSystem.HealthGUI.SetScreenClickerOwned, false, "wszc_minigame")
    end
    if gui and gui.EnableScreenClicker then gui.EnableScreenClicker(false) end
    WSZC._AllowClickerRelease = false
end
WSZC.DisableMinigameClicker = DisableMinigameClicker

-- C:U's WoundSystem_ScreenClickerWatchdog releases the cursor whenever
-- WoundSystemIsAnyWoundMinigameActive() is false.  That global only knows the
-- NATIVE C:U minigames, so it used to steal the cursor from our namespaced
-- copies.  Extend it once, lazily (C:U may load after us).
local function PatchCUMinigameActive()
    if type(WoundSystemIsAnyWoundMinigameActive) ~= "function" then return end
    -- C:U may (re)define this global after our autorun file loads, or a hot
    -- reload may replace it.  A one-shot "already patched" flag used to leave
    -- the watchdog reading a STALE probe, which then released the clicker.
    -- Compare the current global with our wrapper and re-wrap whenever needed.
    if WSZC._CUMinigameActiveWrapper == WoundSystemIsAnyWoundMinigameActive then return end
    local original = WoundSystemIsAnyWoundMinigameActive
    local function wrapped()
        -- MinigameDrawnRecently() is deliberately NOT included here.  C:U's
        -- DelayedRespawnCursorRelease / ScreenClickerWatchdog read this global
        -- to decide whether to release the clicker; a 0.35 s "recently drew"
        -- tail used to make them report "minigame active" after the game had
        -- already closed.  The backdrop stamp is only for OUR cursor watchdog.
        return original() or WSZC.MinigameActive()
    end
    WoundSystemIsAnyWoundMinigameActive = wrapped
    WSZC._CUMinigameActiveWrapper = wrapped
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
local function ClearAllMinigameState(notifyServer)
    WSZC.MinigameHUDOpen = false
    WSZC.PendingBandageOpen = nil
    WSZC.PendingBandageState = nil
    WSZC.PendingSyringeOpen = nil
    WSZC.MinigameFrozenAngles = nil
    WSZC._ViewModelHidden = nil
    local names = {
        "WSZCBandageMinigame", "WSZCSyringeMinigame",
        "WoundSystemDislocationMinigame", "WoundSystemShrapnelMinigame",
        "WoundSystemAEDMinigame", "WoundSystemBandageMinigame",
        "WoundSystemSyringeMinigame", "WoundSystemSelfHarmMinigame",
    }
    for _, name in ipairs(names) do
        local mg = _G[name]
        if type(mg) == "table" then
            if notifyServer and mg.active and type(mg.RequestClose) == "function" then
                pcall(mg.RequestClose, "unconscious")
            end
            mg.active = false
            -- RequestClose normally removes this already.  The direct removal
            -- covers a lost native close upvalue and server-forced cleanup.
            if IsValid(mg.overlay) and mg.overlay.Remove then pcall(mg.overlay.Remove, mg.overlay) end
            mg.overlay = nil
        end
    end
    ReleaseMinigameView()
    DisableMinigameClicker()
    if WSZC.ForceReleaseMinigameCursor then WSZC.ForceReleaseMinigameCursor() end
    if not WSZC.MinigameContextOK() and WoundSystem
        and type(WoundSystem.CloseHealthHUD) == "function" then
        pcall(WoundSystem.CloseHealthHUD)
    end
end
WSZC.ClearAllMinigameState = ClearAllMinigameState

hook.Add("PlayerDeath", "WSZC_MinigameDeathCleanup", function(ply)
    if LocalPlayer and ply ~= LocalPlayer() then return end
    ClearAllMinigameState(true)
end)
hook.Add("PlayerSpawn", "WSZC_MinigameSpawnCleanup", function(ply)
    if LocalPlayer and ply ~= LocalPlayer() then return end
    -- hg.FakeUp() also runs PlayerSpawn internally.  A conscious operator in
    -- that transition keeps the active board/cursor; death and real otrub are
    -- still cleaned here and by the every-frame context watchdog below.
    if WSZC.MinigameContextOK then
        if WSZC.MinigameContextOK() then return end
    end
    ClearAllMinigameState(true)
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
    ClearAllMinigameState(true)
end)

net.Receive("WSZC_MinigameForceClose", function()
    net.ReadString() -- reason is diagnostic; cleanup is identical for all causes
    ClearAllMinigameState(false)
    -- The organism flag can arrive one network tick later.  A server-forced
    -- close is already authoritative, so do not leave WoundView / its cursor
    -- open while waiting for that flag to replicate.
    if WoundSystem and type(WoundSystem.CloseHealthHUD) == "function" then
        pcall(WoundSystem.CloseHealthHUD)
    end
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

-- C:U draws boneDrawX/Y, but its server tests a separately simulated boneX/Y.
-- Once the RENDERED bone is close to the socket, ask the server
-- to validate and complete this exact session immediately.  No click release,
-- extra hit or arbitrary client-selected limb is required.  The receiver
-- repeats the tolerance check and owns the actual state transition.
hook.Add("Think", "WSZC_DislocationVisualCompletion", function()
    local mg = WoundSystemDislocationMinigame
    if type(mg) ~= "table" or mg.active ~= true or mg.closeRequested == true then return end
    if not (GetGlobalBool and GetGlobalBool("WSZC_Ready", false) == true) then return end
    if not WSZC.DislocationVisualAligned then return end
    local x = tonumber(mg.boneDrawX) or tonumber(mg.boneX)
    local y = tonumber(mg.boneDrawY) or tonumber(mg.boneY)
    if not WSZC.DislocationVisualAligned(x, y) then
        mg._WSZCNextVisualComplete = 0
        return
    end
    local now = CurTime and CurTime() or 0
    if now < (mg._WSZCNextVisualComplete or 0) then return end
    mg._WSZCNextVisualComplete = now + 0.1
    net.Start("WSZC_DislocationVisualComplete")
        net.WriteUInt(tonumber(mg.sessionId) or 0, 24)
        net.WriteFloat(x)
        net.WriteFloat(y)
    net.SendToServer()
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
    -- A C:U / ZCity game that our IsActive() probes missed still paints the
    -- shared Clip.DrawBackdrop every frame.  That stamps _LastMinigameDraw, so
    -- the cursor is held for it too: this is the "нельзя управлять курсором"
    -- fix for games started from a ZCity SWEP without a WSZC_MinigameOpen
    -- packet and for C:U tables replaced by a hot reload.
    local running = WSZC.MinigameActive()
        or (WSZC.MinigameDrawnRecently and WSZC.MinigameDrawnRecently())
    WSZC._HoldMinigameCursor = running and true or false
    if not running then
        -- Game ended (including native C:U games whose IsActive() we may
        -- miss): run the hard cleanup exactly once so the clicker, camera
        -- freeze and SetupMove lock cannot outlive the minigame.
        if WSZC._MinigameWasRunning then
            WSZC._MinigameWasRunning = false
            if WSZC.ForceReleaseMinigameCursor then
                WSZC.ForceReleaseMinigameCursor()
            end
        end
        return
    end
    WSZC._MinigameWasRunning = true
    -- Never fight the game/console menu for the cursor, but otherwise keep
    -- re-asserting it unconditionally.  Checking vgui.CursorVisible() here
    -- used to let C:U's watchdog steal it for one frame -> visible flicker.
    if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return end
    if gui and gui.IsConsoleVisible and gui.IsConsoleVisible() then return end
    local now = CurTime and CurTime() or 0
    if (WSZC._NextCursorFix or 0) > now then return end
    WSZC._NextCursorFix = now + 0.05
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
    -- Only OUR bandage/syringe sessions (they set MinigameHUDOpen) need the
    -- full IN_ATTACK lock.  For native C:U games a stale `active` flag must
    -- never swallow the left click - ZCity medical SWEPs (fentanyl, ...)
    -- would stop working after every minigame.
    if WSZC.MinigameHUDOpen == true and cmd.SetButtons then cmd:SetButtons(0) end
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
    -- Only OUR bandage/syringe sessions need to suppress ZCity binds.  A
    -- stale native C:U MG.active must never lock the player out of their
    -- inventory: fentanyl / morphine are picked with a slot bind right after
    -- a minigame, and the blocked bind looked like "medicine does not apply".
    if WSZC.MinigameHUDOpen ~= true then return end
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

local function ReadBandageState()
    return {
        sessionId = net.ReadUInt(24),
        initialBleed = math.max(net.ReadFloat() or 0, 0),
        currentBleed = math.max(net.ReadFloat() or 0, 0),
        progress = math.Clamp(net.ReadFloat() or 0, 0, 1),
        arterialBleed = math.max(net.ReadFloat() or 0, 0),
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
        local state = WSZC.PendingBandageState
        WSZC.PendingBandageState = nil
        if state and state.sessionId == payload.sessionId
            and type(WSZCBandageMinigame.ApplyBleedState) == "function" then
            WSZCBandageMinigame.ApplyBleedState(state)
        end
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
    WSZC._MinigameForceOffUntil = 0
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
    WSZC.PendingBandageState = nil
    WSZC.PendingSyringeOpen = nil
    ReleaseMinigameView()
    DisableMinigameClicker()
    -- Also clear C:U's ownership/watchdog state so the arrow disappears and
    -- ZCity medical SWEPs (fentanyl, morphine, ...) get their clicks back.
    if WSZC.ForceReleaseMinigameCursor then WSZC.ForceReleaseMinigameCursor() end
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
net.Receive("WSZC_BandageState", function()
    local payload = ReadBandageState()
    local mg = WSZCBandageMinigame
    if mg and mg.active and mg.sessionId == payload.sessionId
        and type(mg.ApplyBleedState) == "function" then
        mg.ApplyBleedState(payload)
    else
        -- Open/state are separate reliable messages, but the client copy may
        -- still be loading.  Keep one latest packet until DeliverPending().
        WSZC.PendingBandageState = payload
    end
end)

local function ClientYesNo(value) return value and "yes" or "no" end

function WSZC.MinigameClientStatusLines()
    local bandage, syringe = WSZCBandageMinigame, WSZCSyringeMinigame
    local hpPath = WSZC.ResolveCUPath
        and WSZC.ResolveCUPath("woundsystem/client/minigames/sh_handphysics.lua")
        or "woundsystem/client/minigames/sh_handphysics.lua"
    local clipPath = WSZC.ResolveCUPath
        and WSZC.ResolveCUPath("woundsystem/client/minigames/cl_clip.lua")
        or "woundsystem/client/minigames/cl_clip.lua"
    local hpStatus = WSZC.OptionalIncludeStatus and WSZC.OptionalIncludeStatus[hpPath] or nil
    local hpExists = file and file.Exists and file.Exists(hpPath, "LUA")
    local clipExists = file and file.Exists and file.Exists(clipPath, "LUA")
    return {
        "[ZCity/CU compat] client minigame runtime:",
        "  loaded=" .. ClientYesNo(WSZC._MinigameClientLoaded)
            .. " ready=" .. ClientYesNo(WSZC.MinigameClientReady)
            .. " attempts=" .. tostring(WSZC.MinigameClientAttempts or 0)
            .. " hud_open=" .. ClientYesNo(WSZC.MinigameHUDOpen),
        "  requirements: clip=" .. ClientYesNo(WoundSystem and WoundSystem.MinigameClip)
            .. " items=" .. ClientYesNo(WoundSystem and WoundSystem.Items
                and type(WoundSystem.Items.Get) == "function")
            .. " health_gui_optional=" .. ClientYesNo(WoundSystem and WoundSystem.HealthGUI)
            .. " hud_global_optional=" .. ClientYesNo(WoundSystemHealthHUDOpen ~= nil),
        "  files: handphysics_exists=" .. tostring(hpExists)
            .. " clip_exists=" .. tostring(clipExists)
            .. " handphysics_include=" .. (hpStatus and ClientYesNo(hpStatus.ok) or "not_tried")
            .. " handphysics_result=" .. (hpStatus and tostring(hpStatus.resultType) or "none")
            .. (hpStatus and hpStatus.reason and (" error=" .. tostring(hpStatus.reason)) or ""),
        "  games: bandage_loaded=" .. ClientYesNo(bandage and bandage._Loaded)
            .. " bandage_active=" .. ClientYesNo(bandage and bandage.active)
            .. " syringe_loaded=" .. ClientYesNo(syringe and syringe._Loaded)
            .. " syringe_active=" .. ClientYesNo(syringe and syringe.active),
        "  pending: bandage=" .. ClientYesNo(WSZC.PendingBandageOpen ~= nil)
            .. " syringe=" .. ClientYesNo(WSZC.PendingSyringeOpen ~= nil),
    }
end

function WSZC.PrintMinigameClientStatus()
    if not (WSZC.DebugAllowed and WSZC.DebugAllowed()) then return end
    for _, line in ipairs(WSZC.MinigameClientStatusLines()) do WSZC.DebugDisplay(nil, line) end
end

local function ClientReady()
    -- Bandage/syringe need the clip renderer and item definitions.  The full
    -- inspection GUI is optional: a missing/broken health panel must not leave
    -- these independent namespaced minigames retrying forever without UI.
    return WoundSystem
        and WoundSystem.MinigameClip
        and WoundSystem.Items
        and type(WoundSystem.Items.Get) == "function"
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
        if WSZC.Warn then WSZC.Warn("minigame client load failed: "
            .. tostring(errBandage) .. " / " .. tostring(errSyringe)) end
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
