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
STANDALONE = CONN / "lua/weapons/weapon_wszc_bandage.lua"

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
standalone_s = STANDALONE.read_text(encoding="utf-8")

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
check("S04 client buffers state/STOP percent and never predicts fixed C:U cost",
      "WSZC.PendingBandageState" in client_minigames_s
      and "ApplyBleedState" in client_minigames_s
      and '"STOP " .. tostring(percent) .. "%"' in bandage_s
      and '"TOURNIQUET"' in bandage_s
      and "DrawProgressRing" in bandage_s
      and "bleed = MG.bleedCurrent + artery" in bandage_s
      and "predictedCost" not in bandage_s)
check("S05 reverse unwrap has independent angular progress and no item cost",
      'net.WriteString("unwrap")' in minigames_s
      and 'session.mode == "unwrap"' in minigames_s
      and 'session.unwrapProgress' in minigames_s
      and 'MG.mode == "unwrap"' in bandage_s
      and 'MG.totalDegreesUnwrapped' in bandage_s
      and 'MG.lastUnwrapActionAngle' in bandage_s
      and 'return -- no durability, bleeding treatment or foreign onProgress' in minigames_s
      and '"UNWRAP " .. tostring(percent) .. "%"' in bandage_s
      and 'matInfection' in bandage_s)
check("S06 standalone bandage owns its SWEP and bypasses Workshop Heal",
      'SWEP.Base = "weapon_base"' in standalone_s
      and 'SWEP.Base = "weapon_bandage_sh"' not in standalone_s
      and 'WB.SwepHeal(' not in standalone_s
      and 'function SWEP:PrimaryAttack()' in standalone_s
      and 'function SWEP:SecondaryAttack()' in standalone_s
      and 'UseStandalone(self, false)' in standalone_s
      and 'UseStandalone(self, true)' in standalone_s
      and 'function WSZC.UseStandaloneBandage' in minigames_s)

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
    and math.abs(after - 14.75) < 0.001
    and math.abs(amount - 11.25) < 0.001
    and math.abs(ply.organism.bleed - 7.75) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 4.375) < 0.001
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

    amputated_bandage = lua.execute(r'''
local netvars = {}
local ply = {
    SetNetVar = function(self, key, value) netvars[key] = value end,
    _limbs = {
        arm_R = { bleed = 14, isBandaged = false, dismembered = false },
        forearm_R = { bleed = 14, dismembered = true },
        hand_R = { bleed = 14, dismembered = true },
        thigh_L = { bleed = 100, dismembered = false },
    },
}
ply.organism = {
    owner = ply, bleed = 20, rarmamputated = true, rarmartery = 1,
    wounds = {
        { 4, nil, nil, "ValveBiped.Bip01_R_Forearm", 0 },
    },
    arterialwounds = {
        { 2, nil, nil, "ValveBiped.Bip01_R_Forearm", 0, nil, "rarmartery" },
    },
}
WoundSystem.Health.GetLimbs = function(target) return target._limbs end
WoundSystem.Health.GetLimbState = function(target, id)
    return target._limbs[id]
end
local routed = WSZC.GetBandageBleeding(ply, "arm_R") == 8
    and WSZC.GetArterialBleeding(ply, "arm_R") == 6
    and WSZC.BestBandageLimb(ply, "forearm_R") == "arm_R"
local amount, before, after = WSZC.ApplyBandageToOrganism({
    ply = ply, limbId = "arm_R", limb = ply._limbs.arm_R,
}, { effects = { bandageSlowAmount = 45 } }, 1)
local treated = math.abs(amount - 8) < 0.001 and math.abs(before - 14) < 0.001
    and math.abs(after - 6) < 0.001
    and WSZC.GetBandageBleeding(ply, "arm_R") == 0
    and WSZC.GetArterialBleeding(ply, "arm_R") == 6
    and #ply.organism.wounds == 0 and #ply.organism.arterialwounds == 1
    and ply.organism.arterialwounds[1][1] == 2 and ply.organism.rarmartery == 1
    and math.abs(ply.organism.bleed - 18.4) < 0.001
    and ply._limbs.arm_R.bleed == 6 and ply._limbs.arm_R.isBandaged == false
    and WSZC.BestBandageLimb(ply, "forearm_R") == nil
return routed, treated
''')
    check("R26 confirmed amputation routes bandage selection and progress to the stump", amputated_bandage[0])
    check("R27 stump bandage treats the real distal wound without clearing its artery", amputated_bandage[1])

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
include = function() end
player = { GetAll = function() return {} end }
game = { GetAmmoName = function() return "9mm" end }
isnumber = function(v) return type(v) == "number" end
isvector = function(v) return type(v) == "table" and v._isVector == true end
Vector = function(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _isVector = true }
    v.GetNegated = function(self) return Vector(-self.x, -self.y, -self.z) end
    return v
