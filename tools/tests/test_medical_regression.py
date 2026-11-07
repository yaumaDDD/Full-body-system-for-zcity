#!/usr/bin/env python3
"""Executable regressions for ZCity/C:U medical authority mirroring.

The canonical ZCity WoundBridge is loaded from zcity.zip, not replaced by a
SwepHeal mock.  The tests therefore exercise the real instant/body-drug,
minigame onProgress, BloodBagTake and timed-effect call sites.
"""
from pathlib import Path
from zipfile import ZipFile
import sys

ROOT = Path(__file__).resolve().parents[2]
CONN = ROOT / "woundsystem_zcity_compat"
ORGANISM = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat_organism.lua"
SERVER = CONN / "lua/autorun/server/sv_zcity_woundsystem_compat.lua"

results = []


def check(name, value):
    ok = bool(value)
    results.append((name, ok))
    print(("PASS " if ok else "FAIL ") + name)


organism_s = ORGANISM.read_text(encoding="utf-8")
server_s = SERVER.read_text(encoding="utf-8")
with ZipFile(ROOT / "zcity.zip") as archive:
    shared_bridge_s = archive.read("z_city/lua/homigrad/woundbridge/sh_woundbridge.lua").decode("utf-8")
    server_bridge_s = archive.read("z_city/lua/homigrad/woundbridge/sv_woundbridge.lua").decode("utf-8")
    # Offline Lua has no GMod `continue`.  This canonical file uses it only in
    # BestLimb's single loop; goto+label is semantics-preserving test syntax.
    server_bridge_s = server_bridge_s.replace("then continue end", "then goto continue end")
    server_bridge_s = server_bridge_s.replace(
        "\t\t\tbestId, best = id, score\n\t\tend\n\tend\n\n\treturn bestId",
        "\t\t\tbestId, best = id, score\n\t\tend\n\t\t::continue::\n\tend\n\n\treturn bestId",
        1,
    )
    lungs_s = archive.read("z_city/lua/homigrad/organism/tier_1/modules/sv_lungs.lua").decode("utf-8")
    pain_s = archive.read("z_city/lua/homigrad/organism/tier_1/modules/sv_pain.lua").decode("utf-8")
with ZipFile(ROOT / "casualites unknown.zip") as archive:
    native_items_s = archive.read(
        "casualties_unknown_health_system_beta/lua/woundsystem/medical_tools/sh_more_itemcs_items.lua"
    ).decode("utf-8")
    native_awb_s = archive.read(
        "casualties_unknown_health_system_beta/lua/woundsystem/medical_tools/sh_awb_medical_items.lua"
    ).decode("utf-8")
    native_health_s = archive.read(
        "casualties_unknown_health_system_beta/lua/woundsystem/server/sv_health.lua"
    ).decode("utf-8")
    native_splint_s = archive.read(
        "casualties_unknown_health_system_beta/lua/woundsystem/medical_tools/sh_splint.lua"
    ).decode("utf-8")
    native_tourniquet_s = archive.read(
        "casualties_unknown_health_system_beta/lua/woundsystem/medical_tools/sh_tourniquet.lua"
    ).decode("utf-8")

check("S01 native naloxone dose maps to the authoritative ZCity antagonist",
      "antagonistAmount = 50" in native_items_s
      and "after.antagonistAmount - before.antagonistAmount) * 0.02" in organism_s
      and 'add("naloxoneadd"' in organism_s and "naloxoneadd" in pain_s)
check("S02 body-drug minigame callback has its own guarded snapshot",
      "local function PatchBodyDrugSpecs" in organism_s
      and "(WSZC.SwepHealDepth or 0) <= 0" in organism_s
      and "patchedBodyDrugFns[wrapped] = true" in organism_s)
check("S03 canonical BloodBagTake mirrors its direct blood-volume delta",
      "local function PatchBloodBagTake" in organism_s
      and "WSZC.SnapshotMedical(ply, \"body\")" in organism_s
      and "body.bloodVolume = math.max" in server_bridge_s)
check("S04 only a successful chest drain sets ZCity org.needle",
      'if itemId == "INJECTION" and WSZC.OrganismAuthority' in server_s
      and server_s.index("if not ok then return false, 0 end")
      < server_s.index('if itemId == "INJECTION" and WSZC.OrganismAuthority')
      and "org.needle = 1" in server_s and "org.needle" in lungs_s)
check("S05 native timed medicine is mirrored per step without an outer duplicate",
      "local function InstallTimedEffectBridge" in organism_s
      and "MirrorTimedBodyEffectStep(ply, effect)" in organism_s
      and "effect._WSZCBodyShadow" in organism_s
      and "state.bleed = savedBleed[limbId]" in organism_s
      and 'kind = "procoagulant"' in native_awb_s)
check("S06 negative shadow bleed treatment reduces real ordinary and arterial wounds",
      "local function ReduceLimbWoundBleeding" in organism_s
      and "ReduceLimbWoundBleeding(ply, org, limbId, bleedTreatment)" in organism_s
      and "CompactWoundTable(org.arterialwounds)" in organism_s)
check("S07 fracture timer follows native remaining-time semantics in both directions",
      "state.boneHealTimer = 100" in native_health_s
      and "math.Clamp(dmg * 100, 0, 100)" in organism_s
      and "after.limbBoneHealTimer - before.limbBoneHealTimer" in organism_s
      and "org.brokenribs = math.floor" in organism_s)
check("S08 splint keeps native wear and recovery multipliers in organism authority",
      "* 0.025" in native_splint_s and "splintMult = state.splinted and 2.5" in native_health_s
      and "function WSZC.TickSplints" in organism_s
      and "dt * 0.025" in organism_s and "nativeStep * 1.5" in organism_s
      and "dt * 0.07 * 2" in organism_s)
check("S09 canonical tourniquet return becomes a timed reusable ZCity SWEP",
      "ReturnAttachedMedicalItem" in native_health_s and "returnedItemId" in native_health_s
      and 'WoundSystem.Statuses.Register("TOURNIQUET"' in native_tourniquet_s
      and "TOURNIQUET_CLOT_TIME = 180" in organism_s
      and 'pcall(recipient.Give, recipient, "weapon_tourniquet")' in organism_s
      and 'WSZC.RemoteMedicalReturnRecipient' in organism_s
      and "ReplayRemoveStatus" in organism_s)
