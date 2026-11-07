-- Behavioral fixture for tourniquet return and authoritative shrapnel/bandage care.
-- test_wszc_regression.py supplies production and canonical ZIP sources.
local tests = {}
local function Test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end
local function Assert(value, message)
    if not value then error(message or "assertion failed", 2) end
end
local function Near(actual, expected, message)
    Assert(math.abs((tonumber(actual) or 0) - expected) < 0.0001,
        (message or "not near") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function Equal(actual, expected, message)
    Assert(actual == expected, (message or "not equal") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

SERVER, CLIENT = true, false
AuthorityFlag, MinigameEnabled = true, false
Now = 100
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 0, 0, 0
HITGROUP_GENERIC, HITGROUP_HEAD, HITGROUP_CHEST, HITGROUP_STOMACH = 0, 1, 2, 3
HITGROUP_LEFTARM, HITGROUP_RIGHTARM, HITGROUP_LEFTLEG, HITGROUP_RIGHTLEG, HITGROUP_GEAR = 4, 5, 6, 7, 10
DMG_DISSOLVE, DMG_BLAST, DMG_BULLET, DMG_BUCKSHOT = 1, 2, 4, 8
BLOOD_COLOR_RED, MAT_GLASS, HUD_PRINTCENTER = 0, 1, 2
NULL = {}
WSZC = {
    OrganismAuthority = function() return AuthorityFlag end,
    WithVanillaContext = function(fn, ...) return fn(...) end,
}
WoundSystem = { Health = { HandleDamage = function() end }, Items = {} }
hg = {}
Errors = {}
math.Clamp = function(v, lo, hi) return math.max(lo, math.min(hi, v)) end
math.Rand = function(lo, hi) return (lo + hi) / 2 end
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
FrameTime = function() return 0.1 end
IsValid = function(v) return v ~= nil and v ~= false and (type(v) ~= "table" or v.valid ~= false) end
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
hook = { Add = function() end, Remove = function() end, Run = function() end, GetTable = function() return {} end }
timer = { Simple = function() end, Create = function() end, Remove = function() end, Exists = function() return false end }
net = {
    Receivers = {}, Receive = function(name, fn) net.Receivers[name] = fn end,
    Start = function() end, WriteUInt = function() end, WriteString = function() end,
    WriteFloat = function() end, WriteBool = function() end, WriteEntity = function() end,
    WriteTable = function() end, Send = function() end, Broadcast = function() end,
}
util = { AddNetworkString = function() end }
DamageInfo = function() error("damage is outside this medical suite") end

assert(load(ZCITY_SHARED_SOURCE))()
assert(load(ZCITY_SERVER_SOURCE))()
CanonicalSwepHeal = hg.WoundBridge.SwepHeal
assert(load(ORGANISM_SOURCE))()
assert(load(SERVER_SOURCE))()

local H = WoundSystem.Health
Bodies, Limbs = {}, {}
H.BodyState = Bodies
H.GetBody = function(ply) return Bodies[ply] end
H.GetLimbs = function(ply) return Limbs[ply] end
H.GetLimbState = function(ply, limbId)
    local states = Limbs[ply]
    if not states then return nil end
    if not states[limbId] then
        states[limbId] = { bleed = 0, pain = 0, muscle = 100, dismembered = false }
    end
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
NativeReturns, Renewed = {}, {}
H.ReturnAttachedMedicalItem = function(ply, itemId, durability, slot)
    NativeReturns[#NativeReturns + 1] = { ply = ply, item = itemId, durability = durability, slot = slot }
    return true
end
hg.RenewInv = function(ply) Renewed[ply] = (Renewed[ply] or 0) + 1 end
hg.GetCurrentCharacter = function(owner) return owner end

local Definitions = {}
WoundSystem.Items.Register = function(id, definition) Definitions[id] = definition end
assert(load(NATIVE_GAUZE_SOURCE))()
WoundSystem.Items.Get = function(id) return Definitions[id] end
WoundSystem.Items.GetMax = function(id) return Definitions[id] and Definitions[id].max or 100 end
WoundSystem.Items.CreateSlot = function(id, durability)
    return { type = "tool", toolName = id, durability = durability }
end
WoundSystem.Items.LimbAllowed = function(use, limbId)
    return not use.validLimbs or use.validLimbs == "any" or use.validLimbs == limbId
end
WoundSystem.UseMedicalItem = nil
H.ApplyItemToBody = WSZC.ApplyItemToBodyImpl
WSZC.H, WSZC.Ready = H, true

LimbIds = {
    "head", "thorax", "abdomen", "arm_L", "forearm_L", "hand_L",
    "arm_R", "forearm_R", "hand_R", "thigh_L", "crus_L", "foot_L",
    "thigh_R", "crus_R", "foot_R",
}
function MakePlayer()
    local ply = { _alive = true, valid = true, given = 0, givenClasses = {}, netvars = {} }
    ply.IsPlayer = function() return true end
    ply.Alive = function(self) return self._alive end
    ply.SetNetVar = function(self, key, value) self.netvars[key] = value end
    ply.Give = function(self, class)
        self.given = self.given + 1
        self.givenClasses[class] = (self.givenClasses[class] or 0) + 1
        local swep = { modeValues = { 0 }, netvars = {} }
        swep.SetNetVar = function(self, key, value) self.netvars[key] = value end
        self.lastGiven = swep
        return swep
    end
    ply.organism = {
        owner = ply, blood = 5000, bleed = 20, pain = 20, pulse = 70,
        shock = 0, adrenaline = 0, brain = 0, consciousness = 1,
        stamina = { 90, max = 180 }, wounds = {}, arterialwounds = {},
        wszc_shrapnel = {}, wszc_shrapnel_floor = {}, wszc_shrapnel_irritation = {},
    }
    Bodies[ply] = {
        bloodVolume = 100, heartRate = 70, shock = 0, adrenaline = 0,
        brainHealth = 100, consciousness = 100, stamina = 50, avgPain = 20,
        internalBleeding = 0, totalBleedSpeed = 20, opiateAmount = 0,
    }
    Limbs[ply] = {}
    for _, id in ipairs(LimbIds) do
        Limbs[ply][id] = { bleed = 0, pain = 0, muscle = 100, skin = 100, dismembered = false }
    end
    ply._WSZCLimbsRef = Limbs[ply]
    return ply
end

local function Wound(severity, bone)
    return { severity, Vector(), Angle(), bone, Now }
end

local function NativeBestLimb()
    for i = 1, 64 do
        local name, fn = debug.getupvalue(CanonicalSwepHeal, i)
        if not name then break end
        if name == "BestLimb" then return fn end
    end
    error("canonical BestLimb upvalue not found")
end

local function MakeBandageSwep(owner)
    return {
        mode = 1, modeValues = { 40 }, modeValuesdef = { 40 }, sndcd = 0,
        GetOwner = function() return owner end,
        GetClass = function() return "weapon_bandage_sh" end,
        SetNetVar = function() end,
        Remove = function(self) self.removed = true end,
    }
end

Assert(WSZC.InstallMedicalBridge(), "medical bridge did not install: " .. tostring(hg.WoundBridge)
    .. " / " .. tostring(hg.WoundBridge and hg.WoundBridge.SwepHeal))
Assert(WSZC.InstallTourniquetReturnBridge(), "return bridge did not install")

Test("MED01 canonical bandage selector ignores stale dressing and phantom bleed", function()
    local ply = MakePlayer()
    ply.organism.wounds = {
        Wound(4, "ValveBiped.Bip01_R_Hand"),
        Wound(10, "ValveBiped.Bip01_L_UpperArm"),
    }
    ply.organism.arterialwounds = {
        { 20, Vector(), Angle(), "ValveBiped.Bip01_L_Thigh", Now, nil, "llegartery" },
    }
    Limbs[ply].hand_R.isBandaged = true
    Limbs[ply].thigh_L.bleed = 100 -- artery/damage-only shadow, no ordinary wound
    local best = NativeBestLimb()
    Equal(best(ply, { kind = "bandage", item = "GAUZE" }), "forearm_L")
    Equal(best(ply, { kind = "bandage", item = "GAUZE" }, "hand_R"), "hand_R")
    ply.organism.wounds = {}
    Equal(best(ply, { kind = "bandage", item = "GAUZE" }), nil)
end)

Test("MED02 canonical physical bandage treats real wounds once per partial dose", function()
    MinigameEnabled = true
    local ply = MakePlayer()
    ply.organism.bleed = 30
    Bodies[ply].totalBleedSpeed = 30
    local ordinary = Wound(10, "ValveBiped.Bip01_R_Hand")
    local unrelated = Wound(7, "ValveBiped.Bip01_L_Hand")
    local complication = Wound(4, "ValveBiped.Bip01_R_Hand")
    complication.wszcShrapnel = "WSZC_SHRAPNEL_COMPLICATION"
    complication.wszcLimb = "hand_R"
    ply.organism.wounds = { ordinary, complication, unrelated }
    ply.organism.arterialwounds = {
        { 6, Vector(), Angle(), "ValveBiped.Bip01_R_Hand", Now },
    }
    local state = Limbs[ply].hand_R
    state.bleed, state.isBandaged = 46, true
    local swep = MakeBandageSwep(ply)
    local result = hg.WoundBridge.SwepHeal(swep, ply, 1)
    Assert(result == false and CapturedMinigame ~= nil, "physical minigame did not start")
    Assert(CapturedMinigame.options.limbId == "hand_R", "stale isBandaged vetoed real wound")
    local session = { startAmount = CapturedMinigame.options.amount, deferredUsed = 0 }
    CapturedMinigame.options.onProgress(ply, session, 100 / 12)

    Near(ordinary[1], 8.375, "ordinary wound must receive remainder after complication")
    Near(ply.organism.bleed, 27.75, "bleed treatment was absent or applied twice")
    Near(state.bleed, 34.75, "shadow must retain untouched arterial bleeding")
    Assert(state.isBandaged == false, "partial real wound was incorrectly considered closed")
    Assert(#ply.organism.wounds == 2 and ply.organism.wounds[2] == unrelated,
        "unrelated wound was deleted or replaced")
    Assert(ply.organism.arterialwounds[1][1] == 6, "bandage treated an artery")
    Near(swep.modeValues[1], 40 - (100 / 12) / 100 * 40, "wrong physical roll consumption")
end)

Test("MED03 full extraction closes only that limb complication and preserves bandage target", function()
    local ply = MakePlayer()
    ply.organism.bleed = 20
    local original = Wound(10, "ValveBiped.Bip01_R_Hand")
    local unrelated = Wound(7, "ValveBiped.Bip01_L_Hand")
    ply.organism.wounds = { original, unrelated }
    Limbs[ply].hand_R.shrapnel = 3
    Limbs[ply].foot_L.shrapnel = 3
    ply.organism.wszc_shrapnel.hand_R, ply.organism.wszc_shrapnel.foot_L = 3, 3
    ply.organism.wszc_shrapnel_floor.hand_R, ply.organism.wszc_shrapnel_floor.foot_L = 0.2, 0.3
    Assert(WSZC.ApplyShrapnelComplication(ply, ply.organism, "hand_R", 1, 10))
    Assert(WSZC.ApplyShrapnelComplication(ply, ply.organism, "foot_L", 1, 10))
    local handComplication = ply.organism.wounds[3]
    local footComplication = ply.organism.wounds[4]
    Assert(handComplication.wszcShrapnel == "WSZC_SHRAPNEL_COMPLICATION")
    Assert(handComplication[2] ~= nil and handComplication[3] ~= nil, "native wound vectors missing")

    local bleedBeforeExtraction = ply.organism.bleed
    Limbs[ply].hand_R.shrapnel = 0
    WSZC.SyncShrapnel(ply, ply.organism)
    local handTagLeft, originalLeft, footLeft = false, false, false
    for _, wound in pairs(ply.organism.wounds) do
        if wound == handComplication then handTagLeft = true end
        if wound == original then originalLeft = true end
        if wound == footComplication then footLeft = true end
    end
    Assert(not handTagLeft and originalLeft and footLeft,
        "extraction removed wrong wounds or left its own complication")
    Assert(ply.organism.wszc_shrapnel_irritation.hand_R == nil)
    Assert(ply.organism.wszc_shrapnel_irritation.foot_L ~= nil)
    Assert(ply.organism.wszc_shrapnel_floor.hand_R == nil)
    Near(ply.organism.bleed, bleedBeforeExtraction - 0.8,
        "only extracted complication bleed should be subtracted")
    Assert(NativeBestLimb()(ply, { kind = "bandage", item = "GAUZE" }, "hand_R") == "hand_R",
        "original post-extraction wound cannot be bandaged")
    local closedBleed = ply.organism.bleed
    WSZC.SyncShrapnel(ply, ply.organism)
    Near(ply.organism.bleed, closedBleed, "empty extraction sync subtracted bleed twice")

    -- Complete the actual physical SWEP path after extraction, not merely the
    -- selector: the original wound remains and one real wrap must treat it.
    MinigameEnabled = true
    CapturedMinigame = nil
    local swep = MakeBandageSwep(ply)
    Assert(hg.WoundBridge.SwepHeal(swep, ply, 1) == false and CapturedMinigame ~= nil)
    Assert(CapturedMinigame.options.limbId == "hand_R")
    CapturedMinigame.options.onProgress(ply,
        { startAmount = CapturedMinigame.options.amount, deferredUsed = 0 }, 100 / 12)
    Near(original[1], 4.375, "post-extraction physical bandage did not treat the original wound")
    local footSurvives, unrelatedSurvives = false, false
    for _, wound in pairs(ply.organism.wounds) do
        if wound == footComplication then footSurvives = true end
        if wound == unrelated then unrelatedSurvives = true end
    end
    Assert(footSurvives and unrelatedSurvives, "post-extraction bandage deleted unrelated wounds")
end)

Test("MED04 tourniquet return gives SWEP and native removal clears selected limb", function()
    local ply = MakePlayer()
    for _, id in ipairs({ "arm_R", "forearm_R", "hand_R" }) do
        Limbs[ply][id].tourniqueted = true
        Limbs[ply][id].blockedBleeding = true
        Limbs[ply][id].customStatuses = { TOURNIQUET = 0.01 }
    end
    Limbs[ply].arm_L.tourniqueted = true
    -- Representative native receiver boundary: C:U owns status cleanup and
    -- calls the exported return function only after that cleanup.
    net.Receivers.WoundSystem_RemoveLimbStatus = function(_, target)
        for _, id in ipairs({ "arm_R", "forearm_R", "hand_R" }) do
            local state = Limbs[target][id]
            state.tourniqueted, state.blockedBleeding = false, false
            state.customStatuses.TOURNIQUET = nil
        end
        return H.ReturnAttachedMedicalItem(target, "TOURNIQUET", 100, nil)
    end
    Assert(net.Receivers.WoundSystem_RemoveLimbStatus(0, ply) == true)
    Assert(ply.given == 1 and ply.givenClasses.weapon_tourniquet == 1,
        "removed tourniquet was not given as weapon_tourniquet")
    Assert(ply.lastGiven.modeValues[1] == 1 and ply.lastGiven.netvars.modeValues ~= nil)
    Assert(Renewed[ply] == 1, "ZCity weapon selector was not refreshed")
    Assert(#NativeReturns == 0, "C:U world/inventory fallback spawned the wrong item")
    for _, id in ipairs({ "arm_R", "forearm_R", "hand_R" }) do
        Assert(not Limbs[ply][id].tourniqueted and not Limbs[ply][id].blockedBleeding)
        Assert(Limbs[ply][id].customStatuses.TOURNIQUET == nil)
    end
    Assert(Limbs[ply].arm_L.tourniqueted, "another limb was incorrectly cleared")

    H.ReturnAttachedMedicalItem(ply, "SPLINT", 50, nil)
    Assert(#NativeReturns == 1 and NativeReturns[1].item == "SPLINT" and ply.given == 1,
        "non-tourniquet native returns must remain untouched")
    AuthorityFlag = false
    H.ReturnAttachedMedicalItem(ply, "TOURNIQUET", 100, nil)
    AuthorityFlag = true
    Assert(#NativeReturns == 2 and ply.given == 1, "bridge mode must retain native behavior")
end)

Test("MED05 remote recipient override returns to medic without world fallback", function()
    local patient, medic = MakePlayer(), MakePlayer()
    local nativeReturnsBefore = #NativeReturns
    WSZC.RemoteMedicalReturnRecipient = medic
    Assert(H.ReturnAttachedMedicalItem(patient, "TOURNIQUET", 100, nil) == true)
    WSZC.RemoteMedicalReturnRecipient = nil
    Assert(medic.given == 1 and patient.given == 0)
    Assert(medic.givenClasses.weapon_tourniquet == 1)
    Assert(#NativeReturns == nativeReturnsBefore)
end)

return tests
