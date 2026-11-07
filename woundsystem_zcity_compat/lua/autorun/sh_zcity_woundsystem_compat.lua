-- ZCity <-> Casualties: Unknown compatibility layer (shared part)
--
-- The bundled ZCity bridge (lua/homigrad/woundbridge) expects a newer C:U API
-- than the supplied "casualites unknown.zip" exposes.  Its WB.IsEnabled()
-- therefore returns false on the server.  This addon patches that check at
-- runtime, after both addons have had a chance to load, and exposes a single
-- networked flag so clients use exactly the same decision as the server.
--
-- No file inside the original ZIP addons is modified.

WSZC = WSZC or {}

if WSZC._SharedLoaded then return end
WSZC._SharedLoaded = true

local TAG = "[ZCity/CU compat] "

---------------------------------------------------------------------------
-- Health authority switch
--
--   1 (default) = standard ZCity: `ply.organism` is the ONLY health
--                 simulation.  WoundSystem (C:U) stays loaded as the injury
--                 UI, the treatment minigames and the shrapnel protocol.
--   0           = the original bridge: C:U owns wounds, ZCity owns hits.
--
-- This convar is replicated so the client HUD / radial selector can make the
-- same decision as the server.  It never changes `woundsys_enabled`: C:U must
-- stay enabled for OpenHealthHUD() and WoundSystem_ShrapnelStart to exist.
---------------------------------------------------------------------------
if SERVER and CreateConVar and not ConVarExists("zc_woundsystem_compat_authority") then
    CreateConVar("zc_woundsystem_compat_authority", "1",
        { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
        "1 = standard ZCity ply.organism health with C:U as UI/minigames; 0 = C:U owns wounds", 0, 1)
end

function WSZC.OrganismAuthority()
    if SERVER then
        local cv = GetConVar and GetConVar("zc_woundsystem_compat_authority")
        if not (cv and cv.GetBool) then return true end
        return cv:GetBool() ~= false
    end
    -- FCVAR_REPLICATED convars are not reliably readable via GetConVar() on
    -- the client, so the server also publishes the effective mode as a global.
    return GetGlobalBool("WSZC_OrganismAuthority", true) == true
end

---------------------------------------------------------------------------
-- Amputation is NOT an arterial-bleeding alias
---------------------------------------------------------------------------
-- ZCity keeps org.<limb>amputated and org.arterialwounds as separate pieces
-- of state.  C:U's WoundView hides dismembered sprites and otherwise has only
-- the bleed icon, so the connector projects the amputation onto the remaining
-- proximal stump as its own status.  Statuses.GetActive() is consumed by the
-- native icon loop BEFORE its bleed icon: order -10000 therefore gives the
-- missing limb priority without changing, hiding or deleting the real artery.
WSZC.AMPUTATION_STATUS_ID = "WSZC_AMPUTATION"

function WSZC.InstallAmputationStatus()
    local statuses = WoundSystem and WoundSystem.Statuses
    if not (type(statuses) == "table" and type(statuses.Register) == "function") then
        return false
    end
    local id = WSZC.AMPUTATION_STATUS_ID
    if type(statuses.Stored) == "table" and statuses.Stored[id] then return true end
    statuses.Register(id, {
        title = "Amputation",
        desc = "The limb is severed. Arterial bleeding is a separate wound; apply a tourniquet to the stump.",
        icon = "casunknown-images/moodles/amputation.png",
        type = "bool",
        order = -10000,
        color = { 255, 116, 116 },
    })
    return true
end

---------------------------------------------------------------------------
-- Internal bleeding is a BODY condition, but the owner needs a visible mark
-- on the abdomen.  Project it into the native status list instead of painting
-- a second icon layer: C:U handles spread, tooltips, net sync and disappearing
-- statuses exactly as it does for fractures/infections.
---------------------------------------------------------------------------
WSZC.INTERNAL_BLEEDING_STATUS_ID = "WSZC_INTERNAL_BLEEDING"

function WSZC.InstallInternalBleedingStatus()
    local statuses = WoundSystem and WoundSystem.Statuses
    if not (type(statuses) == "table" and type(statuses.Register) == "function") then
        return false
    end
    local id = WSZC.INTERNAL_BLEEDING_STATUS_ID
    if type(statuses.Stored) == "table" and statuses.Stored[id] then return true end
    statuses.Register(id, {
        title = "Internal bleeding",
        desc = "There is internal bleeding in the abdomen. This is not an external limb bleed.",
        icon = "casunknown-images/moodles/internalbleed_red.png",
        type = "number",
        order = -9000,
        color = { 255, 255, 255 },
        networkDecimals = 2,
    })
    return true
end

-- Short-lived context flag: `Org Think "Main"`, the ZCity damage hook and the
-- ragdoll collision hook must see WB.IsBridged() == false so vanilla ZCity
-- runs.  Medical SWEPs and minigames run OUTSIDE those wrappers and keep
-- seeing true, which is what keeps the treatment minigames alive.
WSZC.VanillaContext = 0

function WSZC.InVanillaContext()
    return (WSZC.VanillaContext or 0) > 0
end

local function CUHealthEnabledOnServer()
    if not (WoundSystem and WoundSystem.Health) then return false end
    if type(WoundSystemHealthEnabled) == "function" and WoundSystemHealthEnabled() == false then
        return false
    end
    return WSZC.Ready == true and type(WoundSystem.Health.HandleDamage) == "function"
end

local function PatchIsEnabled()
    local WB = hg and hg.WoundBridge
    if not (WB and WB.cvBridge and WB.IsEnabled) then return false end
    if WB._WSZCIsEnabledPatched then return true end

    WB._WSZCIsEnabledPatched = true
    WB.IsEnabled = function()
        if not WB.cvBridge:GetBool() then return false end
        if not (WoundSystem and WoundSystem.Health) then return false end

        if SERVER then
            return CUHealthEnabledOnServer()
        end

        -- In organism-authority mode the CLIENT must see the bridge as OFF:
        -- ZCity's own pain vignette, screen effects, statistics HUD and movement
        -- multiplier are gated on WB.IsEnabled() and must stay stock.  C:U's HUD
        -- is gated on `woundsys_enabled` (left at 1) and opens on demand, so it
        -- still works.  The radial inspection button uses WSZC_Ready instead.
        if WSZC.OrganismAuthority() then return false end

        -- woundsys_enabled is replicated; keep the client HUD/radial decision in
        -- sync with the server when C:U is installed but switched off.
        local cvWounds = GetConVar and GetConVar("woundsys_enabled")
        if cvWounds and cvWounds.GetBool and not cvWounds:GetBool() then return false end

        -- SetGlobalBool is server-authoritative, so the client never guesses.
        return GetGlobalBool("WSZC_Ready", false) == true
    end

    return true
end

WSZC.PatchIsEnabled = PatchIsEnabled

---------------------------------------------------------------------------
-- WB.IsBridged() context switch (server only; the function is server-side)
--
-- In organism-authority mode ZCity's simulation hooks must NOT see a bridged
-- player (otherwise Org Think returns early, hits are forwarded to C:U and
-- glass collisions use the C:U impact model).  Medical SWEPs and minigames
-- run outside those hooks and DO need a bridged player, because the stock
-- ZCity StartMinigame callbacks check WB.IsBridged(target) before applying.
---------------------------------------------------------------------------

function WSZC.WithVanillaContext(fn, ...)
    WSZC.VanillaContext = (WSZC.VanillaContext or 0) + 1
    local a, b, c, d = pcall(fn, ...)
    WSZC.VanillaContext = WSZC.VanillaContext - 1
    if WSZC.VanillaContext < 0 then WSZC.VanillaContext = 0 end
    if not a then
        if WSZC.Warn then WSZC.Warn("vanilla hook failed: " .. tostring(b)) end
        return nil
    end
    return b, c, d
end

-- Weak identity set: functions cannot carry fields, and a Lua/ZCity reload may
-- install a brand-new genuine WB.IsBridged that must become the new `base`.
WSZC.BridgedWrappers = WSZC.BridgedWrappers or setmetatable({}, { __mode = "k" })

local function PatchIsBridged()
    if not SERVER then return false end
    local WB = hg and hg.WoundBridge
    if not (WB and WB.IsBridged and type(WB.IsBridged) == "function") then return false end

    local current = WB.IsBridged
    if WSZC.BridgedWrappers[current] then return true end -- already our wrapper

    WSZC.OriginalIsBridged = current -- always capture the CURRENT genuine impl
    local base = current
    local function wrapper(ply)
        if WSZC.OrganismAuthority() and WSZC.InVanillaContext() then return false end
        return base(ply)
    end
    WSZC.BridgedWrappers[wrapper] = true
    WSZC.IsBridgedWrapper = wrapper
    WB.IsBridged = wrapper
    WB._WSZCIsBridgedPatched = true
    return true
end

WSZC.PatchIsBridged = PatchIsBridged

local attempts = 0
local function RetryShared()
    attempts = attempts + 1
    local patched = PatchIsEnabled()
    local bridged = PatchIsBridged()
    if patched and (bridged or CLIENT) then return end
    if attempts < 40 then timer.Simple(0.25, RetryShared) end
end

if not WSZC._SharedRetryStarted then
    WSZC._SharedRetryStarted = true
    timer.Simple(0, RetryShared)
end
hook.Add("InitPostEntity", "WSZC_SharedInit", function()
    PatchIsEnabled()
    PatchIsBridged()
    if WSZC.InstallInternalBleedingStatus then WSZC.InstallInternalBleedingStatus() end
end)