check("S10 all canonical medicine shares the connector's living-patient ragdoll resolver",
      "local function PatchBridgePlayerResolver" in organism_s
      and "wb._WSZCOriginalGetPlayer = original" in organism_s
      and "entOrg == ply.organism and entOrg.owner == ply" in organism_s
      and "PatchBridgePlayerResolver(wb)" in organism_s
      and "WSZC.PatchBridgePlayerResolver = PatchBridgePlayerResolver" in organism_s)

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
AuthorityFlag = true
MinigameEnabled = false
FrameTimeValue = 0.1
Now = 100
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 0, 0, 0
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 0, 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG, HITGROUP_GEAR = 4, 5, 6, 7, 10
DMG_DISSOLVE, DMG_BLAST, DMG_BULLET, DMG_BUCKSHOT = 1, 2, 4, 8
HUD_PRINTCENTER = 2
NULL = NULL or {}
WSZC = {
    OrganismAuthority = function() return AuthorityFlag end,
    WithVanillaContext = function(fn, ...) return fn(...) end,
}
WoundSystem = { Health = { HandleDamage = function() end }, Items = {} }
hg = {}
Errors = {}
math.Clamp = function(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
math.Rand = function(lo, hi) return (lo + hi) / 2 end
math.Approach = function(value, target, amount)
    if value < target then return math.min(value + amount, target) end
    return math.max(value - amount, target)
end
CreateConVar = function(name, default)
    return {
        GetBool = function()
            if name == "zc_woundsystem_minigames" then return MinigameEnabled end
            if string.find(name, "debug", 1, true) then return false end
            return default ~= "0"
        end,
        GetFloat = function() return tonumber(default) or 0 end,
    }
end
ConVarExists = function() return false end
GetConVar = function() return nil end
CurTime = function() return Now end
FrameTime = function() return FrameTimeValue end
IsValid = function(v) return v ~= nil and v ~= false end
isnumber = function(v) return type(v) == "number" end
istable = function(v) return type(v) == "table" end
isvector = function(v) return type(v) == "table" and v._isVector == true end
Vector = function(x, y, z)
    local v = { x = x or 0, y = y or 0, z = z or 0, _isVector = true }
    v.GetNegated = function(self) return Vector(-self.x, -self.y, -self.z) end
    v.LengthSqr = function(self) return self.x * self.x + self.y * self.y + self.z * self.z end
    return v
end
Angle = function(p, y, r) return { p = p or 0, y = y or 0, r = r or 0 } end
vector_origin, angle_zero = Vector(), Angle()
SetGlobalBool = function() end
AddCSLuaFile = function() end
ErrorNoHalt = function(msg) Errors[#Errors + 1] = tostring(msg) end
include = function() end
player = { GetAll = function() return {} end }
game = { GetAmmoName = function() return "9mm" end }
FindMetaTable = function() return nil end
hook = { Add = function() end, Remove = function() end, Run = function() end,
         GetTable = function() return {} end }
timer = { Simple = function() end, Create = function() end, Remove = function() end,
          Exists = function() return false end }
net = { Receivers = {}, Receive = function() end, Start = function() end,
        WriteUInt = function() end, Send = function() end, Broadcast = function() end }
util = { AddNetworkString = function() end }
DamageInfo = function() error("damage is outside this medical suite") end
''')
    lua.execute(shared_bridge_s)
    lua.execute(server_bridge_s)
    lua.execute(organism_s)
    lua.execute(server_s)
    lua.execute(r'''
local H = WoundSystem.Health
Bodies, Limbs = {}, {}
H.BodyState = Bodies
H.GetBody = function(ply) return Bodies[ply] end
H.GetLimbs = function(ply) return Limbs[ply] end
H.GetLimbState = function(ply, limbId)
    local states = Limbs[ply]
    if not states then return nil end
    if not states[limbId] then states[limbId] = { bleed = 0, pain = 0, muscle = 100, dismembered = false } end
    return states[limbId]
end
H.SendCardioUpdate = function() end
H.SendLimbUpdate = function() end
H.ResetPlayer = function() end
H.HasExternalMinigame = function() return false end
H.StartExternalMinigame = function(owner, options)
    CapturedMinigame = { owner = owner, options = options }
    return true
end
H.StopExternalMinigame = function() end
NativeQueueCalls = 0
H.QueueTimedBodyEffect = function()
    NativeQueueCalls = NativeQueueCalls + 1
    return "native-queue"
end
H.ApplyItemToBody = WSZC.ApplyItemToBodyImpl
WSZC.H, WSZC.Ready = H, true
hg.GetCurrentCharacter = function(owner) return owner end

LimbIds = {
    "head", "neck", "thorax", "abdomen", "pelvis",
    "arm_L", "forearm_L", "hand_L", "arm_R", "forearm_R", "hand_R",
    "thigh_L", "crus_L", "foot_L", "thigh_R", "crus_R", "foot_R",
}
function MakePlayer()
    local ply = { _alive = true, _velocity = Vector(), fullsend = false }
    ply.IsPlayer = function() return true end
    ply.Alive = function(self) return self._alive end
    ply.GetVelocity = function(self) return self._velocity end
    ply.EmitSound = function() end
    ply.SelectWeapon = function() end
    ply.PrintMessage = function() end
    ply.SetNetVar = function() end
    ply.organism = {
        owner = ply, blood = 5000, pulse = 70, shock = 35,
        adrenaline = 0, brain = 0.2, consciousness = 1,
        stamina = { 90, max = 180 }, analgesiaAdd = 0, naloxoneadd = 0,
        internalBleed = 20, bleed = 20, pain = 40, avgpain = 40,
        wounds = {}, arterialwounds = {}, needle = 0,
    }
    Bodies[ply] = {
        bloodVolume = 100, heartRate = 70, shock = 50, adrenaline = 0,
        brainHealth = 80, brainDamageBuffer = 20, consciousness = 100,
        stamina = 50, avgPain = 40, internalBleeding = 20,
        hemothorax = 40, opiateAmount = 0, antagonistAmount = 0,
    }
    Limbs[ply] = {}
    for _, id in ipairs(LimbIds) do
        Limbs[ply][id] = { bleed = 0, pain = 0, muscle = 100, skin = 100, dismembered = false }
    end
    return ply
end
function MakeSwep(owner, class, amount)
    return {
        modeValues = { amount or 1 }, modeValuesdef = { 1 }, sndcd = 0,
        GetOwner = function() return owner end,
        GetClass = function() return class end,
        Remove = function(self) self.removed = true end,
    }
end
assert(WSZC.InstallMedicalBridge())
''')

    instant = lua.execute(r'''
MinigameEnabled = false
local ply = MakePlayer()
local swep = MakeSwep(ply, "weapon_adrenaline", 1)
local ok = hg.WoundBridge.SwepHeal(swep, ply, 1)
local body = Bodies[ply]
return ok == true and swep.modeValues[1] == 0
    and math.abs(body.adrenaline - 45) < 0.001
    and math.abs(ply.organism.adrenaline - 0.9) < 0.001
    and math.abs(ply.organism.pulse - 85) < 0.001
    and math.abs(ply.organism.stamina[1] - 144) < 0.001
''')
    check("R01 canonical instant adrenaline applies exactly one authoritative dose", instant)

    asynchronous = lua.execute(r'''
MinigameEnabled = true
CapturedMinigame = nil
local ply = MakePlayer()
local swep = MakeSwep(ply, "weapon_adrenaline", 1)
local startedResult = hg.WoundBridge.SwepHeal(swep, ply, 1)
local captured = CapturedMinigame
local before = ply.organism.adrenaline
local session = { startAmount = captured.options.amount, deferredUsed = 0 }
captured.options.onProgress(ply, session, captured.options.amount)
local oneDose = startedResult == false and ply.organism.adrenaline - before == 0.9
    and math.abs(ply.organism.pulse - 85) < 0.001
    and math.abs(ply.organism.stamina[1] - 144) < 0.001
    and swep.modeValues[1] == 0
captured.options.onClose(ply, session, "complete")
return oneDose and ply.organism.adrenaline == 0.9 and swep.removed == true
''')
    check("R02 canonical minigame adrenaline applies once onProgress and consumes the SWEP", asynchronous)

    other_body_drugs = lua.execute(r'''
MinigameEnabled = false
local beta = MakePlayer()
Bodies[beta].adrenaline, Bodies[beta].heartRate, Bodies[beta].shock = 80, 100, 50
beta.organism.adrenaline, beta.organism.pulse = 1.6, 100
hg.WoundBridge.SwepSpecs.weapon_betablock.fn(beta, Bodies[beta], 1)
local betaOK = math.abs(Bodies[beta].adrenaline - 40) < 0.001
    and math.abs(beta.organism.adrenaline - 0.8) < 0.001
    and beta.organism.pulse == 80 and math.abs(beta.organism.shock - 31.5) < 0.001

local mannitol = MakePlayer()
hg.WoundBridge.SwepSpecs.weapon_mannitol.fn(mannitol, Bodies[mannitol], 1)
local mannitolOK = Bodies[mannitol].brainHealth == 88
    and math.abs(mannitol.organism.brain - 0.12) < 0.001
local thiamine = MakePlayer()
hg.WoundBridge.SwepSpecs.weapon_thiamine.fn(thiamine, Bodies[thiamine], 1)
local thiamineOK = Bodies[thiamine].brainHealth == 84
    and math.abs(thiamine.organism.brain - 0.16) < 0.001
return betaOK, mannitolOK and thiamineOK
''')
    check("R03 asynchronous betablock mirrors adrenaline, pulse and shock", other_body_drugs[0])
    check("R04 mannitol and thiamine both mirror their brain-health effect", other_body_drugs[1])

    blood_take = lua.execute(r'''
local ply = MakePlayer()
local swep = MakeSwep(ply, "weapon_bloodbag", 0)
FrameTimeValue = 0.2
local ok = hg.WoundBridge.BloodBagTake(swep, ply)
return ok == true and math.abs(swep.modeValues[1] - 0.1) < 0.001
    and math.abs(Bodies[ply].bloodVolume - 99) < 0.001
    and math.abs(ply.organism.blood - 4950) < 0.001
    and swep.bloodtype == "o-"
''')
    check("R05 real BloodBagTake removes the same volume from C:U and ZCity", blood_take)

    lua.execute(r'''
local Definitions = {
    GAUZE = { max = 100, use = { minigame = "bandage", validLimbs = "any",
        bandage = { durabilityPerWrap = 100 / 12, effectDivisor = 12,
            effects = { bandageSlowAmount = 45, boneHealTimer = -20, dislocationTimer = -20 },
            bandagedAtSlow = 10 } } },
    STERILIZEDBANDAGE = { max = 100, use = { minigame = "bandage", validLimbs = "any",
        bandage = { durabilityPerWrap = 100 / 12, effectDivisor = 12,
            effects = { bandageSlowAmount = 45 }, bandagedAtSlow = 10 } } },
    MORPHINE = { max = 100, use = { minigame = "syringe", validLimbs = "any",
        syringe = { drugEffects = { opiateAmount = 100 } } } },
    FENTANYL = { max = 100, use = { minigame = "syringe", validLimbs = "any",
        syringe = { drugEffects = { opiateAmount = 100 } } } },
    NALOXONE = { max = 100, use = { minigame = "syringe", validLimbs = "any",
        syringe = { drugEffects = { antagonistAmount = 50 } } } },
    TOURNIQUET = { max = 100, use = { validLimbs = "any",
        apply = function(ctx) return true end } },
    ["BLOOD BAG"] = { max = 50, use = { validLimbs = "any",
        apply = function(ctx)
            ctx.body.bloodVolume = math.min((ctx.body.bloodVolume or 0) + 1, 100)
            return true
        end } },
    INJECTION = { max = 10, use = { validLimbs = "thorax",
        apply = function(ctx)
            if RejectChestDrain then return false end
            ctx.body.hemothorax = math.max((ctx.body.hemothorax or 0) - 25, 0)
            return true
        end } },
    BLOODCOAGULANT = { max = 100, use = { validLimbs = "any", consumeDurability = 33.334,
        apply = function(ctx)
            return WoundSystem.Health.QueueTimedBodyEffect(
                ctx.ply, ctx.body, "procoagulant", 20, { kind = "procoagulant" })
        end } },
    RELIEFCREAM = { max = 100, use = { validLimbs = "any",
        apply = function(ctx)
            return WoundSystem.Health.QueueTimedBodyEffect(
                ctx.ply, ctx.body, "reliefcream", 10,
                { kind = "reliefcream", limbId = ctx.limbId })
        end } },
}
WoundSystem.Items.Get = function(id) return Definitions[id] end
WoundSystem.Items.GetMax = function(id) return Definitions[id] and Definitions[id].max or 100 end
WoundSystem.Items.CreateSlot = function(id, durability)
    return { type = "tool", toolName = id, durability = durability }
end
WoundSystem.Items.LimbAllowed = function(use, limbId)
    return use.validLimbs == "any" or use.validLimbs == limbId
end
WoundSystem.UseMedicalItem = nil
''')

    naloxone = lua.execute(r'''
local ply = MakePlayer()
local ok = WoundSystem.Health.ApplyItemToBody(ply, "NALOXONE", "arm_R", 100)
local first = ok == true and Bodies[ply].antagonistAmount == 50
    and ply.organism.naloxoneadd == 1
WoundSystem.Health.ApplyItemToBody(ply, "NALOXONE", "arm_R", 100)
return first and Bodies[ply].antagonistAmount == 100 and ply.organism.naloxoneadd == 1
''')
    check("R06 full naloxone maps +50 antagonist to +1 and remains clamped", naloxone)

    chest = lua.execute(r'''
RejectChestDrain = false
local ply = MakePlayer()
local ok = WoundSystem.Health.ApplyItemToBody(ply, "INJECTION", "thorax", 100)
local success = ok == true and Bodies[ply].hemothorax == 15
    and ply.organism.needle == 1 and ply.fullsend == true
RejectChestDrain = true
local rejected = MakePlayer()
local ok2 = WoundSystem.Health.ApplyItemToBody(rejected, "INJECTION", "thorax", 100)
local wrongLimb = MakePlayer()
local ok3 = WoundSystem.Health.ApplyItemToBody(wrongLimb, "INJECTION", "arm_R", 100)
RejectChestDrain = false
return success, ok2 == false and rejected.organism.needle == 0
    and Bodies[rejected].hemothorax == 40 and ok3 == false and wrongLimb.organism.needle == 0
''')
    check("R07 successful native chest drain installs the ZCity needle state", chest[0])
    check("R08 rejected or wrong-limb chest drain cannot install a needle", chest[1])

    coagulant = lua.execute(r'''
local ply = MakePlayer()
local hand = Limbs[ply].hand_R
local thigh = Limbs[ply].thigh_L
hand.bleed, thigh.bleed = 8, 20
ply.organism.wounds = {
    { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Hand", 0 },
    { 7, Vector(), Angle(), "ValveBiped.Bip01_L_Thigh", 0 },
}
ply.organism.arterialwounds = {
    { 2, Vector(), Angle(), "ValveBiped.Bip01_L_Thigh", 0, Vector(), "llegartery" },
}
ply.organism.llegartery = 1
local ok = WoundSystem.Health.ApplyItemToBody(ply, "BLOODCOAGULANT", "arm_R", 33.334)
local immediate = ok == true and math.abs(ply.organism.internalBleed - 19) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 3.84) < 0.001
    and math.abs(ply.organism.wounds[2][1] - 6.72) < 0.001
    and math.abs(ply.organism.arterialwounds[1][1] - 1.92) < 0.001
    and Bodies[ply].internalBleeding == 20 and hand.bleed == 8 and thigh.bleed == 20
    and ply._WSZCTimedBodyEffects.procoagulant.remaining == 20
WSZC.TickTimedBodyEffects(ply, 1)
SecondStepDebug = { internal = ply.organism.internalBleed,
    wound1 = ply.organism.wounds[1][1], wound2 = ply.organism.wounds[2][1],
    artery = ply.organism.arterialwounds[1][1] }
local cumulative = math.abs(ply.organism.internalBleed - 18.05) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 3.6864) < 0.001
    and math.abs(ply.organism.wounds[2][1] - 6.4512) < 0.001
    and math.abs(ply.organism.arterialwounds[1][1] - 1.8432) < 0.001
    and ply.organism.llegartery == 1
for _ = 1, 19 do WSZC.TickTimedBodyEffects(ply, 1) end
local finished = ply._WSZCTimedBodyEffects.procoagulant == nil
    and math.abs(ply.organism.internalBleed - 20 * 0.95 ^ 20) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 4 * 0.96 ^ 20) < 0.001
    and Bodies[ply].internalBleeding == 20 and hand.bleed == 8 and thigh.bleed == 20
