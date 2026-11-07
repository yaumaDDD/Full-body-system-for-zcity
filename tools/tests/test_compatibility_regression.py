#!/usr/bin/env python3
"""Adaptive ZCity/C:U capability-detection regressions.

The runtime loads the shipped shared module and the real server minigame
implementation, then simulates legacy, native, partial and missing APIs.
No check in this suite is evidence of a live two-client GMod acceptance test.
"""
from pathlib import Path
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
local lines = WSZC.CompatibilityStatusLines()
local text = table.concat(lines, "\n")
return type(COMMANDS.wszc_compat_status) == "function"
    and type(COMMANDS.wszc_compat_reprobe) == "function"
    and string.find(text, "legacy-adapter", 1, true) ~= nil
    and string.find(text, "remote=no", 1, true) ~= nil
    and string.find(text, "missing test state", 1, true) ~= nil
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

failed = [name for name, ok in results if not ok]
print(f"TEST_OK {len(results) - len(failed)} / {len(results)}")
if failed:
    print("FAILED:", "; ".join(failed))
    raise SystemExit(1)
