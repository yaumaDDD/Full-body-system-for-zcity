-- Portable ZCity/C:U runtime bootstrap.
--
-- External addons always win.  The embedded copies are isolated under
-- wszc_vendor/ and load only when their public API is absent.  A late pass
-- covers external autorun files that exist but have not initialized yet.

WSZC = WSZC or {}
if WSZC._EmbeddedBootstrapLoaded then return end
WSZC._EmbeddedBootstrapLoaded = true

local CU_EXTERNAL = "autorun/sh_health_init.lua"
local CU_LOADER = "wszc_vendor/cu/autorun/sh_health_init.lua"
local CU_WEATHER = "wszc_vendor/cu/autorun/server/sv_woundsys_weather_compat.lua"
local BRIDGE_EXTERNAL = "homigrad/woundbridge/sh_woundbridge.lua"
local BRIDGE_SHARED = "wszc_vendor/zcity/woundbridge/sh_woundbridge.lua"
local BRIDGE_SERVER = "wszc_vendor/zcity/woundbridge/sv_woundbridge.lua"
local BRIDGE_CLIENT = "wszc_vendor/zcity/woundbridge/cl_woundbridge.lua"
local PREFIX = "[ZCity/CU compat] "

local function Exists(path)
    return type(file) == "table" and type(file.Exists) == "function"
        and file.Exists(path, "LUA") == true
end

local function HasCU()
    return type(WoundSystem) == "table"
        and (type(WoundSystem.Health) == "table" or type(WoundSystem.Items) == "table")
end

local function HasBridge()
    return type(hg) == "table" and type(hg.WoundBridge) == "table"
end

local function EmbeddedCU()
    return type(WoundSystem) == "table" and WoundSystem._WSZCEmbedded == true
end

local function EmbeddedBridge()
    return HasBridge() and hg.WoundBridge._WSZCEmbedded == true
end

local function AddClient(path)
    if SERVER and type(AddCSLuaFile) == "function" then AddCSLuaFile(path) end
end

local function PublishSource()
    if not SERVER or type(SetGlobalBool) ~= "function" then return end
    if HasCU() or WSZC._EmbeddedCUAttempted then
        SetGlobalBool("WSZC_CUSourceKnown", true)
        SetGlobalBool("WSZC_CUEmbedded", EmbeddedCU())
    end
    if HasBridge() or WSZC._EmbeddedBridgeAttempted then
        SetGlobalBool("WSZC_BridgeSourceKnown", true)
        SetGlobalBool("WSZC_BridgeEmbedded", EmbeddedBridge())
    end
end

local function ServerAllows(kind)
    if SERVER or type(GetGlobalBool) ~= "function" then return nil end
    if kind == "cu" and GetGlobalBool("WSZC_CUSourceKnown", false) then
        return GetGlobalBool("WSZC_CUEmbedded", false)
    end
    if kind == "bridge" and GetGlobalBool("WSZC_BridgeSourceKnown", false) then
        return GetGlobalBool("WSZC_BridgeEmbedded", false)
    end
    return nil
end

local function LoadCU()
    if WSZC._EmbeddedCUAttempted or HasCU() then return false end
    WSZC._EmbeddedCUAttempted = true
    WoundSystem = WoundSystem or {}
    WoundSystem._WSZCEmbedded = true
    AddClient(CU_LOADER)

    local ok, err = true, nil
    if type(include) == "function" then
        ok, err = pcall(include, CU_LOADER)
        if ok and SERVER and Exists(CU_WEATHER) then
            local weatherOK, weatherErr = pcall(include, CU_WEATHER)
            if not weatherOK then
                print(PREFIX .. "embedded C:U weather compatibility disabled: " .. tostring(weatherErr))
            end
        end
    else
        ok, err = false, "include() unavailable"
    end
    WSZC._EmbeddedCULoadError = not ok and tostring(err) or nil
    WSZC._EmbeddedCULoaded = HasCU()
    if not ok then
        print(PREFIX .. "embedded C:U loader failed: " .. tostring(err))
    elseif WSZC._EmbeddedCULoaded then
        print(PREFIX .. "embedded C:U runtime active")
    end
    return WSZC._EmbeddedCULoaded
end

local function LoadBridge()
    if WSZC._EmbeddedBridgeAttempted or HasBridge() then return false end
    WSZC._EmbeddedBridgeAttempted = true
    hg = hg or {}
    hg.WoundBridge = hg.WoundBridge or {}
    hg.WoundBridge._WSZCEmbedded = true
    AddClient(BRIDGE_SHARED)
    AddClient(BRIDGE_CLIENT)

    local ok, err = true, nil
    if type(include) == "function" then
        ok, err = pcall(include, BRIDGE_SHARED)
        if ok then
            ok, err = pcall(include, SERVER and BRIDGE_SERVER or BRIDGE_CLIENT)
        end
    else
        ok, err = false, "include() unavailable"
    end
    WSZC._EmbeddedBridgeLoadError = not ok and tostring(err) or nil
    WSZC._EmbeddedBridgeLoaded = HasBridge()
        and type(hg.WoundBridge.IsEnabled) == "function"
        and type(hg.WoundBridge.ApplyDamage) == "function"
    if not ok then
        print(PREFIX .. "embedded ZCity WoundBridge loader failed: " .. tostring(err))
    elseif WSZC._EmbeddedBridgeLoaded then
        print(PREFIX .. "embedded ZCity WoundBridge active")
    end
    return WSZC._EmbeddedBridgeLoaded
end

local function FallbackAllowed(kind, lateFallback, externalPath)
    local allowed = ServerAllows(kind)
    if allowed == false then return false end
    -- On a real dedicated client, an unknown replicated decision means wait.
    -- Loading embedded merely because the server decision is late could mix
    -- an external server runtime with an embedded client runtime.
    if CLIENT and allowed == nil and type(GetGlobalBool) == "function" then
        return false
    end
    return lateFallback == true or not Exists(externalPath)
end

function WSZC.EnsureEmbeddedRuntime(lateFallback)
    if not HasCU() and not WSZC._EmbeddedCUAttempted
        and FallbackAllowed("cu", lateFallback, CU_EXTERNAL) then
        LoadCU()
    end

    if not HasBridge() and not WSZC._EmbeddedBridgeAttempted
        and FallbackAllowed("bridge", lateFallback, BRIDGE_EXTERNAL) then
        LoadBridge()
    end

    PublishSource()
    return HasCU(), HasBridge()
end

-- Server initializes immediately when no external loader is visible.  Clients
-- wait for the server's source decision, preventing a dedicated server and its
-- clients from selecting different C:U implementations.
if SERVER then WSZC.EnsureEmbeddedRuntime(false) end
if type(timer) == "table" and type(timer.Simple) == "function" then
    timer.Simple(SERVER and 0.5 or 1, function()
        WSZC.EnsureEmbeddedRuntime(true)
    end)
elseif CLIENT then
    WSZC.EnsureEmbeddedRuntime(true)
end