CoagulantPlayer = ply
CoagulantDebug = { internal = ply.organism.internalBleed,
    wound1 = ply.organism.wounds[1] and ply.organism.wounds[1][1],
    wound2 = ply.organism.wounds[2] and ply.organism.wounds[2][1],
    artery = ply.organism.arterialwounds[1] and ply.organism.arterialwounds[1][1],
    expectedInternal = 20 * 0.95 ^ 20, expectedWound = 4 * 0.96 ^ 20 }
return immediate, cumulative, finished
''')
    check("R09 procoagulant immediately treats internal and ALL real limb wounds once", coagulant[0])
    check("R10 second timed step is cumulative rather than restarting from the shadow", coagulant[1])
    check("R11 all 20 timed steps finish without changing the restored outer shadow", coagulant[2])
    if not all(coagulant):
        debug = lua.globals().CoagulantDebug
        print("COAGULANT_DEBUG", {key: debug[key] for key in (
            "internal", "wound1", "wound2", "artery", "expectedInternal", "expectedWound")})
        second = lua.globals().SecondStepDebug
        print("SECOND_STEP_DEBUG", {key: second[key] for key in ("internal", "wound1", "wound2", "artery")})

    relief_and_bridge = lua.execute(r'''
local ply = MakePlayer()
Limbs[ply].hand_R.pain = 40
ply.organism.pain = 40
local ok = WoundSystem.Health.ApplyItemToBody(ply, "RELIEFCREAM", "hand_R", 100)
local immediate = ok == true and math.abs(ply.organism.pain - 38.65) < 0.001
    and Limbs[ply].hand_R.pain == 40
