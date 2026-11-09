#!/usr/bin/env python3
"""Adaptive ZCity/C:U capability-detection regressions.

The runtime loads the shipped shared module and the real server minigame
implementation, then simulates legacy, native, partial and missing APIs.
No check in this suite is evidence of a live two-client GMod acceptance test.
"""
from pathlib import Path
from zipfile import ZipFile
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / "woundsystem_zcity_compat"
SHARED = CONN / "lua/autorun/sh_zcity_woundsystem_compat.lua"
SERVER = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat.lua"
MINIGAMES = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua"
INSPECT = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_inspect.lua"
REMOTE = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_remote.lua"
ORGANISM = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua"
BANDAGE = CONN / "lua/autorun/client/wszc_cl_bandage.lua"
SYRINGE = CONN / "lua/autorun/client/wszc_cl_syringe.lua"
BOOTSTRAP = CONN / "lua/wszc_vendor/bootstrap.lua"
BUILD = ROOT / "tools/build_packs.py"

results = []


def check(name, value):
    results.append((name, bool(value)))
    print(("PASS " if value else "FAIL ") + name)


def runtime_check(name, fn):
    try:
        check(name, fn())
    except Exception as exc:
        print("ERR", name, type(exc).__name__, str(exc)[:300])
        results.append((name, False))


shared_s = SHARED.read_text(encoding="utf-8")
server_s = SERVER.read_text(encoding="utf-8")
mg_s = MINIGAMES.read_text(encoding="utf-8")
inspect_s = INSPECT.read_text(encoding="utf-8")
remote_s = REMOTE.read_text(encoding="utf-8")
organism_s = ORGANISM.read_text(encoding="utf-8")
bandage_s = BANDAGE.read_text(encoding="utf-8")
syringe_s = SYRINGE.read_text(encoding="utf-8")
bootstrap_s = BOOTSTRAP.read_text(encoding="utf-8")

check("S01 shared layer probes complete native/legacy contracts and independent features",
      "function WSZC.RefreshCapabilities()" in shared_s
      and "cu_native_api" in shared_s and "cu_legacy_api" in shared_s
      and "external_minigames" in shared_s and "organism_extensions" in shared_s
      and "function WSZC.Supports(feature)" in shared_s)
check("S02 server setup fails closed and latches setup errors until reprobe",
      "and caps and not caps.core then return false end" in server_s
      and "WSZC.SetupFailed = tostring(ready)" in server_s
      and 'MarkFeatureFailed("core", "setup error: "' in server_s
      and 'Compatibility.activeAdapter = "legacy-adapter"' in server_s
      and 'Compatibility.activeAdapter = "native-api"' in server_s)
check("S03 a complete native external API is preserved instead of replaced",
      "caps.cu_native_api and WSZC.HasNativeExternalMinigameAPI(H)" in mg_s
      and 'WSZC.ExternalMinigameMode = "native"' in mg_s
      and "H._WSZCOwnsExternalMinigameAPI = true" in mg_s)
check("S04 private C:U minigame includes are optional with local fallbacks",
      'local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")' not in bandage_s
      and 'local HandPhysics = include("woundsystem/client/minigames/sh_handphysics.lua")' not in syringe_s
      and "OptionalInclude" in bandage_s and "OptionalInclude" in syringe_s
      and "if not istable(HandPhysics) then" in syringe_s)
check("S05 inspection, remote and organism extensions have independent capability gates",
      'WSZC.Supports("inspection")' in inspect_s
      and 'WSZC.Supports("remote")' in remote_s
      and 'WSZC.Supports("organism_extensions")' in organism_s)
radial_hook = inspect_s.split('hook.Add("radialOptions", "ZCity_WoundBridge_Inspect_WSZC"', 1)[1]
check("S06 unsupported core cannot install inspection or bridge wrappers",
      radial_hook.index("if not CompatInspectEnabled()") < radial_hook.index("EnsureBridgeWrapper()")
      and 'if WSZC.Supports and not WSZC.Supports("core") then return false end' in shared_s)
check("S07 early organism damage/ragdoll hooks stay inert before supported readiness",
      "local function OrganismHooksActive()" in organism_s
      and "if WSZC.Ready ~= true then return false end" in organism_s
      and organism_s.count("OrganismHooksActive()") >= 5)

# The standalone connector must own every non-code payload required by its UI.
resource_prefix = "casualties_unknown_health_system_beta/"
with ZipFile(ROOT / "casualites unknown.zip") as original_cu:
    relocated = sorted(
        name[len(resource_prefix):] for name in original_cu.namelist()
        if name.startswith(resource_prefix + "resource/fonts/")
        or name.startswith(resource_prefix + "shaders/fxc/")
    )
    relocated_bytes_ok = len(relocated) == 6 and all(
        (CONN / rel).is_file()
        and (CONN / rel).read_bytes() == original_cu.read(resource_prefix + rel)
        for rel in relocated
    )
