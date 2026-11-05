#!/usr/bin/env python3
"""Focused regressions: unconscious cleanup, shrapnel DOT and explicit reset."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / "woundsystem_zcity_compat"
ORGANISM = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua"
SERVER_MG = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua"
CLIENT_MG = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua"
LAYOUT = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_layout.lua"

results = []


def check(name, value):
    results.append((name, bool(value)))
    print(("PASS " if value else "FAIL ") + name)


organism_s = ORGANISM.read_text(encoding="utf-8")
server_mg_s = SERVER_MG.read_text(encoding="utf-8")
client_mg_s = CLIENT_MG.read_text(encoding="utf-8")
layout_s = LAYOUT.read_text(encoding="utf-8")

client_context = layout_s.split("function WSZC.MinigameContextOK()", 1)[1].split("function WSZC.MinigameScale", 1)[0]
check("S01 unconscious closes WSZC + native games on both realms",
      '"WSZC_MinigameForceClose"' in server_mg_s
      and 'StopAllMinigames(ply, "unconscious", true)' in server_mg_s
      and "CUCloseShrapnelSession" in server_mg_s
      and "CUCloseDislocationSession" in server_mg_s
      and "CUCloseAedSession" in server_mg_s and '"Aed"' in server_mg_s
      and 'net.Receive("WSZC_MinigameForceClose"' in client_mg_s
      and '"WoundSystemUnconscious"' in layout_s
      and 'type(ply) == "table"' not in client_context)
check("S02 shotgun source is separate and requires positive identification",
      'RecordShrapnelSource(org, limbId, reason' in organism_s
      and '"shotgun"' in organism_s and '"glass"' in organism_s
      and 'AddShrapnel(ply, limbId, shotgunAdded, "shotgun")' in organism_s
      and "DMG_BUCKSHOT alone is NOT enough" in organism_s)
check("S03 every lodged piece grows a real wound; explicit reset clears it",
      "function WSZC.TickLodgedShrapnel" in organism_s
      and "wound.wszcShrapnel = SHRAPNEL_WOUND_TAG" in organism_s
      and "function WSZC.ClearAllShrapnel" in organism_s
      and "SnapshotZCityStructure(org, false)" in organism_s
      and "_ExplicitResetDepth" in organism_s)
check("S04 polished WoundView has vitals and selected-limb readout",
      "zc_woundsystem_compat_woundview_polish" in layout_s
      and "WSZC_WoundViewPolishBackground" in layout_s
      and "DrawVitalRow" in layout_s and "LIMB STATUS" in layout_s)

try:
    sys.path.insert(0, "/tmp/lupa_pkg")
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print("SKIP runtime checks (lupa unavailable)")
else:
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
SERVER = true; CLIENT = false
WSZC = { OrganismAuthority = function() return true end }
WoundSystem = { Health = { Constants = { ShrapnelPieceCount = 5 } } }
hg = {}
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
CreateConVar = function(name, def)
    return { GetBool = function() return def ~= "0" end,
             GetFloat = function() return tonumber(def) or 0 end }
end
GetConVar = function() return nil end
hook = { _t = {}, Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
         Remove = function() end, GetTable = function() return hook._t end }
timer = { Simple = function() end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
include = function() end
IsValid = function(v) return v ~= nil and v ~= false end
CurTime = function() return 100 end
print = function() end
ErrorNoHalt = function() end
SetGlobalBool = function() end
isnumber = function(v) return type(v) == "number" end
isvector = function() return false end
bit = { band = function(a, b)
    local result, place = 0, 1
    a, b = math.floor(a or 0), math.floor(b or 0)
    while a > 0 and b > 0 do
        if a % 2 == 1 and b % 2 == 1 then result = result + place end
        a, b = math.floor(a / 2), math.floor(b / 2); place = place * 2
    end
    return result
end }
DMG_BULLET, DMG_BUCKSHOT, DMG_BLAST, DMG_DISSOLVE = 1, 2, 4, 8
HITGROUP_RIGHTARM = 5
game = { GetAmmoName = function(id) return id == 12 and "12/70gauge" or "9mm" end }
''')
    lua.execute(organism_s)

    lua.execute(r'''
function MakePlayer()
    local ply = { _nw = {}, _limbs = {}, _body = {} }
    ply._limbs.hand_R = { shrapnel = 0, bleed = 0, pain = 0, muscle = 100, skin = 100 }
    ply.IsPlayer = function() return true end
    ply.Alive = function() return true end
    ply.SetNetVar = function() end
    ply.GetNWBool = function(self, key, fallback) local v = self._nw[key]; if v == nil then return fallback end; return v end
    ply.SetNWBool = function(self, key, value) self._nw[key] = value end
    ply.organism = {
        owner = ply, blood = 5000, bleed = 0, internalBleed = 0,
        pain = 0, avgpain = 0, painadd = 0, shock = 0,
        consciousness = 1, pulse = 70, brain = 0,
        wounds = {}, arterialwounds = {}, rarm = 0,
    }
    return ply
end
WoundSystem.Health.GetLimbs = function(ply) return ply._limbs end
WoundSystem.Health.GetLimbState = function(ply, id) return ply._limbs[id] end
WoundSystem.Health.GetBody = function(ply) return ply._body end
WoundSystem.Health.SendLimbUpdate = function() end
WoundSystem.Health.SendCardioUpdate = function() end
WoundSystem.Health.ResetPlayer = function(ply)
    for _, state in pairs(ply._limbs) do
        state.shrapnel, state.bleed, state.pain = 0, 0, 0
        state.broken, state.dislocated = false, false
    end
    ply._body.unconscious = false
    return true
end
WSZC.StopAllMinigames = function() return true end
function MakeDamage(weaponClass, numBullet, ammoId, damageType)
    local weapon = { NumBullet = numBullet, GetClass = function() return weaponClass end }
    local attacker = { GetActiveWeapon = function() return weapon end }
    return {
        GetDamageType = function() return damageType end,
        GetDamage = function() return 30 end,
        GetAmmoType = function() return ammoId end,
        GetInflictor = function() return weapon end,
        GetAttacker = function() return attacker end,
    }
end
''')

    sources = lua.execute(r'''
local pistolPlayer = MakePlayer()
WSZC.InjectDamageShrapnel(pistolPlayer, MakeDamage("weapon_pistol", 1, 9, 1), HITGROUP_RIGHTARM, 30)
WSZC.InjectDamageShrapnel(pistolPlayer, MakeDamage("weapon_pistol", 1, 9, 2), HITGROUP_RIGHTARM, 30)
local pistolClean = pistolPlayer._limbs.hand_R.shrapnel == 0

local shotgunPlayer = MakePlayer()
WSZC.InjectDamageShrapnel(shotgunPlayer, MakeDamage("weapon_spas12", 8, 12, 0), HITGROUP_RIGHTARM, 30)
local org = shotgunPlayer.organism
local sources = org.wszc_shrapnel_sources.hand_R
return pistolClean, shotgunPlayer._limbs.hand_R.shrapnel == 3
    and sources.shotgun == 3 and sources.glass == nil
''')
    check("R01 pistol and bare DMG_BUCKSHOT create no fragments", sources[0])
    check("R02 confirmed shotgun creates its own fragment source", sources[1])

    effects = lua.execute(r'''
local ply = MakePlayer()
local normal = { 4, nil, nil, "ValveBiped.Bip01_R_Hand", 0 }
ply.organism.wounds = { normal }
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
WSZC.AddShrapnel(ply, "hand_R", 1, "glass")
local org = ply.organism
local tagged
for _, wound in pairs(org.wounds) do if wound.wszcShrapnel then tagged = wound end end
local severity = tagged[1]
WSZC.TickLodgedShrapnel(ply, org, 0.5)
local separate = org.wszc_shrapnel_sources.hand_R.shotgun == 3
    and org.wszc_shrapnel_sources.hand_R.glass == 2
local grows = tagged[1] > severity and org.avgpain > 0 and org.painadd > 0 and org.pain > 0
ply._WSZCLimbsRef = ply._limbs
ply._limbs.hand_R.shrapnel = 0
WSZC.SyncShrapnel(ply, org)
local removed = #org.wounds == 1 and org.wounds[1] == normal
    and org.wszc_shrapnel_sources.hand_R == nil
    and org.wszc_shrapnel_irritation.hand_R == nil
return separate, grows, removed
''')
    check("R03 shotgun and glass counts remain separate", effects[0])
    check("R04 lodged fragments increase real wound severity and pain", effects[1])
    check("R05 extraction removes only tagged shrapnel wounds", effects[2])

    reset = lua.execute(r'''
local ply = MakePlayer()
WSZC.AddShrapnel(ply, "hand_R", 1, "shotgun")
ply.organism.otrub = true
hg.send_organism = function() end; hg.send_bareinfo = function() end
hg.organism = { Clear = function(org)
    local owner = org.owner
    for key in pairs(org) do if key ~= "owner" then org[key] = nil end end
    org.owner = owner
    org.wounds, org.arterialwounds = {}, {}
end }
hg.WoundBridge = {
    GetPlayer = function(ent) return ent end,
    RestoreRagdoll = function() end,
    ResetOrganism = function(ent) hg.organism.Clear(ent.organism); return true end,
}
WSZC.InstallResetStructureGuard()
hg.organism.Clear(ply.organism)
local transitionKept = ply.organism.otrub == true
    and ply.organism.wszc_shrapnel.hand_R == 3
    and ply.organism.wszc_shrapnel_sources.hand_R.shotgun == 3
hg.WoundBridge.ResetOrganism(ply)
local explicitCleared = ply.organism.otrub == true
    and ply.organism.wszc_shrapnel == nil
    and ply.organism.wszc_shrapnel_sources == nil
    and ply.organism.wszc_shrapnel_irritation == nil
    and #ply.organism.wounds == 0 and ply.organism.pain == 0
    and ply.organism.bleed == 0 and ply._limbs.hand_R.shrapnel == 0
return transitionKept, explicitCleared
''')
    check("R06 ordinary ragdoll clear still preserves fragments", reset[0])
    check("R07 explicit reset fully clears fragments and medical residue", reset[1])

    client = LuaRuntime(unpack_returned_tuples=True)
    client.execute(r'''
CLIENT = true; SERVER = false
CurTime = function() return 100 end
IsValid = function(v) return v ~= nil and v ~= false end
include = function() end
timer = { Simple = function() end, Create = function() end, Remove = function() end }
hook = { GetTable = function() return {} end, Add = function() end, Remove = function() end, Call = function() end }
net = { _receivers = {}, Receive = function(name, fn) net._receivers[name] = fn end,
        ReadString = function() return net._reason or "unconscious" end,
        Start = function() end, SendToServer = function() end, WriteString = function() end,
        WriteBool = function() end, WriteUInt = function() end, WriteFloat = function() end }
gui = { EnableScreenClicker = function() end, MousePos = function() return 0, 0 end }
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
vgui = { CursorVisible = function() return true end,
         GetWorldPanel = function() return { GetCursor = function() return "arrow" end, SetCursor = function() end } end }
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 70
WoundSystemInventorySlots, WoundSystemDragState, WoundSystemWorldDrag = {}, {}, {}
WoundSystem = { HealthGUI = {}, Client = {}, CloseHealthHUD = function() WoundSystemHealthHUDOpen = false end }
WoundSystemHealthHUDOpen = true
WoundSystemDislocationMinigame = { active = true }
WoundSystemShrapnelMinigame = { active = true }
WoundSystemFractureMinigame = { active = true }
WoundSystemAEDMinigame = { active = true }
WoundSystemAmputationMinigame = { active = true }
WoundSystemHealthHUDMinigame = { active = true }
WSZC = { MinigameContextOK = function() return true end,
         ForceReleaseMinigameCursor = function() WSZC.released = true end,
         RestoreMinigameCursor = function() end,
         NativeMinigameActive = function() return false end }
''')
    client.execute(client_mg_s)
    cleanup = client.execute(r'''
local requested = 0
local removed = false
WSZCBandageMinigame = { active = true, inputSeq = 0, IsActive = function() return true end,
    RequestClose = function() requested = requested + 1 end,
    overlay = { Remove = function() removed = true end } }
WSZCSyringeMinigame = { active = false }
net._receivers["WSZC_MinigameForceClose"]()
local closed = WSZCBandageMinigame.active == false and requested == 0 and removed
    and WoundSystemDislocationMinigame.active == false
    and WoundSystemShrapnelMinigame.active == false
    and WoundSystemHealthHUDOpen == false and WSZC.released == true
WSZCBandageMinigame.active = true
WoundSystemHealthHUDOpen = true
net._reason = "death"
WSZC.ClearAllMinigameState(true)
return closed, requested == 1 and WSZCBandageMinigame.active == false
''')
    check("R08 force-close removes native/WSZC UI without a duplicate request", cleanup[0])
    check("R09 death cleanup still requests authoritative closure", cleanup[1])

    server = LuaRuntime(unpack_returned_tuples=True)
    server.execute(r'''
SERVER = true; CLIENT = false
WSZC = { Ready = true, BridgeEnabled = function() return true end,
         Bridged = function() return true end }
CreateConVar = function(name, def) return { GetBool = function() return def ~= "0" end } end
GetConVar = function() return nil end
FindMetaTable = function() return nil end
util = { AddNetworkString = function() end }
net = { sent = {}, Receive = function() end, Start = function(name) net.current = name end,
        Send = function(ply) table.insert(net.sent, net.current) end,
        WriteString = function() end, WriteBool = function() end,
        WriteUInt = function() end, WriteFloat = function() end }
hook = { _t = {}, Add = function(e, n, f) hook._t[e] = hook._t[e] or {}; hook._t[e][n] = f end,
         Remove = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
include = function() end
IsValid = function(v) return v ~= nil and v ~= false end
CurTime = function() return 100 end
player = { GetAll = function() return {} end }
''')
    server.execute(server_mg_s)
    native_close = server.execute(r'''
local medic = { organism = {}, IsPlayer = function() return true end,
    Alive = function() return true end, GetNWBool = function() return false end }
local patient = { organism = { otrub = true }, Alive = function() return true end }
local patientDoesNotIncapacitateMedic = not WSZC.PlayerMinigameIncapacitated(medic)
    and WSZC.PlayerMinigameIncapacitated(patient)
medic.organism.otrub = true
local medicIncapacitated = WSZC.PlayerMinigameIncapacitated(medic)
local closed = {}
WSZC.CUSessions = { Shrapnel = {}, Dislocation = {}, Aed = {}, Bandage = {}, Syringe = {} }
for kind, sessions in pairs(WSZC.CUSessions) do sessions[medic] = { id = 1 } end
local function close(kind)
    return function(ply, reason)
        closed[kind] = reason
        WSZC.CUSessions[kind][ply] = nil
    end
end
WSZC.CUCloseShrapnelSession = close("Shrapnel")
WSZC.CUCloseDislocationSession = close("Dislocation")
WSZC.CUCloseAedSession = close("Aed")
WSZC.CUCloseBandageSession = close("Bandage")
WSZC.CUCloseSyringeSession = close("Syringe")
WSZC.MinigameSessions[medic] = { kind = "bandage", id = 1, deferredUsed = 0, startAmount = 0 }
hook._t["HG_OnOtrub"]["WSZC_MinigameUnconscious"](medic)
local allClosed = WSZC.MinigameSessions[medic] == nil
for _, kind in ipairs({ "Shrapnel", "Dislocation", "Aed", "Bandage", "Syringe" }) do
    allClosed = allClosed and closed[kind] == "unconscious" and WSZC.CUSessions[kind][medic] == nil
end
local forced = false
for _, name in ipairs(net.sent) do if name == "WSZC_MinigameForceClose" then forced = true end end
return patientDoesNotIncapacitateMedic and medicIncapacitated, allClosed and forced
''')
    check("R10 only the operator's incapacity controls the session", native_close[0])
    check("R11 unconscious closes every native session plus WSZC", native_close[1])

passed = sum(1 for _, ok in results if ok)
print("TEST_OK %d / %d" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