WSZC.TickTimedBodyEffects(ply, 1)
local later = math.abs(ply.organism.pain - 37.48225) < 0.001
    and Limbs[ply].hand_R.pain == 40
local bridgePly = MakePlayer()
AuthorityFlag = false
NativeQueueCalls = 0
local result = WoundSystem.Health.QueueTimedBodyEffect(
    bridgePly, Bodies[bridgePly], "procoagulant", 20, { kind = "procoagulant" })
local delegated = result == "native-queue" and NativeQueueCalls == 1
    and bridgePly._WSZCTimedBodyEffects == nil and bridgePly.organism.internalBleed == 20
AuthorityFlag = true
return immediate and later, delegated
''')
    check("R12 relief cream mirrors immediate and delayed pain relief without double dosing", relief_and_bridge[0])
    check("R13 bridge mode delegates timed effects to native C:U unchanged", relief_and_bridge[1])

    extension = lua.execute(r'''
local ply = MakePlayer()
WoundSystem.Health.QueueTimedBodyEffect(ply, Bodies[ply], "procoagulant", 20, { kind = "procoagulant" })
local once = ply.organism.internalBleed
local effect = ply._WSZCTimedBodyEffects.procoagulant
WSZC.TickTimedBodyEffects(ply, 1)
local twice = ply.organism.internalBleed
WoundSystem.Health.QueueTimedBodyEffect(ply, Bodies[ply], "procoagulant", 5, { kind = "procoagulant" })
return effect.remaining == 24 and ply.organism.internalBleed == twice
    and math.abs(once - 19) < 0.001 and math.abs(twice - 18.05) < 0.001
''')
    check("R14 extending an active timed effect adds duration without another immediate dose", extension)

    fractures = lua.execute(r'''
