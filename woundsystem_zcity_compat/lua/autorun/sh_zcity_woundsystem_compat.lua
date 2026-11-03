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

        -- SetGlobalBool is server-authoritative, so the client never guesses.
        return GetGlobalBool("WSZC_Ready", false) == true
    end

    return true
end

WSZC.PatchIsEnabled = PatchIsEnabled

local attempts = 0
local function RetryShared()
    attempts = attempts + 1
    if PatchIsEnabled() then return end
    if attempts < 40 then timer.Simple(0.25, RetryShared) end
end

if not WSZC._SharedRetryStarted then
    WSZC._SharedRetryStarted = true
    timer.Simple(0, RetryShared)
end
hook.Add("InitPostEntity", "WSZC_SharedInit", PatchIsEnabled)
