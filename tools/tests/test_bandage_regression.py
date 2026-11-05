#!/usr/bin/env python3
"""Regression tests for real ZCity bandage treatment and its progress UI.

Run from the repository root:
    python3 tools/tests/test_bandage_regression.py

The runtime tests use lupa when available (the main suite also looks in
/tmp/lupa_pkg).  Static protocol checks always run.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / "woundsystem_zcity_compat"
ORGANISM = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua"
SERVER = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat.lua"
MINIGAMES = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_minigames.lua"
CLIENT_MINIGAMES = CONN / "lua/autorun/client/cl_zcity_woundsystem_compat_minigames.lua"
BANDAGE = CONN / "lua/autorun/client/wszc_cl_bandage.lua"

results = []


def check(name, value):
    ok = bool(value)
    results.append((name, ok))
    print(("PASS " if ok else "FAIL ") + name)


organism_s = ORGANISM.read_text(encoding="utf-8")
server_s = SERVER.read_text(encoding="utf-8")
minigames_s = MINIGAMES.read_text(encoding="utf-8")
client_minigames_s = CLIENT_MINIGAMES.read_text(encoding="utf-8")
bandage_s = BANDAGE.read_text(encoding="utf-8")

check("S01 bandage treats ordinary wounds; only tourniquet clears arteries",
      "function WSZC.ApplyBandageToOrganism" in organism_s
      and "function WSZC.ApplyTourniquetToOrganism" in organism_s
      and "collect(org.arterialwounds" not in organism_s
      and "wound[1] = math.max(severity - reduction, 0)" in organism_s
      and "org[wound[7]] = 0" in organism_s
      and "WSZC.GetArterialBleeding" in organism_s)
check("S02 neither treatment can be mirrored twice",
      "WSZC.ApplyBandageToOrganism, ctx, ctx.profile, bandageEffectFraction" in server_s
      and "WSZC.ApplyTourniquetToOrganism, ctx" in server_s
      and server_s.count("medicalBefore.limbBleed = tonumber(afterBleed) or medicalBefore.limbBleed") >= 2)
check("S03 progress is measured from real initial/current bleeding",
      '"WSZC_BandageState"' in minigames_s
      and "initialBleed = initialBleed" in minigames_s
      and "(initial - current) / initial" in minigames_s
      and "SendBandageState(ply, session)" in minigames_s)
check("S04 client buffers state and draws explicit STOP percent",
      "WSZC.PendingBandageState" in client_minigames_s
      and "ApplyBleedState" in client_minigames_s
      and '"STOP " .. tostring(percent) .. "%"' in bandage_s
      and '"TOURNIQUET"' in bandage_s
      and "DrawProgressRing" in bandage_s
      and "bleed = MG.bleedCurrent + artery" in bandage_s)

try:
    sys.path.insert(0, "/tmp/lupa_pkg")
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

if LuaRuntime is None:
    print("SKIP runtime checks (lupa unavailable)")
else:
    # ------------------------------------------------------ real treatment --
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
SERVER = true; CLIENT = false
WSZC = { OrganismAuthority = function() return true end }
WoundSystem = { Health = {} }
hg = {}
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
CreateConVar = function(name)
    return { GetBool = function() return name ~= "zc_woundsystem_compat_organism_debug" end }
end
GetConVar = function() return nil end
hook = { Add = function() end, Remove = function() end, GetTable = function() return {} end }
timer = { Simple = function() end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
include = function() end
IsValid = function(v) return v ~= nil and v ~= false end
CurTime = function() return 100 end
print = function() end
ErrorNoHalt = function() end
SetGlobalBool = function() end
''')
    lua.execute(organism_s)
    treated = lua.execute(r'''
local limb = { bleed = 26, isBandaged = false }
WoundSystem.Health.GetLimbState = function() return limb end
local netvars = {}
local ply = { SetNetVar = function(self, key, value) netvars[key] = value end }
ply.organism = {
    owner = ply, bleed = 10, rlegartery = 1,
    wounds = {
        { 10, nil, nil, "ValveBiped.Bip01_R_Thigh", 0 },
        { 7, nil, nil, "ValveBiped.Bip01_L_Hand", 0 },
    },
    arterialwounds = {
        { 2, nil, nil, "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
    },
}
local ctx = { ply = ply, limbId = "thigh_R", limb = limb }
local profile = { effects = { bandageSlowAmount = 45 } }
local amount, before, after = WSZC.ApplyBandageToOrganism(ctx, profile, 1 / 12)
local oneWrap = math.abs(before - 26) < 0.001
    and math.abs(after - 18.5) < 0.001
    and math.abs(amount - 7.5) < 0.001
    and math.abs(ply.organism.bleed - 8.5) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 6.25) < 0.001
    and ply.organism.wounds[2][1] == 7
    and ply.organism.arterialwounds[1][1] == 2
    and netvars.bandaged_limbs["ValveBiped.Bip01_R_Thigh"] == true
    and limb.isBandaged == false -- a second roll may finish a partial treatment

WSZC.ApplyBandageToOrganism(ctx, profile, 1)
local complete = WSZC.GetBandageBleeding(ply, "thigh_R") == 0
    and WSZC.GetArterialBleeding(ply, "thigh_R") == 6
    and WSZC.GetBandageBleeding(ply, "hand_L") == 14
    and #ply.organism.wounds == 1 and ply.organism.wounds[1][1] == 7
    and #ply.organism.arterialwounds == 1 and ply.organism.rlegartery == 1
    and limb.bleed == 6 and limb.isBandaged == false
BandageTestPlayer = ply
BandageTestNetvars = netvars
return oneWrap, complete
''')
    check("R01 one wrap treats only ordinary wounds on the selected limb", treated[0])
    check("R02 bandage closes normal wounds but never clears an artery", treated[1])

    tourniquet = lua.execute(r'''
local ply = BandageTestPlayer
local netvars = BandageTestNetvars
local limb = WoundSystem.Health.GetLimbState()
local amount, before, after = WSZC.ApplyTourniquetToOrganism({
    ply = ply, limbId = "thigh_R", limb = limb,
})
local arteryClosed = math.abs(before - 6) < 0.001 and after == 0 and amount == 6
    and #ply.organism.arterialwounds == 0 and ply.organism.rlegartery == 0
    and #ply.organism.wounds == 1 and ply.organism.wounds[1][1] == 7
    and limb.bleed == 0 and ply.tourniquets[1][3] == "ValveBiped.Bip01_R_Thigh"
    and netvars.Tourniquets == ply.tourniquets
    and hg.TourniquetGuys[1] == ply

local states = {}
WoundSystem.Health.GetLimbState = function(_, id)
    states[id] = states[id] or { bleed = 0 }
    return states[id]
end
local downstream = {
    SetNetVar = function() end,
    organism = {
        bleed = 10, rlegartery = 1, wounds = {
            { 2, nil, nil, "ValveBiped.Bip01_R_Foot", 0 },
            { 7, nil, nil, "ValveBiped.Bip01_L_Hand", 0 },
        },
        arterialwounds = {
            { 2, nil, nil, "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
        },
    },
}
downstream.organism.owner = downstream
WSZC.ApplyTourniquetToOrganism({ ply = downstream, limbId = "thigh_R" })
local downstreamClosed = #downstream.organism.wounds == 1
    and downstream.organism.wounds[1][1] == 7
    and states.foot_R.bleed == 0 and states.thigh_R.bleed == 0
return arteryClosed, downstreamClosed
''')
    check("R05 tourniquet really closes artery and syncs native markers", tourniquet[0])
    check("R06 tourniquet closes ordinary downstream wounds only", tourniquet[1])

    # ----------------------------------------------------- server progress --
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
SERVER = true; CLIENT = false
WSZC = {
    Bridged = function() return true end,
    OrganismAuthority = function() return true end,
    BandageProfile = function() return { durabilityPerWrap = 10 } end,
    GetBandageBleeding = function(ply) return ply._bleed end,
    GetArterialBleeding = function(ply) return ply._arterial or 0 end,
    Warn = function(msg) error(msg) end,
    H = {},
}
WoundSystem = { Health = { Constants = {} } }
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
CreateConVar = function() return { GetBool = function() return true end } end
GetConVar = function() return nil end
FindMetaTable = function() return nil end
CurTime = function() return 100 end
IsValid = function(v) return v ~= nil and v ~= false end
util = { AddNetworkString = function() end }
hook = { Add = function() end, Remove = function() end }
timer = { Simple = function() end, Create = function() end, Remove = function() end }
receivers, sent, readQueue = {}, {}, {}
net = {
    Receive = function(name, fn) receivers[name] = fn end,
    Start = function(name) outgoing = { name = name, writes = {} } end,
    WriteUInt = function(v) outgoing.writes[#outgoing.writes + 1] = { "uint", v } end,
    WriteFloat = function(v) outgoing.writes[#outgoing.writes + 1] = { "float", v } end,
    WriteString = function(v) outgoing.writes[#outgoing.writes + 1] = { "string", v } end,
    Send = function() sent[#sent + 1] = outgoing end,
    ReadUInt = function() local v = readQueue[1]; table.remove(readQueue, 1); return v end,
    ReadFloat = function() local v = readQueue[1]; table.remove(readQueue, 1); return v end,
    ReadString = function() local v = readQueue[1]; table.remove(readQueue, 1); return v end,
}
''')
    lua.execute(minigames_s)
    progress = lua.execute(r'''
local ply = { _bleed = 40,
    IsPlayer = function() return true end, Alive = function() return true end }
local target = { _bleed = 40, organism = {}, Alive = function() return true end }
local session = {
    id = 77, kind = "bandage", itemId = "GAUZE", limbId = "thigh_R",
    owner = ply, target = target, startAmount = 100, deferredUsed = 0,
    initialBleed = 40, live = true, lastAckSeq = 0,
    onProgress = function(_, _, cost) target._bleed = math.max(target._bleed - cost, 0) end,
}
WSZC.MinigameSessions[ply] = session
local ok = true
for i = 1, 4 do
    sent, readQueue = {}, { 77, 360 }
    receivers["WSZC_BandageInput"](0, ply)
    local state
    for _, message in ipairs(sent) do
        if message.name == "WSZC_BandageState" then state = message end
    end
    ok = ok and state ~= nil
        and state.writes[1][2] == 77
        and state.writes[2][2] == 40
        and math.abs(state.writes[3][2] - (40 - i * 10)) < 0.001
        and math.abs(state.writes[4][2] - i / 4) < 0.001
        and state.writes[5][2] == 0
end
return ok, session.deferredUsed == 40 and target._bleed == 0
''')
    check("R03 server sends 25/50/75/100% from actual normal remainder", progress[0])
    check("R04 tested input consumes durability once and reaches zero bleed", progress[1])

    arteryState = lua.execute(r'''
local ply, session = next(WSZC.MinigameSessions)
local target = session.target
target._bleed, target._arterial = 0, 6
session.initialBleed = 0
sent, readQueue = {}, { 77, 360 }
receivers["WSZC_BandageInput"](0, ply)
local state
for _, message in ipairs(sent) do
    if message.name == "WSZC_BandageState" then state = message end
end
local stateOk = state ~= nil and state.writes[3][2] == 0
    and state.writes[4][2] == 1 and state.writes[5][2] == 6
return stateOk, session.deferredUsed == 40
''')
    check("R07 artery-only state remains visible and requests tourniquet", arteryState[0])
    check("R08 artery-only bandage input consumes no durability", arteryState[1])

    # ---------------------------------------------------------- client UI --
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
CLIENT = true; SERVER = false
WSZC = {
    MinigameScale = function() return 1 end,
    MinigameFullscreen = function() return false end,
    ApplyFullscreenClip = function() end,
}
WoundSystem = {
    MinigameClip = {
        Begin = function() return false end, End = function() end,
        DrawBackdrop = function() end, MarkOpened = function() end,
    },
    Items = { Get = function()
        return { max = 100, title = "Dressing", use = { bandage = {} } }
    end },
}
WoundSystemInventorySlots = { [6] = { type = "tool", toolName = "GAUZE", durability = 100 } }
WoundSystemMedToolConfig = { GAUZE = { max = 100 } }
WoundSystemClientState = { PlayerLimbs = {} }
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
math.Round = function(v) return math.floor(v + 0.5) end
Lerp = function(t, a, b) return a + (b - a) * t end
Color = function(r, g, b, a) return { r = r, g = g, b = b, a = a or 255 } end
istable = function(v) return type(v) == "table" end
CreateClientConVar = function() return { GetFloat = function() return 1 end } end
include = function(path)
    if string.find(path, "sh_handphysics", 1, true) then
        return { Init = function() end, Step = function() end, Rotation = function() return 0 end }
    end
    return {}
end
file = { Exists = function() return false end }
Material = function(path)
    return { _path = path,
        Width = function() return 25 end, Height = function() return 40 end }
end
ScrW = function() return 1000 end; ScrH = function() return 1000 end
CurTime = function() return 100 end
RealTime = function() return 100 end
IsValid = function(v) return v ~= nil and v ~= false and not v._removed end
MOUSE_LEFT, MOUSE_RIGHT, KEY_ESCAPE = 107, 108, 70
TEXT_ALIGN_CENTER = 1
input = { IsMouseDown = function() return false end, IsKeyDown = function() return false end }
gui = { MousePos = function() return 500, 500 end }
net = { Receive = function() end, Start = function() end, SendToServer = function() end }
hook = { Add = function() end }
timer = { Simple = function() end }
surfaceCalls, textCalls, fontCalls = {}, {}, {}
surface = {
    CreateFont = function(name) fontCalls[#fontCalls + 1] = name end,
    SetMaterial = function(m) surfaceCalls[#surfaceCalls + 1] = { kind = "mat", path = m._path } end,
    SetDrawColor = function() end,
    DrawTexturedRect = function() end, DrawTexturedRectUV = function() end,
    DrawTexturedRectRotated = function() end,
    DrawPoly = function() surfaceCalls[#surfaceCalls + 1] = { kind = "poly" } end,
}
draw = {
    NoTexture = function() end,
    SimpleText = function(text, font)
        textCalls[#textCalls + 1] = { text = text, font = font }
    end,
}
vgui = { Create = function()
    return { SetSize = function() end, SetPos = function() end, SetZPos = function() end,
        SetMouseInputEnabled = function() end, SetKeyboardInputEnabled = function() end,
        SetPaintBackground = function() end,
        Remove = function(self) self._removed = true end }
end }
''')
    lua.execute(bandage_s)
    ui = lua.execute(r'''
local mg = WSZCBandageMinigame
mg.OpenFromServer({ sessionId = 55, limbId = "thigh_R", mode = "gauze", slotIdx = 6 })
local accepted = mg.ApplyBleedState({ sessionId = 55,
    initialBleed = 40, currentBleed = 24, progress = 0.4 })
local rejected = mg.ApplyBleedState({ sessionId = 54,
    initialBleed = 99, currentBleed = 0, progress = 1 })
textCalls, surfaceCalls = {}, {}
mg.overlay.Paint(mg.overlay, 1000, 1000)
local label, polys = nil, 0
for _, call in ipairs(textCalls) do if call.text == "STOP 40%" then label = call end end
for _, call in ipairs(surfaceCalls) do if call.kind == "poly" then polys = polys + 1 end end
local first = accepted == true and rejected == false and label ~= nil
    and string.find(label.font, "WSZCBandageProgress", 1, true) == 1
    and polys > 72 and mg.bleedCurrent == 24

mg.ApplyBleedState({ sessionId = 55, initialBleed = 40, currentBleed = 0, progress = 1 })
mg.bleedDisplayProgress = 1 -- skip the cosmetic interpolation for the assertion
textCalls, surfaceCalls = {}, {}
mg.overlay.Paint(mg.overlay, 1000, 1000)
local stopped, bloodIcon = false, false
for _, call in ipairs(textCalls) do if call.text == "STOP 100%" then stopped = true end end
for _, call in ipairs(surfaceCalls) do
    if call.kind == "mat" and string.find(call.path, "casunknown-images/icons/", 1, true) then
        bloodIcon = true
    end
end
mg.ApplyBleedState({ sessionId = 55,
    initialBleed = 0, currentBleed = 0, progress = 1, arterialBleed = 6 })
textCalls, surfaceCalls = {}, {}
mg.overlay.Paint(mg.overlay, 1000, 1000)
local needsTourniquet, arteryIcon = false, false
for _, call in ipairs(textCalls) do if call.text == "TOURNIQUET" then needsTourniquet = true end end
for _, call in ipairs(surfaceCalls) do
    if call.kind == "mat" and string.find(call.path, "casunknown-images/icons/", 1, true) then
        arteryIcon = true
    end
end
return first, stopped and not bloodIcon, needsTourniquet and arteryIcon
''')
    check("R09 client draws server percentage and rejects stale sessions", ui[0])
    check("R10 ordinary 100% is complete and the blood drop disappears", ui[1])
    check("R11 remaining artery keeps drop and shows TOURNIQUET", ui[2])

passed = sum(1 for _, ok in results if ok)
print("TEST_OK %d / %d" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