required_resource_roots = [
    "materials/casunknown-images",
    "materials/homigrad/bleedanim", "materials/homigrad/handanim",
    "materials/homigrad/limbs", "materials/smiley", "materials/traits",
    "materials/woundsystem", "materials/wszc", "materials/zcity_delta/other",
    "materials/zcity_delta/unitmenu", "materials/zcity_delta_moodles",
]
source_resources = [
    path.relative_to(CONN).as_posix()
    for path in (CONN / "materials").rglob("*") if path.is_file()
] + relocated
resources_covered = all(
    rel in relocated or any(rel.startswith(root + "/") for root in required_resource_roots)
    for rel in source_resources
)
build_s = BUILD.read_text(encoding="utf-8")
check("S08 connector owns byte-identical C:U fonts/shaders and scans every material root",
      relocated_bytes_ok and resources_covered and len(source_resources) == 659
      and all(('"' + root + '"') in server_s for root in required_resource_roots)
      and all(('"' + rel + '"') in server_s for rel in relocated)
      and "CU_RELOCATED" in build_s
      and "len(fonts) == 3" in build_s and "len(shaders) == 3" in build_s)

connector_zip = ROOT / "woundsystem_zcity_compat.zip"
full_zip = ROOT / "zcity_full_pack.zip"
with ZipFile(connector_zip) as packed, ZipFile(full_zip) as full:
    connector_names = {info.filename for info in packed.infolist()}
    full_names = {info.filename for info in full.infolist()}
    full_prefix = "garrysmod/addons/woundsystem_zcity_compat/"
    old_cu_prefix = "garrysmod/addons/casualties_unknown_health_system_beta/"
    packaged_relocated_ok = all(
        "woundsystem_zcity_compat/" + rel in connector_names
        and packed.read("woundsystem_zcity_compat/" + rel) == (CONN / rel).read_bytes()
        and full.read(full_prefix + rel) == (CONN / rel).read_bytes()
        and not any(name.startswith(old_cu_prefix + rel) for name in full_names)
        for rel in relocated
    )
    source_count = sum(1 for path in CONN.rglob("*") if path.is_file() and "__pycache__" not in path.parts)
    check("S09 rebuilt ZIPs contain one physical copy of relocated C:U resources",
          packaged_relocated_ok and len(connector_names) == source_count == 753
          and len(full_names) == 2856)

vendor_check = subprocess.run(
    [sys.executable, str(ROOT / "tools/embed_runtime.py"), "--check"],
    cwd=ROOT, capture_output=True, text=True,
)
embedded_health_s = (CONN / "lua/wszc_vendor/cu/woundsystem/server/sv_health.lua").read_text(encoding="utf-8")
embedded_bridge_s = (CONN / "lua/wszc_vendor/zcity/woundbridge/sv_woundbridge.lua").read_text(encoding="utf-8")
embedded_ref_names = (
    "Fn", "Const", "SendCardioUpdate", "ProcessImpactDamage", "SendLimbUpdate",
    "BodyState", "PlayerLimbs", "GetBody", "TryCreateUnconsciousRagdoll",
    "GuessRagdollDamageLimb", "RagdollBoneNameToLimb", "BuildMedicalItemContext",
    "ApplyBandageProfile", "GetSyringeProfile", "ApplySyringeProfile", "Sessions",
    "CloseBandageSession", "CloseSyringeSession", "CloseShrapnelSession",
    "CloseDislocationSession", "CloseAedSession",
)
embedded_contract_ok = all(f"{name} = {name}," in embedded_health_s for name in embedded_ref_names) \
    and "function WoundSystem.Health._WSZCReplaceUpvalue" in embedded_health_s \
    and "WB._WSZCBridgeRefs = { version = 1, BestLimb = BestLimb }" in embedded_bridge_s \
    and "function WB._WSZCReplaceBestLimb" in embedded_bridge_s \
    and "_WSZCSetAppliedLive = function(value)" in embedded_bridge_s \
    and all(f"{name} = {name}," in embedded_bridge_s
            for name in ("swep", "idx", "spec", "target", "maxDur", "live", "oneDose"))
check("S10 isolated embedded C:U/WoundBridge matches the supplied sources and path resolver",
      vendor_check.returncode == 0 and "cu=71 bridge=3" in vendor_check.stdout
      and embedded_contract_ok
      and 'pcall(include, "wszc_vendor/bootstrap.lua")' in shared_s
      and "function WSZC.ResolveCUPath(path)" in shared_s
      and "runtime: cu=" in shared_s
      and "_WSZCEmbeddedLoaderRan" in (CONN /
          "lua/wszc_vendor/cu/autorun/sh_health_init.lua").read_text(encoding="utf-8"))

