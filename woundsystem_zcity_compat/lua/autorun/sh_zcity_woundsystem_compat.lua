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

-- Connector diagnostics are private and opt-in per administrator.  Keep a
-- bounded history so early loader failures are available after enabling debug.
local TAG = "[ZCity/CU compat] "
WSZC.DebugHistory = WSZC.DebugHistory or {}
WSZC.DebugSubscribers = WSZC.DebugSubscribers or setmetatable({}, { __mode = "k" })
local DEBUG_LIMIT = 150
local DEBUG_NET = "WSZC_DebugControl"

local function IsDebugAdmin(ply)
    return IsValid and IsValid(ply) and ply.IsAdmin and ply:IsAdmin() == true
end

function WSZC.DebugAllowed(ply)
    if SERVER then
        if IsValid and IsValid(ply) then return IsDebugAdmin(ply) and WSZC.DebugSubscribers[ply] == true end
        return WSZC.DebugConsole == true
    end
    local localPly = LocalPlayer and LocalPlayer() or nil
    return WSZC.DebugClient == true and IsDebugAdmin(localPly)
end

function WSZC.DebugDisplay(ply, line)
    if not WSZC.DebugAllowed(ply) then return end
    if SERVER and IsValid and IsValid(ply) then
        if ply.PrintMessage then ply:PrintMessage(HUD_PRINTCONSOLE or 4, tostring(line) .. "\n") end
    else
        print(tostring(line))
    end
end