end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
vector_origin = Vector(0, 0, 0)
angle_zero = Angle(0, 0, 0)
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
    lua.execute(organism_s)
    lua.execute(r'''
WSZC.RealApplyBandageToOrganism = WSZC.ApplyBandageToOrganism
WSZC.RealTickLodgedShrapnel = WSZC.TickLodgedShrapnel
WSZC.RealTickShrapnelAftercare = WSZC.TickShrapnelAftercare
WSZC.RealTickBandagedShrapnel = WSZC.TickBandagedShrapnel
WSZC.RealIsShrapnelBandaged = WSZC.IsShrapnelBandaged
WSZC.RealGetBandageBleeding = WSZC.GetBandageBleeding
WSZC.RealAddShrapnel = WSZC.AddShrapnel
WSZC.GetBandageBleeding = function(ply) return ply._bleed end
WSZC.GetArterialBleeding = function(ply) return ply._arterial or 0 end
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

    real_input = lua.execute(r'''
WSZC.MinigameSessions = {}
WSZC.GetBandageBleeding = WSZC.RealGetBandageBleeding
WSZC.IsShrapnelBandaged = WSZC.RealIsShrapnelBandaged
WoundSystem.Health.Constants.ShrapnelPieceCount = 5
WoundSystem.Health.GetLimbs = function(ply) return ply._limbs end
WoundSystem.Health.GetLimbState = function(ply, id) return ply._limbs[id] end
WoundSystem.Health.GetBody = function(ply) return ply._body end
WoundSystem.Health.SendLimbUpdate = function() end
WoundSystem.Health.SendCardioUpdate = function() end
local function Patient()
    local ply = {
        _limbs = {
            hand_R = { shrapnel = 0, bleed = 0, pain = 0, infection = 0,
                       infectionSpeed = 0, muscle = 100, skin = 100 },
            thorax = { infection = 0, infectionSpeed = 0 },
            head = { infection = 0, infectionSpeed = 0 },
        },
        _body = {},
        IsPlayer = function() return true end, Alive = function() return true end,
        SetNetVar = function() end,
    }
    ply.organism = { owner = ply, consciousness = 1, blood = 5000, bleed = 0,
        pain = 0, avgpain = 0, painadd = 0, wounds = {}, arterialwounds = {} }
    return ply
end
local patient = Patient()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun")
local operator = Patient()
local perWrap = 100 / 12
WSZC.BandageProfile = function()
    return { durabilityPerWrap = perWrap, effectDivisor = 12,
             effects = { bandageSlowAmount = 45 } }
end
local session = {
    id = 88, kind = "bandage", itemId = "GAUZE", limbId = "hand_R",
    owner = operator, target = patient, startAmount = 100, deferredUsed = 0,
    initialBleed = WSZC.RealGetBandageBleeding(patient, "hand_R"),
    live = true, lastAckSeq = 0,
    onProgress = function(_, _, cost)
        WSZC.RealApplyBandageToOrganism(
            { ply = patient, limbId = "hand_R", limb = patient._limbs.hand_R },
            { effects = { bandageSlowAmount = 45 } }, (cost / perWrap) / 12)
    end,
}
WSZC.MinigameSessions[operator] = session
for _ = 1, 12 do
    sent, readQueue = {}, { 88, 360 }
    receivers["WSZC_BandageInput"](0, operator)
    WSZC.RealTickLodgedShrapnel(patient, patient.organism, 0.5)
    WSZC.RealTickShrapnelAftercare(patient, patient.organism, 0.5)
    WSZC.RealTickBandagedShrapnel(patient, patient.organism, 0.5)
end
local infection = patient.organism.wszc_bandaged_shrapnel.hand_R
local oneRealTurn = patient._limbs.hand_R.shrapnel == 5
    and WSZC.RealGetBandageBleeding(patient, "hand_R") == 0
    and WSZC.RealIsShrapnelBandaged(patient, "hand_R")
    and math.abs(session.deferredUsed - perWrap) < 0.001
    and infection and infection.infectionAge > 0

-- A clotted extraction wound still requires the FINAL dressing.  The zero-
-- bleed fast path must not discard this input (artery-only remains covered by
-- R08 above and still spends nothing).
WSZC.MinigameSessions = {}
local finalPatient = Patient()
finalPatient.organism.wszc_shrapnel_aftercare = {
    hand_R = { awaitingBandage = true, age = 1, baseSeverity = 0.3 },
}
finalPatient.organism.wounds = {{
    0, Vector(0, 0, 0), Angle(0, 0, 0), "ValveBiped.Bip01_R_Hand", CurTime(),
    wszcShrapnelExtraction = "WSZC_SHRAPNEL_EXTRACTION", wszcLimb = "hand_R",
}}
local finalSession = {
    id = 89, kind = "bandage", itemId = "GAUZE", limbId = "hand_R",
    owner = operator, target = finalPatient, startAmount = 100, deferredUsed = 0,
    initialBleed = 0, live = true, lastAckSeq = 0,
    onProgress = function(_, _, cost)
        WSZC.RealApplyBandageToOrganism(
            { ply = finalPatient, limbId = "hand_R", limb = finalPatient._limbs.hand_R },
            { effects = { bandageSlowAmount = 45 } }, (cost / perWrap) / 12)
    end,
}
WSZC.MinigameSessions[operator] = finalSession
local wasPending = WSZC.ShrapnelAftercarePending(finalPatient, "hand_R")
sent, readQueue = {}, { 89, 360 }
receivers["WSZC_BandageInput"](0, operator)
local extractionLeft = false
for _, wound in pairs(finalPatient.organism.wounds) do
    if wound.wszcShrapnelExtraction then extractionLeft = true end
end
local finalDressing = wasPending
    and not WSZC.ShrapnelAftercarePending(finalPatient, "hand_R")
    and not extractionLeft and math.abs(finalSession.deferredUsed - perWrap) < 0.001
BandagePatientFactory = Patient
BandageNativePerWrap = perWrap
return oneRealTurn, finalDressing
''')
    check("R15 real server GAUZE input stops max shrapnel in one turn without reroll", real_input[0])
    check("R16 real server input accepts the required zero-bleed aftercare dressing", real_input[1])

    native_cost = lua.execute(r'''
WSZC.MinigameSessions = {}
local Patient, perWrap = BandagePatientFactory, BandageNativePerWrap
WSZC.H.ApplyItemToBody = function(target, itemId, limbId, amount)
    WSZC.RealApplyBandageToOrganism(
        { ply = target, limbId = limbId, limb = target._limbs[limbId] },
        { effects = { bandageSlowAmount = 45 } }, amount / (perWrap * 12))
    return true, amount
end
local function NewSwep(def)
    return { modeValues = { def }, modeValuesdef = { { def, true } }, _net = {},
        SetNetVar = function(self, key, value) self._net[key] = value end }
end
local function NewNativeSession(id, patient, swep, def, startAmount)
    local operator = Patient()
    local appliedLive, progressCalls = 0, 0
    local progress = function()
        progressCalls = progressCalls + 1
        appliedLive = appliedLive + 1
    end
    local appliedLiveIdx
    for i = 1, 20 do
        local name = debug.getupvalue(progress, i)
        if not name then break end
        if name == "appliedLive" then appliedLiveIdx = i break end
    end
    local session = {
        id = id, kind = "bandage", itemId = "GAUZE", limbId = "hand_R",
        owner = operator, target = patient, startAmount = startAmount,
        deferredUsed = 0, initialBleed = WSZC.RealGetBandageBleeding(patient, "hand_R"),
        live = true, lastAckSeq = 0, onProgress = progress, onClose = function() end,
        nativeBandage = { swep = swep, idx = 1, def = def, maxDur = 100,
                          appliedLiveIdx = appliedLiveIdx },
        _calls = function() return progressCalls end,
        _applied = function()
            for i = 1, 20 do
                local name, value = debug.getupvalue(progress, i)
                if not name then break end
                if name == "appliedLive" then return value end
            end
        end,
    }
    WSZC.MinigameSessions[operator] = session
    return session, operator
end
NativeBandageSessionFactory = NewNativeSession
NativeBandageSwepFactory = NewSwep

local smallPatient = Patient()
WSZC.RealAddShrapnel(smallPatient, "hand_R", 3, "shotgun") -- five pieces, severity 4
local smallSwep = NewSwep(40)
local operator = Patient()
local spec = { mg = { kind = "bandage" }, kind = "item", item = "GAUZE" }
local swep, idx, target = smallSwep, 1, smallPatient
local live, oneDose, maxDur, appliedLive, progressCalls = true, false, 100, 0, 0
local data = { kind = "bandage", itemId = "GAUZE", limbId = "hand_R", amount = 100 }
-- Reproduce WB.StartMinigame's shared-upvalue closure shape: every native
-- value is genuinely captured, and appliedLive is shared with onClose.
data.onProgress = function()
    progressCalls = progressCalls + 1
    if live and not oneDose and IsValid(swep) and IsValid(target) then
        local _ = spec.item .. tostring(idx) .. tostring(maxDur)
        appliedLive = appliedLive + 1
    end
end
data.onClose = function()
    local _ = spec.item .. tostring(idx) .. tostring(maxDur) .. tostring(appliedLive)
    if not IsValid(swep) or not IsValid(target) or not live or oneDose then return end
end
WSZC.Ready = true
WSZC.BridgeEnabled = function() return true end
WoundSystem.Items = {
    Get = function() return { max = 100, title = "Dressing", use = { bandage = {} } } end,
    GetMax = function() return 100 end,
}
WSZC.MinigameSessions = {}
local started = WSZC.StartExternalMinigameImpl(operator, data)
local small = WSZC.MinigameSessions[operator]
sent, readQueue = {}, { small and small.id or 0, 360 }
if small then receivers["WSZC_BandageInput"](0, operator) end
local appliedValue = 0
for i = 1, 20 do
    local name, value = debug.getupvalue(data.onProgress, i)
    if not name then break end
    if name == "appliedLive" then appliedValue = value end
end
local smallOK = started and small and small.nativeBandage
    and small.nativeBandage.swep == smallSwep and small.nativeBandage.def == 40
    and smallSwep.modeValues[1] == 36
    and math.abs(small.deferredUsed - 10) < 0.001
    and progressCalls == 0 and math.abs(appliedValue - 10) < 0.001
    and WSZC.RealGetBandageBleeding(smallPatient, "hand_R") == 0
    and smallSwep._net.modeValues == smallSwep.modeValues

WSZC.MinigameSessions = {}
local bigPatient = Patient()
WSZC.RealAddShrapnel(bigPatient, "hand_R", 3, "shotgun")
local bigSwep = NewSwep(150)
local big = NativeBandageSessionFactory(102, bigPatient, bigSwep, 150, 100)
sent, readQueue = {}, { 102, 360 }
receivers["WSZC_BandageInput"](0, big.owner)
local bigOK = bigSwep.modeValues[1] == 146
    and math.abs(big.deferredUsed - (4 * 100 / 150)) < 0.001
    and big._calls() == 0 and WSZC.RealGetBandageBleeding(bigPatient, "hand_R") == 0
return smallOK, bigOK
''')
    check("R18 native 40-unit bandage spends exactly four severity, with no double consume", native_cost[0])
    check("R19 native 150-unit big bandage spends the same four severity, not C:U percent", native_cost[1])

    native_edge = lua.execute(r'''
WSZC.MinigameSessions = {}
local Patient = BandagePatientFactory
local patient = Patient()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun") -- severity 4, only 1 unit left
local swep = NativeBandageSwepFactory(40)
swep.modeValues[1] = 1
local session = NativeBandageSessionFactory(103, patient, swep, 40, 2.5)
sent, readQueue = {}, { 103, 360 }
receivers["WSZC_BandageInput"](0, session.owner)
local capped = swep.modeValues[1] == 0
    and math.abs(session.deferredUsed - 2.5) < 0.001
    and math.abs(WSZC.RealGetBandageBleeding(patient, "hand_R") - 6) < 0.001
    and WSZC.MinigameSessions[session.owner] == nil and session._calls() == 0

WSZC.MinigameSessions = {}
local finalPatient = Patient()
finalPatient.organism.wszc_shrapnel_aftercare = {
    hand_R = { awaitingBandage = true, age = 1, baseSeverity = 0.3 },
}
finalPatient.organism.wounds = {{
    0, Vector(0, 0, 0), Angle(0, 0, 0), "ValveBiped.Bip01_R_Hand", CurTime(),
    wszcShrapnelExtraction = "WSZC_SHRAPNEL_EXTRACTION", wszcLimb = "hand_R",
}}
local finalSwep = NativeBandageSwepFactory(40)
local finalSession = NativeBandageSessionFactory(104, finalPatient, finalSwep, 40, 100)
sent, readQueue = {}, { 104, 360 }
receivers["WSZC_BandageInput"](0, finalSession.owner)
local aftercareFree = finalSwep.modeValues[1] == 40
    and finalSession.deferredUsed == 0 and finalSession._calls() == 0
    and math.abs(finalSession._applied() - 0.02) < 0.001
    and not WSZC.ShrapnelAftercarePending(finalPatient, "hand_R")
return capped, aftercareFree
''')
    check("R20 nearly empty ZCity bandage cannot overheal beyond its last severity unit", native_edge[0])
    check("R21 native zero-severity aftercare completes without spending a clean item", native_edge[1])

    unwrap = lua.execute(r'''
WSZC.MinigameSessions = {}
WSZC.Ready = true
WSZC.IsShrapnelBandaged = function(ply) return ply._covered == true end
local removed = 0
WSZC.RemoveBandageForShrapnel = function(ply, limbId)
    if limbId ~= "hand_R" or not ply._covered then return false end
    ply._covered = false
    removed = removed + 1
    return true
end
local ply = {
    _covered = true, organism = { consciousness = 1 },
    IsPlayer = function() return true end, Alive = function() return true end,
}
local started = WSZC.StartShrapnelUnwrap(ply, "hand_R")
local session = WSZC.MinigameSessions[ply]
local openMode = false
for _, message in ipairs(sent) do
    if message.name == "WSZC_BandageOpen" then
        openMode = message.writes[3][2] == "unwrap"
    end
end
local startedOK = started and session and session.mode == "unwrap"
    and session.itemId == "WSZC_UNWRAP" and session.unwrapRequired == 360
    and session.unwrapProgress == 0 and session.deferredUsed == 0 and openMode

sent, readQueue = {}, { session.id, 180 }
receivers["WSZC_BandageInput"](0, ply)
local halfState
for _, message in ipairs(sent) do
    if message.name == "WSZC_BandageState" then halfState = message end
end
local halfOK = ply._covered and removed == 0
    and WSZC.MinigameSessions[ply] == session
    and session.unwrapProgress == 180 and session.deferredUsed == 0
    and halfState and halfState.writes[4][2] == 0.5

sent, readQueue = {}, { session.id, 180 }
receivers["WSZC_BandageInput"](0, ply)
local closeReason
for _, message in ipairs(sent) do
    if message.name == "WSZC_BandageClose" then closeReason = message.writes[2][2] end
end
local completeOK = not ply._covered and removed == 1
    and WSZC.MinigameSessions[ply] == nil and session.closed == true
    and session.unwrapProgress == 360 and session.deferredUsed == 0
    and closeReason == "unwrapped"
return startedOK, halfOK, completeOK
''')
    check("R09 covered shrapnel opens a virtual reverse-bandage session", unwrap[0])
    check("R10 180 reverse degrees keep the dressing on and spend no item", unwrap[1])
    check("R11 360 reverse degrees unwrap exactly once and close the session", unwrap[2])

    # Keep the authoritative server runtime for the final client->net->server
    # end-to-end regression below.
    server_lua = lua

    # ---------------------------------------------------------- client UI --
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
CLIENT = true; SERVER = false
WSZC = {
    MinigameScale = function() return 1 end,
    MinigameFullscreen = function() return false end,
    ApplyFullscreenClip = function() end,
    HandRectAtPivot = function(cx, cy, w, h, rot, px, py)
        local lx, ly = (0.5 - px) * w, (0.5 - py) * h
        local a = math.rad(rot or 0)
        local c, s = math.cos(a), math.sin(a)
        return cx + lx * c - ly * s, cy + lx * s + ly * c, w, h
    end,
}
WoundSystem = {
    MinigameClip = {
        Begin = function() return false end, End = function() end,
        DrawBackdrop = function() end, MarkOpened = function() end,
        DrawHeader = function() end, DrawExitGuide = function() end,
    },
    Items = { Get = function()
        return { max = 100, title = "Dressing", use = { bandage = {} } }
    end },
}
WoundSystemInventorySlots = { [6] = { type = "tool", toolName = "GAUZE", durability = 100 } }
WoundSystemMedToolConfig = { GAUZE = { max = 100 } }
WoundSystemClientState = { PlayerLimbs = {} }
DevMinigameCfg = {}
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
math.Round = function(v) return math.floor(v + 0.5) end
math.atan2 = function(y, x) return math.atan(y, x) end
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
file = { Exists = function(path)
    return string.find(path, "sh_handphysics", 1, true) ~= nil
end }
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
mouseDown = false
input = { IsMouseDown = function() return mouseDown end, IsKeyDown = function() return false end }
gui = { MousePos = function() return 500, 500 end,
    IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end }
net = { Receive = function() end, Start = function() end, SendToServer = function() end,
    WriteUInt = function() end, WriteFloat = function() end }
hook = { _t = {}, Add = function(event, name, fn) hook._t[name] = fn end }
timer = { Simple = function() end }
surfaceCalls, textCalls, fontCalls = {}, {}, {}
surface = {
    CreateFont = function(name) fontCalls[#fontCalls + 1] = name end,
    SetMaterial = function(m) surfaceCalls[#surfaceCalls + 1] = { kind = "mat", path = m._path } end,
    SetDrawColor = function() end,
    DrawTexturedRect = function() end, DrawTexturedRectUV = function() end,
    DrawTexturedRectRotated = function(x, y, w, h, rot)
        surfaceCalls[#surfaceCalls + 1] = { kind = "rot", x = x, y = y, w = w, h = h, rot = rot }
    end,
    PlaySound = function() end,
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

    hand_pivot = lua.execute(r'''
local mg = WSZCBandageMinigame
mg.active = true
mg.handPos = { x = 0, y = 0 }
local devCfg
for i = 1, 60 do
    local name, value = debug.getupvalue(mg.overlay.PaintOver, i)
    if not name then break end
    if name == "DevMinigameCfg" then devCfg = value break end
end
devCfg.bandageHandOffsetX = 20
devCfg.bandageHandOffsetY = -30
WSZC.UnitmenuHandAngle = function() return 37 end
surfaceCalls = {}
mg.overlay.PaintOver(mg.overlay, 1000, 1000)
local call
for _, candidate in ipairs(surfaceCalls) do
    if candidate.kind == "rot" then call = candidate end
end
WSZC.UnitmenuHandAngle = nil
if not call then return false end
local a = math.rad(call.rot)
local co, si = math.cos(a), math.sin(a)
local ox, oy = (0.4 - 0.5) * call.w, (0.1 - 0.5) * call.h
local gripX = call.x + ox * co - oy * si
local gripY = call.y + ox * si + oy * co
-- BaseScale is the mocked CFG.ScaleMultiplier = 1.7.
local targetX, targetY = 500 + 20 * 1.7, 500 - 30 * 1.7
return call.rot == 37 and math.abs(gripX - targetX) < 0.001
    and math.abs(gripY - targetY) < 0.001
''')
    check("R17 legacy unpinned WSZC hand keeps C:U offset and rotated pivot", hand_pivot)

    pinned_hand = lua.execute(r'''
local mg = WSZCBandageMinigame
WSZC.MinigameHandPinned = function() return true end
mg.active = true
mg.handPos = { x = 0, y = 0 }
local devCfg
for i = 1, 60 do
    local name, value = debug.getupvalue(mg.overlay.PaintOver, i)
    if not name then break end
    if name == "DevMinigameCfg" then devCfg = value break end
end
devCfg.bandageHandOffsetX = 100
devCfg.bandageHandOffsetY = 400
WSZC.UnitmenuHandAngle = function() return 37 end
surfaceCalls = {}
mg.overlay.PaintOver(mg.overlay, 1000, 1000)
local call
for _, candidate in ipairs(surfaceCalls) do
    if candidate.kind == "rot" then call = candidate end
end
WSZC.UnitmenuHandAngle = nil
WSZC.MinigameHandPinned = nil
if not call then return false end
local a = math.rad(call.rot)
local co, si = math.cos(a), math.sin(a)
local ox, oy = (0.4 - 0.5) * call.w, (0.1 - 0.5) * call.h
local gripX = call.x + ox * co - oy * si
local gripY = call.y + ox * si + oy * co
return call.rot == 37 and math.abs(gripX - 500) < 0.001
    and math.abs(gripY - 500) < 0.001
''')
    check("R22 pinned WSZC hand ignores the 100/400 offset at arbitrary rotation", pinned_hand)

    pinned_think = lua.execute(r'''
local mg = WSZCBandageMinigame
local think = hook._t.WSZC_BandageInput
local hp
for i = 1, 80 do
    local name, value = debug.getupvalue(think, i)
    if not name then break end
    if name == "HandPhysics" then hp = value break end
end
local oldStep = hp.Step
local physicsCalls = 0
hp.Step = function(mg)
    physicsCalls = physicsCalls + 1
    mg.handScreenX, mg.handScreenY = 0, 0
end
WSZC.MinigameHandPinned = function() return true end
WSZC.PinMinigameHandToCursor = function(mg)
    local mx, my = gui.MousePos()
    mg.handScreenX, mg.handScreenY = mx, my
    mg.handScreenVelX, mg.handScreenVelY = 0, 0
    mg._hp_acc = 0
    return mx, my
end
mg.OpenFromServer({ sessionId = 88, limbId = "hand_R", mode = "gauze", slotIdx = 6 })
mg.handScreenVelX, mg.handScreenVelY, mg._hp_acc = 8, -4, 3
think() -- cursor is (500,500), inside the old collision radius
local exact = physicsCalls == 0 and mg.handScreenX == 500 and mg.handScreenY == 500
    and mg.handPos.x == 0 and mg.handPos.y == 0
    and mg.handScreenVelX == 0 and mg.handScreenVelY == 0 and mg._hp_acc == 0
hp.Step = oldStep
WSZC.MinigameHandPinned = nil
WSZC.PinMinigameHandToCursor = nil
return exact
''')
    check("R23 real WSZC Think bypasses spring and centre collision in cursor mode", pinned_think)

    client_unwrap = lua.execute(r'''
local mg = WSZCBandageMinigame
local think = hook._t.WSZC_BandageInput
local function place(physicalAngle)
    local rad = math.rad(physicalAngle)
    local scale = 1.7 -- CFG.ScaleMultiplier with the mocked 1000x1000 screen
    mg.handScreenX = 500 + math.sin(rad) * 260 * scale
    mg.handScreenY = 500 - math.cos(rad) * 260 * scale
end
local function openUnwrap()
    mouseDown = false
    mg.OpenFromServer({ sessionId = 77, limbId = "hand_R", mode = "unwrap", slotIdx = 6 })
    place(0)
    think()
    mouseDown = true
end
openUnwrap()
for angle = 5, 90, 5 do place(angle); think() end
local forwardDegrees = mg.totalDegreesUnwrapped

openUnwrap()
for angle = -5, -360, -5 do place(angle); think() end
local reverseDegrees = mg.totalDegreesUnwrapped
mg.ApplyBleedState({ sessionId = 77, initialBleed = 360, currentBleed = 0, progress = 1 })
mg.bleedDisplayProgress = 1
textCalls, surfaceCalls = {}, {}
mg.overlay.Paint(mg.overlay, 1000, 1000)
local unwrapLabel, infectionIcon = false, false
for _, call in ipairs(textCalls) do
    if call.text == "UNWRAP 100%" then unwrapLabel = true end
end
for _, call in ipairs(surfaceCalls) do
    if call.kind == "mat" and call.path == "casunknown-images/icons/infection.png" then
        infectionIcon = true
    end
end
return forwardDegrees == 0, reverseDegrees >= 360, unwrapLabel and infectionIcon
''')
    check("R12 forward wrapping motion does not count as reverse unwrapping", client_unwrap[0])
    check("R13 a reverse circle accumulates 360 degrees in the real client Think", client_unwrap[1])
    check("R14 completed unwrap shows UNWRAP percent and standard infection icon", client_unwrap[2])

    # --------------------------------------- real client -> net -> server ---
    client_circle = lua.execute(r'''
local mg = WSZCBandageMinigame
local think = hook._t.WSZC_BandageInput
local clock = 200
CurTime = function() return clock end
WSZC.MinigameHUDOpen = true
WSZC.MinigameHandPinned = function() return true end
WSZC.PinMinigameHandToCursor = function(mg)
    local mx, my = gui.MousePos()
    mg.handScreenX, mg.handScreenY = mx, my
    mg.handScreenVelX, mg.handScreenVelY = 0, 0
    mg._hp_acc = 0
    return mx, my
end

ClientWire, wire = {}, nil
net.Start = function(name) wire = { name = name, writes = {} } end
net.WriteUInt = function(value) wire.writes[#wire.writes + 1] = { "uint", value } end
net.WriteFloat = function(value) wire.writes[#wire.writes + 1] = { "float", value } end
net.WriteString = function(value) wire.writes[#wire.writes + 1] = { "string", value } end
net.SendToServer = function()
    ClientWire[#ClientWire + 1] = wire
    wire = nil
end

local function place(physicalAngle)
    local rad = math.rad(physicalAngle)
    local scale = 1.7 -- mocked 1000x1000, fullscreen off => CFG 1.7
    local x = 500 + math.sin(rad) * 260 * scale
    local y = 500 - math.cos(rad) * 260 * scale
    gui.MousePos = function() return x, y end
end

mouseDown = false
place(0)
mg.OpenFromServer({ sessionId = 105, limbId = "hand_R", mode = "gauze", slotIdx = 6 })
think()
mouseDown = true
think()
local grabbed = mg.holdingBandage
for angle = 5, 360, 5 do
    clock = clock + 0.02
    place(angle)
    think()
end
clock = clock + 0.2
think() -- flush the final partial network batch

ClientWireDegrees, ClientWireSessions = {}, {}
local sum = 0
for _, message in ipairs(ClientWire) do
    if message.name == "WSZC_BandageInput" then
        local degrees = message.writes[2][2]
        ClientWireDegrees[#ClientWireDegrees + 1] = degrees
        ClientWireSessions[#ClientWireSessions + 1] = message.writes[1][2]
        sum = sum + degrees
    end
end
ClientCircleOK = grabbed and mg.totalDegreesWrapped >= 360 and sum >= 360
    and #ClientWireDegrees > 0
for _, sessionId in ipairs(ClientWireSessions) do
    if sessionId ~= 105 then ClientCircleOK = false end
end
return ClientCircleOK, mg.totalDegreesWrapped, sum, #ClientWireDegrees
''')
    check("R24 real clockwise client circle emits 360 degrees for the native session", client_circle[0])

    degrees = [float(v) for v in lua.execute('return ClientWireDegrees').values()]
    lua_degrees = ', '.join('%.9g' % value for value in degrees)
    end_to_end = server_lua.execute(r'''
WSZC.MinigameSessions = {}
local Patient = BandagePatientFactory
local patient = Patient()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun") -- severity 4 / bleed 8
local swep = NativeBandageSwepFactory(40)
local session = NativeBandageSessionFactory(105, patient, swep, 40, 100)
NativeCloseReason = nil
session.onClose = function(_, _, reason) NativeCloseReason = reason end
sent = {}
for _, degrees in ipairs(CLIENT_DEGREES) do
    readQueue = { 105, degrees }
    receivers["WSZC_BandageInput"](0, session.owner)
end
local closePacket, slotClose = false, false
for _, message in ipairs(sent) do
    if message.name == "WSZC_BandageClose" and message.writes[2][2] == "completed" then
        closePacket = true
    end
    if message.name == "WSZC_MinigameClose" then slotClose = true end
end
return WSZC.RealGetBandageBleeding(patient, "hand_R") == 0
    and swep.modeValues[1] == 36
    and math.abs(session.deferredUsed - 10) < 0.001
    and session._calls() == 0 -- no second native onProgress consumption
    and session._applied() >= 0.02
    and WSZC.MinigameSessions[session.owner] == nil
    and NativeCloseReason == "completed" and closePacket and slotClose
'''.replace('CLIENT_DEGREES', '{ ' + lua_degrees + ' }'))
    check("R25 client packets really close the wound, spend four units and complete/close server session", end_to_end)

    no_debug = server_lua.execute(r'''
WSZC.MinigameSessions = {}
local Patient = BandagePatientFactory
local patient, operator = Patient(), Patient()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun")
local swep = NativeBandageSwepFactory(40)
local spec = { mg = { kind = "bandage" }, kind = "item", item = "GAUZE" }
local appliedLive, progressCalls = 0, 0
local data = {
    kind = "bandage", itemId = "GAUZE", limbId = "hand_R", amount = 100,
    swep = swep, idx = 1, spec = spec, target = patient, maxDur = 100,
    live = true, oneDose = false,
    _WSZCSetAppliedLive = function(value) appliedLive = value end,
    onProgress = function() progressCalls = progressCalls + 1 end,
    onClose = function() local _ = appliedLive end,
}
local previousDebug = debug
debug = nil
local ok, result = pcall(function()
    WSZC.Ready = true
    WSZC.BridgeEnabled = function() return true end
    local started = WSZC.StartExternalMinigameImpl(operator, data)
    local session = WSZC.MinigameSessions[operator]
    if not session then return false end
    sent, readQueue = {}, { session.id, 360 }
    receivers["WSZC_BandageInput"](0, operator)
    return started and session.nativeBandage and session.nativeBandage.setAppliedLive
        and swep.modeValues[1] == 36 and math.abs(session.deferredUsed - 10) < 0.001
        and math.abs(appliedLive - 10) < 0.001 and progressCalls == 0
        and WSZC.RealGetBandageBleeding(patient, "hand_R") == 0
end)
debug = previousDebug
return ok and result == true
''')
    check("R26 embedded native bandage keeps exact cost without debug upvalues", no_debug)

    standalone = server_lua.execute(r'''
WSZC.MinigameSessions = {}
local patient = BandagePatientFactory()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun")
local swep = NativeBandageSwepFactory(40)
swep.GetOwner = function() return patient end
swep.GetClass = function() return "weapon_wszc_bandage" end
swep.Remove = function(self) self.removed = true end
local previousHg = hg
hg = { WoundBridge = { SwepHeal = function()
    error("standalone bandage called WB.SwepHeal")
end } }
WSZC.Ready = true
WSZC.BridgeEnabled = function() return true end
WSZC.Bridged = function() return true end
local ok, result = pcall(function()
    local started = WSZC.UseStandaloneBandage(swep, patient)
    local session = WSZC.MinigameSessions[patient]
    if not session then return false end
    sent, readQueue = {}, { session.id, 360 }
    receivers["WSZC_BandageInput"](0, patient)
    return started and session.nativeBandage
        and swep.modeValues[1] == 36 and math.abs(session.deferredUsed - 10) < 0.001
        and WSZC.RealGetBandageBleeding(patient, "hand_R") == 0
        and WSZC.LastMedicalHealRoute == "weapon_wszc_bandage -> standalone (true)"
        and string.find(WSZC.LastMinigameStartResult or "", "opened bandage", 1, true) ~= nil
        and swep.removed ~= true
end)
hg = previousHg
return ok and result == true
''')
    check("R27 standalone connector bandage bypasses Workshop Heal with exact cost", standalone)

    standalone_remote = server_lua.execute(r'''
WSZC.MinigameSessions = {}
local operator, patient = BandagePatientFactory(), BandagePatientFactory()
WSZC.RealAddShrapnel(patient, "hand_R", 3, "shotgun")
local swep = NativeBandageSwepFactory(40)
swep.GetOwner = function() return operator end
swep.GetClass = function() return "weapon_wszc_bandage" end
swep.Remove = function(self) self.removed = true end
local pairChecked = false
WSZC.RemoteMedicalValidPair = function(medic, target)
    pairChecked = medic == operator and target == patient
    return pairChecked
end
WSZC.Ready = true
WSZC.BridgeEnabled = function() return true end
WSZC.Bridged = function() return true end
local started = WSZC.UseStandaloneBandage(swep, patient)
local session = WSZC.MinigameSessions[operator]
if not session then return false end
sent, readQueue = {}, { session.id, 360 }
receivers["WSZC_BandageInput"](0, operator)
return started and pairChecked and session.remote and session.target == patient
    and session.nativeBandage and swep.modeValues[1] == 36
    and math.abs(session.deferredUsed - 10) < 0.001
    and WSZC.RealGetBandageBleeding(patient, "hand_R") == 0
    and WSZC.RealGetBandageBleeding(operator, "hand_R") == 0
    and swep.removed ~= true
''')
    check("R28 standalone remote session treats the patient, not the medic", standalone_remote)

    standalone_swep = server_lua.execute(r'''
local previousSwep, previousAddCS = SWEP, AddCSLuaFile
local previousHg = hg
local previousUse = WSZC.UseStandaloneBandage
SWEP = { Primary = {}, Secondary = {} }
AddCSLuaFile = function() end
''' + standalone_s + r'''
local class = SWEP
local operator, patient = BandagePatientFactory(), BandagePatientFactory()
local traced = { marker = true }
local calls, getPlayerCalls, traceCalls = {}, 0, 0
WSZC.UseStandaloneBandage = function(swep, target)
    calls[#calls + 1] = { swep = swep, target = target }
    return true
end
hg = { WoundBridge = {
    GetPlayer = function(ent)
        getPlayerCalls = getPlayerCalls + 1
        return ent == traced and patient or nil
    end,
    SwepHeal = function() error("standalone SWEP called WB.SwepHeal") end,
} }
operator.GetEyeTrace = function()
    traceCalls = traceCalls + 1
    return { Entity = traced }
end
local swep = setmetatable({
    GetOwner = function() return operator end,
    SetNextPrimaryAttack = function() end,
    SetNextSecondaryAttack = function() end,
}, { __index = class })
local ok, result = pcall(function()
    swep:Initialize()
    swep:PrimaryAttack()
    swep:SecondaryAttack()
    return class.Base == "weapon_base" and #calls == 2
        and calls[1].swep == swep and calls[1].target == operator
        and calls[2].swep == swep and calls[2].target == patient
        and getPlayerCalls == 1 and traceCalls == 1
        and swep.modeValues[1] == 40 and swep.modeValuesdef[1][1] == 40
end)
WSZC.UseStandaloneBandage = previousUse
SWEP, AddCSLuaFile, hg = previousSwep, previousAddCS, previousHg
return ok and result == true
''')
    check("R29 real standalone SWEP LMB/RMB route self and traced patient", standalone_swep)

passed = sum(1 for _, ok in results if ok)
print("TEST_OK %d / %d" % (passed, len(results)))
sys.exit(0 if passed == len(results) else 1)