try:
    sys.path.insert(0, "/tmp/lupa_pkg")
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print("SKIP runtime capability checks (lupa unavailable)")
else:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
SERVER = true
CLIENT = false
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 1, 2, 4
HUD_PRINTCONSOLE = 4
LOGS = {}
CVARS = {}
GLOBALS = {}
COMMANDS = {}
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(parts, " ")
end
function ErrorNoHalt(msg) LOGS[#LOGS + 1] = tostring(msg) end
function CreateConVar(name, default)
    local cv = { value = default }
    cv.GetBool = function(self) return self.value ~= "0" and self.value ~= 0 and self.value ~= false end
    cv.GetFloat = function(self) return tonumber(self.value) or 0 end
    cv.GetString = function(self) return tostring(self.value) end
    CVARS[name] = cv
    return cv
end
function ConVarExists(name) return CVARS[name] ~= nil end
function GetConVar(name) return CVARS[name] end
function SetGlobalBool(name, value) GLOBALS[name] = value and true or false end
function GetGlobalBool(name, fallback)
    if GLOBALS[name] == nil then return fallback end
    return GLOBALS[name]
end
function CurTime() return 100 end
hook = { _t = {} }
function hook.Add(event, name, fn)
    hook._t[event] = hook._t[event] or {}
    hook._t[event][name] = fn
end
function hook.Remove(event, name)
    if hook._t[event] then hook._t[event][name] = nil end
end
function hook.GetTable() return hook._t end
concommand = { Add = function(name, fn) COMMANDS[name] = fn end }
timer = { Simple = function() end, Create = function() end, Exists = function() return false end,
    Remove = function() end }
net = { Receivers = {}, Receive = function(name, fn) net.Receivers[name] = fn end,
    Start = function() end, Send = function() end, Broadcast = function() end,
    WriteUInt = function() end, WriteString = function() end, WriteEntity = function() end,
    WriteType = function() end, WriteBool = function() end, WriteFloat = function() end,
    ReadUInt = function() return 0 end, ReadString = function() return "" end,
    ReadEntity = function() return NULL end, ReadType = function() return nil end,
    ReadBool = function() return false end, ReadFloat = function() return 0 end }
util = { AddNetworkString = function() end }
file = { Exists = function() return true end }
includeCalls = 0
include = function() includeCalls = includeCalls + 1; return {} end
function IsValid(value) return value ~= nil and value ~= false and value ~= NULL end
NULL = {}
player = { GetAll = function() return {} end }
ents = { Create = function() return NULL end }
Vector = function() return {} end
Angle = function() return {} end
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function ResetEnvironment()
    WSZC.ClearCompatibilityFailures()
    WSZC.Ready = nil
    WSZC.SetupFailed = nil
    WSZC.ExternalMinigameMode = nil
    WoundSystem = nil
    hg = nil
    debug = nil
    hook._t = {}
    file.Exists = function() return true end
    CVARS.zc_woundsystem_compat_adaptive.value = "1"
    CVARS.zc_woundsystem_compat_prefer_native_api.value = "1"
end
function InstallLegacyContract()
    hg = { organism = { Clear = function() end }, WoundBridge = {
        IsEnabled = function() return true end,
        IsBridged = function() return true end,
        ApplyDamage = function() end,
        SwepHeal = function() return true end,
        GetPlayer = function(ent) return ent end,
        StartMinigame = function() end,
        Sync = function() end,
        Think = function() end,
    } }
    WoundSystem = {
        Health = {}, Items = { Get = function() return nil end },
        OpenHealthHUD = function() end,
        UseMedicalItem = function() end,
    }
    debug = { getupvalue = function() return nil end, setupvalue = function() return nil end }
    hook._t.EntityTakeDamage = { WoundSystem_Damage = function() end }
end
function InstallNativeContract()
    InstallLegacyContract()
    debug = nil
    WoundSystem.UseMedicalItem = nil
    hook._t = {}
    local H = WoundSystem.Health
    H.GetBody = function() return {} end
    H.GetLimbs = function() return {} end
    H.HandleDamage = function() end
    H.ApplyItemToBody = function() return true end
    H.StartExternalMinigame = function() return "native" end
    H.StopExternalMinigame = function() end
end
''')
    lua.execute(shared_s)
    lua.execute(mg_s)
    lua.globals().SHARED_SOURCE = shared_s
    lua.globals().CLIENT_MINIGAMES_SOURCE = (
        CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua"
    ).read_text(encoding="utf-8")

    def embedded_runtime(server=True, initial=""):
        runtime = LuaRuntime(unpack_returned_tuples=True)
        runtime.globals().SERVER = server
        runtime.globals().CLIENT = not server
        runtime.execute(r'''
INCLUDES, CLIENT_FILES, EXTERNALS, GLOBALS, LOGS = {}, {}, {}, {}, {}
file = { Exists = function(path, searchPath) return EXTERNALS[path] == true end }
timer = { Simple = function(_, fn) LATE = fn end }
function AddCSLuaFile(path) CLIENT_FILES[#CLIENT_FILES + 1] = path end
function SetGlobalBool(name, value) GLOBALS[name] = value and true or false end
function GetGlobalBool(name, fallback)
    if GLOBALS[name] == nil then return fallback end
    return GLOBALS[name]
end
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    LOGS[#LOGS + 1] = table.concat(parts, " ")
end
include = function(path)
    INCLUDES[#INCLUDES + 1] = path
    if path == "wszc_vendor/cu/autorun/sh_health_init.lua" then
        EXTERNALS["wszc_vendor/cu/autorun/server/sv_woundsys_weather_compat.lua"] = true
        WoundSystem = WoundSystem or {}
        WoundSystem.Health = WoundSystem.Health or {}
        WoundSystem.Items = WoundSystem.Items or { Get = function() return nil end }
    elseif path == "wszc_vendor/zcity/woundbridge/sh_woundbridge.lua" then
        hg = hg or {}
        hg.WoundBridge = hg.WoundBridge or {}
        hg.WoundBridge.IsEnabled = function() return true end
        hg.WoundBridge.ApplyDamage = function() return true end
    end
    return {}
end
''')
        if initial:
            runtime.execute(initial)
        runtime.execute(bootstrap_s)
        return runtime

    runtime_check("R01 completely missing ZCity/C:U stays inactive without throwing", lambda: lua.execute(r'''
ResetEnvironment()
local caps = WSZC.RefreshCapabilities()
return not caps.core and not caps.remote and WSZC.Compatibility.profile == "unavailable"
    and not WSZC.Supports("core") and not WSZC.Supports("inspection")
'''))

    runtime_check("R02 the supplied legacy build keeps every connector feature available", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
local caps = WSZC.RefreshCapabilities()
return caps.core and caps.cu_legacy_api and not caps.cu_native_api
    and WSZC.Compatibility.profile == "legacy-adapter"
    and WSZC.Supports("inspection") and WSZC.Supports("medicine")
    and WSZC.Supports("external_minigames") and WSZC.Supports("remote")
    and WSZC.Supports("organism_extensions")
'''))

    runtime_check("R03 a modern native C:U API needs no debug introspection", lambda: lua.execute(r'''
ResetEnvironment(); InstallNativeContract()
local caps = WSZC.RefreshCapabilities()
return caps.core and caps.cu_native_api and not caps.cu_legacy_api
    and caps.cu_native_external and WSZC.Compatibility.profile == "native-api"
    and WSZC.Supports("external_minigames") and WSZC.Supports("remote")
'''))

    runtime_check("R04 similarly named but partial C:U tables are not a compatible core", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
debug = nil
WoundSystem.UseMedicalItem = nil
hook._t = {}
local caps = WSZC.RefreshCapabilities()
return not caps.core and not caps.cu_native_api and not caps.cu_legacy_api
    and WSZC.Compatibility.profile == "partial" and not WSZC.Supports("medicine")
'''))

    runtime_check("R05 legacy mode is rejected when debug upvalue mutation is unavailable", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract(); debug = nil
local caps = WSZC.RefreshCapabilities()
return caps.cu_health and not caps.cu_legacy_api and not caps.core
'''))

    runtime_check("R06 C:U alone cannot activate the connector without ZCity WoundBridge", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract(); hg = nil
return not WSZC.RefreshCapabilities().core and not WSZC.Supports("remote")
'''))

    runtime_check("R07 a setup failure latches off and an explicit reprobe can recover", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
WSZC.MarkFeatureFailed("core", "test mismatch")
local disabled = not WSZC.Supports("core") and not WSZC.Supports("medicine")
WSZC.SetupFailed = "test mismatch"
WSZC.ClearCompatibilityFailures(); WSZC.SetupFailed = nil
return disabled and WSZC.Supports("core") and WSZC.Supports("medicine")
'''))

    runtime_check("R08 the connector's own exported minigame is not misdetected as native", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
WoundSystem.Health.StartExternalMinigame = WSZC.StartExternalMinigameImpl
return not WSZC.HasNativeExternalMinigameAPI(WoundSystem.Health)
    and not WSZC.RefreshCapabilities().cu_native_external
'''))

    runtime_check("R09 status/reprobe commands expose profile, features and failure reasons", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract(); WSZC.MarkFeatureFailed("remote", "missing test state")
WSZC._EmbeddedCULoadError = "test load error"
local lines = WSZC.CompatibilityStatusLines()
local text = table.concat(lines, "\n")
local ok = type(COMMANDS.wszc_compat_status) == "function"
    and type(COMMANDS.wszc_compat_reprobe) == "function"
    and string.find(text, "legacy-adapter", 1, true) ~= nil
    and string.find(text, "remote=no", 1, true) ~= nil
    and string.find(text, "missing test state", 1, true) ~= nil
    and string.find(text, "embedded_cu_error=test load error", 1, true) ~= nil
WSZC._EmbeddedCULoadError = nil
return ok
'''))

    runtime_check("R10 missing or broken optional includes degrade without a Lua exception", lambda: lua.execute(r'''
ResetEnvironment()
includeCalls = 0
file.Exists = function() return false end
include = function() includeCalls = includeCalls + 1; error("must not include missing file") end
local missing, missingOK = WSZC.OptionalInclude("missing.lua")
local first = missing == nil and missingOK == false and includeCalls == 0
file.Exists = function() return true end
local broken, brokenOK = WSZC.OptionalInclude("broken.lua")
return first and broken == nil and brokenOK == false and includeCalls == 1
'''))

    runtime_check("R11 native external minigame functions survive installation verbatim", lambda: lua.execute(r'''
ResetEnvironment(); InstallNativeContract()
local H = WoundSystem.Health
local nativeStart, nativeStop = H.StartExternalMinigame, H.StopExternalMinigame
local installed = WSZC.InstallMinigameAPI(H)
return installed == true and H.StartExternalMinigame == nativeStart
    and H.StopExternalMinigame == nativeStop and WSZC.ExternalMinigameMode == "native"
    and H._WSZCOwnsExternalMinigameAPI ~= true
'''))

    runtime_check("R12 the supplied legacy build still installs the advanced WSZC implementation", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
local H = WoundSystem.Health
local installed = WSZC.InstallMinigameAPI(H)
return installed == true and H.StartExternalMinigame == WSZC.StartExternalMinigameImpl
    and H.StopExternalMinigame == WSZC.StopExternalMinigameImpl
    and H._WSZCOwnsExternalMinigameAPI == true and WSZC.ExternalMinigameMode == "wszc"
'''))

    runtime_check("R13 adaptive=0 is an explicit legacy override, not the default", lambda: lua.execute(r'''
ResetEnvironment()
CVARS.zc_woundsystem_compat_adaptive.value = "0"
local override = WSZC.Supports("core") and WSZC.Supports("remote")
CVARS.zc_woundsystem_compat_adaptive.value = "1"
return override and not WSZC.Supports("core")
'''))

    runtime_check("R14 late-loading dependencies become available after a fresh probe", lambda: lua.execute(r'''
ResetEnvironment()
local before = not WSZC.Supports("core")
InstallLegacyContract()
local caps = WSZC.RefreshCapabilities()
return before and caps.core and WSZC.Supports("remote")
'''))

    runtime_check("R15 optional ZCity contracts degrade independently without disabling inspection", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
hg.WoundBridge.SwepHeal = nil
hg.WoundBridge.GetPlayer = nil
hg.WoundBridge.StartMinigame = nil
hg.organism.Clear = nil
local caps = WSZC.RefreshCapabilities()
return caps.core and caps.inspection and not caps.medicine
    and not caps.external_minigames and not caps.organism_extensions
    and WSZC.Supports("inspection") and not WSZC.Supports("organism_extensions")
'''))

    runtime_check("R16 the real server Setup selects and preserves the native adapter", lambda: (lambda: (
        lua.execute(r'''
AddCSLuaFile = function() end
HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM = 4, 5
HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG = 6, 7
HITGROUP_GEAR, HITGROUP_GENERIC = 10, 0
ResetEnvironment(); InstallNativeContract()
include = function() return {} end
'''),
        lua.execute(server_s),
        lua.execute(r'''
local ok, ready = pcall(WSZC.Setup)
return ok and ready == true and WSZC.SetupDone == true
    and WSZC.Compatibility.activeAdapter == "native-api"
    and WSZC.ExternalMinigameMode == "native"
    and WoundSystem.Health.StartExternalMinigame() == "native"
''')
    )[-1])())

    runtime_check("R17 the real Attempt latches a failed Setup instead of spamming errors", lambda: lua.execute(r'''
WSZC.Ready = nil
WSZC.SetupDone = nil
WSZC.SetupFailed = nil
WSZC.ClearCompatibilityFailures()
local calls = 0
local originalSetup = WSZC.Setup
WSZC.Setup = function()
    calls = calls + 1
    error("unsupported fixture")
end
WSZC.Attempt()
WSZC.Attempt()
WSZC.Setup = originalSetup
return calls == 1 and WSZC.SetupFailed ~= nil and WSZC.Ready ~= true
    and not WSZC.Supports("core") and GetGlobalBool("WSZC_Ready", true) == false
'''))

    runtime_check("R18 unsupported core leaves native WB.IsEnabled/IsBridged untouched", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
WoundSystem.Items.Get = nil -- partial core
local WB = hg.WoundBridge
WB.cvBridge = { GetBool = function() return true end }
local nativeEnabled, nativeBridged = WB.IsEnabled, WB.IsBridged
local enabledPatch = WSZC.PatchIsEnabled()
local bridgedPatch = WSZC.PatchIsBridged()
return enabledPatch == false and bridgedPatch == false
    and WB.IsEnabled == nativeEnabled and WB.IsBridged == nativeBridged
'''))

    runtime_check("R19 the real Setup returns false cleanly with both dependencies absent", lambda: lua.execute(r'''
ResetEnvironment()
WSZC.SetupDone = nil
WSZC.SetupFailed = nil
local ok, ready = pcall(WSZC.Setup)
return ok and ready == false and WSZC.Ready ~= true and WSZC.SetupDone ~= true
    and WSZC.Compatibility.profile == "unavailable" and not WSZC.Supports("core")
'''))

    runtime_check("R20 portable resources recurse, filter extensions and never register twice", lambda: lua.execute(r'''
ResetEnvironment()
WSZC._PortableResourcesInstalled = nil
CVARS.zc_woundsystem_compat_resource_downloads.value = "1"
local added = {}
resource = { AddFile = function(path) added[#added + 1] = path end }
local tree = {
    ["materials/wszc"] = { { "root.PNG", "ignore.txt" }, { "limbs" } },
    ["materials/wszc/limbs"] = { { "fill.vmt", "mesh.mdl" }, {} },
    -- Global font/shader directories must never be scanned.  Only the six
    -- explicit C:U filenames below may arrive from those roots.
    ["resource/fonts"] = { { "unrelated-font.ttf" }, {} },
    ["shaders/fxc"] = { { "unrelated-shader.vcs" }, {} },
}
file.Find = function(path, searchPath)
    if searchPath ~= "GAME" then return {}, {} end
    local node = tree[string.sub(path, 1, #path - 2)]
    if node then return node[1], node[2] end
    return {}, {}
end
local count = WSZC.InstallPortableResources()
local again = WSZC.InstallPortableResources()
local expected = {
    ["materials/wszc/root.PNG"] = true,
    ["materials/wszc/limbs/fill.vmt"] = true,
    ["resource/fonts/i-pixel-u.ttf"] = true,
    ["resource/fonts/perfectdosvga437.ttf"] = true,
    ["resource/fonts/retro gaming.ttf"] = true,
    ["shaders/fxc/woundsystem_aberration_ps20b.vcs"] = true,
    ["shaders/fxc/woundsystem_condition_ps20b.vcs"] = true,
    ["shaders/fxc/woundsystem_pain_ps20b.vcs"] = true,
}
local exact = count == 8 and again == 0 and #added == 8
for _, path in ipairs(added) do
    if not expected[path] or WoundSystem.Resources.Added[path] ~= true then exact = false end
end
for path in pairs(expected) do
    if WoundSystem.Resources.Added[path] ~= true then exact = false end
end
WSZC._PortableResourcesInstalled = nil
CVARS.zc_woundsystem_compat_resource_downloads.value = "0"
local disabled = WSZC.InstallPortableResources() == false and #added == 8
resource, file.Find = nil, nil
return exact and disabled
'''))

    runtime_check("R21 an existing native C:U resource entry is reused, not duplicated", lambda: lua.execute(r'''
ResetEnvironment()
WoundSystem = { Resources = { Added = { ["materials/wszc/already.png"] = true } } }
WSZC._PortableResourcesInstalled = nil
CVARS.zc_woundsystem_compat_resource_downloads.value = "1"
local added = {}
resource = { AddFile = function(path) added[#added + 1] = path end }
file.Find = function(path)
    if path == "materials/wszc/*" then return { "already.png", "new.png" }, {} end
    return {}, {}
end
file.Exists = function(path) return string.sub(path, 1, 10) == "materials/" end
local count = WSZC.InstallPortableResources()
local ok = count == 1 and #added == 1 and added[1] == "materials/wszc/new.png"
    and WoundSystem.Resources.Added["materials/wszc/new.png"] == true
resource, file.Find = nil, nil
return ok
'''))

    runtime_check("R22 missing external APIs load the isolated server runtime and publish that choice", lambda: embedded_runtime(True).execute(r'''
local expected = table.concat({
    "wszc_vendor/cu/autorun/sh_health_init.lua",
    "wszc_vendor/cu/autorun/server/sv_woundsys_weather_compat.lua",
    "wszc_vendor/zcity/woundbridge/sh_woundbridge.lua",
    "wszc_vendor/zcity/woundbridge/sv_woundbridge.lua",
}, "|")
local clients = table.concat({
    "wszc_vendor/cu/autorun/sh_health_init.lua",
    "wszc_vendor/zcity/woundbridge/sh_woundbridge.lua",
    "wszc_vendor/zcity/woundbridge/cl_woundbridge.lua",
}, "|")
return table.concat(INCLUDES, "|") == expected
    and table.concat(CLIENT_FILES, "|") == clients
    and WoundSystem._WSZCEmbedded == true and hg.WoundBridge._WSZCEmbedded == true
    and GLOBALS.WSZC_CUSourceKnown == true and GLOBALS.WSZC_CUEmbedded == true
    and GLOBALS.WSZC_BridgeSourceKnown == true and GLOBALS.WSZC_BridgeEmbedded == true
    and type(LATE) == "function"
'''))

    runtime_check("R23 existing Workshop/GitHub APIs win without any embedded include", lambda: embedded_runtime(True, r'''
WoundSystem = { Health = {}, Items = { Get = function() return nil end } }
hg = { WoundBridge = {} }
''').execute(r'''
LATE()
return #INCLUDES == 0 and GLOBALS.WSZC_CUSourceKnown == true
    and GLOBALS.WSZC_CUEmbedded == false and GLOBALS.WSZC_BridgeEmbedded == false
'''))

    runtime_check("R24 a present but uninitialized external loader falls back only on the late pass", lambda: embedded_runtime(True, r'''
EXTERNALS["autorun/sh_health_init.lua"] = true
EXTERNALS["homigrad/woundbridge/sh_woundbridge.lua"] = true
''').execute(r'''
local initial = #INCLUDES
LATE()
return initial == 0 and #INCLUDES == 4
    and WoundSystem._WSZCEmbedded == true and hg.WoundBridge._WSZCEmbedded == true
'''))

    runtime_check("R25 dedicated client waits for and honors the server's external-runtime decision", lambda: embedded_runtime(False).execute(r'''
local initial = #INCLUDES
LATE()
local waitedForServer = initial == 0 and #INCLUDES == 0 and #CLIENT_FILES == 0
GLOBALS.WSZC_CUSourceKnown = true
GLOBALS.WSZC_CUEmbedded = false
GLOBALS.WSZC_BridgeSourceKnown = true
GLOBALS.WSZC_BridgeEmbedded = false
LATE()
return waitedForServer and #INCLUDES == 0 and #CLIENT_FILES == 0
'''))

    runtime_check("R26 dedicated client loads only embedded shared/client realms when requested", lambda: embedded_runtime(False, r'''
GLOBALS.WSZC_CUSourceKnown = true
GLOBALS.WSZC_CUEmbedded = true
GLOBALS.WSZC_BridgeSourceKnown = true
GLOBALS.WSZC_BridgeEmbedded = true
''').execute(r'''
LATE()
local expected = table.concat({
    "wszc_vendor/cu/autorun/sh_health_init.lua",
    "wszc_vendor/zcity/woundbridge/sh_woundbridge.lua",
    "wszc_vendor/zcity/woundbridge/cl_woundbridge.lua",
}, "|")
return table.concat(INCLUDES, "|") == expected and #CLIENT_FILES == 0
    and WoundSystem._WSZCEmbedded == true and hg.WoundBridge._WSZCEmbedded == true
'''))

    runtime_check("R27 connector optional includes resolve into the embedded C:U namespace", lambda: lua.execute(r'''
ResetEnvironment()
WoundSystem = { _WSZCEmbedded = true }
local expected = "wszc_vendor/cu/woundsystem/client/minigames/cl_clip.lua"
file.Exists = function(path) return path == expected end
include = function(path) INCLUDED = path; return { loaded = true } end
local resolved = WSZC.ResolveCUPath("woundsystem/client/minigames/cl_clip.lua")
local result, ok = WSZC.OptionalInclude("woundsystem/client/minigames/cl_clip.lua")
return resolved == expected and ok == true and INCLUDED == expected and result.loaded == true
'''))

    runtime_check("R28 the supplied SwepHeal-local minigame helper is a supported contract", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
hg.WoundBridge.StartMinigame = nil
local caps = WSZC.RefreshCapabilities()
return caps.zcity_minigames and caps.external_minigames and WSZC.Supports("external_minigames")
'''))

    runtime_check("R29 a client uses replicated server contracts and readiness instead of server-only Lua", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
WoundSystem.UseMedicalItem = nil
hook._t = {}
debug = nil
hg.WoundBridge = { IsEnabled = function() return true end }
SERVER, CLIENT = false, true
GetGlobalString = function(name, fallback)
    if GLOBALS[name] == nil then return fallback end
    return GLOBALS[name]
end
GLOBALS.WSZC_CapabilitiesKnown = true
GLOBALS.WSZC_CapZCityBridge = true
GLOBALS.WSZC_CapNativeAPI = false
GLOBALS.WSZC_CapLegacyAPI = true
GLOBALS.WSZC_CapNativeState = false
GLOBALS.WSZC_CapNativeExternal = false
GLOBALS.WSZC_CapDebugIntrospection = true
GLOBALS.WSZC_CapZCityMedicine = true
GLOBALS.WSZC_CapZCityMinigames = true
GLOBALS.WSZC_CapZCityOrganism = true
GLOBALS.WSZC_CapCore = true
GLOBALS.WSZC_CapMedicine = true
GLOBALS.WSZC_CapExternalMinigames = true
GLOBALS.WSZC_CapOrganismExtensions = true
GLOBALS.WSZC_Ready = true
GLOBALS.WSZC_ActiveAdapter = "legacy-adapter"
local caps = WSZC.RefreshCapabilities()
local text = table.concat(WSZC.CompatibilityStatusLines(), "\n")
local ok = caps.core and caps.cu_legacy_api and not caps.cu_native_api
    and caps.inspection and caps.medicine and caps.external_minigames
    and caps.remote and caps.organism_extensions
    and string.find(text, "realm=client", 1, true) ~= nil
    and string.find(text, "ready=yes", 1, true) ~= nil
    and string.find(text, "active_adapter=legacy-adapter", 1, true) ~= nil
GLOBALS.WSZC_CapNativeAPI = true
GLOBALS.WSZC_CapLegacyAPI = false
GLOBALS.WSZC_CapNativeState = true
GLOBALS.WSZC_CapNativeExternal = true
file.Exists = function() return false end
local nativeCaps = WSZC.RefreshCapabilities()
local nativeOK = nativeCaps.core and nativeCaps.remote and nativeCaps.external_minigames
    and not nativeCaps.cu_minigame_files
SERVER, CLIENT = true, false
GetGlobalString = nil
return ok and nativeOK
'''))

    runtime_check("R30 a medical-only partial C:U table is not a legacy damage contract", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
hook._t = {}
WoundSystem.Health.HandleDamage = nil
local caps = WSZC.RefreshCapabilities()
return type(WoundSystem.UseMedicalItem) == "function"
    and not caps.cu_legacy_api and not caps.core
'''))

    runtime_check("R31 embedded lexical refs run the real legacy Setup with debug unavailable", lambda: lua.execute(r'''
ResetEnvironment(); InstallLegacyContract()
debug = nil
WSZC.SetupDone, WSZC.Ready, WSZC.SetupFailed = nil, nil, nil
WSZC.OriginalFn, WSZC.OriginalConst = nil, nil
WSZC.DamageProxiesApplied, WSZC.ProxiedCUDamage = nil, nil
WSZC.HandleDamageWrapped, WSZC.WrappedCUDamage = nil, nil
WSZC.HandleDamageWrapper, WSZC.OriginalHandleDamage = nil, nil
WSZC.CUDamageHandler, WSZC.DamageWrapper = nil, nil
WoundSystem._WSZCEmbedded = true
local H = WoundSystem.Health
H._WSZCBridgeRefs = { version = 1 }
H._WSZCReplaceUpvalue = function() return false end
local partial = WSZC.RefreshCapabilities()
local rejectedPartial = not partial.cu_embedded_bridge and not partial.cu_legacy_api and not partial.core

local refs = {
    version = 1, Fn = {}, Const = {}, BodyState = {}, PlayerLimbs = {}, Sessions = {},
    GetBody = function(ply) return nil end,
}
local function noop() end
for _, key in ipairs({
    "SendCardioUpdate", "ProcessImpactDamage", "SendLimbUpdate",
    "TryCreateUnconsciousRagdoll", "GuessRagdollDamageLimb", "RagdollBoneNameToLimb",
    "BuildMedicalItemContext", "ApplyBandageProfile", "GetSyringeProfile",
    "ApplySyringeProfile", "CloseBandageSession", "CloseSyringeSession",
    "CloseShrapnelSession", "CloseDislocationSession", "CloseAedSession",
}) do refs[key] = noop end
H._WSZCBridgeRefs = refs
local replaced = {}
H._WSZCReplaceUpvalue = function(fn, wanted, value)
    local registered = hook.GetTable().EntityTakeDamage.WoundSystem_Damage
    if registered ~= fn or type(value) ~= "table" then return false end
    if wanted ~= "Fn" and wanted ~= "Const" then return false end
    replaced[wanted] = value
    return true
end
local ok, ready = pcall(WSZC.Setup)
local caps = WSZC.RefreshCapabilities()
return rejectedPartial and ok and ready == true and WSZC.SetupDone == true
    and WSZC.Compatibility.activeAdapter == "legacy-adapter"
    and caps.cu_embedded_bridge and caps.cu_legacy_api and not caps.debug_introspection
    and WSZC.Fn == refs.Fn and WSZC.Const == refs.Const
    and type(replaced.Fn) == "table" and type(replaced.Const) == "table"
    and type(H.HandleDamage) == "function" and type(H.ApplyItemToBody) == "function"
'''))

    runtime_check("R32 embedded optional include trusts the downloadable Lua cache", lambda: lua.execute(r'''
ResetEnvironment()
WoundSystem = { _WSZCEmbedded = true }
includeCalls = 0
file.Exists = function() return false end
include = function(path)
    includeCalls = includeCalls + 1
    INCLUDED = path
    return { loaded = true }
end
local expected = "wszc_vendor/cu/woundsystem/client/minigames/sh_handphysics.lua"
local resolved = WSZC.ResolveCUPath("woundsystem/client/minigames/sh_handphysics.lua")
local result, ok = WSZC.OptionalInclude("woundsystem/client/minigames/sh_handphysics.lua")
local status = WSZC.OptionalIncludeStatus[expected]
return resolved == expected and INCLUDED == expected and includeCalls == 1
    and ok == true and result.loaded == true
    and status and status.ok == true and status.exists == false
    and status.resultType == "table"
'''))

    runtime_check("R33 a rejected server minigame start exposes its exact reason", lambda: lua.execute(r'''
ResetEnvironment()
WSZC.Ready = nil
WSZC.LastMinigameStartResult = nil
local started = WSZC.StartExternalMinigameImpl(nil, {})
local text = table.concat(WSZC.CompatibilityStatusLines(), "\n")
return started == false and WSZC.LastMinigameStartResult == "connector not ready"
    and string.find(text, "last_minigame_start=connector not ready", 1, true) ~= nil
'''))

    runtime_check("R34 client-only status and minigames do not require health GUI", lambda: lua.execute(r'''
ResetEnvironment()
SERVER, CLIENT = false, true
WSZC._SharedLoaded = nil
COMMANDS = {}
assert(load(SHARED_SOURCE))()
WoundSystem = {
    _WSZCEmbedded = true,
    MinigameClip = {},
    Items = { Get = function() return {} end },
}
WoundSystemHealthHUDOpen = nil
WSZC._MinigameClientLoaded = nil
includeCalls = 0
include = function() includeCalls = includeCalls + 1; return {} end
file.Exists = function() return false end
assert(load(CLIENT_MINIGAMES_SOURCE))()
local activate = hook._t.InitPostEntity.WSZC_MinigameClientInit
activate()
local logs = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    logs[#logs + 1] = table.concat(parts, " ")
end
-- Server-authorized debug is private to the local administrator.
local admin = { IsAdmin = function() return true end }
LocalPlayer = function() return admin end
WSZC.DebugClient = true
COMMANDS.wszc_compat_client_status()
local text = table.concat(logs, "\n")
return type(COMMANDS.wszc_compat_client_status) == "function"
    and WSZC.MinigameClientReady == true and WSZC.MinigameClientAttempts == 1
    and includeCalls == 2
    and string.find(text, "realm=client", 1, true) ~= nil
    and string.find(text, "client minigame runtime:", 1, true) ~= nil
    and string.find(text, "loaded=yes ready=yes attempts=1", 1, true) ~= nil
    and string.find(text, "health_gui_optional=no", 1, true) ~= nil
    and string.find(text, "hud_global_optional=no", 1, true) ~= nil
'''))

    runtime_check("R35 real server realm without client OpenHealthHUD keeps remote treatment supported", lambda: lua.execute(r'''
SERVER, CLIENT = true, false
WSZC._SharedLoaded = nil
assert(load(SHARED_SOURCE))()
ResetEnvironment()
InstallLegacyContract()
-- Real Garry's Mod servers never include client/cl_health_gui.lua, so
-- WoundSystem.OpenHealthHUD and WoundSystem.ToggleHealthHUD are nil on SERVER.
WoundSystem.OpenHealthHUD = nil
WoundSystem.ToggleHealthHUD = nil
local caps = WSZC.RefreshCapabilities()
local serverSupportsRemote = caps.core == true
    and caps.cu_ui == true
    and caps.inspection == true
    and caps.remote == true
    and WSZC.Supports("remote") == true

-- Even when file.Exists returns false on a packed mount, embedded C:U on SERVER
-- still reports remote support, while a CLIENT without OpenHealthHUD does not.
file.Exists = function() return false end
WoundSystem._WSZCEmbedded = true
local embeddedCaps = WSZC.RefreshCapabilities()
local embeddedRemoteOK = embeddedCaps.remote == true and WSZC.Supports("remote") == true

SERVER, CLIENT = false, true
WoundSystem._WSZCEmbedded = nil
local clientCaps = WSZC.RefreshCapabilities()
local clientWithoutUIBlocked = clientCaps.cu_ui == false and clientCaps.remote == false
    and WSZC.Supports("remote") == false
SERVER, CLIENT = true, false
file.Exists = function() return true end
return serverSupportsRemote and embeddedRemoteOK and clientWithoutUIBlocked
'''))

failed = [name for name, ok in results if not ok]
print(f"TEST_OK {len(results) - len(failed)} / {len(results)}")
if failed:
    print("FAILED:", "; ".join(failed))
    raise SystemExit(1)