function WSZC.DebugRecord(msg)
    local line = TAG .. tostring(msg)
    local history = WSZC.DebugHistory
    history[#history + 1] = line
    if #history > DEBUG_LIMIT then table.remove(history, 1) end
    if SERVER then
        if WSZC.DebugConsole then WSZC.DebugDisplay(nil, line) end
        for ply in pairs(WSZC.DebugSubscribers) do
            if IsDebugAdmin(ply) then WSZC.DebugDisplay(ply, line)
            else WSZC.DebugSubscribers[ply] = nil end
        end
    elseif WSZC.DebugAllowed() then
        WSZC.DebugDisplay(nil, line)
    end
end

function WSZC.Debug(fmt, ...)
    local ok, msg = pcall(string.format, tostring(fmt), ...)
    WSZC.DebugRecord(ok and msg or tostring(fmt))
end
function WSZC.Log(msg) WSZC.DebugRecord(msg) end
function WSZC.Warn(msg) WSZC.DebugRecord("WARNING: " .. tostring(msg)) end

if SERVER and util and util.AddNetworkString then util.AddNetworkString(DEBUG_NET) end
if CLIENT and net and net.Receive then
    net.Receive(DEBUG_NET, function()
        local enabled = net.ReadBool()
        local ply = LocalPlayer and LocalPlayer() or nil
        WSZC.DebugClient = enabled == true and IsDebugAdmin(ply) or false
        if WSZC.DebugClient then
            WSZC.DebugDisplay(nil, TAG .. "client debug enabled")
            for _, line in ipairs(WSZC.DebugHistory) do WSZC.DebugDisplay(nil, line) end
        end
    end)
end

if SERVER and concommand and concommand.Add then
    -- Preserve an existing Lua `debug` command for every other subcommand.
    local commands = concommand.GetTable and concommand.GetTable() or nil
    local previous = commands and commands.debug or nil
    previous = type(previous) == "table" and (previous[1] or previous.callback) or previous
    concommand.Add("debug", function(ply, cmd, args, argstr)
        if not (args and string.lower(tostring(args[1] or "")) == "wscz") then
            if type(previous) == "function" then return previous(ply, cmd, args, argstr) end
            return
        end
        local valid = IsValid and IsValid(ply)
        if valid and not IsDebugAdmin(ply) then return end
        if valid then
            local enabled = not WSZC.DebugSubscribers[ply]
            WSZC.DebugSubscribers[ply] = enabled or nil
            if net and net.Start and net.WriteBool and net.Send then
                net.Start(DEBUG_NET); net.WriteBool(enabled); net.Send(ply)
            end
            if enabled then
                WSZC.DebugDisplay(ply, TAG .. "debug enabled; repeat debug wscz to disable")
                for _, line in ipairs(WSZC.DebugHistory) do WSZC.DebugDisplay(ply, line) end
            elseif ply.PrintMessage then
                ply:PrintMessage(HUD_PRINTCONSOLE or 4, TAG .. "debug disabled\n")
            end
        else
            WSZC.DebugConsole = not WSZC.DebugConsole
            if WSZC.DebugConsole then
                WSZC.DebugDisplay(nil, TAG .. "debug enabled; repeat debug wscz to disable")
                for _, line in ipairs(WSZC.DebugHistory) do WSZC.DebugDisplay(nil, line) end
            else
                print(TAG .. "debug disabled")
            end
        end
    end)
end

-- Load missing dependencies from the isolated embedded runtime.  External
-- Workshop/GitHub C:U and WoundBridge installations keep priority.  A loader
-- error is reported without aborting the connector's adaptive status/probe.
if SERVER and AddCSLuaFile then AddCSLuaFile("wszc_vendor/bootstrap.lua") end
if include then
    local ok, err = pcall(include, "wszc_vendor/bootstrap.lua")
    if not ok then WSZC.Warn("embedded bootstrap failed: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Adaptive compatibility / capability detection
---------------------------------------------------------------------------
-- There is no stable public API shared by every ZCity or C:U build.  Never
-- infer full compatibility from one globally named table: probe the complete
-- core contract, prefer a native modern API when it exists, and use the
-- legacy upvalue adapter only for a recognisable legacy damage/medical path.
-- Individual features can then fail closed without breaking the whole gamemode.
---------------------------------------------------------------------------
if SERVER and CreateConVar then
    if not ConVarExists or not ConVarExists("zc_woundsystem_compat_adaptive") then
        CreateConVar("zc_woundsystem_compat_adaptive", "1",
            { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
            "Probe ZCity/C:U capabilities and disable unsupported connector features instead of patching blindly", 0, 1)
    end
    if not ConVarExists or not ConVarExists("zc_woundsystem_compat_prefer_native_api") then
        CreateConVar("zc_woundsystem_compat_prefer_native_api", "1",
            { FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY },
            "Use a native C:U external-minigame API when available instead of replacing it", 0, 1)
    end
end

WSZC.Compatibility = WSZC.Compatibility or {
    capabilities = {}, failures = {}, notes = {}, profile = "waiting",
}
local Compatibility = WSZC.Compatibility
Compatibility.capabilities = Compatibility.capabilities or {}
Compatibility.failures = Compatibility.failures or {}
Compatibility.notes = Compatibility.notes or {}

local FEATURES = { "core", "inspection", "medicine", "external_minigames", "remote", "organism_extensions" }

local function ConVarFlag(name, fallback)
    local cv = GetConVar and GetConVar(name) or nil
    if cv and cv.GetBool then
        local ok, value = pcall(cv.GetBool, cv)
        if ok then return value ~= false end
    end
    return fallback ~= false
end

function WSZC.AdaptiveCompatibility()
    return ConVarFlag("zc_woundsystem_compat_adaptive", true)
end

function WSZC.PreferNativeAPI()
    return ConVarFlag("zc_woundsystem_compat_prefer_native_api", true)
end

function WSZC.HasNativeExternalMinigameAPI(H)
    if type(H) ~= "table" or type(H.StartExternalMinigame) ~= "function" then return false end
    -- Once our legacy adapter is installed its exported function must not be
    -- mistaken for a native API on the next probe or hot reload.
    if WSZC.StartExternalMinigameImpl
        and H.StartExternalMinigame == WSZC.StartExternalMinigameImpl then return false end
    return H._WSZCOwnsExternalMinigameAPI ~= true
end

local function LegacyDamageEntrypoint(H)
    if type(H and H.HandleDamage) == "function" then return true end
    if not (hook and hook.GetTable) then return false end
    local ok, hooks = pcall(hook.GetTable)
    local damage = ok and type(hooks) == "table" and hooks.EntityTakeDamage or nil
    return type(damage) == "table" and type(damage.WoundSystem_Damage) == "function"
end

local EMBEDDED_FUNCTION_REFS = {
    "SendCardioUpdate", "ProcessImpactDamage", "SendLimbUpdate", "GetBody",
    "TryCreateUnconsciousRagdoll", "GuessRagdollDamageLimb", "RagdollBoneNameToLimb",
    "BuildMedicalItemContext", "ApplyBandageProfile", "GetSyringeProfile",
    "ApplySyringeProfile", "CloseBandageSession", "CloseSyringeSession",
    "CloseShrapnelSession", "CloseDislocationSession", "CloseAedSession",
}

local function EmbeddedLegacyBridge(H)
    if type(H) ~= "table" or type(WoundSystem) ~= "table"
        or WoundSystem._WSZCEmbedded ~= true
        or type(H._WSZCReplaceUpvalue) ~= "function" then return false end
    local refs = H._WSZCBridgeRefs
    if type(refs) ~= "table" or refs.version ~= 1 then return false end
    for _, key in ipairs({ "Fn", "Const", "BodyState", "PlayerLimbs", "Sessions" }) do
        if type(refs[key]) ~= "table" then return false end
    end
    for _, key in ipairs(EMBEDDED_FUNCTION_REFS) do
        if type(refs[key]) ~= "function" then return false end
    end
    return true
end

--- Resolve C:U source files without letting the embedded copy shadow an
--- external Workshop/GitHub installation.  Once embedded runtime is selected,
--- its isolated namespace is preferred consistently on that realm.
function WSZC.ResolveCUPath(path)
    if type(WoundSystem) == "table" and WoundSystem._WSZCEmbedded == true then
        -- Server replication selects ONE runtime for both realms.  A client's
        -- file.Exists(..., LUA) may not see an AddCSLuaFile cache entry even
        -- though include() can load it; falling back to an external path here
        -- would silently mix two C:U namespaces and lose minigame modules.
        return "wszc_vendor/cu/" .. tostring(path)
    end
    return path
end

-- Most legacy C:U/WoundBridge contracts are server-only.  A client cannot
-- discover them from its own Lua realm (and some ZCity loaders accidentally
-- include parts of sv_ files there), so the server publishes the probed
-- contracts instead of letting every client guess a different adapter.
local SERVER_CAPABILITY_GLOBALS = {
    zcity_bridge = "WSZC_CapZCityBridge",
    cu_native_api = "WSZC_CapNativeAPI",
    cu_legacy_api = "WSZC_CapLegacyAPI",
    cu_embedded_bridge = "WSZC_CapEmbeddedBridge",
    cu_native_state = "WSZC_CapNativeState",
    cu_native_external = "WSZC_CapNativeExternal",
    debug_introspection = "WSZC_CapDebugIntrospection",
    zcity_medicine = "WSZC_CapZCityMedicine",
    zcity_minigames = "WSZC_CapZCityMinigames",
    zcity_organism = "WSZC_CapZCityOrganism",
    core = "WSZC_CapCore",
    medicine = "WSZC_CapMedicine",
    external_minigames = "WSZC_CapExternalMinigames",
    organism_extensions = "WSZC_CapOrganismExtensions",
}

local function PublishServerCapabilities(caps)
    if not SERVER or type(SetGlobalBool) ~= "function" then return end
    local published = Compatibility.publishedServerCaps or {}
    Compatibility.publishedServerCaps = published
    if published.known ~= true then
        SetGlobalBool("WSZC_CapabilitiesKnown", true)
        published.known = true
    end
    for key, globalName in pairs(SERVER_CAPABILITY_GLOBALS) do
        local value = caps[key] == true
        if published[key] ~= value then
            SetGlobalBool(globalName, value)
            published[key] = value
        end
    end
end

local function ApplyServerCapabilities(caps)
    if not CLIENT or type(GetGlobalBool) ~= "function"
        or not GetGlobalBool("WSZC_CapabilitiesKnown", false) then return false end
    for key, globalName in pairs(SERVER_CAPABILITY_GLOBALS) do
        caps[key] = GetGlobalBool(globalName, false) == true
    end
    -- Inspection and remote UI still require the actual client panel.  Other
    -- feature contracts above are authoritative server decisions.
    caps.inspection = caps.core and caps.cu_ui
    caps.remote = caps.inspection and (caps.cu_native_state or caps.cu_legacy_api)
    caps.external_minigames = caps.cu_native_external
        or (caps.external_minigames and caps.cu_minigame_files)
    return true
end

function WSZC.RefreshCapabilities()
    local WB = hg and hg.WoundBridge or nil
    local H = WoundSystem and WoundSystem.Health or nil
    local Items = WoundSystem and WoundSystem.Items or nil
    local hasDebug = type(debug) == "table"
        and type(debug.getupvalue) == "function" and type(debug.setupvalue) == "function"
    local nativeState = type(H) == "table" and type(H.GetBody) == "function"
        and type(H.GetLimbs) == "function"
    local nativeAPI = nativeState and type(H.HandleDamage) == "function"
        and type(H.ApplyItemToBody) == "function"
    local embeddedLegacy = EmbeddedLegacyBridge(H)
    local legacyAPI = type(H) == "table" and (hasDebug or embeddedLegacy)
        and type(WoundSystem and WoundSystem.UseMedicalItem) == "function"
        and LegacyDamageEntrypoint(H)
    local nativeExternal = WSZC.HasNativeExternalMinigameAPI(H)

    local minigameFiles = false
    if SERVER and not CLIENT and WoundSystem and WoundSystem._WSZCEmbedded == true then
        minigameFiles = true
    elseif file and file.Exists then
        local hpPath = WSZC.ResolveCUPath("woundsystem/client/minigames/sh_handphysics.lua")
        local clipPath = WSZC.ResolveCUPath("woundsystem/client/minigames/cl_clip.lua")
        minigameFiles = (file.Exists(hpPath, "LUA") or file.Exists("lua/" .. hpPath, "GAME"))
            and (file.Exists(clipPath, "LUA") or file.Exists("lua/" .. clipPath, "GAME"))
    else
        -- GMod always exposes file.Exists.  Headless/limited hosts can still
        -- use the legacy adapter; OptionalInclude remains the final guard.
        minigameFiles = legacyAPI
    end

    local cuUI = type(WoundSystem and WoundSystem.OpenHealthHUD) == "function"
        or type(WoundSystem and WoundSystem.ToggleHealthHUD) == "function"
    if not cuUI and SERVER and not CLIENT and type(H) == "table" then
        -- WoundSystem.OpenHealthHUD lives in client-only cl_health_gui.lua and
        -- is never included in the SERVER Lua state.  Probe the downloadable
        -- client UI script (or embedded bundle) so server-side WSZC.Supports("remote")
        -- and status reporting remain true on real Garry's Mod servers.
        if WoundSystem and WoundSystem._WSZCEmbedded == true then
            cuUI = true
        elseif file and file.Exists then
            local guiPath = WSZC.ResolveCUPath("woundsystem/client/cl_health_gui.lua")
            cuUI = file.Exists(guiPath, "LUA") == true
                or file.Exists("lua/" .. guiPath, "GAME") == true
        end
    end

    local caps = {
        zcity_bridge = type(WB) == "table" and type(WB.IsEnabled) == "function"
            and type(WB.IsBridged) == "function" and type(WB.ApplyDamage) == "function",
        cu_health = type(H) == "table",
        cu_items = type(Items) == "table" and type(Items.Get) == "function",
        cu_ui = cuUI == true,
        cu_native_api = nativeAPI == true,
        cu_legacy_api = legacyAPI == true,
        cu_embedded_bridge = embeddedLegacy == true,
        cu_native_state = nativeState == true,
        cu_native_external = nativeExternal == true,
        cu_minigame_files = minigameFiles == true,
        debug_introspection = hasDebug,
        zcity_medicine = type(WB) == "table" and type(WB.SwepHeal) == "function"
            and type(WB.GetPlayer) == "function",
        -- Supplied ZCity keeps StartMinigame as a local helper called by
        -- SwepHeal; it does not export WB.StartMinigame at all.
        zcity_minigames = type(WB) == "table" and (type(WB.SwepHeal) == "function"
            or type(WB.StartMinigame) == "function"),
        zcity_organism = type(WB) == "table" and type(WB.Sync) == "function"
            and type(WB.Think) == "function" and type(hg and hg.organism) == "table"
            and type(hg.organism.Clear) == "function",
    }
    caps.core = caps.zcity_bridge and caps.cu_health and caps.cu_items
        and (caps.cu_native_api or caps.cu_legacy_api)
    caps.inspection = caps.core and caps.cu_ui
    caps.medicine = caps.core and (caps.cu_native_api or caps.zcity_medicine)
    caps.external_minigames = caps.core and (caps.cu_native_external
        or (caps.zcity_minigames and caps.cu_minigame_files))
    caps.remote = (CLIENT and caps.inspection or caps.core)
        and (caps.cu_native_state or caps.cu_legacy_api)
    caps.organism_extensions = caps.core and caps.zcity_organism

    local usingServerCaps = ApplyServerCapabilities(caps)
    Compatibility.capabilities = caps
    Compatibility.serverCapsKnown = usingServerCaps
    Compatibility.nativeAPI = caps.cu_native_api == true
    Compatibility.legacyAPI = caps.cu_legacy_api == true
    Compatibility.nativeExternal = caps.cu_native_external == true
    Compatibility.lastProbe = CurTime and CurTime() or 0

    local reportedAdapter
    if usingServerCaps and type(GetGlobalString) == "function" then
        reportedAdapter = GetGlobalString("WSZC_ActiveAdapter", "")
    elseif SERVER and WSZC.Ready then
        reportedAdapter = Compatibility.activeAdapter
    end
    if caps.core then
        if reportedAdapter == "native-api" or reportedAdapter == "legacy-adapter" then
            Compatibility.profile = reportedAdapter
        else
            Compatibility.profile = caps.cu_native_api and "native-api" or "legacy-adapter"
        end
    elseif caps.zcity_bridge or caps.cu_health or caps.cu_items then
        Compatibility.profile = "partial"
    else
        Compatibility.profile = "unavailable"
    end
    PublishServerCapabilities(caps)
    return caps
end

function WSZC.Capability(name)
    return WSZC.RefreshCapabilities()[name] == true
end

function WSZC.Supports(feature)
    if not WSZC.AdaptiveCompatibility() then return true end
    local caps = WSZC.RefreshCapabilities()
    if Compatibility.failures.core or Compatibility.failures[feature] then return false end
    if feature ~= "core" and not caps.core then return false end
    return caps[feature] == true
end

function WSZC.MarkFeatureFailed(feature, reason)
    reason = tostring(reason or "unsupported API")
    Compatibility.failures[feature] = reason
    Compatibility.lastError = reason
    local noteKey = tostring(feature) .. ":" .. reason
    if Compatibility.notes[noteKey] then return end
    Compatibility.notes[noteKey] = true
    local msg = "feature '" .. tostring(feature) .. "' disabled: " .. reason
    WSZC.Warn(msg)
end

function WSZC.ClearCompatibilityFailures()
    Compatibility.failures = {}
    Compatibility.lastError = nil
    Compatibility.notes = {}
    WSZC._CompatibilityStatusReported = nil
    if not WSZC.Ready then Compatibility.activeAdapter = nil end
    return WSZC.RefreshCapabilities()
end

local function YesNo(value) return value and "yes" or "no" end

function WSZC.CompatibilityStatusLines()
    local caps = WSZC.RefreshCapabilities()
    local ready = WSZC.Ready == true
    local activeAdapter = Compatibility.activeAdapter
    if CLIENT then
        ready = type(GetGlobalBool) == "function" and GetGlobalBool("WSZC_Ready", false) == true
        if type(GetGlobalString) == "function" then
            local serverAdapter = GetGlobalString("WSZC_ActiveAdapter", "")
            if serverAdapter ~= "" then activeAdapter = serverAdapter end
        end
    end
    local hasCU = type(WoundSystem) == "table"
        and (type(WoundSystem.Health) == "table" or type(WoundSystem.Items) == "table")
    local cuRuntime = (type(WoundSystem) == "table" and WoundSystem._WSZCEmbedded == true) and "embedded"
        or (hasCU and "external" or "missing")
    local bridgeRuntime = (type(hg and hg.WoundBridge) == "table"
        and hg.WoundBridge._WSZCEmbedded == true) and "embedded"
        or (type(hg and hg.WoundBridge) == "table" and "external" or "missing")
    local lines = {
        TAG .. "adaptive compatibility: " .. tostring(Compatibility.profile)
            .. " realm=" .. (SERVER and "server" or "client"),
        "  ready=" .. YesNo(ready)
            .. " active_adapter=" .. tostring(activeAdapter or "none")
            .. " adaptive=" .. YesNo(WSZC.AdaptiveCompatibility()),
        "  runtime: cu=" .. cuRuntime .. " zcity_bridge=" .. bridgeRuntime,
        "  contracts: zcity_bridge=" .. YesNo(caps.zcity_bridge)
            .. " cu_health=" .. YesNo(caps.cu_health)
            .. " cu_items=" .. YesNo(caps.cu_items)
            .. " native_api=" .. YesNo(caps.cu_native_api)
            .. " legacy_api=" .. YesNo(caps.cu_legacy_api)
            .. " native_external=" .. YesNo(caps.cu_native_external)
            .. " debug=" .. YesNo(caps.debug_introspection)
            .. " embedded_bridge=" .. YesNo(caps.cu_embedded_bridge),
        "  optional contracts: zcity_medicine=" .. YesNo(caps.zcity_medicine)
            .. " zcity_minigames=" .. YesNo(caps.zcity_minigames)
            .. " zcity_organism=" .. YesNo(caps.zcity_organism)
            .. " cu_minigame_files=" .. YesNo(caps.cu_minigame_files),
    }
    if WSZC._EmbeddedCULoadError then
        lines[#lines + 1] = "  embedded_cu_error=" .. tostring(WSZC._EmbeddedCULoadError)
    end
    if WSZC._EmbeddedBridgeLoadError then
        lines[#lines + 1] = "  embedded_bridge_error=" .. tostring(WSZC._EmbeddedBridgeLoadError)
    end
    if SERVER and WSZC.DirectMedicalAdapterCount then
        lines[#lines + 1] = "  direct_medical_adapters=" .. tostring(WSZC.DirectMedicalAdapterCount)
    end
    if SERVER and WSZC.LastMedicalHealRoute then
        lines[#lines + 1] = "  last_medical_heal=" .. tostring(WSZC.LastMedicalHealRoute)
    end
    if SERVER and WSZC.LastMinigameStartResult then
        lines[#lines + 1] = "  last_minigame_start=" .. tostring(WSZC.LastMinigameStartResult)
    end
    for _, feature in ipairs(FEATURES) do
        local failed = Compatibility.failures[feature]
        local supported = caps[feature] == true and not Compatibility.failures.core and not failed
        lines[#lines + 1] = "  " .. feature .. "=" .. YesNo(supported)
            .. (failed and (" reason=" .. tostring(failed)) or "")
    end
    return lines
end

function WSZC.PrintCompatibilityStatus(ply)
    if not WSZC.DebugAllowed(ply) then return end
    for _, line in ipairs(WSZC.CompatibilityStatusLines()) do
        WSZC.DebugDisplay(ply, line)
    end
end

-- Optional C:U source files differ between builds.  Missing optional artwork
-- or hand physics must degrade locally, never abort the whole autorun file.
WSZC.OptionalIncludeStatus = WSZC.OptionalIncludeStatus or {}

function WSZC.OptionalInclude(path)
    path = WSZC.ResolveCUPath and WSZC.ResolveCUPath(path) or path
    local embedded = type(WoundSystem) == "table" and WoundSystem._WSZCEmbedded == true
    local exists
    if file and file.Exists then exists = file.Exists(path, "LUA") == true end
    -- Keep the cheap missing-file guard for unknown external addons.  For the
    -- selected embedded runtime, however, include() is authoritative: GMod's
    -- client LUA search may hide a server-downloaded cache entry from
    -- file.Exists even though the file is available to include().
    if exists == false and not embedded then
        WSZC.OptionalIncludeStatus[path] = { ok = false, exists = false, reason = "missing" }
        return nil, false
    end
    if not include then
        WSZC.OptionalIncludeStatus[path] = { ok = false, exists = exists, reason = "include unavailable" }
        return nil, false
    end
    local ok, result = pcall(include, path)
    WSZC.OptionalIncludeStatus[path] = {
        ok = ok, exists = exists, resultType = type(result),
        reason = not ok and tostring(result) or nil,
    }
    if ok then return result, true end
    if not Compatibility.notes["include:" .. path] then
        Compatibility.notes["include:" .. path] = true
        WSZC.Warn("optional module disabled: " .. tostring(path) .. " (" .. tostring(result) .. ")")
    end
    return nil, false
end

if concommand and concommand.Add then
    concommand.Add("wszc_compat_status", function(ply)
        WSZC.PrintCompatibilityStatus(ply)
    end)
    concommand.Add("wszc_compat_reprobe", function(ply)
        if not WSZC.DebugAllowed(ply) then return end
        if type(WSZC.EnsureEmbeddedRuntime) == "function" then
            local ok, err = pcall(WSZC.EnsureEmbeddedRuntime, true)
            if not ok then WSZC.Warn("embedded runtime reprobe failed: " .. tostring(err)) end
        end
        WSZC.ClearCompatibilityFailures()
        WSZC.SetupFailed = nil
        if SERVER and not WSZC.Ready and type(WSZC.Attempt) == "function" then
            local ok, err = pcall(WSZC.Attempt)
            if not ok then WSZC.MarkFeatureFailed("core", err) end
        end
        WSZC.PrintCompatibilityStatus(ply)
    end)
    -- A dedicated server exports same-named Lua server commands to clients;
    -- they can shadow the shared status command and print realm=server even
    -- when the client runtime is healthy.  This client-only name cannot be
    -- intercepted by that forwarding rule.
    if CLIENT then
        concommand.Add("wszc_compat_client_status", function()
            if not WSZC.DebugAllowed() then return end
            WSZC.PrintCompatibilityStatus()
            if type(WSZC.PrintMinigameClientStatus) == "function" then
                WSZC.PrintMinigameClientStatus()
            end
        end)
    end
end

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

-- While the connector is active, ZCity's chance-based radial medicine is not
-- a second treatment authority.  The C:U/WoundView action opens the native
-- reduction minigame instead.  Both the client option filter and the server
-- command/bridge wrappers use this same readiness predicate.
function WSZC.LegacyRadialMedicineBlocked()
    if SERVER then return WSZC.Ready == true end
    return GetGlobalBool and GetGlobalBool("WSZC_Ready", false) == true or false
end

-- Native C:U predicts bone motion on the client and then simulates it again on
-- the server.  Those positions can diverge, so a socket that looks perfectly
-- aligned can still be rejected by the server's copy.  This predicate uses the
-- SAME finish point/tolerance as native C:U, but is evaluated on the rendered
-- position and then revalidated by the server before committing the reduction.
function WSZC.DislocationVisualAligned(x, y)
    x, y = tonumber(x), tonumber(y)
    if not (x and y) or x ~= x or y ~= y
        or x == math.huge or x == -math.huge
        or y == math.huge or y == -math.huge then return false end
    local constants = WoundSystem and WoundSystem.Health
        and WoundSystem.Health.Constants or nil
    local finishX = constants and tonumber(constants.DislocationFinishX) or 421.82
    local finishY = constants and tonumber(constants.DislocationFinishY) or 229.82
    local successTimer = constants and tonumber(constants.DislocationSuccessTimer) or 3
    local dx, dy = x - finishX, y - finishY
    return math.sqrt(dx * dx + dy * dy) * 0.2 < math.max(successTimer, 0.001)
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
    local existing = type(statuses.Stored) == "table" and statuses.Stored[id] or nil
    if existing then
        existing.icon = ""
        return true
    end
    statuses.Register(id, {
        title = "Amputation",
        desc = "The limb is severed. Arterial bleeding is a separate wound; apply a tourniquet to the stump.",
        icon = "",
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

-- Distinct critical status reserved for a real ZCity arterial wound, shown
-- alongside ordinary C:U bleeding icons so arterial vs ordinary bleeding stay
-- visually distinct.  Only a tourniquet closes the represented arterial wound.
WSZC.ARTERIAL_BLEEDING_STATUS_ID = "WSZC_ARTERIAL_BLEEDING"

function WSZC.InstallArterialBleedingStatus()
    local statuses = WoundSystem and WoundSystem.Statuses
    if not (type(statuses) == "table" and type(statuses.Register) == "function") then
        return false
    end
    local id = WSZC.ARTERIAL_BLEEDING_STATUS_ID
    local existing = type(statuses.Stored) == "table" and statuses.Stored[id] or nil
    if existing then
        existing.icon = "wszc/unitmenu/status/arterial.png"
        existing.color = { 255, 255, 255 }
        return true
    end
    statuses.Register(id, {
        title = "Arterial bleeding",
        desc = "An artery is open. Apply a tourniquet; an ordinary bandage cannot close it.",
        icon = "wszc/unitmenu/status/arterial.png",
        type = "number",
        order = -8000,
        color = { 255, 255, 255 },
        networkDecimals = 2,
    })
    return true
end

-- Internal ZCity fracture-immobilization marker (distinct from C:U's
-- removable SPLINTED status).  It has no icon in WoundView.
WSZC.FRACTURE_BANDAGED_STATUS_ID = "WSZC_FRACTURE_BANDAGED"

function WSZC.InstallFractureBandagedStatus()
    local statuses = WoundSystem and WoundSystem.Statuses
    if not (type(statuses) == "table" and type(statuses.Register) == "function") then
        return false
    end
    local id = WSZC.FRACTURE_BANDAGED_STATUS_ID
    local existing = type(statuses.Stored) == "table" and statuses.Stored[id] or nil
    if existing then
        existing.icon = ""
        return true
    end
    statuses.Register(id, {
        title = "Fracture immobilized",
        desc = "The fracture is tightly bandaged and knitting by ZCity physiology.",
        icon = "",
        type = "bool",
        order = -7500,
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
    if WSZC.Supports and not WSZC.Supports("core") then return false end
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
    if WSZC.Supports and not WSZC.Supports("core") then return false end
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
    if WSZC.InstallArterialBleedingStatus then WSZC.InstallArterialBleedingStatus() end
end)