local ply = MakePlayer()
ply.organism.rarm = 1
local forearm = Limbs[ply].forearm_R
forearm.broken, forearm.boneHealTimer, forearm.muscle = true, 100, 0
local perWrap = 100 / 12
WoundSystem.Health.ApplyItemToBody(ply, "GAUZE", "forearm_R", perWrap)
local oneWrap = math.abs(ply.organism.rarm - (1 - 0.2 / 12)) < 0.001
    and math.abs(forearm.boneHealTimer - (100 - 20 / 12)) < 0.001
    and forearm.broken == true
for _ = 2, 12 do
    WoundSystem.Health.ApplyItemToBody(ply, "GAUZE", "forearm_R", perWrap)
end
local fullRoll = math.abs(ply.organism.rarm - 0.8) < 0.001
    and math.abs(forearm.boneHealTimer - 80) < 0.001
WSZC.RestoreBones(ply)
local restored = forearm.broken == false and forearm.boneHealTimer == 0
    and math.abs(ply.organism.rarm - 0.8) < 0.001

local nonAnchor = MakePlayer()
nonAnchor.organism.rarm = 1
Limbs[nonAnchor].arm_R.muscle = 100
WoundSystem.Health.ApplyItemToBody(nonAnchor, "GAUZE", "arm_R", 100)
local onlyMiddle = nonAnchor.organism.rarm == 1

local neck = MakePlayer()
neck.organism.skull = 1
local neckState = Limbs[neck].neck
neckState.broken, neckState.boneHealTimer, neckState.muscle = true, 100, 0
WoundSystem.Health.ApplyItemToBody(neck, "GAUZE", "neck", 100)
local neckHeals = math.abs(neck.organism.skull - 0.8) < 0.001
return oneWrap, fullRoll and restored, onlyMiddle, neckHeals
''')
    check("R15 one GAUZE wrap reduces the real fracture without instant healing", fractures[0])
    check("R16 a full roll survives RestoreBones instead of clearing only the icon", fractures[1])
    check("R17 fracture treatment remains only on the anatomical middle limb", fractures[2])
    check("R18 neck fracture treatment changes org.skull, not merely its shadow", fractures[3])

    ribs = lua.execute(r'''
local ply = MakePlayer()
ply.organism.chest, ply.organism.brokenribs = 1, 3
local thorax = Limbs[ply].thorax
thorax.broken, thorax.boneHealTimer, thorax.muscle = true, 100, 0
for _ = 1, 5 do WoundSystem.Health.ApplyItemToBody(ply, "GAUZE", "thorax", 100) end
return math.abs(ply.organism.chest) < 0.001 and ply.organism.brokenribs == 0
    and thorax.broken == false and thorax.boneHealTimer == 0
''')
    check("R19 rib treatment keeps chest and brokenribs authoritative through full healing", ribs)

    dislocations = lua.execute(r'''
local ply = MakePlayer()
ply.organism.rarmdislocation = true
WSZC.RestoreBones(ply)
local arm = Limbs[ply].arm_R
arm.dislocated, arm.dislocationTimer = true, 35
WoundSystem.Health.ApplyItemToBody(ply, "GAUZE", "arm_R", 100)
local firstRoll = arm.dislocated == true and math.abs(arm.dislocationTimer - 15) < 0.001
    and ply.organism.rarmdislocation == true
WoundSystem.Health.ApplyItemToBody(ply, "GAUZE", "arm_R", 100)
local nativeReduced = arm.dislocated == false and arm.dislocationTimer == 0
WSZC.SyncDislocation(ply, ply.organism, Limbs[ply], false)
local authoritative = nativeReduced and ply.organism.rarmdislocation == false
    and ply.organism.painadd == 10

local neighbor = MakePlayer()
neighbor.organism.rarmdislocation = true
WSZC.RestoreBones(neighbor)
Limbs[neighbor].forearm_R.dislocated = false
WSZC.SyncDislocation(neighbor, neighbor.organism, Limbs[neighbor], false)
local neighborCannotReduce = neighbor.organism.rarmdislocation == true
return firstRoll and authoritative, neighborCannotReduce
''')
    check("R20 two real GAUZE rolls reduce a dislocation through the authoritative anchor", dislocations[0])
    check("R21 a non-anchor neighbour cannot falsely reduce the whole arm", dislocations[1])

    splints = lua.execute(r'''
local ply = MakePlayer()
ply.organism.rarm = 0.5
local forearm = Limbs[ply].forearm_R
forearm.broken, forearm.boneHealTimer = true, 50
forearm.splinted = true
forearm.customStatuses = { SPLINTED = 100 }
WSZC.TickSplints(ply, ply.organism, 1)
local accelerated = math.abs(ply.organism.rarm - (0.5 - 1.5 / 240)) < 0.000001
    and math.abs(forearm.customStatuses.SPLINTED - 99.975) < 0.000001

local full = MakePlayer()
full.organism.rarm = 1
local fullState = Limbs[full].forearm_R
fullState.broken, fullState.splinted = true, true
fullState.customStatuses = { SPLINTED = 100 }
WSZC.TickSplints(full, full.organism, 1)
local startsFullBreak = math.abs(full.organism.rarm - (1 - 2.5 / 240)) < 0.000001

local joint = MakePlayer()
joint.organism.rarmdislocation = true
WSZC.RestoreBones(joint)
local arm = Limbs[joint].arm_R
arm.splinted = true
arm.customStatuses = { SPLINTED = 100 }
for _ = 1, 250 do WSZC.TickSplints(joint, joint.organism, 1) end
WSZC.SyncDislocation(joint, joint.organism, Limbs[joint], false)
local jointRecovers = arm.dislocated == false and arm.dislocationTimer == 0
    and joint.organism.rarmdislocation == false

local expiring = MakePlayer()
expiring.organism.rarm = 0.5
local expiringState = Limbs[expiring].forearm_R
expiringState.broken, expiringState.splinted = true, true
expiringState.customStatuses = { SPLINTED = 0.025 }
WSZC.TickSplints(expiring, expiring.organism, 1)
local expires = expiringState.splinted == false
    and expiringState.customStatuses.SPLINTED == nil and expiring.organism.rarm == 0.5
return accelerated and startsFullBreak, jointRecovers, expires
''')
    check("R22 splint multiplies real ZCity fracture recovery and can start a full break", splints[0])
    check("R23 splinted joint recovery finishes through the real dislocation flag", splints[1])
    check("R24 SPLINTED wears out at the native rate and then stops healing", splints[2])

    intervening_damage = lua.execute(r'''
local ply = MakePlayer()
Limbs[ply].hand_R.bleed = 8
ply.organism.wounds = {
    { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Hand", 0 },
}
WoundSystem.Health.ApplyItemToBody(ply, "BLOODCOAGULANT", "arm_R", 33.334)
-- A later native PushShadow includes BOTH the last treatment and a new wound.
-- The next timed step must use this current baseline, not the stale cached 8.
ply.organism.wounds[#ply.organism.wounds + 1] = {
    2, Vector(), Angle(), "ValveBiped.Bip01_R_Hand", 0,
}
Bodies[ply].internalBleeding = 19
Limbs[ply].hand_R.bleed = 11.68
WSZC.TickTimedBodyEffects(ply, 1)
return math.abs(ply.organism.internalBleed - 18.05) < 0.001
    and math.abs(ply.organism.wounds[1][1] - 3.6864) < 0.001
    and math.abs(ply.organism.wounds[2][1] - 1.92) < 0.001
''')
    check("R25 a timed step includes intervening authoritative damage in its baseline", intervening_damage)

    early_removal = lua.execute(r'''
function NewTourniquetPatient()
    local ply = MakePlayer()
    ply.given, ply.givenClasses = 0, {}
    ply.Give = function(self, class)
        self.given = self.given + 1
        self.givenClasses[class] = (self.givenClasses[class] or 0) + 1
        return { modeValues = { 0 } }
    end
    ply.organism.bleed, ply.organism.rlegartery = 20, 1
    ply.organism.wounds = {
        { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Calf", 0 },
        { 3, Vector(), Angle(), "ValveBiped.Bip01_R_Foot", 0 },
        { 7, Vector(), Angle(), "ValveBiped.Bip01_L_Hand", 0 },
    }
    ply.organism.arterialwounds = {
        { 6, Vector(), Angle(), "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
    }
    return ply
end
TourniquetPatientFactory = NewTourniquetPatient
Now = 1000
local ply = NewTourniquetPatient()
WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
local applied = #ply.organism.arterialwounds == 0 and #ply.organism.wounds == 1
    and ply.organism.rlegartery == 0 and ply.given == 0
    and ply._WSZCTourniquetCycles.thigh_R ~= nil
for _, id in ipairs({ "thigh_R", "crus_R", "foot_R" }) do
    local state = Limbs[ply][id]
    state.tourniqueted, state.blockedBleeding = true, true
    state.customStatuses = { TOURNIQUET = 0.01 }
end
-- New damage is not part of the backup and must survive an early removal.
ply.organism.wounds[#ply.organism.wounds + 1] = {
    2, Vector(), Angle(), "ValveBiped.Bip01_R_Foot", 0,
}
local rag = {
    tourniquets = {
        { 1, 1, "ValveBiped.Bip01_R_Thigh" },
        { 1, 1, "ValveBiped.Bip01_L_Hand" },
    },
    SetNetVar = function() end,
}
ply.FakeRagdoll = rag
hg.TourniquetGuys = { ply, rag }
Now = 1100
WSZC.TickTourniquets(ply, ply.organism, 0.1)
local beforeMaturity = ply._WSZCTourniquetCycles.thigh_R.mature ~= true
local removed = WSZC.RemoveTourniquet(ply, "thigh_R")
local second = WSZC.RemoveTourniquet(ply, "thigh_R")
local found = {}
for _, wound in pairs(ply.organism.wounds) do found[wound[1]] = (found[wound[1]] or 0) + 1 end
local restored = removed and not second and ply.given == 1
    and ply.givenClasses.weapon_tourniquet == 1
    and #ply.organism.arterialwounds == 1 and ply.organism.arterialwounds[1][1] == 6
    and ply.organism.rlegartery == 1 and found[4] == 1 and found[3] == 1
    and found[2] == 1 and found[7] == 1
local function HasBone(ent, bone)
    for _, marker in ipairs(ent.tourniquets or {}) do
        if marker[3] == bone then return true end
    end
    return false
end
local visuals = not HasBone(ply, "ValveBiped.Bip01_R_Thigh")
    and not HasBone(rag, "ValveBiped.Bip01_R_Thigh")
    and HasBone(rag, "ValveBiped.Bip01_L_Hand")
    and hg.TourniquetGuys[1] == rag and #hg.TourniquetGuys == 1
local statuses = ply._WSZCTourniquetCycles.thigh_R == nil
for _, id in ipairs({ "thigh_R", "crus_R", "foot_R" }) do
    local state = Limbs[ply][id]
    statuses = statuses and state.tourniqueted == false and state.blockedBleeding == false
        and state.customStatuses.TOURNIQUET == nil
end
return applied and beforeMaturity and restored, visuals and statuses
''')
    check("R26 early tourniquet removal restores only its wounds and returns one SWEP", early_removal[0])
    check("R27 removal clears selected player/ragdoll visuals and downstream statuses", early_removal[1])

    mature_reuse = lua.execute(r'''
local ply = TourniquetPatientFactory()
ply.messages = 0
ply.PrintMessage = function(self) self.messages = self.messages + 1 end
Now = 2000
WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
Limbs[ply].thigh_R.tourniqueted = true
Limbs[ply].thigh_R.customStatuses = { TOURNIQUET = 0.01 }
local originalCycle = ply._WSZCTourniquetCycles.thigh_R
local duplicateTreatment = WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
local noOverwrite = duplicateTreatment == 0
    and ply._WSZCTourniquetCycles.thigh_R == originalCycle and originalCycle.appliedAt == 2000
Now = 2179.99
WSZC.TickTourniquets(ply, ply.organism, 0.1)
local beforeBoundary = ply._WSZCTourniquetCycles.thigh_R.mature ~= true
Now = 2180
WSZC.TickTourniquets(ply, ply.organism, 0.1)
local cycle = ply._WSZCTourniquetCycles.thigh_R
local matured = noOverwrite and beforeBoundary and cycle.mature == true
    and cycle.arterial == nil and cycle.ordinary == nil and ply.messages == 1
local removed = WSZC.RemoveTourniquet(ply, "thigh_R")
local remainsClosed = removed and #ply.organism.arterialwounds == 0
    and #ply.organism.wounds == 1 and ply.organism.wounds[1][1] == 7
    and ply.organism.rlegartery == 0 and ply.given == 1
local duplicate = WSZC.RemoveTourniquet(ply, "thigh_R")
-- The returned item can treat a later wound; an early second removal still
-- restores that new cycle and returns exactly one more SWEP.
ply.organism.arterialwounds = {
    { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
}
ply.organism.rlegartery = 1
Now = 2181
WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
local newCycle = ply._WSZCTourniquetCycles.thigh_R
local reusable = newCycle ~= nil and newCycle.mature ~= true
Now = 2182
local removedAgain = WSZC.RemoveTourniquet(ply, "thigh_R")
reusable = reusable and removedAgain and ply.given == 2
    and ply.givenClasses.weapon_tourniquet == 2
    and #ply.organism.arterialwounds == 1 and ply.organism.arterialwounds[1][1] == 4
-- No Org Think between application and this click: removal itself must still
-- enforce the exact 180-second boundary.
local direct = TourniquetPatientFactory()
Now = 2500
WSZC.ApplyTourniquetToOrganism({ ply = direct, limbId = "thigh_R" })
Now = 2680
local directRemoved = WSZC.RemoveTourniquet(direct, "thigh_R")
local noTickMatured = directRemoved and #direct.organism.arterialwounds == 0
    and #direct.organism.wounds == 1 and direct.organism.rlegartery == 0 and direct.given == 1
return matured and remainsClosed and not duplicate and noTickMatured, reusable
''')
    check("R28 exactly 180 seconds fixes the wound without a duplicate return", mature_reuse[0])
    check("R29 returned tourniquet can be applied and removed again", mature_reuse[1])

    removal_receiver = lua.execute(r'''
local nativeCalls = {}
net.Receivers["WoundSystem_RemoveLimbStatus"] = function(_, ply)
    local limbId, statusId = net.ReadString(), net.ReadString()
    nativeCalls[#nativeCalls + 1] = { ply = ply, limbId = limbId, statusId = statusId }
    return limbId, statusId
end
assert(WSZC.InstallTourniquetRemovalBridge())
local receiver = net.Receivers["WoundSystem_RemoveLimbStatus"]
local function Send(ply, limbId, statusId)
    local queue = { limbId, statusId }
    net.ReadString = function() return table.remove(queue, 1) end
    return receiver(0, ply)
end
AuthorityFlag = true
Now = 3000
local ply = TourniquetPatientFactory()
WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
local removed = Send(ply, "thigh_R", "TOURNIQUET")
local authority = removed and ply.given == 1 and #nativeCalls == 0
local limb, status = Send(ply, "arm_L", "SPLINTED")
local splint = limb == "arm_L" and status == "SPLINTED" and #nativeCalls == 1
    and nativeCalls[1].limbId == "arm_L" and nativeCalls[1].statusId == "SPLINTED"
local bridgePly = TourniquetPatientFactory()
WSZC.ApplyTourniquetToOrganism({ ply = bridgePly, limbId = "thigh_R" })
AuthorityFlag = false
Send(bridgePly, "thigh_R", "TOURNIQUET")
AuthorityFlag = true
local bridge = #nativeCalls == 2 and nativeCalls[2].statusId == "TOURNIQUET"
    and bridgePly.given == 0 and bridgePly._WSZCTourniquetCycles.thigh_R ~= nil
return authority and splint, bridge
''')
    check("R30 authority receiver handles TOURNIQUET but replays native SPLINTED", removal_receiver[0])
    check("R31 bridge mode still delegates tourniquet removal to native C:U", removal_receiver[1])

    remote_return = lua.execute(r'''
Now = 3500
local patient = TourniquetPatientFactory()
local medic = TourniquetPatientFactory()
WSZC.ApplyTourniquetToOrganism({ ply = patient, limbId = "thigh_R" })
WSZC.RemoteMedicalReturnRecipient = medic
local removed = WSZC.RemoveTourniquet(patient, "thigh_R")
WSZC.RemoteMedicalReturnRecipient = nil
return removed and medic.given == 1 and medic.givenClasses.weapon_tourniquet == 1
    and patient.given == 0 and #patient.organism.arterialwounds == 1
    and patient.organism.arterialwounds[1][1] == 6
''')
    check("R33 remote tourniquet removal treats patient but returns SWEP to medic", remote_return)

    reset_cycle = lua.execute(r'''
Now = 4000
local ply = TourniquetPatientFactory()
WSZC.ApplyTourniquetToOrganism({ ply = ply, limbId = "thigh_R" })
Limbs[ply].thigh_R.tourniqueted = true
Limbs[ply].thigh_R.customStatuses = { TOURNIQUET = 1 }
WSZC.ClearAllShrapnel(ply, ply.organism)
return ply._WSZCTourniquetCycles == nil and ply.given == 0
    and ply.organism.bleed == 0 and #ply.organism.arterialwounds == 0
    and #ply.tourniquets == 0 and Limbs[ply].thigh_R.tourniqueted == false
    and Limbs[ply].thigh_R.customStatuses.TOURNIQUET == nil
''')
    check("R32 reset clears an active cycle without manufacturing a SWEP", reset_cycle)

    remote_ragdoll_resolver = lua.execute(r'''
MinigameEnabled = false
-- Simulate a shared-organism/C:U proxy for which canonical hg.RagdollOwner
-- has no current FakeRagdoll link. Native WB.GetPlayer must reject it, while
-- the connector's verified owner fallback must still treat the living patient.
hg.RagdollOwner = function() return nil end
function MakeRemoteSharedBody(patient)
    local body = { organism = patient.organism, _velocity = Vector() }
    body.IsPlayer = function() return false end
    body.IsRagdoll = function() return true end
    body.GetVelocity = function(self) return self._velocity end
    return body
end
function MakeRemoteMedicalPatient(kind)
    local patient = MakePlayer()
    if kind == "bandage" then
        Limbs[patient].thigh_R.bleed = 4
        patient.organism.wounds = {
            { 4, Vector(), Angle(), "ValveBiped.Bip01_R_Thigh", 0 },
        }
    elseif kind == "tourniquet" then
        Limbs[patient].thigh_R.bleed = 6
        patient.organism.rlegartery = 1
        patient.organism.arterialwounds = {
            { 6, Vector(), Angle(), "ValveBiped.Bip01_R_Thigh", 0, nil, "rlegartery" },
        }
    end
    return patient, MakeRemoteSharedBody(patient)
end
local patient, body = MakeRemoteMedicalPatient("body")
local native = hg.WoundBridge._WSZCOriginalGetPlayer(body)
local resolved = hg.WoundBridge.GetPlayer(body)
local medic = MakePlayer()
local swep = MakeSwep(medic, "weapon_adrenaline", 1)
local ok = hg.WoundBridge.SwepHeal(swep, body, 1)

local linkedPatient = MakePlayer()
local linkedBody = { GetNWEntity = function() return nil end }
linkedBody.IsPlayer = function() return false end
linkedBody.IsRagdoll = function() return true end
linkedPatient.GetNWEntity = function(_, key)
    return key == "FakeRagdoll" and linkedBody or NULL
end
local oldGetAll = player.GetAll
player.GetAll = function() return { linkedPatient } end
local networkResolved = hg.WoundBridge.GetPlayer(linkedBody)
player.GetAll = oldGetAll
return native == nil and resolved == patient and networkResolved == linkedPatient and ok == true
    and Bodies[patient].adrenaline == 45 and Bodies[medic].adrenaline == 0
    and patient.organism.adrenaline > 0 and medic.organism.adrenaline == 0
''')
    check("R34 shared-organism/network-only ragdolls resolve when native owner lookup fails", remote_ragdoll_resolver)

    remote_standalone = lua.execute(r'''
MinigameEnabled = false
FrameTimeValue = 0.2
RemoteStandaloneFailure = nil
local cases = {
    { "weapon_bandage_sh", "bandage", 40 },
    { "weapon_bigbandage_sh", "bandage", 150 },
    { "weapon_tourniquet", "tourniquet", 1 },
    { "weapon_needle", "body", 1 },
    { "weapon_morphine", "body", 1 },
    { "weapon_fentanyl", "body", 1 },
    { "weapon_naloxone", "body", 1 },
    { "weapon_painkillers", "body", 1 },
    { "weapon_adrenaline", "body", 1 },
    { "weapon_betablock", "body", 1 },
    { "weapon_mannitol", "body", 1 },
    { "weapon_thiamine", "body", 1 },
}
for _, case in ipairs(cases) do
    local class, kind, capacity = case[1], case[2], case[3]
    for _, ragdollForm in ipairs({ false, true }) do
        local patient, body = MakeRemoteMedicalPatient(kind)
        local target = ragdollForm and body or patient
        local medic = MakePlayer()
        local swep = MakeSwep(medic, class, capacity)
        if capacity > 1 then swep.modeValuesdef = { { capacity, true } } end
        local before = swep.modeValues[1]
        local ok = hg.WoundBridge.SwepHeal(swep, target, 1)
        if ok ~= true or not (swep.modeValues[1] < before) then
            RemoteStandaloneFailure = class .. (ragdollForm and "/ragdoll" or "/standing")
            return false
        end
    end
end
return true
''')
    check("R35 all 12 standalone ZCity medical SWEPs treat standing/ragdoll patients and consume medic items", remote_standalone)
    if not remote_standalone:
        print("REMOTE_STANDALONE_FAILURE", lua.globals().RemoteStandaloneFailure)

    remote_medkit = lua.execute(r'''
MinigameEnabled = false
RemoteMedkitFailure = nil
for mode = 1, 5 do
    for _, ragdollForm in ipairs({ false, true }) do
        local kind = mode == 1 and "bandage" or (mode == 4 and "tourniquet" or "body")
        local patient, body = MakeRemoteMedicalPatient(kind)
        local target = ragdollForm and body or patient
        local medic = MakePlayer()
        local swep = MakeSwep(medic, "weapon_medkit_sh", 1)
        swep.mode = mode
        swep.modeValues = { 80, 1, 10, 1, 1 }
        swep.modeValuesdef = { { 80, true }, { 1, false }, { 10, true }, { 1, true }, { 1, false } }
        local before = swep.modeValues[mode]
        local ok = hg.WoundBridge.SwepHeal(swep, target, mode)
        if ok ~= true or not (swep.modeValues[mode] < before) then
            RemoteMedkitFailure = tostring(mode) .. (ragdollForm and "/ragdoll" or "/standing")
            return false
        end
    end
end
return true
''')
    check("R36 all five medkit modes work on standing and ragdoll patients", remote_medkit)
    if not remote_medkit:
        print("REMOTE_MEDKIT_FAILURE", lua.globals().RemoteMedkitFailure)

    remote_bloodbag = lua.execute(r'''
FrameTimeValue = 0.2
for _, ragdollForm in ipairs({ false, true }) do
    local patient, body = MakeRemoteMedicalPatient("body")
    local target = ragdollForm and body or patient
    Bodies[patient].bloodVolume = 80
    local medic = MakePlayer()
    local bag = MakeSwep(medic, "weapon_bloodbag", 1)
    local gave = hg.WoundBridge.BloodBagGive(bag, target)
    local giveOK = gave == true and bag.modeValues[1] < 1
        and Bodies[patient].bloodVolume > 80 and Bodies[medic].bloodVolume == 100

    local donor, donorBody = MakeRemoteMedicalPatient("body")
    local donorTarget = ragdollForm and donorBody or donor
    local donorMedic = MakePlayer()
    local emptyBag = MakeSwep(donorMedic, "weapon_bloodbag", 0)
    local took = hg.WoundBridge.BloodBagTake(emptyBag, donorTarget)
    local takeOK = took == true and math.abs(emptyBag.modeValues[1] - 0.1) < 0.001
        and math.abs(Bodies[donor].bloodVolume - 99) < 0.001
        and math.abs(donor.organism.blood - 4950) < 0.001
        and donorMedic.organism.blood == 5000
    if not (giveOK and takeOK) then return false end
end
return true
''')
    check("R37 bloodbag give/take work on standing and shared-organism ragdoll patients", remote_bloodbag)

    remote_minigames = lua.execute(r'''
MinigameEnabled = true
local function RunContinuous(class, kind, capacity, ragdollForm)
    local patient, body = MakeRemoteMedicalPatient(kind)
    local target = ragdollForm and body or patient
    local medic = MakePlayer()
    local swep = MakeSwep(medic, class, capacity)
    if capacity > 1 then swep.modeValuesdef = { { capacity, true } } end
    CapturedMinigame = nil
    local result = hg.WoundBridge.SwepHeal(swep, target, 1)
    local captured = CapturedMinigame
    if result ~= false or not captured or captured.owner ~= medic then return false end
    local session = { startAmount = captured.options.amount, deferredUsed = 0 }
    captured.options.onProgress(medic, session, captured.options.amount)
    captured.options.onClose(medic, session, "complete")
    return patient, medic, swep
end
for _, ragdollForm in ipairs({ false, true }) do
    local bandagePatient, bandageMedic, bandageSwep = RunContinuous("weapon_bandage_sh", "bandage", 40, ragdollForm)
    local bandageOK = bandagePatient and #bandagePatient.organism.wounds == 0
        and bandageSwep.modeValues[1] == 0 and bandageMedic.organism.wounds
        and #bandageMedic.organism.wounds == 0
    local drugPatient, drugMedic, drugSwep = RunContinuous("weapon_morphine", "body", 1, ragdollForm)
    local drugOK = drugPatient and Bodies[drugPatient].opiateAmount > 0
        and Bodies[drugMedic].opiateAmount == 0 and drugSwep.modeValues[1] == 0
    if not (bandageOK and drugOK) then return false end
end
return true
''')
    check("R38 continuous bandage/syringe minigames keep medic and standing/ragdoll patient separate", remote_minigames)

failed = [name for name, ok in results if not ok]
print(f"TEST_OK {len(results) - len(failed)} / {len(results)}")
if failed:
    raise SystemExit(1)
